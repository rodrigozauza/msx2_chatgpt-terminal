// Phase 4 LAN fixture server. No OpenAI, external requests, credentials or SD sharing.
'use strict';
const http=require('node:http'),fs=require('node:fs/promises'),path=require('node:path');
const crypto=require('node:crypto'),net=require('node:net');
const {parseEnvelope,makeResponse}=require('./make-response.cjs');
const fields=['protocol','request_id','conversation_id','state','message','response_id','reply','error_code'];
const normalize=ip=>ip&&ip.startsWith('::ffff:')?ip.slice(7):ip;
const privateIP=ip=>net.isIPv4(ip)&&(/^10\./.test(ip)||/^192\.168\./.test(ip)||(/^172\./.test(ip)&&Number(ip.split('.')[1])>=16&&Number(ip.split('.')[1])<=31));
function failure(code,status){return Object.assign(Error(code),{status,code});}
function createCache(directory,reply,error=''){
 const folder=path.resolve(directory),inflight=new Map();
 async function exchange(peer,bytes){
  let req,rsp;
  try{req=parseEnvelope(bytes);rsp=makeResponse(req,reply,error);}catch(e){throw failure('E_JSON',422);}
  const digest=crypto.createHash('sha256').update(JSON.stringify(fields.map(k=>req[k]))).digest('hex');
  const filename=path.join(folder,peer.replace(/\./g,'_')+'-'+req.request_id+'.json');
  const run=async()=>{
   await fs.mkdir(folder,{recursive:true});
   try{
    const saved=JSON.parse(await fs.readFile(filename,'utf8'));
    if(saved.format!=='msxchat-lan-cache/1'||!saved.request_sha256||!saved.response)throw Error('Invalid cache');
    if(saved.request_sha256!==digest)throw failure('E_CONFLICT',409);
    const check=parseEnvelope(Buffer.from(JSON.stringify(saved.response)));
    if(check.request_id!==req.request_id||check.conversation_id!==req.conversation_id||
       !['completed','error'].includes(check.state)||check.message||!check.response_id||check.response_id==='00000000'||
       (check.state==='completed'&&(!check.reply||check.error_code))||(check.state==='error'&&!check.error_code))throw Error('Invalid cached response');
    return {response:check,cached:true};
   }catch(e){if(e.code!=='ENOENT')throw e;}
   const file=await fs.open(filename,'wx');
   try{await file.writeFile(JSON.stringify({format:'msxchat-lan-cache/1',request_sha256:digest,response:rsp})+'\n');await file.sync();}
   finally{await file.close();}
   return {response:rsp,cached:false};
  };
  const previous=inflight.get(filename)||Promise.resolve();
  const task=previous.catch(()=>{}).then(run);
  inflight.set(filename,task);
  try{return await task;}catch(e){if(e.status)throw e;throw failure('E_CACHE',503);}
  finally{if(inflight.get(filename)===task)inflight.delete(filename);}
 }
 return {exchange,folder};
}
function createHandler({peer,cache,fragment=0,delay=0,log=()=>{}}){
 if(!net.isIPv4(peer))throw Error('Explicit IPv4 peer required');
 return async function handler(req,res){
  const respond=async(status,value)=>{
   const body=Buffer.from(JSON.stringify(value)+'\r\n','utf8');
   res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Content-Length':body.length,'Connection':'close',...(status===202?{'Retry-After':'2'}:{})});
   if(fragment>0&&status===200){
    for(let at=0;at<body.length;at+=fragment){
     if(res.destroyed)return;
     res.write(body.subarray(at,at+fragment));
     if(delay)await new Promise(resolve=>setTimeout(resolve,delay));
    }
    res.end();
   }else res.end(body);
  };
  try{
   if(normalize(req.socket.remoteAddress)!==peer)throw failure('E_PEER',403);
   if(req.method!=='POST'||req.url!=='/msxchat/v1/exchange')throw failure('E_ENDPOINT',404);
   const raw=req.rawHeaders||[],values=Object.create(null);
   for(let i=0;i<raw.length;i+=2){const key=raw[i].toLowerCase();(values[key]??=[]).push(raw[i+1]);}
   if(values['transfer-encoding']||values['content-encoding'])throw failure('E_ENCODING',400);
   if(!values['content-length']||values['content-length'].length!==1||
      !/^[0-9]{1,5}$/.test(values['content-length'][0]))throw failure('E_LENGTH',411);
   const length=Number(values['content-length'][0]);
   if(length<1||length>32767)throw failure('E_SIZE',413);
   if(!values['content-type']||values['content-type'].length!==1||
      !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(values['content-type'][0]))throw failure('E_TYPE',415);
   let total=0;const parts=[];
   for await(const chunk of req){total+=chunk.length;if(total>length||total>32767)throw failure('E_SIZE',413);parts.push(chunk);}
   if(total!==length||req.aborted)throw failure('E_LENGTH',400);
   const result=await cache.exchange(peer,Buffer.concat(parts));
   if(result.processing){log({status:202,state:'processing'});await respond(202,{state:'processing'});return;}
   log({request_id:result.response.request_id,status:200,cached:result.cached});
   await respond(200,result.response);
  }catch(e){
   const status=e.status||500;log({status,error:e.code||'E_SERVER'});
   if(!res.headersSent&&!res.destroyed)await respond(status,{error:e.code||'E_SERVER'});
   else if(!res.destroyed)res.destroy();
   req.resume();
  }
 };
}
function createServer(options){
 const server=http.createServer({maxHeaderSize:2048},createHandler(options));
 server.requestTimeout=20000;server.headersTimeout=10000;server.keepAliveTimeout=1000;
 server.maxRequestsPerSocket=1;server.setTimeout(20000,socket=>socket.destroy());
 return server;
}
async function main(){
 const args=process.argv.slice(2),o={};while(args.length){const k=args.shift(),v=args.shift();
  if(!['--bind','--peer','--port','--state','--reply','--error','--fragment','--delay-ms'].includes(k)||v===undefined||o[k]!==undefined)throw Error('Invalid/duplicate argument '+k);o[k]=v;}
 const bind=o['--bind'],peer=o['--peer'],port=Number(o['--port']);
 if(!privateIP(bind)||!privateIP(peer)||!Number.isInteger(port)||port<1||port>65535||!o['--state']||o['--reply']===undefined)throw Error('Usage: node LAN-SERVER.cjs --bind PC-PRIVATE-IP --peer MSX-PRIVATE-IP --port 8765 --state PC-CACHE-DIR --reply "Manual LAN response" [--error E_TEST] [--fragment 17 --delay-ms 5]');
 const fragment=Number(o['--fragment']||0),delay=Number(o['--delay-ms']||0);
 if(!Number.isInteger(fragment)||fragment<0||fragment>256||!Number.isInteger(delay)||delay<0||delay>100)throw Error('Invalid fragmentation settings');
 // Validate configured reply before listening.
 makeResponse({state:'pending',request_id:'00000001',message:'check',response_id:'',reply:'',error_code:'',conversation_id:'00000001'},o['--reply'],o['--error']||'');
 const cache=createCache(o['--state'],o['--reply'],o['--error']||'');
 const server=createServer({peer,cache,fragment,delay,log:value=>console.log(JSON.stringify(value))});
 server.on('error',e=>{console.error(e.code||e.message);process.exitCode=1;});
 server.listen(port,bind,()=>console.log('Listening '+bind+':'+port+'; allowed MSX '+peer+'; manual replies only, no API.'));
 for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close());
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={createCache,createHandler,createServer,privateIP};
