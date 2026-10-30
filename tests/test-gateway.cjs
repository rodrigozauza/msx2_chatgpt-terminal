'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {EventEmitter}=require('node:events'),{Readable}=require('node:stream');
const {createOpenAIClient}=require('../OPENAI-CLIENT.cjs');
const {openStore,inspect,digest}=require('../GATEWAY-STORE.cjs');
const {createHandler,createServer}=require('../LAN-SERVER.cjs');
const {clientFromEnv}=require('../GATEWAY.cjs');
const base=path.resolve(__dirname,'..'),results=[],fakeKey='TEST_ONLY_SECRET_NOT_A_REAL_API_KEY';
const envelope=(id='00000001',message='Pergunta')=>({protocol:'msxchat/1',request_id:id,conversation_id:'00000001',state:'pending',message,response_id:'',reply:'',error_code:''});
const bytes=req=>Buffer.from(JSON.stringify(req));
const apiValue=(text='Resposta')=>({id:'resp_test',status:'completed',output:[{type:'reasoning',summary:[]},{type:'message',role:'assistant',content:[{type:'output_text',text}]}],usage:{input_tokens:5,output_tokens:3,total_tokens:8}});
function fakeHTTPS(value,options={}){
 const seen=[];
 function request(settings,callback){
  const req=new EventEmitter();req.destroy=()=>{req.destroyed=true;};
  req.end=payload=>{
   seen.push({settings,payload:JSON.parse(payload.toString())});
   if(options.hang)return;
   process.nextTick(()=>{
    if(options.network){req.emit('error',Error(fakeKey));return;}
    const res=new EventEmitter();res.statusCode=options.status||200;res.headers={'x-request-id':options.requestId||'req_test'};
    res.destroy=()=>{res.destroyed=true;};
    callback(res);
    const raw=options.raw||Buffer.from(JSON.stringify(value));
    for(let at=0;at<raw.length;at+=options.chunk||37)res.emit('data',raw.subarray(at,at+(options.chunk||37)));
    res.emit('end');
   });
  };return req;
 }
 return {request,seen};
}
const providerResult=text=>({text,error:'',fullText:text,apiResponseId:'resp_test',requestId:'req_test',apiStatus:'completed',usage:{total_tokens:8}});
async function rejection(fn,code){await assert.rejects(fn,e=>e.code===code||e.message===code);}
async function main(){
 const scratch=path.resolve(process.argv[2]||os.tmpdir()),dir=await fs.mkdtemp(path.join(scratch,'msxchat-phase5-'));
 let serial=0;
 async function test(name,fn){await fn();results.push({test:name,status:'PASS'});}
 async function state(fn,options={}){
  const folder=path.join(dir,'case-'+(++serial)),calls=[];
  const provider={model:'test-model',fingerprint:'test-config',generate:async(input,id)=>{calls.push({input,id});return providerResult('Resposta '+calls.length);},...options.provider};
  const store=await openStore({directory:folder,peer:'192.168.1.50',provider,...options});
  try{return await fn({folder,calls,provider,store});}finally{await store.close();}
 }
 try{
  await test('HTTPS uses fixed official host, certificate validation and bearer only in headers',async()=>{
   const mock=fakeHTTPS(apiValue()),client=createOpenAIClient({apiKey:fakeKey,model:'test-model',requestImpl:mock.request});
   const value=await client.generate([{role:'user',content:'Olá'}],'client-test');
   assert.equal(value.text,'Resposta');assert.equal(mock.seen.length,1);
   assert.ok(mock.seen[0].payload.instructions.includes('80 colunas'));
   assert.ok(!mock.seen[0].payload.instructions.includes('64 colunas'));
   const {settings,payload}=mock.seen[0];assert.equal(settings.hostname,'api.openai.com');assert.equal(settings.port,443);assert.equal(settings.path,'/v1/responses');
   assert.equal(settings.rejectUnauthorized,true);assert.equal(settings.headers.Authorization,'Bearer '+fakeKey);
   assert.equal(settings.headers['X-Client-Request-Id'],'client-test');assert.equal(payload.store,false);assert.equal(payload.stream,false);
   assert.equal(payload.model,'test-model');assert.ok(!JSON.stringify(payload).includes(fakeKey));assert.equal(payload.max_output_tokens,1024);
  });
  await test('Output is collected across assistant messages rather than output[0]',async()=>{
   const value=apiValue();value.output.push({type:'message',role:'assistant',content:[{type:'output_text',text:'Outra parte'}]});
   const mock=fakeHTTPS(value),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   assert.equal((await c.generate([])).text,'Resposta\nOutra parte');
  });
  await test('Model context receives safe Unicode and no local private-byte encoding',async()=>{
   const mock=fakeHTTPS(apiValue()),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   await c.generate([{role:'user',content:'ação\ue0ff\u0001\n'}]);
   assert.equal(mock.seen[0].payload.input[0].content,'ação? \n');
  });
  await test('Large Unicode reply is truncated at scalar boundaries with visible marker',async()=>{
   const mock=fakeHTTPS(apiValue('😀'.repeat(3000))),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   const r=await c.generate([]);assert.equal(Array.from(r.text).length,2047);assert.ok(r.text.endsWith('[TRUNCADO NO MSX]'));assert.ok(r.truncated);
  });
  await test('Secret in unexpected upstream text is redacted before local output',async()=>{
   const mock=fakeHTTPS(apiValue('prefix '+fakeKey+' suffix')),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   const r=await c.generate([]);assert.ok(!JSON.stringify(r).includes(fakeKey));assert.ok(r.text.includes('[SEGREDO REMOVIDO]'));
  });
  for(const [name,value,code]of [
   ['incomplete',{...apiValue('Parcial'),status:'incomplete'},'E_OUTPUT_LIMIT'],
   ['refusal',{...apiValue(),output:[{type:'message',role:'assistant',content:[{type:'refusal',refusal:'Nao posso atender.'}]}]},'E_REFUSAL'],
   ['empty',apiValue(''),'E_EMPTY'],['failed',{...apiValue(),status:'failed'},'E_API_FAILED']
  ])await test('API '+name+' maps to a local error envelope',async()=>{
   const mock=fakeHTTPS(value),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   assert.equal((await c.generate([])).error,code);
  });
  for(const [status,code]of [[400,'E_API_REQUEST'],[401,'E_API_AUTH'],[403,'E_API_ACCESS'],[404,'E_API_MODEL'],[429,'E_API_RATE'],[500,'E_API_SERVICE'],[302,'E_API_SERVICE']]){
   await test('HTTP '+status+' is sanitized and never retried automatically',async()=>{
    const mock=fakeHTTPS({error:{message:fakeKey}},{status}),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
    await rejection(()=>c.generate([]),code);assert.equal(mock.seen.length,1);
   });
  }
  await test('Network and timeout failures do not re-dispatch the API request',async()=>{
   for(const option of [{network:true},{hang:true}]){
    const mock=fakeHTTPS(apiValue(),option),c=createOpenAIClient({apiKey:fakeKey,model:'test',timeoutMs:1000,requestImpl:mock.request});
    await rejection(()=>c.generate([]),option.hang?'E_API_TIMEOUT':'E_API_NETWORK');assert.equal(mock.seen.length,1);
   }
  });
  await test('Invalid UTF8, malformed schema and unpaired Unicode are rejected',async()=>{
   for(const option of [{raw:Buffer.from([0xff])},{raw:Buffer.from('{}')},{raw:Buffer.from(JSON.stringify(apiValue('\ud800')))}]){
    const mock=fakeHTTPS(null,option),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
    await rejection(()=>c.generate([]),'E_API_FORMAT');
   }
  });
  await test('API response is bounded to 1 MiB',async()=>{
   const mock=fakeHTTPS(null,{raw:Buffer.alloc(1048577,32),chunk:65536}),c=createOpenAIClient({apiKey:fakeKey,model:'test',requestImpl:mock.request});
   await rejection(()=>c.generate([]),'E_API_SIZE');
  });
  await test('Configuration requires key/model and refuses disabled TLS verification',()=>{
   assert.throws(()=>clientFromEnv({OPENAI_API_KEY:fakeKey}),/E_CONFIG_MODEL/);
   assert.throws(()=>clientFromEnv({OPENAI_MODEL:'test'}),/E_CONFIG_KEY/);
   assert.throws(()=>clientFromEnv({OPENAI_API_KEY:fakeKey,OPENAI_MODEL:fakeKey}),/E_CONFIG_MODEL/);
   assert.throws(()=>clientFromEnv({OPENAI_API_KEY:fakeKey,OPENAI_MODEL:'test',NODE_DEBUG:'http'}),/E_CONFIG_DEBUG/);
   assert.throws(()=>clientFromEnv({OPENAI_API_KEY:fakeKey,OPENAI_MODEL:'test',NODE_TLS_REJECT_UNAUTHORIZED:'0'}),/E_CONFIG_TLS/);
  });
  await test('API is invoked only after durable reservation and start records exist',()=>state(async({store,folder,provider,calls})=>{
   provider.generate=async(input,id)=>{
    assert.ok((await fs.stat(path.join(folder,'jobs/192_168_1_50-00000001.job.json'))).size>0);
    assert.ok((await fs.stat(path.join(folder,'jobs/192_168_1_50-00000001.started.json'))).size>0);
    calls.push({input,id});return providerResult('Ok');
   };
   const first=await store.exchange('192.168.1.50',bytes(envelope()));assert.ok(first.processing);
   await store.idle();const final=await store.exchange('192.168.1.50',bytes(envelope()));
   assert.equal(final.response.reply,'Ok');assert.equal(final.response.response_id,'00000001');assert.equal(calls.length,1);
  }));
  await test('Concurrent polls reserve one job and produce one API call',()=>state(async({store,calls})=>{
   const replies=await Promise.all(Array.from({length:12},()=>store.exchange('192.168.1.50',bytes(envelope()))));
   assert.ok(replies.every(x=>x.processing||x.response));await store.idle();assert.equal(calls.length,1);
   await store.exchange('192.168.1.50',bytes(envelope()));assert.equal(calls.length,1);
  }));
  await test('Changed content with same ID is rejected',()=>state(async({store,calls})=>{
   await store.exchange('192.168.1.50',bytes(envelope()));await store.idle();
   await rejection(()=>store.exchange('192.168.1.50',bytes(envelope('00000001','Outra'))),'E_CONFLICT');assert.equal(calls.length,1);
  }));
  await test('Persisted response replays after gateway restart without another API call',async()=>{
   const folder=path.join(dir,'restart'),first={model:'test',fingerprint:'same',generate:async()=>providerResult('Persistida')};
   let s=await openStore({directory:folder,peer:'192.168.1.50',provider:first});
   await s.exchange('192.168.1.50',bytes(envelope()));await s.idle();await s.close();
   let count=0;s=await openStore({directory:folder,peer:'192.168.1.50',provider:{...first,generate:async()=>{count++;return providerResult('errado');}}});
   try{assert.equal((await s.exchange('192.168.1.50',bytes(envelope()))).response.reply,'Persistida');assert.equal(count,0);}finally{await s.close();}
  });
  await test('Conversation sends bounded earlier question/answer pairs as API input',()=>state(async({store,calls})=>{
   await store.exchange('192.168.1.50',bytes(envelope('00000001','Primeira')));await store.idle();
   await store.exchange('192.168.1.50',bytes(envelope('00000002','Segunda')));await store.idle();
   assert.deepEqual(calls[1].input,[{role:'user',content:'Primeira'},{role:'assistant',content:'Resposta 1'},{role:'user',content:'Segunda'}]);
  }));
  await test('Context turn limit discards older pairs and keeps chronological order',()=>state(async({store,calls})=>{
   for(let i=1;i<=3;i++){await store.exchange('192.168.1.50',bytes(envelope(String(i).padStart(8,'0'),'Q'+i)));await store.idle();}
   assert.equal(calls[2].input.length,3);assert.equal(calls[2].input[0].content,'Q2');
  },{maxContextTurns:1}));
  await test('Failed API turns do not become successful conversation context',()=>state(async({store,provider})=>{
   let count=0,second;
   provider.generate=async input=>{if(++count===1)return {...providerResult('recusa'),error:'E_REFUSAL'};second=input;return providerResult('ok');};
   await store.exchange('192.168.1.50',bytes(envelope()));await store.idle();
   await store.exchange('192.168.1.50',bytes(envelope('00000002','Nova')));await store.idle();
   assert.deepEqual(second,[{role:'user',content:'Nova'}]);
  }));
  await test('API timeout is terminal for that ID and is not resubmitted on polling',()=>state(async({store,provider,calls})=>{
   provider.generate=async()=>{calls.push(1);throw Object.assign(Error(fakeKey),{code:'E_API_TIMEOUT',ambiguous:true});};
   await store.exchange('192.168.1.50',bytes(envelope()));await store.idle();
   const r=await store.exchange('192.168.1.50',bytes(envelope()));assert.equal(r.response.error_code,'E_API_TIMEOUT');
   assert.ok(!JSON.stringify(r).includes(fakeKey));await store.exchange('192.168.1.50',bytes(envelope()));assert.equal(calls.length,1);
  }));
  await test('A second gateway cannot take the same journal lock',()=>state(async({folder,provider})=>{
   await rejection(()=>openStore({directory:folder,peer:'192.168.1.50',provider}),'E_LOCK');
  }));
  await test('A started job without result becomes ambiguous and never calls API again',()=>state(async({store,folder,provider,calls})=>{
   const req=envelope(),k='192_168_1_50-00000001';
   await fs.writeFile(path.join(folder,'jobs',k+'.job.json'),JSON.stringify({schema:'msxchat-openai-job/1',peer:'192.168.1.50',request:req,request_sha256:digest(req),config_id:provider.fingerprint,model:provider.model,client_request_id:'previous'}));
   await fs.writeFile(path.join(folder,'jobs',k+'.started.json'),'partial');
   const r=await store.exchange('192.168.1.50',bytes(req));assert.equal(r.response.error_code,'E_AMBIGUOUS');assert.equal(calls.length,0);
  }));
  await test('Reserved but unsent job with changed configuration is not dispatched',()=>state(async({store,folder,calls})=>{
   const req=envelope(),k='192_168_1_50-00000001';
   await fs.writeFile(path.join(folder,'jobs',k+'.job.json'),JSON.stringify({schema:'msxchat-openai-job/1',peer:'192.168.1.50',request:req,request_sha256:digest(req),config_id:'old-config',model:'old',client_request_id:'previous'}));
   await store.exchange('192.168.1.50',bytes(req));await store.idle();
   assert.equal((await store.exchange('192.168.1.50',bytes(req))).response.error_code,'E_CONFIG_CHANGED');assert.equal(calls.length,0);
  }));
  await test('Corrupt reservation is preserved and cannot trigger API work',()=>state(async({store,folder,calls})=>{
   const file=path.join(folder,'jobs/192_168_1_50-00000001.job.json');await fs.writeFile(file,'partial');
   await rejection(()=>store.exchange('192.168.1.50',bytes(envelope())),'E_STATE');
   assert.equal(await fs.readFile(file,'utf8'),'partial');assert.equal(calls.length,0);
  }));
  await test('Failed result commit never triggers another API dispatch',()=>state(async({store,folder,provider,calls})=>{
   provider.generate=async()=>{calls.push(1);await fs.mkdir(path.join(folder,'jobs/192_168_1_50-00000001.done.json'));return providerResult('lost commit');};
   await store.exchange('192.168.1.50',bytes(envelope()));await store.idle();
   await rejection(()=>store.exchange('192.168.1.50',bytes(envelope())),'E_STATE');assert.equal(calls.length,1);
  }));
  await test('Unknown older request IDs are rejected instead of branching conversation silently',()=>state(async({store,calls})=>{
   await store.exchange('192.168.1.50',bytes(envelope('00000002','Nova')));await store.idle();
   await rejection(()=>store.exchange('192.168.1.50',bytes(envelope('00000001','Antiga'))),'E_ORDER');assert.equal(calls.length,1);
  }));
  await test('Inspection is read-only and excludes question/answer bodies',()=>state(async({store,folder})=>{
   await store.exchange('192.168.1.50',bytes(envelope('00000001','PRIVATE_QUESTION')));await store.idle();
   const report=await inspect(folder);assert.equal(report.jobs[0].state,'completed');assert.ok(!JSON.stringify(report).includes('PRIVATE_QUESTION'));
  }));
  await test('Gateway HTTP returns 202 before API completion, then 200 local envelope',()=>state(async({store})=>{
   const handler=createHandler({peer:'192.168.1.50',cache:store});
   async function invoke(){
    const data=bytes(envelope()),req=Readable.from([data]);req.method='POST';req.url='/msxchat/v1/exchange';req.socket={remoteAddress:'192.168.1.50'};
    req.rawHeaders=['Content-Length',String(data.length),'Content-Type','application/json'];
    const res={headersSent:false,destroyed:false,parts:[],writeHead(status,headers){this.status=status;this.headers=headers;this.headersSent=true;},
     end(p){if(p)this.parts.push(p);},destroy(){this.destroyed=true;}};
    await handler(req,res);res.body=Buffer.concat(res.parts);return res;
   }
   const p=await invoke();assert.equal(p.status,202);assert.equal(p.headers['Retry-After'],'2');
   await store.idle();const r=await invoke();assert.equal(r.status,200);assert.equal(JSON.parse(r.body).state,'completed');
  }));

  await test('Graceful shutdown waits for the active API call and leaves queued work unsent',async()=>{
   const folder=path.join(dir,'shutdown');let release,started;const began=new Promise(r=>started=r),hold=new Promise(r=>release=r),calls=[];
   const provider={model:'test',fingerprint:'same',generate:async input=>{calls.push(input);started();await hold;return providerResult('done');}};
   const s=await openStore({directory:folder,peer:'192.168.1.50',provider});
   await s.exchange('192.168.1.50',bytes(envelope()));await began;
   await s.exchange('192.168.1.50',bytes(envelope('00000002','queued')));
   const closing=s.close();release();await closing;assert.equal(calls.length,1);
   assert.equal((await inspect(folder)).jobs[1].state,'reserved');
   const next=await openStore({directory:folder,peer:'192.168.1.50',provider});
   try{await next.exchange('192.168.1.50',bytes(envelope('00000002','queued')));await next.idle();assert.equal(calls.length,2);}finally{await next.close();}
  });

  if(process.argv.includes('--real')){

   await test('Real HTTPS rejects an untrusted certificate before sending bearer, then accepts the test CA',async()=>{
    const https=require('node:https'),key=await fs.readFile(path.join(base,'tests/fixtures/loopback-test-key.pem')),
     cert=await fs.readFile(path.join(base,'tests/fixtures/loopback-test-cert.pem'));
    let requests=0;
    const server=https.createServer({key,cert},(req,res)=>{
     requests++;assert.equal(req.headers.authorization,'Bearer '+fakeKey);assert.equal(req.url,'/v1/responses');
     const parts=[];req.on('data',p=>parts.push(p));req.on('end',()=>{
      assert.equal(JSON.parse(Buffer.concat(parts)).store,false);
      const body=Buffer.from(JSON.stringify(apiValue('TLS test '+fakeKey)));
      res.writeHead(200,{'Content-Type':'application/json','Content-Length':body.length,'Connection':'close','X-Request-Id':'req_tls'});
      res.write(body.subarray(0,17));res.end(body.subarray(17));
     });
    });
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    try{
     const port=server.address().port;
     const untrusted=createOpenAIClient({apiKey:fakeKey,model:'test',timeoutMs:3000,requestImpl:(o,cb)=>https.request({...o,hostname:'127.0.0.1',port},cb)});
     await rejection(()=>untrusted.generate([{role:'user',content:'test'}]),'E_API_NETWORK');assert.equal(requests,0);
     const trusted=createOpenAIClient({apiKey:fakeKey,model:'test',timeoutMs:3000,requestImpl:(o,cb)=>https.request({...o,hostname:'127.0.0.1',port,ca:cert},cb)});
     const response=await trusted.generate([{role:'user',content:'test'}]);
     assert.equal(response.requestId,'req_tls');assert.equal(requests,1);assert.ok(!JSON.stringify(response).includes(fakeKey));
    }finally{await new Promise(resolve=>server.close(resolve));}
   });

   await test('Real loopback HTTP processing/poll/result replay uses one mock API call',async()=>{
    const folder=path.join(dir,'real'),calls=[],provider={model:'test',fingerprint:'same',generate:async()=>{calls.push(1);await new Promise(r=>setTimeout(r,50));return providerResult('Real HTTP, simulated OpenAI');}};
    const store=await openStore({directory:folder,peer:'127.0.0.1',provider}),server=createServer({peer:'127.0.0.1',cache:store});
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    try{
     const send=()=>new Promise((resolve,reject)=>{
      const data=bytes(envelope()),http=require('node:http'),req=http.request({host:'127.0.0.1',port:server.address().port,method:'POST',path:'/msxchat/v1/exchange',headers:{'Content-Type':'application/json','Content-Length':data.length,'Connection':'close'}},res=>{
       const pieces=[];res.on('data',p=>pieces.push(p));res.on('end',()=>resolve({status:res.statusCode,body:Buffer.concat(pieces)}));});
      req.on('error',reject);req.setTimeout(5000,()=>req.destroy(Error('timeout')));req.end(data);
     });
     assert.equal((await send()).status,202);await store.idle();
     const first=await send(),again=await send();assert.equal(first.status,200);assert.deepEqual(first.body,again.body);assert.equal(calls.length,1);
    }finally{await new Promise(r=>server.close(r));await store.close();}
   });
  }
  const filename=process.argv.includes('--real')?'GATEWAY-REAL-RESULTS.json':'GATEWAY-RESULTS.json';
  await fs.writeFile(path.join(base,filename),JSON.stringify({scope:process.argv.includes('--real')?'Real PC loopback HTTP/TLS and filesystem; synthetic certificate and mocked OpenAI responses, no paid/live API call':'PC filesystem and mocked HTTPS adapter/HTTP streams; no live OpenAI call',results},null,2)+'\n');
  console.log(JSON.stringify({passed:results.length,total:results.length,realLoopback:process.argv.includes('--real'),liveOpenAI:false},null,2));
 }finally{
  if(path.dirname(path.resolve(dir))!==scratch||!path.basename(dir).startsWith('msxchat-phase5-'))throw Error('Unsafe cleanup');
  await fs.rm(dir,{recursive:true,force:true});
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
