// GATEWAY.cjs -- LAN HTTP -> durable queue -> fixed OpenAI HTTPS Responses endpoint.
'use strict';
const fs=require('node:fs/promises');
const {createOpenAIClient}=require('./OPENAI-CLIENT.cjs');
const {openStore,inspect}=require('./GATEWAY-STORE.cjs');
const {createServer,privateIP}=require('./LAN-SERVER.cjs');
function cliOptions(args){
 const o={};
 while(args.length){
  const k=args.shift();
  if(['--inspect','--check-config'].includes(k)){if(o[k])throw Error('E_ARGS');o[k]=true;continue;}
  const v=args.shift();if(!['--bind','--peer','--port','--state'].includes(k)||v===undefined||o[k]!==undefined)throw Error('E_ARGS');o[k]=v;
 }
 return o;
}
function clientFromEnv(env=process.env,extra={}){
 if(/http|\*/i.test(env.NODE_DEBUG||''))throw Object.assign(Error('E_CONFIG_DEBUG'),{code:'E_CONFIG_DEBUG'});
 if(env.NODE_TLS_REJECT_UNAUTHORIZED==='0')throw Object.assign(Error('E_CONFIG_TLS'),{code:'E_CONFIG_TLS'});
 return createOpenAIClient({apiKey:env.OPENAI_API_KEY,model:env.OPENAI_MODEL,
  maxOutputTokens:env.GATEWAY_MAX_OUTPUT_TOKENS?Number(env.GATEWAY_MAX_OUTPUT_TOKENS):1024,
  timeoutMs:env.GATEWAY_API_TIMEOUT_MS?Number(env.GATEWAY_API_TIMEOUT_MS):90000,
  reasoningEffort:env.OPENAI_REASONING_EFFORT||undefined,...extra});
}
async function main(){
 const o=cliOptions(process.argv.slice(2));
 if(o['--inspect']){
  if(!o['--state'])throw Error('E_ARGS');
  console.log(JSON.stringify(await inspect(o['--state']),null,2));return;
 }
 const provider=clientFromEnv();
 if(o['--check-config']){console.log(JSON.stringify({configured:true,model:provider.model,max_output_tokens:provider.maxOutputTokens,key:'present; value never printed'}));return;}
 const bind=o['--bind'],peer=o['--peer'],port=Number(o['--port']);
 if(!privateIP(bind)||!privateIP(peer)||!Number.isInteger(port)||port<1||port>65535||!o['--state'])throw Error('E_ARGS');
 const store=await openStore({directory:o['--state'],peer,provider});
 const server=createServer({peer,cache:store,log:entry=>console.log(JSON.stringify(entry))});
 try{
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,bind,resolve);});
 }catch(e){await store.close();throw e;}
 console.log('Listening '+bind+':'+port+'; peer '+peer+'; model '+provider.model+'; API key stays on this PC.');
 let stopping=false;
 async function stop(){
  if(stopping)return;stopping=true;
  console.log('Stopping listener; waiting for already reserved API work.');
  await new Promise(resolve=>server.close(resolve));
  try{await store.close();}catch(e){console.error('E_STATE_CLOSE: preserve the journal and lock for inspection.');process.exitCode=1;}
 }
 for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>stop().catch(()=>{console.error('E_STOP');process.exitCode=1;}));
}
if(require.main===module)main().catch(e=>{
 const code=/^E_[A-Z_]+$/.test(e.code||e.message)?(e.code||e.message):'E_START';
 console.error(code+': configure OPENAI_API_KEY and OPENAI_MODEL on the PC; use --bind PRIVATE-IP --peer MSX-IP --port 8765 --state NEW-PC-DIRECTORY.');
 process.exitCode=1;
});
module.exports={clientFromEnv,cliOptions};
