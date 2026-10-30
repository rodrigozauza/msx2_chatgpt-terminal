'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {parseEnvelope,makeResponse,publish}=require('../make-response.cjs');
async function main(){
 const base=path.resolve(__dirname,'..'),results=[];
 async function test(name,fn){await fn();results.push({test:name,status:'PASS'});}
 const request=parseEnvelope(await fs.readFile(path.join(base,'examples/00000001.REQ'))),raw=JSON.stringify(request);
 await test('Read generated-format request',()=>assert.equal(request.state,'pending'));
 await test('Duplicate field rejected',()=>assert.throws(()=>parseEnvelope(Buffer.from(raw.replace(/}$/,',"message":"duplicate"}')))));
 await test('Nested value rejected',()=>assert.throws(()=>parseEnvelope(Buffer.from(raw.replace('"pending"','{}')))));
 await test('Trailing data rejected',()=>assert.throws(()=>parseEnvelope(Buffer.from(raw+'x'))));
 await test('Unpaired surrogate rejected',()=>assert.throws(()=>parseEnvelope(Buffer.from(raw.replace('Olá','\\uD800')))));
 await test('Invalid UTF8 rejected',()=>assert.throws(()=>parseEnvelope(Buffer.from([0xc0,0xaf]))));
 await test('BOM rejected',()=>assert.throws(()=>parseEnvelope(Buffer.concat([Buffer.from([239,187,191]),Buffer.from(raw)]))));
 await test('Oversize reply rejected',()=>assert.throws(()=>makeResponse(request,'x'.repeat(2048))));
 await test('Non-ASCII error code rejected',()=>assert.throws(()=>makeResponse(request,'ok','é')));
 await test('Remote error fixture accepted',()=>assert.equal(makeResponse(request,'','E_TEST').state,'error'));
 const tempRoot=path.resolve(process.argv[2]||os.tmpdir());
 await fs.mkdir(tempRoot,{recursive:true});
 const dir=await fs.mkdtemp(path.join(tempRoot,'msxchat-phase2-'));
 try{
  const source=path.join(dir,'00000001.REQ');await fs.writeFile(source,raw);
  let target;
  await test('Real file stage/sync/rename publication',async()=>{
   target=await publish(source,'Teste ação\nSegundo parágrafo.');
   assert.equal(parseEnvelope(await fs.readFile(target)).reply,'Teste ação\nSegundo parágrafo.');
  });
  await test('Published RSP cannot be overwritten',async()=>{
   await assert.rejects(()=>publish(source,'overwritten'));
   assert.equal(parseEnvelope(await fs.readFile(target)).reply,'Teste ação\nSegundo parágrafo.');
  });
 }finally{
  const resolved=path.resolve(dir);
  assert.ok(path.dirname(resolved)===tempRoot&&path.basename(resolved).startsWith('msxchat-phase2-'));
  await fs.rm(resolved,{recursive:true,force:true});
 }
 const result={scope:'Node filesystem and manual offline fixture publisher; no network',results};
 await fs.writeFile(path.join(base,'HELPER-RESULTS.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify({passed:results.length,total:results.length,scope:result.scope},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
