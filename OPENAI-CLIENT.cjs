// OPENAI-CLIENT.cjs -- HTTPS only, one dispatch, no implicit SDK retries.
'use strict';
const https=require('node:https'),crypto=require('node:crypto');
const INSTRUCTIONS='Responda em portugues, de forma direta e em texto simples. O terminal MSX2 tem 80 colunas. Procure limitar a resposta a 1800 caracteres. Nao use ferramentas nem gere segredos. Responda ao pedido atual levando em conta apenas o contexto fornecido.';
function textSafe(s){return String(s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,' ').replace(/[\ue080-\ue0ff]/g,'?');}
function scalarValid(s){
 if(typeof s!=='string')return false;
 for(let i=0;i<s.length;i++){const c=s.charCodeAt(i);if(c>=0xd800&&c<=0xdbff){const d=s.charCodeAt(++i);if(!(d>=0xdc00&&d<=0xdfff))return false;}
 else if(c>=0xdc00&&c<=0xdfff)return false;}return true;
}
function bounded(s,limit=2047,marker='\n[TRUNCADO NO MSX]'){
 const a=Array.from(s);if(a.length<=limit)return s;return a.slice(0,limit-Array.from(marker).length).join('')+marker;
}
function apiError(code,extra={}){return Object.assign(Error(code),{code,...extra});}
function createOpenAIClient({apiKey,model,maxOutputTokens=1024,timeoutMs=90000,reasoningEffort,requestImpl=https.request}){
 if(typeof apiKey!=='string'||!apiKey.trim()||/[\r\n]/.test(apiKey))throw apiError('E_CONFIG_KEY');
 if(typeof model!=='string'||!/^[-a-zA-Z0-9._:]{1,120}$/.test(model)||/^sk-/i.test(model)||model.includes(apiKey))throw apiError('E_CONFIG_MODEL');
 if(!Number.isInteger(maxOutputTokens)||maxOutputTokens<16||maxOutputTokens>8192)throw apiError('E_CONFIG_TOKENS');
 if(!Number.isInteger(timeoutMs)||timeoutMs<1000||timeoutMs>120000)throw apiError('E_CONFIG_TIMEOUT');
 if(reasoningEffort&&!['none','minimal','low','medium','high','xhigh'].includes(reasoningEffort))throw apiError('E_CONFIG_REASONING');
 const redact=s=>String(s).split(apiKey).join('[SEGREDO REMOVIDO]');
 const identifier=s=>typeof s==='string'&&/^[A-Za-z0-9_-]{1,256}$/.test(s)&&!s.includes(apiKey)?s:'';
 function build(input){
  const body={model,instructions:INSTRUCTIONS,input:input.map(m=>({role:m.role,content:textSafe(m.content)})),
   max_output_tokens:maxOutputTokens,store:false,stream:false};
  if(reasoningEffort)body.reasoning={effort:reasoningEffort};
  return body;
 }
 async function generate(input,clientRequestId=crypto.randomUUID()){
  const payload=Buffer.from(JSON.stringify(build(input)),'utf8');
  return new Promise((resolve,reject)=>{
   let settled=false,timer,response,req;
   const fail=(code,extra={})=>{if(settled)return;settled=true;clearTimeout(timer);if(response)response.destroy();if(req)req.destroy();reject(apiError(code,extra));};
   const options={hostname:'api.openai.com',port:443,path:'/v1/responses',method:'POST',
    rejectUnauthorized:true,minVersion:'TLSv1.2',agent:false,
    headers:{'Authorization':'Bearer '+apiKey,'Content-Type':'application/json','Content-Length':payload.length,
      'Accept':'application/json','Connection':'close','X-Client-Request-Id':clientRequestId}};
   try{
    req=requestImpl(options,res=>{
     response=res;let total=0;const pieces=[];
     const status=res.statusCode,requestId=identifier(res.headers['x-request-id']);
     if(status<200||status>=300){
      const codes={400:'E_API_REQUEST',401:'E_API_AUTH',403:'E_API_ACCESS',404:'E_API_MODEL',408:'E_API_TIMEOUT',409:'E_API_CONFLICT',429:'E_API_RATE'};
      return fail(codes[status]||'E_API_SERVICE',{httpStatus:status,requestId,ambiguous:status>=500||status===408});
     }
     res.on('data',chunk=>{total+=chunk.length;if(total>1048576)return fail('E_API_SIZE',{requestId,ambiguous:true});pieces.push(Buffer.from(chunk));});
     res.on('aborted',()=>fail('E_API_NETWORK',{requestId,ambiguous:true}));
     res.on('error',()=>fail('E_API_NETWORK',{requestId,ambiguous:true}));
     res.on('end',()=>{
      if(settled)return;
      try{
       const raw=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(pieces)),data=JSON.parse(raw);
       if(!data||typeof data!=='object'||!Array.isArray(data.output)||!['completed','incomplete','failed','cancelled'].includes(data.status))throw Error('schema');
       const texts=[],refusals=[];
       for(const item of data.output){
        if(item&&item.type==='message'&&item.role==='assistant'&&Array.isArray(item.content)){
         for(const part of item.content){
          if(part&&part.type==='output_text'){if(!scalarValid(part.text))throw Error('scalar');texts.push(part.text);}
          if(part&&part.type==='refusal'){if(!scalarValid(part.refusal))throw Error('scalar');refusals.push(part.refusal);}
         }
        }
       }
       const fullText=redact(textSafe(texts.join('\n'))),refusal=redact(textSafe(refusals.join('\n')));
       let code='',text=fullText;
       if(data.status==='incomplete'){code='E_OUTPUT_LIMIT';text=(fullText||'A API nao concluiu a resposta.')+'\n[RESPOSTA INCOMPLETA]';}
       else if(data.status!=='completed'){code='E_API_FAILED';text='A API nao concluiu o processamento.';}
       else if(refusal){code='E_REFUSAL';text=refusal;}
       else if(!fullText.trim()){code='E_EMPTY';text='A API nao retornou texto para exibir.';}
       const usage={};
       for(const name of ['input_tokens','output_tokens','total_tokens']){
        const value=data.usage&&data.usage[name];if(Number.isSafeInteger(value)&&value>=0)usage[name]=value;
       }
       settled=true;clearTimeout(timer);
       resolve({text:bounded(text),error:code,fullText:Array.from(fullText).slice(0,65536).join(''),
        apiResponseId:identifier(data.id),requestId,apiStatus:data.status,usage,truncated:Array.from(fullText).length>2047});
      }catch(e){fail('E_API_FORMAT',{requestId,ambiguous:true});}
     });
    });
    req.on('error',()=>fail('E_API_NETWORK',{ambiguous:true}));
    timer=setTimeout(()=>fail('E_API_TIMEOUT',{ambiguous:true}),timeoutMs);
    req.end(payload);
   }catch(e){fail('E_API_NETWORK',{ambiguous:true});}
  });
 }
 return {generate,build,model,maxOutputTokens,fingerprint:crypto.createHash('sha256').update(JSON.stringify({model,maxOutputTokens,reasoningEffort:reasoningEffort||null})).digest('hex')};
}
module.exports={createOpenAIClient,bounded,textSafe,scalarValid};
