// Explicit live smoke test: no call without --live and PC-only env credentials.
'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const {clientFromEnv}=require('../GATEWAY.cjs');
const base=path.resolve(__dirname,'..');
async function main(){
 let report={status:'NOT_RUN',liveOpenAI:false,reason:'Pass --live after configuring OPENAI_API_KEY and OPENAI_MODEL on the PC.'};
 if(process.argv.includes('--live')){
  let client;
  try{client=clientFromEnv();}catch(e){report.reason=e.code||'E_CONFIG';await save(report);process.exitCode=2;return;}
  try{
   const result=await client.generate([{role:'user',content:'Responda somente com a palavra OK.'}]);
   report={status:result.error?'FAIL':'PASS',liveOpenAI:true,model:client.model,api_status:result.apiStatus,
    api_response_id:result.apiResponseId,request_id:result.requestId,error_code:result.error,reply:result.text,usage:result.usage};
   if(result.error)process.exitCode=1;
  }catch(e){
   report={status:'FAIL',liveOpenAI:true,model:client.model,error_code:e.code||'E_API',request_id:e.requestId||'',ambiguous:!!e.ambiguous};
   process.exitCode=1;
  }
 }
 await save(report);
}
async function save(report){await fs.writeFile(path.join(base,'LIVE-API-RESULTS.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));}
main().catch(()=>{console.error('E_SMOKE_FILE');process.exitCode=1;});
