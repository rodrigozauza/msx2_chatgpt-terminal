'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const {Readable}=require('node:stream');
const {createCache,createHandler,createServer,privateIP}=require('../LAN-SERVER.cjs');
const base=path.resolve(__dirname,'..'),results=[];
async function main(){
 const scratch=path.resolve(process.argv[2]||os.tmpdir()),dir=await fs.mkdtemp(path.join(scratch,'msxchat-phase4-'));
 const raw=await fs.readFile(path.join(base,'examples/00000001.REQ')),request=JSON.parse(raw);
 async function test(name,fn){await fn();results.push({test:name,status:'PASS'});}
 async function invoke(handler,bytes=raw,options={}){
  const chunks=options.chunks||[bytes];
  const req=Readable.from(chunks);req.method=options.method||'POST';req.url=options.url||'/msxchat/v1/exchange';
  req.socket={remoteAddress:options.peer||'192.168.1.50'};
  req.rawHeaders=options.headers||['Content-Length',String(bytes.length),'Content-Type','application/json'];
  const res={headersSent:false,destroyed:false,parts:[],writeHead(status,headers){this.status=status;this.headers=headers;this.headersSent=true;},
   write(bytes){this.parts.push(Buffer.from(bytes));return true;},end(bytes){if(bytes)this.write(bytes);this.ended=true;},destroy(){this.destroyed=true;}};
  await handler(req,res);res.body=Buffer.concat(res.parts);return res;
 }
 try{
  const state=path.join(dir,'cache'),cache=createCache(state,'Resposta manual LAN.'),
   handler=createHandler({peer:'192.168.1.50',cache});
  await test('Fragmented HTTP body produces a bounded local response and Content-Length',async()=>{
   const r=await invoke(handler,raw,{chunks:Array.from(raw,b=>Buffer.from([b]))});
   assert.equal(r.status,200);assert.equal(Number(r.headers['Content-Length']),r.body.length);
   assert.equal(r.headers.Connection,'close');assert.equal(JSON.parse(r.body).request_id,'00000001');
   assert.equal(JSON.parse(r.body).reply,'Resposta manual LAN.');
  });
  await test('Idempotent retry replays response without changing the cache file',async()=>{
   const file=path.join(state,'192_168_1_50-00000001.json'),before=await fs.readFile(file);
   const r=await invoke(handler);assert.equal(r.status,200);assert.deepEqual(await fs.readFile(file),before);
  });
  await test('Restart replays persisted result even if configured reply changes',async()=>{
   const h=createHandler({peer:'192.168.1.50',cache:createCache(state,'different reply')});
   assert.equal(JSON.parse((await invoke(h)).body).reply,'Resposta manual LAN.');
  });
  await test('Changed question under same request ID returns 409',async()=>{
   const changed=Buffer.from(JSON.stringify({...request,message:'different'}));
   assert.equal((await invoke(handler,changed)).status,409);
  });
  await test('Concurrent identical requests serialize to one persisted result',async()=>{
   const h=createHandler({peer:'192.168.1.50',cache:createCache(path.join(dir,'parallel'),'same')});
   const replies=await Promise.all(Array.from({length:8},()=>invoke(h)));
   assert.ok(replies.every(r=>r.status===200));assert.equal(new Set(replies.map(r=>r.body.toString())).size,1);
  });
  await test('Peer restriction rejects another LAN address',async()=>assert.equal((await invoke(handler,raw,{peer:'192.168.1.51'})).status,403));
  await test('Wrong endpoint and method are rejected',async()=>{
   assert.equal((await invoke(handler,raw,{url:'/other'})).status,404);assert.equal((await invoke(handler,raw,{method:'GET'})).status,404);
  });
  await test('Missing or duplicate Content-Length is rejected',async()=>{
   assert.equal((await invoke(handler,raw,{headers:['Content-Type','application/json']})).status,411);
   assert.equal((await invoke(handler,raw,{headers:['Content-Length','1','Content-Length','1','Content-Type','application/json']})).status,411);
  });
  await test('Chunked and compressed bodies are rejected',async()=>{
   for(const key of ['Transfer-Encoding','Content-Encoding'])assert.equal((await invoke(handler,raw,{headers:['Content-Length',String(raw.length),'Content-Type','application/json',key,'chunked']})).status,400);
  });
  await test('Declared length beyond limit is rejected before caching',async()=>{
   assert.equal((await invoke(handler,raw,{headers:['Content-Length','32768','Content-Type','application/json']})).status,413);
  });
  await test('Wrong content type is rejected',async()=>assert.equal((await invoke(handler,raw,{headers:['Content-Length',String(raw.length),'Content-Type','text/plain']})).status,415));
  await test('Truncated and excess request body are rejected',async()=>{
   assert.equal((await invoke(handler,raw,{chunks:[raw.subarray(0,-1)]})).status,400);
   assert.equal((await invoke(handler,raw,{chunks:[raw,Buffer.from('x')]})).status,413);
  });
  await test('Invalid UTF8 and duplicate JSON keys are rejected',async()=>{
   assert.equal((await invoke(handler,Buffer.from([0xff]))).status,422);
   assert.equal((await invoke(handler,Buffer.from(raw.toString().replace(/}\s*$/,',"message":"again"}')))).status,422);
  });
  await test('Input must be a valid pending request with nonzero local ID',async()=>{
   for(const patch of [{state:'completed'},{request_id:'00000000'},{conversation_id:'00000002'},{message:''}]){
    const bytes=Buffer.from(JSON.stringify({...request,...patch}));assert.equal((await invoke(handler,bytes)).status,422);
   }
  });
  await test('Remote error response is encoded in the local envelope',async()=>{
   const h=createHandler({peer:'192.168.1.50',cache:createCache(path.join(dir,'error'),'','E_TEST')});
   const r=await invoke(h);assert.equal(r.status,200);assert.equal(JSON.parse(r.body).state,'error');assert.equal(JSON.parse(r.body).error_code,'E_TEST');
  });
  await test('Invalid persistent cache is preserved and returns 503',async()=>{
   const folder=path.join(dir,'broken');await fs.mkdir(folder);const file=path.join(folder,'192_168_1_50-00000001.json');
   await fs.writeFile(file,'partial');const h=createHandler({peer:'192.168.1.50',cache:createCache(folder,'x')});
   assert.equal((await invoke(h)).status,503);assert.equal(await fs.readFile(file,'utf8'),'partial');
  });
  await test('Response fragmentation preserves exact Content-Length and body',async()=>{
   const h=createHandler({peer:'192.168.1.50',cache,fragment:3,delay:0});
   const r=await invoke(h);assert.ok(r.parts.length>10);assert.equal(r.body.length,Number(r.headers['Content-Length']));
  });
  await test('CLI address policy accepts private LAN and rejects wildcard/public targets',()=>{
   for(const ip of ['10.0.0.1','172.16.0.1','172.31.255.1','192.168.1.1'])assert.ok(privateIP(ip));
   for(const ip of ['0.0.0.0','8.8.8.8','172.32.0.1','127.0.0.1','::1'])assert.ok(!privateIP(ip));
  });
  if(process.argv.includes('--real')){
   await test('Real loopback HTTP POST, fragmentation, close and persisted retry',async()=>{
    const server=createServer({peer:'127.0.0.1',cache:createCache(path.join(dir,'loopback'),'TCP loopback ok'),fragment:5,delay:1});
    const http=require('node:http');await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    try{
     const port=server.address().port;
     const send=()=>new Promise((resolve,reject)=>{
      const req=http.request({host:'127.0.0.1',port,method:'POST',path:'/msxchat/v1/exchange',
       headers:{'Content-Type':'application/json','Content-Length':raw.length,'Connection':'close'}},res=>{
        const parts=[];res.on('data',p=>parts.push(p));res.on('end',()=>resolve({status:res.statusCode,body:Buffer.concat(parts),headers:res.headers}));});
      req.on('error',reject);req.setTimeout(5000,()=>req.destroy(Error('timeout')));
      req.write(raw.subarray(0,17));req.end(raw.subarray(17));
     });
     const first=await send(),second=await send();assert.equal(first.status,200);assert.deepEqual(first.body,second.body);
     assert.equal(first.body.length,Number(first.headers['content-length']));assert.equal(first.headers.connection,'close');
    }finally{await new Promise(resolve=>server.close(resolve));}
   });
  }
  await fs.writeFile(path.join(base,process.argv.includes('--real')?'LAN-REAL-RESULTS.json':'LAN-SERVER-RESULTS.json'),JSON.stringify({scope:process.argv.includes('--real')?'PC filesystem plus real loopback HTTP; no MSX hardware':'PC filesystem plus in-memory HTTP request/response streams; no real TCP',results},null,2)+'\n');
  console.log(JSON.stringify({passed:results.length,total:results.length,realLoopback:process.argv.includes('--real')},null,2));
 }finally{
  if(path.dirname(path.resolve(dir))!==scratch||!path.basename(dir).startsWith('msxchat-phase4-'))throw Error('Unsafe cleanup');
  await fs.rm(dir,{recursive:true,force:true});
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
