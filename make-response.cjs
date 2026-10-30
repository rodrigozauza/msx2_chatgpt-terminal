// Offline fixture publisher. No network or OpenAI calls.
'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const fields=['protocol','request_id','conversation_id','state','message','response_id','reply','error_code'];
function scalarString(s){
 for(let i=0;i<s.length;i++){
  const c=s.charCodeAt(i);
  if(c>=0xd800&&c<=0xdbff){const n=s.charCodeAt(++i);if(!(n>=0xdc00&&n<=0xdfff))throw Error('Unpaired high surrogate');}
  else if(c>=0xdc00&&c<=0xdfff)throw Error('Unpaired low surrogate');
 }
}
function parseEnvelope(bytes){
 if(bytes.length>32767)throw Error('File exceeds 32767 bytes');
 const raw=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes);
 if(raw.charCodeAt(0)===0xfeff)throw Error('BOM is not supported');
 let i=0;const out={};
 const ws=()=>{while(/[ \t\r\n]/.test(raw[i]||'x'))i++;};
 const take=c=>{ws();if(raw[i++]!==c)throw Error('Expected '+c);};
 function string(){
  ws();const start=i;if(raw[i++]!=='"')throw Error('String value required');
  let closed=false;
  while(i<raw.length){const c=raw[i++];if(c==='\\'){i++;continue;}if(c==='"'){closed=true;break;}}
  if(!closed)throw Error('Unterminated string');
  const value=JSON.parse(raw.slice(start,i));scalarString(value);return value;
 }
 take('{');
 for(;;){
  const key=string();if(!fields.includes(key)||Object.hasOwn(out,key))throw Error('Unknown or duplicate field');
  take(':');out[key]=string();ws();
  if(raw[i]===','){i++;continue;}
  if(raw[i]==='}'){i++;break;}
  throw Error('Expected comma or closing brace');
 }
 ws();if(i!==raw.length||Object.keys(out).length!==8)throw Error('Incomplete or extra JSON data');
 if(out.protocol!=='msxchat/1'||out.conversation_id!=='00000001')throw Error('Unsupported protocol/conversation');
 for(const key of ['request_id','response_id']){
  if(out[key]!==''&&!/^[0-9A-F]{8}$/.test(out[key]))throw Error('Invalid '+key);
 }
 if(!/^[\x20-\x7e]{0,31}$/.test(out.error_code))throw Error('Invalid error code');
 for(const key of ['message','reply'])if(Array.from(out[key]).length>2047)throw Error('Text limit exceeded');
 return out;
}
function makeResponse(request,text,error='',responseId=request.request_id){
 if(request.state!=='pending'||request.request_id==='00000000'||!/^0000[0-9A-F]{4}$/.test(request.request_id)||
    !request.message||request.response_id||request.reply||request.error_code)throw Error('Input must be a valid pending request');
 scalarString(text);
 if(Array.from(text).length>2047||(!error&&!text))throw Error('Reply must contain 1..2047 Unicode scalar values');
 if(!/^[\x20-\x7e]{0,31}$/.test(error))throw Error('Error code must be printable ASCII, at most 31 bytes');
 if(!/^[0-9A-F]{8}$/.test(responseId)||responseId==='00000000')throw Error('Invalid response ID');
 return {protocol:'msxchat/1',request_id:request.request_id,conversation_id:request.conversation_id,
  state:error?'error':'completed',message:'',response_id:responseId,reply:text,error_code:error};
}
async function exists(p){try{await fs.access(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function publish(requestPath,text,error='',responseId){
 const source=path.resolve(requestPath);
 const request=parseEnvelope(await fs.readFile(source));
 const name=path.basename(source);
 if(name.toUpperCase()!==request.request_id+'.REQ')throw Error('Filename does not match request_id');
 const value=makeResponse(request,text,error,responseId);
 const raw=Buffer.from(JSON.stringify(value)+'\r\n','utf8');
 if(raw.length>32767)throw Error('Response file exceeds 32767 bytes');
 const target=path.join(path.dirname(source),request.request_id+'.RSP');
 const stage=path.join(path.dirname(source),request.request_id+'.NEW');
 if(await exists(target))throw Error('RSP already exists; it will not be overwritten');
 const file=await fs.open(stage,'wx');
 try{await file.writeFile(raw);await file.sync();}finally{await file.close();}
 if(await exists(target))throw Error('RSP appeared during publication; NEW preserved');
 // One publisher only. Rename is within the same volume; retain NEW on failure.
 await fs.rename(stage,target);
 return target;
}
async function main(){
 const args=process.argv.slice(2),request=args.shift();let text,code='',id;
 while(args.length){const flag=args.shift(),value=args.shift();if(value===undefined)throw Error('Missing argument');
  if(flag==='--text'&&text===undefined)text=value;else if(flag==='--error'&&!code)code=value;
  else if(flag==='--response-id'&&id===undefined)id=value;else throw Error('Unknown or duplicate option '+flag);
 }
 if(!request||text===undefined)throw Error('Usage: node make-response.cjs 00000001.REQ --text "Offline reply" [--error E_TEST] [--response-id 00000001]');
 console.log(await publish(request,text,code,id));
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={parseEnvelope,makeResponse,publish};
