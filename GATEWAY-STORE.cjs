// GATEWAY-STORE.cjs -- durable reservation/start/result journal, one API dispatch.
'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto'),net=require('node:net');
const {parseEnvelope,makeResponse}=require('./make-response.cjs');
const {bounded,textSafe}=require('./OPENAI-CLIENT.cjs');
const FIELDS=['protocol','request_id','conversation_id','state','message','response_id','reply','error_code'];
function error(code,status=503){return Object.assign(Error(code),{code,status});}
const digest=req=>crypto.createHash('sha256').update(JSON.stringify(FIELDS.map(k=>req[k]))).digest('hex');
async function readJSON(p){
 const st=await fs.lstat(p);if(!st.isFile()||st.isSymbolicLink()||st.size>1048576)throw error('E_STATE');
 return JSON.parse(await fs.readFile(p,'utf8'));
}
async function present(p){try{await fs.lstat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function writeNew(p,value){
 const file=await fs.open(p,'wx',0o600);
 try{await file.writeFile(JSON.stringify(value)+'\n');await file.sync();}finally{await file.close();}
}
const messages={
 E_AMBIGUOUS:'Chamada anterior pode ter sido enviada antes da interrupcao. Nenhuma repeticao automatica foi feita. Verifique o registro no PC.',
 E_API_TIMEOUT:'A chamada excedeu o tempo limite. O resultado pode ser incerto. Nenhuma nova chamada foi feita automaticamente.',
 E_API_NETWORK:'A conexao HTTPS falhou. O resultado pode ser incerto. Nenhuma nova chamada foi feita automaticamente.',
 E_API_AUTH:'A API recusou a chave. Corrija OPENAI_API_KEY no PC e envie uma nova pergunta com novo ID.',
 E_API_ACCESS:'A API recusou o acesso. Confira projeto e modelo no PC.',
 E_API_MODEL:'Modelo ou recurso indisponivel. Confira OPENAI_MODEL no PC.',
 E_API_RATE:'A API limitou o uso ou a cota. Confira os limites no PC antes de novo pedido.',
 E_API_REQUEST:'A API recusou os parametros. Confira o modelo e as opcoes no PC.',
 E_API_SERVICE:'A API retornou falha de servico. Nenhuma repeticao automatica foi feita.',
 E_API_CONFLICT:'A API informou conflito. Verifique o registro no PC.',
 E_API_SIZE:'A resposta da API excedeu o limite do gateway.',
 E_API_FORMAT:'A resposta da API nao tinha o formato esperado.',
 E_CONFIG_CHANGED:'A configuracao mudou antes do envio. O pedido nao foi enviado. Use novo ID depois de conferir a configuracao.',
 E_STATE:'Falha no diario do gateway. Preserve os arquivos e verifique o PC.'
};
function checkedRequest(bytes){
 const req=parseEnvelope(bytes);makeResponse(req,'validate');return req;
}
function checkedResult(job,done){
 if(done.schema!=='msxchat-openai-done/1'||done.request_sha256!==job.request_sha256)throw error('E_STATE');
 const r=parseEnvelope(Buffer.from(JSON.stringify(done.result)));
 if(r.request_id!==job.request.request_id||r.response_id!==job.request.request_id||r.message||
   !['completed','error'].includes(r.state)||(r.state==='completed'&&(!r.reply||r.error_code))||(r.state==='error'&&!r.error_code))throw error('E_STATE');
 return r;
}
async function openStore({directory,peer,provider,maxContextTurns=8,maxContextChars=16000,maxPending=8}){
 if(!net.isIPv4(peer)||!provider||typeof provider.generate!=='function')throw error('E_CONFIG',400);
 const folder=path.resolve(directory),jobs=path.join(folder,'jobs'),prefix=peer.replace(/\./g,'_')+'-';
 await fs.mkdir(folder,{recursive:true});
 const lockPath=path.join(folder,'gateway.lock'),lockToken=crypto.randomUUID();
 try{await writeNew(lockPath,{pid:process.pid,token:lockToken,started:new Date().toISOString()});}
 catch(e){throw error('E_LOCK');}
 let closing=false,workerTail=Promise.resolve(),gate=Promise.resolve();
 const active=new Map(),configId=provider.fingerprint||provider.model||'test-provider';
 const serial=fn=>{const task=gate.then(fn);gate=task.catch(()=>{});return task;};
 const key=req=>prefix+req.request_id;
 const jobPath=k=>path.join(jobs,k+'.job.json'),startPath=k=>path.join(jobs,k+'.started.json'),donePath=k=>path.join(jobs,k+'.done.json');
 async function unlock(){const saved=await readJSON(lockPath);if(saved.token!==lockToken)throw error('E_LOCK');await fs.unlink(lockPath);}
 try{
  const meta=path.join(folder,'GATEWAY-STATE.json');
  if(await present(meta)){
   const value=await readJSON(meta);if(value.schema!=='msxchat-openai-state/1'||value.peer!==peer||value.conversation_id!=='00000001')throw error('E_NAMESPACE');
  }else{
   const other=(await fs.readdir(folder)).filter(n=>n!=='gateway.lock');
   if(other.length)throw error('E_NAMESPACE');
   await writeNew(meta,{schema:'msxchat-openai-state/1',peer,conversation_id:'00000001'});
  }
  await fs.mkdir(jobs,{recursive:true});
 }catch(e){await unlock();throw error(e.code&&e.code.startsWith('E_')?e.code:'E_STATE');}
 async function loadJob(k){
  const job=await readJSON(jobPath(k));
  if(job.schema!=='msxchat-openai-job/1'||job.peer!==peer||!job.request)throw error('E_STATE');
  const req=checkedRequest(Buffer.from(JSON.stringify(job.request)));
  if(key(req)!==k||job.request_sha256!==digest(req))throw error('E_STATE');
  return job;
 }
 async function contextFor(job){
  const files=(await fs.readdir(jobs)).filter(n=>n.startsWith(prefix)&&n.endsWith('.done.json')).sort();
  const turns=[];
  for(let i=files.length-1;i>=0&&turns.length<maxContextTurns;i--){
   const k=files[i].slice(0,-'.done.json'.length);
   if(k>=key(job.request))continue;
   const previous=await loadJob(k),done=await readJSON(donePath(k)),result=checkedResult(previous,done);
   if(result.state==='completed')turns.push([{role:'user',content:textSafe(previous.request.message)},{role:'assistant',content:textSafe(result.reply)}]);
  }
  const out=[];let used=0;
  for(const pair of turns){
   const chars=pair.reduce((n,m)=>n+Array.from(m.content).length,0);
   if(used+chars>maxContextChars)break;
   used+=chars;out.unshift(...pair);
  }
  out.push({role:'user',content:textSafe(job.request.message)});return out;
 }
 async function finish(job,result,metadata={}){
  const done={schema:'msxchat-openai-done/1',request_sha256:job.request_sha256,result,metadata,finished:new Date().toISOString()};
  checkedResult(job,done);await writeNew(donePath(key(job.request)),done);return result;
 }
 async function finishError(job,code,metadata={}){
  if(!messages[code])code='E_API_FORMAT';
  return finish(job,makeResponse(job.request,messages[code],code),metadata);
 }
 async function runJob(job){
  const k=key(job.request);
  try{
   if(closing)return;
   if(job.config_id!==configId)return await finishError(job,'E_CONFIG_CHANGED');
   const input=await contextFor(job);
   if(closing)return;
   await writeNew(startPath(k),{schema:'msxchat-openai-started/1',client_request_id:job.client_request_id,
    model:job.model,context_messages:input.length,started:new Date().toISOString()});
   let value;
   try{value=await provider.generate(input,job.client_request_id);}
   catch(e){
    const code=messages[e.code]?e.code:'E_API_FORMAT';
    const safeId=typeof e.requestId==='string'&&/^[A-Za-z0-9_-]{1,256}$/.test(e.requestId)?e.requestId:'';
    return await finishError(job,code,{request_id:safeId,ambiguous:!!e.ambiguous,http_status:Number.isInteger(e.httpStatus)?e.httpStatus:null});
   }
   const result=makeResponse(job.request,bounded(textSafe(value.text)),value.error||'');
   return await finish(job,result,{api_response_id:value.apiResponseId||'',request_id:value.requestId||'',api_status:value.apiStatus||'',
    usage:value.usage||{},truncated:!!value.truncated,full_output_text:value.fullText||''});
  }catch(e){
   // A failed disk commit must never cause another external dispatch on a retry.
   // Existing partial files are preserved; next lookup returns E_STATE or ambiguity.
   if(!await present(donePath(k))){try{await finishError(job,'E_STATE',{ambiguous:await present(startPath(k))});}catch(ignored){}}
  }
 }
 function schedule(job){
  const k=key(job.request),task=workerTail.catch(()=>{}).then(()=>runJob(job));
  active.set(k,task);workerTail=task;
  task.finally(()=>active.delete(k)).catch(()=>{});
 }
 async function exchange(remote,bytes){
  if(remote!==peer)throw error('E_PEER',403);
  let req;try{req=checkedRequest(bytes);}catch(e){throw error('E_JSON',422);}
  return serial(async()=>{
   if(closing)throw error('E_STOPPING');
   const k=key(req),hash=digest(req);let job;
   try{
    if(await present(jobPath(k))){
     job=await loadJob(k);if(job.request_sha256!==hash)throw error('E_CONFLICT',409);
     if(await present(donePath(k)))return {response:checkedResult(job,await readJSON(donePath(k))),cached:true};
     if(active.has(k))return {processing:true};
     if(await present(startPath(k))){
      const response=await finishError(job,'E_AMBIGUOUS',{ambiguous:true});return {response,cached:true};
     }
    }else{
     const old=(await fs.readdir(jobs)).filter(n=>n.startsWith(prefix)&&n.endsWith('.job.json')).sort();
     if(old.length&&old[old.length-1].slice(prefix.length,prefix.length+8)>=req.request_id)throw error('E_ORDER',409);
     if(active.size>=maxPending)throw error('E_BUSY',429);
     job={schema:'msxchat-openai-job/1',peer,request:req,request_sha256:hash,config_id:configId,model:provider.model,
      client_request_id:crypto.randomUUID(),created:new Date().toISOString()};
     await writeNew(jobPath(k),job);
    }
    if(active.size>=maxPending)throw error('E_BUSY',429);
    schedule(job);return {processing:true};
   }catch(e){if(e.status)throw e;throw error('E_STATE');}
  });
 }
 async function idle(){await gate;await workerTail;}
 async function close(){closing=true;await idle();await unlock();}
 return {exchange,idle,close,folder,peer};
}
async function inspect(directory){
 const folder=path.resolve(directory),meta=await readJSON(path.join(folder,'GATEWAY-STATE.json'));
 if(meta.schema!=='msxchat-openai-state/1')throw error('E_NAMESPACE');
 const jobs=path.join(folder,'jobs'),records=[];
 for(const name of (await fs.readdir(jobs)).filter(n=>n.endsWith('.job.json')).sort()){
  const k=name.slice(0,-'.job.json'.length);let state='reserved',localError='';
  if(await present(path.join(jobs,k+'.done.json'))){
   try{const done=await readJSON(path.join(jobs,k+'.done.json'));state=done.result.state;localError=done.result.error_code;}catch(e){state='invalid';}
  }else if(await present(path.join(jobs,k+'.started.json')))state='started/ambiguous';
  records.push({request_id:k.slice(-8),state,error_code:localError});
 }
 return {peer:meta.peer,locked:await present(path.join(folder,'gateway.lock')),jobs:records};
}
module.exports={openStore,inspect,digest,checkedResult};
