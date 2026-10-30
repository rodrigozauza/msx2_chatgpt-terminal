// Execute the real MSXCHAT.COM instructions. BIOS/VDP transfers are simulated.
// CPU emulator: Z80.js (MIT). This is NOT a complete MSX emulator or physical test.
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),zlib=require('node:zlib');
const base=path.resolve(__dirname,'..');
const ctx={window:{}};vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname,'Z80.js'),'utf8'),ctx);
const binary=fs.readFileSync(path.join(base,'MSXCHAT.COM'));
const font=fs.readFileSync(path.join(base,'FONT8X8.bin'));
const symbols=Object.fromEntries(fs.readFileSync(path.join(base,'MSXCHAT.MAP'),'utf8').trim().split(/\r?\n/).map(line=>{
 const at=line.indexOf('=');return [line.slice(at+1),parseInt(line.slice(0,at),16)];
}));
const spec=JSON.parse(fs.readFileSync(path.join(base,'src/FONTSPEC.json'),'utf8'));
const unicodeMap=Object.fromEntries(Object.entries(spec.accents).map(([code,entry])=>[entry[2],Number(code)]));
function encode(s){return Buffer.from(Array.from(s,ch=>ch.charCodeAt(0)<128?ch.charCodeAt(0):unicodeMap[ch]===undefined?63:unicodeMap[ch]));}
function crc32(data){let c=0xffffffff;for(const b of data){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function pngChunk(name,data){const tag=Buffer.from(name);const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(Buffer.concat([tag,data])));return Buffer.concat([len,tag,data,crc]);}
const palette=[[0,0,0],[0,0,0],[33,200,66],[94,220,120],[84,85,237],[125,118,252],[212,82,77],[66,235,245],[252,85,84],[255,121,120],[212,193,84],[230,206,128],[33,176,59],[201,91,186],[204,204,204],[255,255,255]];
function savePNG(vram,file,scale=3,displayAspect=false){
 const width=displayAspect?Math.round(212*scale*4/3):512*scale,height=212*scale;
 const raw=Buffer.alloc((width*3+1)*height);
 for(let y=0;y<height;y++){const sy=Math.floor(y/scale),r=sy>>3,s=sy&7;let off=y*(width*3+1)+1;
  for(let x=0;x<width;x++){const sx=Math.floor(x*512/width),tile=sx>>3;
   const packed=vram[sy*256+(sx>>1)];
   const index=(sx&1)?packed&15:packed>>4;
   for(const byte of palette[index])raw[off++]=byte;
  }
 }
 const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width,0);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=2;
 fs.writeFileSync(path.join(base,file),Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),pngChunk('IHDR',ihdr),pngChunk('IDAT',zlib.deflateSync(raw)),pngChunk('IEND',Buffer.alloc(0))]));
}
function machine(opts={}){
 const mem=new Uint8Array(65536);mem.set(binary,256);
 const regs=Uint8Array.from([...(opts.regs||[0,0x70,0,0,1,0x36,7,4]),...(opts.extRegs||Array(16).fill(0))]);
 const originalRegs=Buffer.from(regs);
 mem.set(regs.slice(0,8),0xf3df);mem.set(regs.slice(8),0xffe7);mem[0xfafc]=opts.vramMode===undefined?4:opts.vramMode;mem[0xfaf6]=opts.acpage||0;mem[0xfcaf]=opts.mode||0;mem[0xf3de]=opts.cnsdfg||0;
 const originalMode=mem[0xfcaf],originalCNS=mem[0xf3de];
 mem[0xfcc0]=0x5a;mem[0xfcc1]=0x80;
 const tpa=opts.tpa||0xf000;mem[6]=tpa&255;mem[7]=tpa>>8;
 const vram=Uint8Array.from({length:131072},(_,i)=>(i*37+(i>>8)*17+5)&255);
 const originalVRAM=Buffer.from(vram);
 let key=null,steps=0,output='',exited=false;
 const transfers=[],registerWrites=[];
 const core={
  mem_read:a=>mem[a&65535],
  mem_write:(a,v)=>{
   a&=65535;
   assert.ok((a>=256&&a<256+binary.length)||(a>=0x4000&&a<0xc000)||(a>=(opts.sp||0xf000)-4096&&a<(opts.sp||0xf000))||
     (a>=0xf3df&&a<0xf3e7)||(a>=0xffe7&&a<0xfff7)||a===0xfaf6||(a>=0xf847&&a<0xf857)||a===0xfcaf||a===0xf3de,'Unexpected memory write '+a.toString(16));
   mem[a]=v;
  },
  io_read:p=>{throw Error('Unexpected direct IN '+p);},
  io_write:p=>{throw Error('Unexpected direct OUT '+p);}
 };
 const cpu=new ctx.Z80(core);
 let state=cpu.getState();state.pc=256;state.sp=opts.sp||0xf000;state.iff1=1;state.iff2=1;cpu.setState(state);
 const get16=a=>mem[a]|mem[a+1]<<8;
 const put16=(a,v)=>{mem[a]=v&255;mem[a+1]=v>>8&255;};
 const hl=s=>s.h<<8|s.l,de=s=>s.d<<8|s.e,bc=s=>s.b<<8|s.c;
 function ret(s){s.pc=get16(s.sp);s.sp=s.sp+2&65535;cpu.setState(s);}
 function clobber(s){s.a=0xa5;s.b=0xa5;s.c=0xa5;s.d=0xa5;s.e=0xa5;s.h=0xa5;s.l=0xa5;s.ix=0xa5a5;s.iy=0xa5a5;}
  const files=new Map(Object.entries(opts.files||{}).map(([name,data])=>[name,Buffer.from(data)]));
  let dta=0x80;
  const fsCalls=[];
  function fcbName(at){return Buffer.from(mem.slice(at,at+8)).toString('ascii').trimEnd()+'.'+Buffer.from(mem.slice(at+8,at+11)).toString('ascii').trimEnd();}
  const get32=at=>(mem[at]|mem[at+1]<<8|mem[at+2]<<16|mem[at+3]<<24)>>>0;
  const put32=(at,v)=>{for(let k=0;k<4;k++)mem[at+k]=v>>>(k*8)&255;};
  function dos(s){
    const fn=s.c,ptr=de(s),n=hl(s);
    if(fn===6){output+=String.fromCharCode(s.e);ret(s);return;}
    assert.ok(fn<0x40,'No DOS2-only functions');
    assert.deepEqual(Buffer.from(regs),originalRegs,'DOS video restored before file operations');
    const name=[0x0f,0x10,0x13,0x16,0x17,0x26,0x27].includes(fn)?fcbName(ptr+1):'';
    assert.ok(!name.includes('?'),'No wildcard mutations');
    fsCalls.push({fn,name,n,dta,rename:fn===0x17?fcbName(ptr+17):undefined});
    const fail=opts.failFS&&opts.failFS(fn,name,fsCalls);
    const pos=get32(ptr+33);
    clobber(s);s.a=0;s.l=0;
    if(fn===0x1a){dta=ptr;}
    else if(fn===0x0d){dta=0x80;}
    else if(fn===0x0f){
      if(!files.has(name)||fail){s.a=255;s.l=255;}
      else{put32(ptr+16,files.get(name).length);put16(ptr+14,128);}
    }else if(fn===0x16){
      if(fail||opts.readonly){s.a=255;s.l=255;}
      else{files.set(name,Buffer.alloc(0));put32(ptr+16,0);put16(ptr+14,128);}
    }else if(fn===0x10){if(fail){s.a=255;s.l=255;}}
    else if(fn===0x13){
      if(fail||opts.readonly||!files.has(name)){s.a=255;s.l=255;}
      else files.delete(name);
    }else if(fn===0x17){
      const target=fcbName(ptr+17);
      if(fail||opts.readonly||!files.has(name)||files.has(target)){s.a=255;s.l=255;}
      else{files.set(target,files.get(name));files.delete(name);}
    }else if(fn===0x26){
      assert.equal(get16(ptr+14),1);assert.ok(n>0&&n<=256);assert.equal(dta,0xb000);
      if(fail||opts.readonly){s.a=1;s.l=1;}
      else{
        const old=files.get(name);assert.ok(old);
        const value=Buffer.alloc(Math.max(old.length,pos+n));old.copy(value);
        Buffer.from(mem.slice(dta,dta+n)).copy(value,pos);files.set(name,value);
        put32(ptr+33,pos+n);put32(ptr+16,value.length);
      }
    }else if(fn===0x27){
      assert.equal(get16(ptr+14),1);assert.ok(n>0&&n<=256);assert.equal(dta,0xb000);
      const data=files.get(name);assert.ok(data);
      const actual=Math.max(0,Math.min(n,data.length-pos)-(fail?1:0));
      mem.set(data.subarray(pos,pos+actual),dta);put32(ptr+33,pos+actual);
      s.h=actual>>8;s.l=actual&255;s.a=actual===n?0:1;
    }else throw Error('Unexpected DOS function '+fn.toString(16));
    ret(s);
  }


 const netopt=opts.network||{},netlog={calls:[],sent:Buffer.alloc(0),open:0,closed:false,aborts:0},argOriginal=Buffer.from(mem.slice(0xf847,0xf857));
 let netRemaining=Buffer.from(netopt.wire||''),netFragment=0,netStates=0,sendTries=0;
 netlog.setWire=wire=>{netRemaining=Buffer.from(wire);netFragment=0;netStates=0;netlog.closed=false;};
 mem[0xfb20]=opts.network&&!netopt.noExt?1:0;
 if(opts.cmd){mem[0x80]=opts.cmd.length;mem.set(Buffer.from(opts.cmd),0x81);}
 function netAPI(s){
  const fn=s.a,ib=s.b,ic=s.c,p=hl(s),data=de(s);
  netlog.calls.push(fn);
  const outBC=v=>{s.b=v>>8&255;s.c=v&255;},outHL=v=>{s.h=v>>8&255;s.l=v&255;},outDE=v=>{s.d=v>>8&255;s.e=v&255;};
  clobber(s);s.a=0;
  if(fn===0){outBC(0x0203);outDE(netopt.badVersion?0x0200:0x0101);outHL(0xc800);}
  else if(fn===1){assert.equal(ib,1);outHL(netopt.noActive?0:8);outDE(netopt.blocking?0x0800:0);}
  else if(fn===13){
   assert.equal(p,0xb700);assert.equal(get16(p+6),65535);assert.equal(mem[p+10],0);
   netlog.open++;if(netopt.openError)s.a=netopt.openError;else s.b=37;
  }else if(fn===16){
   assert.equal(ib,37);assert.equal(p,0);netStates++;
   if(netlog.closed){if(netopt.closeStall)s.b=6;else s.a=11;}
   else if(netopt.stateError)s.a=netopt.stateError;
   else s.b=netopt.neverConnect?2:netopt.state===undefined?(netRemaining.length===0&&!netopt.noEOF&&netlog.sent.length?7:4):netopt.state;
  }else if(fn===17){
   assert.equal(ib,37);assert.equal(ic,1);assert.equal(data,0xb600);assert.ok(p>0&&p<=256);
   sendTries++;
   if(netopt.sendError)s.a=netopt.sendError;
   else if(netopt.bufferBusy&&(sendTries<=netopt.bufferBusy))s.a=13;
   else netlog.sent=Buffer.concat([netlog.sent,Buffer.from(mem.slice(data,data+p))]);
  }else if(fn===18){
   assert.equal(ib,37);assert.equal(data,0xb400);assert.equal(p,256);
   if(netopt.receiveError)s.a=netopt.receiveError;
   else if(netopt.badLength){outBC(257);outHL(0);}
   else if(netopt.urgent){outBC(0);outHL(1);}
   else{
    const sizes=netopt.fragments||[1,2,17,256,3,0,41],max=sizes[netFragment++%sizes.length];
    const n=Math.min(netRemaining.length,max,256);
    mem.set(netRemaining.subarray(0,n),data);netRemaining=netRemaining.subarray(n);
    outBC(n);outHL(0);
   }
  }else if(fn===14){assert.equal(ib,37);if(netopt.closeError)s.a=netopt.closeError;else netlog.closed=true;}
  else if(fn===15){assert.equal(ib,37);netlog.aborts++;if(netopt.abortError)s.a=netopt.abortError;}
  else if(fn===29){if(netopt.waitError)s.a=netopt.waitError;}
  else throw Error('Unexpected network function '+fn);
  ret(s);
 }
 function netExt(s){
  assert.ok(s.sp>=0xc000);assert.equal(de(s),0x2222);
  if(s.a===255){s.a=3;s.h=netopt.noHelper?0:0xc1;s.l=0;s.b=0;s.c=0;}
  else{
   assert.equal(Buffer.from(mem.slice(0xf847,0xf84e)).toString(),'TCP/IP\0');
   if(s.a===0)s.b=netopt.noTcp?0:1;
   else{assert.equal(s.a,1);s.a=3;s.b=netopt.rom?255:5;
    s.h=netopt.badEntry?0x80:netopt.direct?0xc7:0x40;s.l=netopt.direct?0x20:0x20;}
  }
  ret(s);
 }

 function step(){
  const s=cpu.getState();steps++;
  if(s.pc===0){exited=true;return;}
  if(s.pc===0x0c){assert.equal(hl(s),0x2d);assert.equal(s.a,0x80);s.a=opts.generation===undefined?1:opts.generation;ret(s);return;}
  if(s.pc===5){dos(s);return;}
  if(s.pc===0xffca){netExt(s);return;}
  if(s.pc===0xc100||s.pc===0xc720||(s.pc===0x1c&&s.ix===0x4020)){netAPI(s);return;}
  if(s.pc===0x1c){
   assert.equal(s.iy>>8,0x80,'Main ROM slot from EXPTBL');
   assert.ok(s.sp>=0xc000,'BIOS stack page 3');
   const fn=s.ix;
   if(fn===0x59){
    assert.equal(hl(s),0);assert.equal(de(s),0x6000);assert.equal(bc(s),16384);
    mem.set(vram.slice(0,16384),de(s));transfers.push({kind:'read',vram:hl(s),ram:de(s),bytes:bc(s)});clobber(s);
   }else if(fn===0x5c){
    assert.ok(hl(s)>=0x4000&&hl(s)+bc(s)<=0xa000,'BIOS RAM source outside ROM page 0');
    assert.ok(de(s)+bc(s)<=65536,'VRAM bounds');assert.equal(mem[0xfaf6],0,'Active page zero');
    vram.set(mem.slice(hl(s),hl(s)+bc(s)),de(s));
    transfers.push({kind:'write',vram:de(s),ram:hl(s),bytes:bc(s)});clobber(s);
   }else if(fn===0x56){
    assert.ok(hl(s)+bc(s)<=16384,'VRAM fill bounds');
    vram.fill(s.a,hl(s),hl(s)+bc(s));transfers.push({kind:'fill',vram:hl(s),bytes:bc(s),value:s.a});clobber(s);
   }else if(fn===0x47){
    assert.ok(s.c<24,'MSX2 VDP registers');
    regs[s.c]=s.b;mem[s.c<8?0xf3df+s.c:0xffe7+s.c-8]=s.b;registerWrites.push({register:s.c,value:s.b});
    s.a=0xa5;s.b=0xa5;s.c=0xa5;s.ix=0xa5a5;s.iy=0xa5a5;
   }else if(fn===0x9c){
    // One virtual VBlank per keyboard poll; no real time claim.
    put16(0xfc9e,get16(0xfc9e)+1);
    if(opts.network&&netopt.cancelAfter&&netlog.calls.length>=netopt.cancelAfter)key=27;
    s.flags.Z=key===null?1:0;s.a=0xa5;
   }else if(fn===0x9f){
    assert.notEqual(key,null);s.a=key;key=null;s.flags.Z=s.a===0?1:0;
   }else throw Error('Unexpected BIOS routine '+fn.toString(16));
   ret(s);return;
  }
  cpu.run_instruction();
 }
 function until(predicate,limit=12000000){const start=steps;while(!predicate()){assert.ok(steps-start<limit,'Step limit at '+cpu.getState().pc.toString(16));step();}return steps-start;}
 function boot(){return until(()=>exited||cpu.getState().pc===symbols.main_loop);}
 function press(k){assert.ok(!exited);assert.equal(cpu.getState().pc,symbols.main_loop);key=k;step();return until(()=>exited||cpu.getState().pc===symbols.main_loop);}
 function idle(n=1){for(let i=0;i<n;i++){step();until(()=>exited||cpu.getState().pc===symbols.main_loop);}}
 function call(label,params={}){
  let s=cpu.getState();assert.equal(s.pc,symbols.main_loop);
  if(params.hl!==undefined){s.h=params.hl>>8;s.l=params.hl&255;}
  if(params.de!==undefined){s.d=params.de>>8;s.e=params.de&255;}
  if(params.a!==undefined)s.a=params.a;
  const saved=s.pc;s.sp-=2;put16(s.sp,0xbffe);s.pc=symbols[label];cpu.setState(s);
  const count=until(()=>cpu.getState().pc===0xbffe);s=cpu.getState();s.pc=saved;cpu.setState(s);return count;
 }
 function setEditor(text,cursor){
  const data=typeof text==='string'?encode(text):Buffer.from(text);
  assert.ok(data.length<=2047);mem.fill(0,0x4800,0x5000);mem.set(data,0x4800);
  put16(symbols.editor_length,data.length);put16(symbols.editor_cursor,cursor===undefined?data.length:cursor);
  put16(symbols.view_top,0);call('editor_update');call('render_dirty');
 }
 function text(){return Buffer.from(mem.slice(0x4800,0x4800+get16(symbols.editor_length)));}
 function row(n){return Buffer.from(mem.slice(0x4000+n*80,0x4000+n*80+80));}
 function exit(){
  if(!exited)press(27);
  assert.ok(exited);
  assert.deepEqual(Buffer.from(vram.slice(0,16384)),originalVRAM.slice(0,16384),'DOS low 16K VRAM restored');assert.deepEqual(Buffer.from(vram.slice(0xd400)),originalVRAM.slice(0xd400),'VRAM outside bitmap untouched');assert.equal(mem[0xfaf6],opts.acpage||0);
  assert.deepEqual(Buffer.from(regs),originalRegs,'VDP registers restored');
  assert.deepEqual(Buffer.from([...mem.slice(0xf3df,0xf3e7),...mem.slice(0xffe7,0xfff7)]),originalRegs,'BIOS mirrors restored');
  assert.equal(mem[0xfcaf],originalMode);assert.equal(mem[0xf3de],originalCNS);
  assert.equal(cpu.getState().sp,opts.sp||0xf000,'Original stack balanced');
  assert.equal(cpu.getState().iff1,1,'Interrupts enabled');
  assert.deepEqual(Buffer.from(mem.slice(0xf847,0xf857)),argOriginal,'ARG restored');
 }
 return {mem,vram,regs,cpu,transfers,registerWrites,boot,press,idle,call,setEditor,text,row,exit,get16,put16,files,fsCalls,netlog,get dta(){return dta;},
  get steps(){return steps;},get output(){return output;},get exited(){return exited;}};
}
const results=[];
const startupOnly=process.argv.includes('--startup');
function test(label,fn){if(startupOnly&&!label.startsWith('VRAM startup'))return;const metrics=fn()||{};results.push({test:label,status:'PASS',...metrics});if(results.length%25===0)console.log('PASS '+results.length+' tests');}
for(const generation of [1,2])for(const vramMode of [0x04,0x0c,0x84,0x8c,0x06,0x0e]){
 test('VRAM startup generation='+generation+' MODE='+vramMode.toString(16),()=>{
  const m=machine({generation,vramMode});m.boot();
  assert.equal(m.exited,false,'128KB BIOS encoding must start SCREEN7: '+m.output);
  assert.equal(m.mem[0xfcaf],7);assert.equal(m.mem[0xfafc],vramMode,'MODE flags preserved');
  m.setEditor('SM-X 128K');m.press(19);assert.ok(m.files.has('MSXDRAFT.JSN'));
  assert.equal(m.mem[0xfcaf],7);assert.equal(m.mem[0xfafc],vramMode);m.exit();
 });
}
// Real V9938/V9958 BIOS values have R#1 bit 7 clear. The previous fixture
// used F0h and incorrectly required that MSX1-only bit.
for(const generation of [1,2])for(const r1 of [0x10,0x30,0x50,0x70,0x60,0x68,0xf0]){
 test('VRAM startup reserved R1 bit generation='+generation+' R1='+r1.toString(16),()=>{
  const m=machine({generation,regs:[0,r1,0,0,1,0x36,7,4]});m.boot();
  assert.equal(m.exited,false,m.output);assert.equal(m.mem[0xfcaf],7);assert.equal(m.regs[1],0x60);
  assert.ok(m.registerWrites.filter(w=>w.register===1).every(w=>(w.value&0x80)===0));
  m.setEditor('BIOS R1 / SD Mapper');m.press(19);m.press(4);
  assert.equal(m.text().toString(),'BIOS R1 / SD Mapper');assert.equal(m.mem[0xfcaf],7);
  m.exit();assert.equal(m.regs[1],r1,'Exact original BIOS state restored');
 });
}
for(const [label,regs] of [['TEXT2 80 columns',[4,0x70,3,0,1,0x36,7,0xf1]],['TEXT1 40 columns',[0,0x70,0,0,1,0x36,7,0xf1]]]){
 test('VRAM startup '+label+' after network and disk I/O',()=>{
  const m=machine({regs,network:{},cmd:' 192.168.1.10 8080'});m.boot();
  assert.equal(m.exited,false,m.output);m.setEditor('Pergunta');m.press(17);
  assert.ok(m.files.has('00000001.REQ'));m.press(23);assert.equal(m.mem[0xfcaf],7);m.exit();
 });
}
test('COM format, font size and full eight-pixel glyphs',()=>{
 assert.equal(binary[0],0xc3);assert.ok(binary.length+256<0x4000);assert.equal(font.length,2048);assert.ok(font.some(v=>v>15));
 for(let code=32;code<127;code++)assert.ok(spec.patterns[String.fromCharCode(code)]);
 return {comBytes:binary.length,entry:256,end:256+binary.length};
});
test('SCREEN7 bitmap, 80 columns, 16 colors, all scanlines and page boundaries',()=>{
 const m=machine();m.boot();assert.equal(m.mem[0xfcaf],7);
 assert.equal(m.regs[0],10);assert.equal(m.regs[2],31);assert.equal(m.regs[8],10);assert.equal(m.regs[9],128);
 for(let y=0;y<192;y++)for(let x=0;x<512;x++){
  const row=y>>3,col=Math.floor((x-16)/6),colors=m.mem[0x5420+row];
  let expected=colors&15;
  if(x>=16&&x<496){const code=m.mem[0x4000+row*80+col];let bits=font[code*8+(y&7)];if(row===20&&col===0)bits^=255;
    expected=(bits>>(7-(x-16)%6)&1)?colors>>4:colors&15;}
  const packed=m.vram[y*256+(x>>1)],actual=x&1?packed&15:packed>>4;
  assert.equal(actual,expected,'x='+x+' y='+y);
 }
 assert.ok(m.vram.slice(192*256,212*256).every(v=>v===17));
 savePNG(m.vram,'PREVIA-INICIAL.png');savePNG(m.vram,'PREVIA-LEITURA.png',3,true);m.exit();
});
test('80-column UI labels fit without clipping',()=>{
 const m=machine();m.boot();
 for(const label of ['title_text','ruler_text','intro_text','user_text','chatgpt_text','history_intro','cancel_intro','footer_text','net_title','font_text','json_text','accents_text','accents_upper','cal_title','cal_upper','cal_lower','cal_note','history_header_text','history_footer_text','history_editor_busy',...Array.from({length:9},(_,i)=>'help_'+(i+1))]){
  let p=symbols[label],n=0;assert.ok(p!==undefined,label);while(m.mem[p+n])n++;
  assert.ok(n<=80,label+' has '+n+' columns');
 }
 m.press(7);assert.ok(m.row(10).toString().includes('2047 bytes'));
 m.press(18);assert.equal(m.row(2).toString(),'0123456789'.repeat(8));m.press(18);m.exit();
});
test('80th column survives editor, preview, overlays and scrolling',()=>{
 const m=machine();m.boot();m.setEditor('A'.repeat(79)+'Z'+'B'.repeat(80),0);
 assert.equal(m.row(20)[79],90);assert.equal(m.row(21).toString(),'B'.repeat(80));
 const editor=m.text();m.press(16);m.press(7);m.press(7);assert.deepEqual(m.text(),editor);
 assert.equal(m.row(20)[79],90);m.exit();
});
test('Insert, left/right, Backspace, Delete and empty boundaries',()=>{
 const m=machine();m.boot();for(const b of encode('ac'))m.press(b);m.press(29);m.press(98);
 assert.equal(m.text().toString(),'abc');assert.equal(m.get16(symbols.editor_cursor),2);
 m.press(8);assert.equal(m.text().toString(),'ac');m.press(127);assert.equal(m.text().toString(),'a');
 m.press(28);assert.equal(m.get16(symbols.editor_cursor),1);m.press(12);m.press(8);m.press(127);m.press(29);
 assert.equal(m.text().length,0);m.exit();
});
test('Explicit newline, logical Home/End and line join',()=>{
 const m=machine();m.boot();for(const b of [97,98,13,99,100])m.press(b);
 assert.equal(m.text().toString(),'ab\ncd');m.press(1);assert.equal(m.get16(symbols.editor_cursor),3);
 m.press(8);assert.equal(m.text().toString(),'abcd');m.press(5);assert.equal(m.get16(symbols.editor_cursor),4);
 m.press(11);assert.equal(m.get16(symbols.editor_cursor),0);m.exit();
});
test('80-column wrap and cursor advances into next visual line',()=>{
 const m=machine();m.boot();m.setEditor('X'.repeat(79));m.press(89);
 assert.equal(m.text().length,80);assert.equal(m.get16(symbols.cursor_row),1);assert.equal(m.mem[symbols.cursor_col],0);
 assert.equal(m.row(20).toString(),'X'.repeat(79)+'Y');m.exit();
});
test('Enter immediately after column 80 avoids an extra blank line',()=>{ const m=machine();m.boot();m.setEditor('X'.repeat(80));m.press(13);assert.equal(m.get16(symbols.cursor_row),1);m.press(13);assert.equal(m.get16(symbols.cursor_row),2);m.exit();});
test('Vertical movement clamps to short lines',()=>{
 const m=machine();m.boot();m.setEditor('abcdef\nxy\n12345',5);
 m.press(31);assert.equal(m.get16(symbols.editor_cursor),9);
 m.press(31);assert.equal(m.get16(symbols.editor_cursor),12);
 m.press(30);assert.equal(m.get16(symbols.editor_cursor),9);
 m.press(30);assert.equal(m.get16(symbols.editor_cursor),2);m.exit();
});
test('Viewport scrolls to cursor beyond three lines and returns to top',()=>{
 const m=machine();m.boot();m.setEditor('A'.repeat(400));
 assert.equal(m.get16(symbols.cursor_row),5);assert.equal(m.get16(symbols.view_top),3);assert.equal(m.mem[symbols.cursor_screen_row],22);
 m.press(1);assert.equal(m.get16(symbols.editor_cursor),0);assert.equal(m.get16(symbols.view_top),0);m.exit();
});
test('Long newline-only buffer uses 16-bit row counters',()=>{
 const m=machine();m.boot();m.setEditor('\n'.repeat(1000));assert.equal(m.get16(symbols.cursor_row),1000);assert.equal(m.get16(symbols.view_top),998);
 m.press(30);assert.equal(m.get16(symbols.editor_cursor),999);m.exit();
});
test('2047-byte full buffer rejects insert without overwrite',()=>{
 const m=machine();m.boot();m.setEditor('A'.repeat(2047));m.mem[0x5000]=0x5a;
 const before=m.text();m.press(66);assert.deepEqual(m.text(),before);assert.equal(m.get16(symbols.editor_cursor),2047);
 assert.equal(m.mem[0x4800+2047],0);assert.equal(m.mem[symbols.buffer_full],1);assert.equal(m.mem[0x5420+19],0x81);m.exit();
});
test('Insertion at start near limit and deletion preserve NUL',()=>{
 const m=machine();m.boot();m.setEditor('B'.repeat(2046),0);m.press(65);
 assert.equal(m.text().length,2047);assert.equal(m.text()[0],65);assert.equal(m.text()[2046],66);assert.equal(m.mem[0x4fff],0);
 m.press(8);assert.equal(m.text().length,2046);assert.equal(m.mem[0x4800+2046],0);m.exit();
});
test('Help/calibration overlays preserve conversation and editor',()=>{
 const m=machine();m.boot();m.setEditor('text\nkept');
 const conversation=Buffer.from(m.mem.slice(0x4050,0x45f0));const editor=m.text();const cursor=m.get16(symbols.editor_cursor);
 m.press(7);assert.equal(m.mem[symbols.overlay_mode],1);m.press(18);assert.equal(m.mem[symbols.overlay_mode],2);
 savePNG(m.vram,'PREVIA-FONTE.png');
 m.press(18);assert.equal(m.mem[symbols.overlay_mode],0);assert.deepEqual(Buffer.from(m.mem.slice(0x4050,0x45f0)),conversation);
 assert.deepEqual(m.text(),editor);assert.equal(m.get16(symbols.editor_cursor),cursor);m.exit();
});
test('Local preview and window scroll preserve typed message',()=>{
 const m=machine();m.boot();m.setEditor(('LINHA LOCAL\n').repeat(22));
 const text=m.text();m.press(16);assert.deepEqual(m.text(),text);assert.ok(Buffer.from(m.mem.slice(0x4050,0x45f0)).toString().includes('Nada foi enviado.'));
 assert.equal(m.get16(symbols.editor_length),text.length);m.exit();
});
test('Dirty rows redraw bitmap; blinking redraws one row',()=>{
 const m=machine();m.boot();let n=m.transfers.length;m.press(65);let tr=m.transfers.slice(n);
 assert.equal(tr.filter(t=>t.kind==='write').reduce((a,t)=>a+t.bytes,0),4096);
 assert.ok(tr.every(t=>t.vram>=19*2048&&t.vram<23*2048));
 n=m.transfers.length;m.idle(31);tr=m.transfers.slice(n);
 assert.equal(tr.filter(t=>t.kind==='write').reduce((a,t)=>a+t.bytes,0),2048);m.exit();
});
test('Bitmap cursor preserves adjacent cells at even and odd columns',()=>{
 const m=machine();m.boot();m.setEditor('AB',0);
 const cell=col=>Buffer.from(Array.from({length:24},(_,i)=>m.vram[20*2048+Math.floor(i/3)*256+8+col*3+(i%3)]));
 const other=cell(1);m.idle(31);assert.deepEqual(cell(1),other);
 m.press(28);const first=cell(0);m.idle(31);assert.deepEqual(cell(0),first);m.exit();
});
test('Portuguese MSX-BR bytes remain unchanged in editor',()=>{
 const m=machine();m.boot();const data=encode('Olá, MSX! Ação, coração, café.\nEdição em 80 colunas.');
 for(const b of data)m.press(b===10?13:b);
 assert.deepEqual(m.text(),data);savePNG(m.vram,'PREVIA-EDITOR.png');savePNG(m.vram,'PREVIA-NATIVA.png',1);m.exit();
});
for(const [label,opts,expected] of [
 ['MSX1 generation',{generation:0},'MSX2 or newer'],
 ['16K VRAM',{vramMode:0},'128K VRAM'],
 ['16K VRAM masked',{vramMode:8},'128K VRAM'],
 ['64K VRAM masked',{vramMode:10},'128K VRAM'],
 ['64K VRAM',{vramMode:2},'128K VRAM'],
 ['insufficient TPA',{tpa:0xa000},'TPA must extend'],
 ['stack outside page 3',{sp:0xb000},'stack must be in page 3'],
 ['unsupported initial video mode',{mode:5},'start from video mode']
]){
 test('Reject '+label+' before video writes',()=>{const m=machine(opts);m.boot();assert.ok(m.exited);assert.ok(m.output.includes(expected));assert.equal(m.transfers.length,0);assert.equal(m.registerWrites.length,0);m.exit();});
}
test('PAL timing, active page and extended register restoration',()=>{
 const ext=Array.from({length:16},(_,i)=>(i*7)&255);ext[1]=2;
 const m=machine({extRegs:ext,acpage:1});m.boot();
 assert.equal(m.regs[9],130);assert.equal(m.mem[0xfaf6],0);
 m.setEditor('pagina e video');m.press(19);assert.equal(m.regs[9],130);
 m.exit();
});
for(const mode of [0,1,2,3]){
 test('Exact full video/BIOS restoration from initial mode '+mode,()=>{
  const regs=mode===0?[0,0x70,0,0,1,0x36,7,4]:mode===2?[2,0x60,6,255,3,0x36,7,1]:[0,mode===3?0x68:0x60,6,0x80,0,0x36,7,1];
  const m=machine({mode,regs,cnsdfg:1});m.boot();m.press(65);m.press(7);m.exit();return {cpuInstructions:m.steps};
 });
}

function envelope(overrides={}){
 return {protocol:'msxchat/1',request_id:'00000000',conversation_id:'00000001',state:'draft',message:'Rascunho café',response_id:'',reply:'',error_code:'',...overrides};
}
const packedName=(name)=>{const [n,e]=name.split('.');return n.padEnd(8,' ')+e.padEnd(3,' ');};
const stringify=o=>JSON.stringify(o);
const pendingFiles=(message='Pergunta')=>({
 '00000001.ID':Buffer.from('00000001'),
 '00000001.REQ':Buffer.from(stringify(envelope({request_id:'00000001',state:'pending',message})))
});
function response(reply='Resposta offline',overrides={}){
 return envelope({request_id:'00000001',state:'completed',message:'',response_id:'00000001',reply,...overrides});
}
function parsed(file){return JSON.parse(file.toString('utf8'));}
function loadJSON(m,data){
 m.files.set('TESTJSON.JSN',Buffer.from(data));
 m.mem.set(Buffer.from(packedName('TESTJSON.JSN')),0xb340);
 m.call('io_begin');m.call('json_load',{hl:0xb340});
 const carry=m.cpu.getState().flags.C,error=m.mem[symbols.last_error];
 m.call('io_end');
 return {carry,error};
}
function bufferText(m,at){let end=at;while(m.mem[end]&&end<at+2048)end++;return Buffer.from(m.mem.slice(at,end));}

test('FCB draft create/write/readback/close/rename and Unicode escaping',()=>{
 const m=machine();m.boot();const input='Aspas " e barra \\\nOlá, ação.';m.setEditor(input);m.press(19);
 assert.ok(m.files.has('MSXDRAFT.JSN')); assert.ok(!m.files.has('MSXDRAFT.TMP'));
 const data=parsed(m.files.get('MSXDRAFT.JSN'));assert.equal(data.message,input);assert.equal(data.state,'draft');
 assert.deepEqual(m.text(),encode(input));assert.equal(m.dta,0x80);
 for(const fn of [0x16,0x26,0x27,0x10,0x17,0x0d])assert.ok(m.fsCalls.some(c=>c.fn===fn));
 m.exit();
});
test('Two-generation draft rotation and explicit restoration',()=>{
 const m=machine();m.boot();m.setEditor('primeiro');m.press(19);m.setEditor('segundo');m.press(19);
 assert.equal(parsed(m.files.get('MSXDRAFT.BAK')).message,'primeiro');
 m.setEditor('terceiro');m.press(19);assert.equal(parsed(m.files.get('MSXDRAFT.BAK')).message,'segundo');
 assert.ok(m.fsCalls.some(c=>c.fn===0x13));
 m.setEditor('nao salvo');m.press(4);assert.equal(m.text().toString(),'terceiro');m.exit();
});
test('Draft recovery on fresh process and backup fallback',()=>{
 const files={'MSXDRAFT.JSN':Buffer.from('{"partial"'),'MSXDRAFT.BAK':Buffer.from(stringify(envelope({message:'válido'})))};
 const m=machine({files});m.boot();assert.deepEqual(m.text(),encode('válido'));assert.equal(m.mem[symbols.draft_problem],1);
 m.press(19);assert.equal(m.files.get('MSXDRAFT.JSN').toString(),'{"partial"');
 assert.equal(parsed(m.files.get('MSXDRAFT.BAK')).message,'válido');m.exit();
});
test('Uncommitted draft TMP is ignored after interruption',()=>{
 const m=machine({files:{'MSXDRAFT.TMP':Buffer.from(stringify(envelope({message:'nao publicado'})))}});m.boot();
 assert.equal(m.text().length,0);m.exit();
});
test('Request reservation, immutable REQ and pending block',()=>{
 const m=machine();m.boot();m.setEditor('Pergunta ação');m.press(17);
 assert.equal(m.get16(symbols.pending_id),1);assert.ok(m.files.has('00000001.ID'));assert.ok(m.files.has('00000001.REQ'));
 const req=parsed(m.files.get('00000001.REQ'));assert.equal(req.message,'Pergunta ação');assert.equal(req.state,'pending');
 const reqBytes=Buffer.from(m.files.get('00000001.REQ'));m.setEditor('Outra pergunta');m.press(17);
 assert.deepEqual(m.files.get('00000001.REQ'),reqBytes);assert.ok(!m.files.has('00000002.ID'));m.exit();
});
test('Pending request recovered after restart',()=>{
 const m=machine({files:pendingFiles()});m.boot();assert.equal(m.get16(symbols.pending_id),1);m.exit();
});
test('Response import, ACK publication, editor preservation and explicit review',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.setEditor('editor preservado');
 m.files.set('00000001.RSP',Buffer.from(stringify(response('Olá, resposta 😀!'))));m.press(15);
 assert.equal(m.get16(symbols.pending_id),0);assert.equal(m.get16(symbols.last_response_id),1);
 const ack=parsed(m.files.get('00000001.ACK'));assert.equal(ack.state,'ack');assert.equal(ack.reply,'');assert.equal(ack.request_id,'00000001');
 assert.equal(bufferText(m,0xa800).toString('latin1'),encode('Olá, resposta ').toString('latin1')+'?!');
 assert.equal(m.text().toString(),'editor preservado');savePNG(m.vram,'PREVIA-ARQUIVOS.png');
 const writes=m.fsCalls.filter(c=>c.fn===0x26).length;m.press(15);assert.equal(m.fsCalls.filter(c=>c.fn===0x26).length,writes);
 m.press(2);assert.equal(m.fsCalls.filter(c=>c.fn===0x26).length,writes);m.exit();
});
test('ACK prevents automatic reprocessing across restart and advances ID',()=>{
 const files=pendingFiles();files['00000001.RSP']=Buffer.from(stringify(response()));
 files['00000001.ACK']=Buffer.from(stringify(envelope({request_id:'00000001',state:'ack',message:'',response_id:'00000001'})));
 const m=machine({files});m.boot();assert.equal(m.get16(symbols.pending_id),0);assert.equal(m.get16(symbols.last_response_id),1);
 const writes=m.fsCalls.filter(c=>c.fn===0x26).length;m.idle(610);assert.equal(m.fsCalls.filter(c=>c.fn===0x26).length,writes);
 m.setEditor('Nova');m.press(17);assert.ok(m.files.has('00000002.REQ'));assert.equal(m.get16(symbols.pending_id),2);m.exit();
});
test('Automatic periodic response polling',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.files.set('00000001.RSP',Buffer.from(stringify(response())));
 m.idle(610);assert.ok(m.files.has('00000001.ACK'));assert.equal(m.get16(symbols.pending_id),0);m.exit();
});
test('Remote error JSON is acknowledged but editor survives',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.setEditor('Repetir depois');
 m.files.set('00000001.RSP',Buffer.from(stringify(response('',{state:'error',error_code:'E_TEST'}))));m.press(15);
 assert.ok(m.files.has('00000001.ACK'));assert.equal(m.text().toString(),'Repetir depois');m.exit();
});
test('Wrong response ID binding is not acknowledged',()=>{
 const m=machine({files:pendingFiles()});m.boot();
 m.files.set('00000001.RSP',Buffer.from(stringify(response('x',{request_id:'00000002'}))));m.press(15);
 assert.ok(!m.files.has('00000001.ACK'));assert.equal(m.get16(symbols.pending_id),1);assert.equal(m.mem[symbols.auto_enabled],0);m.exit();
});
test('An RSP staging file is never interpreted',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.files.set('00000001.NEW',Buffer.from(stringify(response())));
 m.press(15);assert.equal(m.get16(symbols.pending_id),1);assert.ok(!m.files.has('00000001.ACK'));m.exit();
});
test('Orphan reservation is consumed and never reuses ID',()=>{
 const m=machine({files:{'00000001.ID':Buffer.alloc(0),'00000001.TMP':Buffer.from('partial')}});m.boot();
 m.setEditor('Nova');m.press(17);assert.ok(m.files.has('00000002.REQ'));assert.ok(m.files.has('00000001.TMP'));m.exit();
});
test('Corrupt ACK blocks queue and automatic polling',()=>{
 const files=pendingFiles();files['00000001.ACK']=Buffer.from('broken');
 const m=machine({files});m.boot();assert.equal(m.mem[symbols.storage_locked],1);const count=m.fsCalls.length;m.idle(610);
 assert.equal(m.fsCalls.length,count);m.setEditor('safe');m.press(17);assert.ok(!m.files.has('00000002.REQ'));m.exit();
});
test('Multiple pending requests lock instead of guessing',()=>{
 const files=pendingFiles();files['00000002.ID']=Buffer.from('00000002');
 files['00000002.REQ']=Buffer.from(stringify(envelope({request_id:'00000002',state:'pending',message:'two'})));
 const m=machine({files});m.boot();assert.equal(m.mem[symbols.storage_locked],1);const count=m.fsCalls.length;m.idle(610);assert.equal(m.fsCalls.length,count);m.exit();
});
test('Read-only medium keeps editor and publishes no draft/request',()=>{
 const m=machine({readonly:true});m.boot();m.setEditor('Preservar');m.press(19);m.press(17);
 assert.equal(m.text().toString(),'Preservar');assert.ok(!m.files.has('MSXDRAFT.JSN'));assert.ok(!m.files.has('00000001.REQ'));m.exit();
});
test('Mid-write failure keeps old committed draft',()=>{
 let writes=0;const old=stringify(envelope({message:'old'}));
 const m=machine({files:{'MSXDRAFT.JSN':Buffer.from(old)},failFS:(fn,name)=>fn===0x26&&name==='MSXDRAFT.TMP'&&++writes===2});m.boot();
 m.setEditor('X'.repeat(1000));m.press(19);assert.equal(m.files.get('MSXDRAFT.JSN').toString(),old);assert.equal(m.text().length,1000);
 assert.ok(m.files.has('MSXDRAFT.TMP'));m.exit();
});
test('Failed final rename recovers previous committed backup after restart',()=>{
 const old=stringify(envelope({message:'committed'}));
 const m=machine({files:{'MSXDRAFT.JSN':Buffer.from(old)},failFS:(fn,name)=>fn===0x17&&name==='MSXDRAFT.TMP'});m.boot();
 m.setEditor('new');m.press(19);assert.ok(!m.files.has('MSXDRAFT.JSN'));assert.equal(m.files.get('MSXDRAFT.BAK').toString(),old);m.exit();
 const restarted=machine({files:Object.fromEntries(m.files)});restarted.boot();assert.equal(restarted.text().toString(),'committed');restarted.exit();
});
test('Failed ACK rename leaves response pending and undisplayed',()=>{
 const m=machine({files:pendingFiles(),failFS:(fn,name)=>fn===0x17&&name==='00000001.AKT'});m.boot();
 m.files.set('00000001.RSP',Buffer.from(stringify(response())));m.press(15);
 assert.equal(m.get16(symbols.pending_id),1);assert.ok(!m.files.has('00000001.ACK'));assert.ok(m.files.has('00000001.AKT'));m.exit();
});
test('Short disk read is an error, not successful EOF',()=>{
 const m=machine({failFS:(fn,name)=>fn===0x27&&name==='TESTJSON.JSN'});m.boot();
 const result=loadJSON(m,stringify(envelope()));assert.equal(result.carry,1);m.exit();
});
test('Max-size draft roundtrip, including unsupported MSX bytes via private Unicode',()=>{
 const m=machine();m.boot();const data=Buffer.alloc(2047,233);m.setEditor(data);m.press(19);
 const raw=m.files.get('MSXDRAFT.JSN');assert.ok(raw&&raw.length>12000);assert.ok(m.fsCalls.filter(c=>c.fn===0x27).length>40);
 m.press(12);m.press(4);assert.deepEqual(m.text(),data);m.exit();
});
const parserCases=[
 ['reordered fields',JSON.stringify(Object.fromEntries(Object.entries(response('ok')).reverse())),true],
 ['all legal string escapes',stringify(response('quote" slash/ back\\ tab\t CR\r LF\n NUL\u0000')),true],
 ['escaped accent',stringify(response('x')).replace('"reply":"x"','"reply":"\\u00e9"'),true],
 ['valid surrogate pair',stringify(response('x')).replace('"reply":"x"','"reply":"\\uD83D\\uDE00"'),true],
 ['raw UTF-8 non-BMP',stringify(response('😀 ação')),true],
 ['trailing whitespace',stringify(response())+' \r\n\t',true],
 ['missing field',stringify(response()).replace(',"error_code":""',''),false],
 ['unknown field',stringify(response()).replace(/}$/,',"extra":""}'),false],
 ['duplicate key',stringify(response()).replace(/}$/,',"reply":"again"}'),false],
 ['nested object',stringify(response()).replace('"reply":"Resposta offline"','"reply":{}'),false],
 ['array value',stringify(response()).replace('"reply":"Resposta offline"','"reply":[]'),false],
 ['number value',stringify(response()).replace('"reply":"Resposta offline"','"reply":3'),false],
 ['trailing comma',stringify(response()).replace(/}$/,',}'),false],
 ['trailing garbage',stringify(response())+'x',false],
 ['incomplete object',stringify(response()).slice(0,-2),false],
 ['invalid escape',stringify(response('x')).replace('"reply":"x"','"reply":"\\x42"'),false],
 ['unpaired high surrogate',stringify(response('x')).replace('"reply":"x"','"reply":"\\uD800"'),false],
 ['unpaired low surrogate',stringify(response('x')).replace('"reply":"x"','"reply":"\\uDC00"'),false],
 ['raw control',stringify(response('x')).replace('"reply":"x"','"reply":"a\u0001b"'),false],
 ['oversize decoded text',stringify(response('x'.repeat(2048))),false],
 ['oversize metadata',stringify(response('x',{response_id:'A'.repeat(9)})),false]
];
for(const [label,data,valid]of parserCases)test('JSON parser '+label,()=>{
 const m=machine();m.boot();const result=loadJSON(m,data);assert.equal(result.carry,valid?0:1,label);m.exit();
});
for(const [label,bytes]of [
 ['overlong two-byte',[0xc0,0xaf]],['overlong three-byte',[0xe0,0x80,0xaf]],['overlong four-byte',[0xf0,0x80,0x80,0xaf]],
 ['UTF8 encoded surrogate',[0xed,0xa0,0x80]],['out of Unicode range',[0xf4,0x90,0x80,0x80]],['bad continuation',[0xe2,0x41,0xa1]],['standalone continuation',[0x80]]
])test('UTF8 rejects '+label,()=>{
 const raw=Buffer.from(stringify(response('PLACEHOLDER')));const at=raw.indexOf('PLACEHOLDER');
 const data=Buffer.concat([raw.subarray(0,at),Buffer.from(bytes),raw.subarray(at+11)]);
 const m=machine();m.boot();assert.equal(loadJSON(m,data).carry,1);m.exit();
});
test('JSON file over 32767 bytes is rejected before streaming',()=>{
 const m=machine();m.boot();assert.equal(loadJSON(m,Buffer.alloc(32768,32)).carry,1);m.exit();
});


test('UTF8 and Unicode escapes span the 256-byte read boundary',()=>{
 for(const suffix of ['é','😀']){
  const empty=stringify(response(''));const start=empty.indexOf('"reply":"')+9;
  const data=stringify(response('X'.repeat(255-start)+suffix));
  const m=machine();m.boot();assert.equal(loadJSON(m,data).carry,0);
  assert.ok(m.fsCalls.filter(c=>c.fn===0x27).length>=2);m.exit();
 }
 const empty=stringify(response(''));const start=empty.indexOf('"reply":"')+9;
 const raw=stringify(response('X'.repeat(254-start)+'PLACE')).replace('PLACE','\\u00E9');
 const m=machine();m.boot();assert.equal(loadJSON(m,raw).carry,0);m.exit();
});
test('End-to-end COM request to PC fixture to COM response and restart',()=>{
 const helper=require('../make-response.cjs');
 const m=machine();m.boot();m.setEditor('Teste integrado ação');m.press(17);
 const req=helper.parseEnvelope(m.files.get('00000001.REQ'));
 const rsp=helper.makeResponse(req,'Resposta local validada.');
 m.files.set('00000001.RSP',Buffer.from(JSON.stringify(rsp)));m.press(15);
 assert.ok(m.files.has('00000001.ACK'));m.exit();
 const restarted=machine({files:Object.fromEntries(m.files)});restarted.boot();
 assert.equal(restarted.get16(symbols.pending_id),0);assert.equal(restarted.get16(symbols.last_response_id),1);
 assert.deepEqual(restarted.text(),encode('Teste integrado ação'));restarted.exit();
});


function completedFiles(message='Pergunta',reply='Resposta',id='00000001',opts={}){
 const f={};
 f[id+'.ID']=Buffer.from(id);
 f[id+'.REQ']=Buffer.from(stringify(envelope({request_id:id,state:'pending',message})));
 f[id+'.RSP']=Buffer.from(stringify(response(reply,{request_id:id,...opts})));
 f[id+'.ACK']=Buffer.from(stringify(envelope({request_id:id,state:'ack',message:'',response_id:opts.response_id||'00000001',error_code:opts.error_code||''})));
 return f;
}
function viewText(m){return Buffer.concat(Array.from({length:17},(_,i)=>m.row(i+2))).toString('latin1');}
test('History empty preserves editor and remains in live mode',()=>{
 const m=machine();m.boot();m.setEditor('unsaved');m.press(25);
 assert.equal(m.mem[symbols.history_active],0);assert.equal(m.text().toString(),'unsaved');m.exit();
});
test('History shows committed USER and CHATGPT after reboot without another ACK',()=>{
 const m=machine({files:completedFiles('Pergunta anterior','Resposta anterior')});m.boot();
 m.setEditor('editor preservado');const before=new Map(m.files),writes=m.fsCalls.filter(c=>c.fn===0x26).length;
 const live=Buffer.from(m.mem.slice(0x4050,0x45f0));m.press(25);
 assert.equal(m.mem[symbols.history_active],1);assert.equal(m.get16(symbols.history_id),1);
 assert.ok(viewText(m).includes('[USER]'));assert.ok(viewText(m).includes('Pergunta anterior'));
 assert.ok(viewText(m).includes('[CHATGPT / RESPOSTA LOCAL]'));assert.ok(viewText(m).includes('Resposta anterior'));
 assert.ok(m.row(1).toString().includes('PRONTO'));
 savePNG(m.vram,'PREVIA-HISTORICO.png');
 assert.equal(m.fsCalls.filter(c=>c.fn===0x26).length,writes);assert.deepEqual(m.files,before);
 m.press(27);assert.ok(!m.exited);assert.equal(m.mem[symbols.history_active],0);
 assert.deepEqual(Buffer.from(m.mem.slice(0x4050,0x45f0)),live);
 assert.equal(m.text().toString(),'editor preservado');m.exit();
});
test('History question recall only replaces an empty editor and is not sent',()=>{
 const m=machine({files:completedFiles('Pergunta reutilizavel','ok')});m.boot();m.press(25);m.press(6);
 assert.equal(m.text().toString(),'Pergunta reutilizavel');assert.equal(m.mem[symbols.history_active],0);
 assert.ok(!m.files.has('00000002.REQ'));m.press(17);assert.ok(m.files.has('00000002.REQ'));m.exit();
});
test('History refuses recall over unsaved input and ignores editing keys',()=>{
 const m=machine({files:completedFiles('old','ok')});m.boot();m.setEditor('nao perder');m.press(25);
 for(const key of [65,8,127,12,13,17,19,4,24,15])m.press(key);
 assert.equal(m.text().toString(),'nao perder');assert.ok(!m.files.has('00000002.REQ'));
 m.press(6);assert.equal(m.mem[symbols.history_active],1);assert.equal(m.text().toString(),'nao perder');
 assert.ok(m.row(1).toString().includes('Editor ocupado'));m.press(27);m.exit();
});
test('History modal navigation pauses automatic response import',()=>{
 const files=pendingFiles();files['00000001.RSP']=Buffer.from(stringify(response('late')));
 const m=machine({files});m.boot();m.press(25);const calls=m.fsCalls.length;m.idle(610);
 assert.equal(m.fsCalls.length,calls);assert.ok(!m.files.has('00000001.ACK'));
 assert.ok(m.row(1).toString().includes('PENDENTE'));assert.ok(!viewText(m).includes('late'));assert.ok(!viewText(m).includes('[CHATGPT'));
 m.press(27);m.press(15);assert.ok(m.files.has('00000001.ACK'));m.exit();
});
test('History wraps at exactly 80 and scrolls by lines and pages',()=>{
 const message=Array.from({length:45},(_,i)=>'LINHA '+String(i).padStart(2,'0')).join('\n');
 const m=machine({files:completedFiles(message,'Z'.repeat(160))});m.boot();m.press(25);
 assert.equal(m.get16(symbols.history_top_row),0);assert.ok(viewText(m).includes('LINHA 00'));
 m.press(31);assert.equal(m.get16(symbols.history_top_row),1);
 m.press(14);assert.equal(m.get16(symbols.history_top_row),18);assert.ok(viewText(m).includes('LINHA 17'));
 m.press(21);assert.equal(m.get16(symbols.history_top_row),1);
 m.press(30);assert.equal(m.get16(symbols.history_top_row),0);m.press(30);assert.equal(m.get16(symbols.history_top_row),0);
 m.press(5);assert.equal(m.get16(symbols.history_top_row),m.get16(symbols.history_max_top));
 const bottom=m.get16(symbols.history_top_row);m.press(14);assert.equal(m.get16(symbols.history_top_row),bottom);
 savePNG(m.vram,'PREVIA-HISTORICO-PAGINA.png');m.press(1);assert.equal(m.get16(symbols.history_top_row),0);m.press(27);m.exit();
});
test('History 80-column LF agrees with editor layout and does not double wrap',()=>{
 const m=machine({files:completedFiles('X'.repeat(80)+'\nY','R')});m.boot();m.press(25);
 assert.equal(m.row(3).toString(),'X'.repeat(80));assert.equal(m.row(4)[0],89);m.press(27);m.exit();
});
test('History supports 16-bit page positions for newline-heavy messages',()=>{
 const m=machine({files:completedFiles('\n'.repeat(2000)+'FIM','R')});m.boot();m.press(25);
 assert.ok(m.get16(symbols.history_rows)>2000);m.press(5);assert.ok(m.get16(symbols.history_top_row)>1900);
 assert.ok(viewText(m).includes('FIM'));m.press(27);m.exit();
});
test('History buffers contain full 2047-byte question and reply without crossing boundaries',()=>{
 const m=machine({files:completedFiles('Q'.repeat(2047),'R'.repeat(2047))});m.boot();
 m.mem[0xbc00]=0x6b;m.press(25);
 assert.equal(bufferText(m,0xb400).length,2047);assert.equal(bufferText(m,0xa800).length,2047);
 assert.equal(m.mem[0xbc00],0x6b);m.press(5);assert.ok(viewText(m).includes('R'.repeat(64)));
 m.press(27);m.exit();
});
test('History left/right skips archived and reserved-only IDs and clamps both ends',()=>{
 const files={...completedFiles('one','r1'), '00000002.ID':Buffer.from('00000002'),...completedFiles('three','r3','00000003')};
 const m=machine({files});m.boot();m.press(25);assert.equal(m.get16(symbols.history_id),3);
 m.press(29);assert.equal(m.get16(symbols.history_id),1);m.press(29);assert.equal(m.get16(symbols.history_id),1);
 m.press(28);assert.equal(m.get16(symbols.history_id),3);m.press(28);assert.equal(m.get16(symbols.history_id),3);
 assert.ok(viewText(m).includes('three'));m.press(27);m.exit();
});
test('History opens latest available request when last reservation has no REQ',()=>{
 const files={...completedFiles('one','ok'),'00000002.ID':Buffer.alloc(0)};
 const m=machine({files});m.boot();m.press(25);assert.equal(m.get16(symbols.history_id),1);m.press(27);m.exit();
});
test('Corrupt request in locked journal is never rendered or recalled',()=>{
 const files=pendingFiles();files['00000001.REQ']=Buffer.from('{"reply":"UNTRUSTED"');
 const m=machine({files});m.boot();assert.equal(m.mem[symbols.storage_locked],1);m.press(25);
 assert.ok(m.row(1).toString().includes('INV.REQ'));assert.ok(!viewText(m).includes('UNTRUSTED'));
 m.press(6);assert.equal(m.text().length,0);assert.equal(m.mem[symbols.history_active],1);m.press(27);m.exit();
});
test('Mismatched receipt response_id prevents historical response display',()=>{
 const files=completedFiles('safe','UNTRUSTED');files['00000001.RSP']=Buffer.from(stringify(response('UNTRUSTED',{response_id:'12345678'})));
 const m=machine({files});m.boot();m.press(25);assert.ok(viewText(m).includes('safe'));
 assert.ok(!viewText(m).includes('UNTRUSTED'));assert.ok(m.row(1).toString().includes('INV.RSP'));m.press(27);m.exit();
});
test('Missing historical RSP retains question and reports invalid link',()=>{
 const files=completedFiles('safe','gone');delete files['00000001.RSP'];
 const m=machine({files});m.boot();m.press(25);assert.ok(viewText(m).includes('safe'));
 assert.ok(m.row(1).toString().includes('INV.RSP'));m.press(27);m.exit();
});
test('Historical error response preserves and displays its error code',()=>{
 const m=machine({files:completedFiles('q','Falha offline','00000001',{state:'error',error_code:'E_LOCAL'})});m.boot();m.press(25);
 assert.ok(m.row(1).toString().includes('ERRO API'));assert.ok(viewText(m).includes('E_LOCAL'));m.press(27);m.exit();
});
test('History read failure never overwrites editor or displays partial reply',()=>{
 const m=machine({files:completedFiles('q','UNTRUSTED'),failFS:(fn,name)=>fn===0x27&&name==='00000001.RSP'});
 m.boot();m.setEditor('kept');m.press(25);assert.ok(!viewText(m).includes('UNTRUSTED'));
 assert.equal(m.text().toString(),'kept');m.press(27);m.exit();
});
test('Cancel requires two Ctrl+X and another key disarms it',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.setEditor('kept');m.press(24);
 assert.ok(!m.files.has('00000001.CAN'));assert.equal(m.mem[symbols.cancel_armed],1);
 m.press(65);assert.equal(m.mem[symbols.cancel_armed],0);m.press(24);
 assert.ok(!m.files.has('00000001.CAN'));m.press(24);assert.ok(m.files.has('00000001.CAN'));
 assert.equal(m.text().toString(),'keptA');assert.equal(m.get16(symbols.pending_id),0);
 const can=parsed(m.files.get('00000001.CAN'));assert.equal(can.state,'cancelled');
 assert.equal(can.request_id,'00000001');assert.equal(can.message,'');assert.equal(can.response_id,'');m.exit();
});
test('Cancellation survives reboot, reserves ID, ignores late response and permits next request',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.press(24);m.press(24);
 m.files.set('00000001.RSP',Buffer.from(stringify(response('late'))));m.exit();
 const r=machine({files:Object.fromEntries(m.files)});r.boot();assert.equal(r.get16(symbols.pending_id),0);
 assert.equal(r.mem[symbols.storage_locked],0);r.idle(610);assert.ok(!r.files.has('00000001.ACK'));
 r.press(25);assert.ok(r.row(1).toString().includes('CANCEL.'));assert.ok(!viewText(r).includes('late'));
 r.press(27);r.setEditor('two');r.press(17);assert.ok(r.files.has('00000002.REQ'));r.exit();
});
test('Failed cancel rename keeps pending request and uncommitted CNT ignored after reboot',()=>{
 const m=machine({files:pendingFiles(),failFS:(fn,name)=>fn===0x17&&name==='00000001.CNT'});m.boot();m.press(24);m.press(24);
 assert.equal(m.get16(symbols.pending_id),1);assert.ok(!m.files.has('00000001.CAN'));assert.ok(m.files.has('00000001.CNT'));m.exit();
 const r=machine({files:Object.fromEntries(m.files)});r.boot();assert.equal(r.get16(symbols.pending_id),1);r.exit();
});
test('Read-only cancel fails without losing editor or request',()=>{
 const m=machine({files:pendingFiles(),readonly:true});m.boot();m.setEditor('safe');m.press(24);m.press(24);
 assert.equal(m.text().toString(),'safe');assert.equal(m.get16(symbols.pending_id),1);assert.ok(!m.files.has('00000001.CAN'));m.exit();
});
test('Conflicting ACK and CAN lock the journal instead of accepting both',()=>{
 const files=completedFiles();files['00000001.CAN']=Buffer.from(stringify(envelope({request_id:'00000001',state:'cancelled',message:''})));
 const m=machine({files});m.boot();assert.equal(m.mem[symbols.storage_locked],1);m.press(25);
 assert.ok(m.row(1).toString().includes('INV.RSP'));m.press(27);m.exit();
});
test('Corrupt cancel marker blocks queue and is never treated as cancellation',()=>{
 const files=pendingFiles();files['00000001.CAN']=Buffer.from('broken');
 const m=machine({files});m.boot();assert.equal(m.mem[symbols.storage_locked],1);m.exit();
});
test('Orphan CAN without its reservation is never reused',()=>{
 const files={'00000001.CAN':Buffer.from('{}')};const m=machine({files});m.boot();
 assert.equal(m.mem[symbols.storage_locked],1);m.exit();
});
test('History maximum reserved ID does not wrap to zero during browsing',()=>{
 const m=machine({files:completedFiles()});m.boot();m.put16(symbols.history_ceiling,65535);
 m.put16(symbols.history_candidate,65535);m.mem[symbols.history_direction]=1;
 m.call('history_step');assert.equal(m.cpu.getState().flags.C,1);m.exit();
});


const command=' 192.168.1.10 8765';
function httpWire(body=stringify(response('Resposta LAN')),headers=[],status='HTTP/1.1 200 OK'){
 return Buffer.from(status+'\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: '+Buffer.byteLength(body)+'\r\n'+headers.map(h=>h+'\r\n').join('')+'\r\n'+body);
}
function netMachine(network={},files=pendingFiles()){
 const m=machine({cmd:command,network:{wire:httpWire(),...network},files});m.boot();return m;
}
function networkFail(network,category){
 const m=netMachine(network);m.setEditor('kept editor');m.press(23);
 assert.equal(m.text().toString(),'kept editor');assert.equal(m.get16(symbols.pending_id),1);
 assert.ok(!m.files.has('00000001.RSP'));assert.ok(!m.files.has('00000001.ACK'));
 if(category!==undefined)assert.equal(m.mem[symbols.net_error],category);
 if(m.netlog.open&&!network.openError&&!m.netlog.closed)assert.ok(m.netlog.aborts>0);
 m.exit();
}
for(const transport of [{},{rom:true},{direct:true},{bufferBusy:2},{fragments:[1]},{fragments:[256]}]){
 test('Network POST commits RSP/ACK via UNAPI '+JSON.stringify(transport),()=>{
  const m=netMachine(transport);m.setEditor('não perder');m.press(23);
  assert.ok(m.files.has('00000001.RSP'));assert.ok(m.files.has('00000001.ACK'));
  assert.equal(m.get16(symbols.pending_id),0);assert.equal(m.mem[symbols.net_owned],0);
  assert.ok(m.netlog.closed);assert.equal(m.netlog.aborts,0);assert.deepEqual(m.text(),encode('não perder'));
  const sent=m.netlog.sent.toString('utf8'),at=sent.indexOf('\r\n\r\n');
  assert.ok(sent.startsWith('POST /msxchat/v1/exchange HTTP/1.1\r\nHost: 192.168.1.10:8765\r\n'));
  const head=sent.slice(0,at),body=sent.slice(at+4);
  assert.equal(Number(head.match(/Content-Length: ([0-9]+)/)[1]),Buffer.byteLength(body));
  assert.equal(body,m.files.get('00000001.REQ').toString());assert.ok(head.includes('Connection: close'));
  assert.ok(m.netlog.calls.includes(29));savePNG(m.vram,'PREVIA-REDE.png');m.exit();
 });
}
test('Network mode absent keeps full offline behavior and makes no UNAPI calls',()=>{
 const m=machine({files:pendingFiles()});m.boot();m.press(23);assert.equal(m.netlog.calls.length,0);
 assert.equal(m.get16(symbols.pending_id),1);m.exit();
});
test('Configured LAN without pending request does not open a connection',()=>{
 const m=netMachine({},{});m.press(23);assert.equal(m.netlog.open,0);m.exit();
});
test('Existing RSP is imported without resubmitting pending REQ',()=>{
 const files=pendingFiles();files['00000001.RSP']=Buffer.from(stringify(response('existing')));
 const m=netMachine({},files);m.press(23);assert.equal(m.netlog.open,0);assert.ok(m.files.has('00000001.ACK'));m.exit();
});
for(const [name,options,category]of [
 ['missing EXTBIO',{noExt:true},1],['missing TCP',{noTcp:true},1],['missing helper',{noHelper:true},1],
 ['bad entry',{badEntry:true},1],['API major',{badVersion:true},1],['no active TCP',{noActive:true},1],
 ['blocking OPEN',{blocking:true},1],['OPEN error',{openError:9},3],['STATE error',{stateError:11},3],
 ['unexpected state',{state:5},3],['SEND error',{sendError:2},3],['RCV error',{receiveError:11},3],
 ['WAIT error',{waitError:2},3],['receive overrun',{badLength:true},6],['urgent data',{urgent:true},6],
 ['connect timeout',{neverConnect:true},4],['receive/EOF timeout',{noEOF:true},4],
 ['close timeout',{closeStall:true},4],['close error',{closeError:12},3],['Escape',{cancelAfter:7},5]
])test('Network failure preserves request: '+name,()=>networkFail(options,category));
test('Abort error retains ownership and a later transmission first retries cleanup',()=>{
 const m=netMachine({sendError:2,abortError:2});m.press(23);
 assert.equal(m.mem[symbols.net_owned],1);const opens=m.netlog.open;m.press(23);
 assert.equal(m.netlog.open,opens);assert.ok(m.netlog.aborts>=2);m.exit();
});
for(const [name,wire]of [
 ['HTTP 500',httpWire('{}',[],'HTTP/1.1 500 Error')],
 ['HTTP 100',httpWire('{}',[],'HTTP/1.1 100 Continue')],
 ['duplicate length',httpWire(undefined,['Content-Length: 1'])],
 ['chunked',httpWire(undefined,['Transfer-Encoding: chunked'])],
 ['gzip',httpWire(undefined,['Content-Encoding: gzip'])],
 ['missing length',Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}')],
 ['length overflow',Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 65536\r\n\r\n')],
 ['length beyond file limit',Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 32768\r\n\r\n')],
 ['negative length',Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: -1\r\n\r\n')],
 ['empty body',httpWire('')],
 ['missing type',Buffer.from('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}')],
 ['wrong type',Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\n\r\n{}')],
 ['folded field',httpWire(undefined,[' folded: no'])],
 ['empty field name',httpWire(undefined,[': no'])],
 ['line exceeds 255',httpWire(undefined,['X-Long: '+'x'.repeat(256)])],
 ['headers exceed 2048',httpWire(undefined,Array.from({length:10},()=> 'X-Long: '+'x'.repeat(220)))],
 ['bare LF',Buffer.from('HTTP/1.1 200 OK\nContent-Length: 2\n\n{}')],
 ['truncated body',httpWire().subarray(0,-5)],
 ['extra body bytes',Buffer.concat([httpWire(),Buffer.from('EXTRA')])]
])test('HTTP framing rejects '+name,()=>networkFail({wire},6));
test('HTTP header names and media type accept ASCII case and OWS',()=>{
 const wire=httpWire().toString().replace('Content-Length: ','cOnTeNt-LeNgTh:\t').replace('Content-Type: application/json','CONTENT-TYPE: Application/JSON');
 const m=netMachine({wire});m.press(23);assert.ok(m.files.has('00000001.ACK'));m.exit();
});
test('Valid body with wrong envelope binding is never published',()=>{
 networkFail({wire:httpWire(stringify(response('wrong',{request_id:'00000002'})))},8);
});
test('Partially decoded or invalid JSON remains staged without ACK',()=>{
 networkFail({wire:httpWire('{"reply":"untrusted"')},8);
});
test('JSON remote error is committed as a response and acknowledged',()=>{
 const m=netMachine({wire:httpWire(stringify(response('Falha local',{state:'error',error_code:'E_LAN'})))});
 m.press(23);assert.ok(m.files.has('00000001.ACK'));assert.equal(parsed(m.files.get('00000001.RSP')).error_code,'E_LAN');m.exit();
});
test('Network body write failure preserves input and does not publish RSP',()=>{
 const m=machine({cmd:command,network:{wire:httpWire()},files:pendingFiles(),failFS:(fn,name)=>fn===0x26&&name==='00000001.RXT'});
 m.boot();m.setEditor('safe');m.press(23);assert.equal(m.text().toString(),'safe');assert.ok(!m.files.has('00000001.RSP'));
 assert.ok(!m.files.has('00000001.ACK'));assert.equal(m.get16(symbols.pending_id),1);m.exit();
});
test('Interrupted RXT is ignored at boot and retry uses original immutable REQ',()=>{
 const files=pendingFiles();files['00000001.RXT']=Buffer.from('partial');
 const m=netMachine({},files);m.press(23);assert.ok(m.files.has('00000001.ACK'));assert.ok(!m.files.has('00000001.RXT'));m.exit();
});
test('Largest request is streamed in 256-byte API blocks and exact byte length',()=>{
 const m=netMachine({fragments:[256]},pendingFiles('Q'.repeat(2047)));m.press(23);
 assert.ok(m.files.has('00000001.ACK'));assert.ok(m.netlog.calls.filter(f=>f===17).length>8);m.exit();
});
test('Largest decoded reply survives multi-block network and history buffers',()=>{
 const m=netMachine({wire:httpWire(stringify(response('R'.repeat(2047)))),fragments:[256]});m.press(23);
 assert.ok(m.files.has('00000001.ACK'));m.press(25);m.press(5);assert.ok(viewText(m).includes('R'.repeat(64)));m.press(27);m.exit();
});
test('Network timeout calculations survive JIFFY wraparound',()=>{
 const m=netMachine({bufferBusy:2});m.put16(0xfc9e,65530);m.press(23);assert.ok(m.files.has('00000001.ACK'));m.exit();
});
for(const cmd of [' 8.8.8.8 80',' 192.168.1.10 0',' 192.168.1.10 65536',' 256.1.1.1 80',
 ' 192.168.1.10',' 192.168.1.10 80 extra',' 172.32.1.1 80',' 0000000192.168.1.10 80',' 192.168.1.10 00000080']){
 test('Network command tail rejects '+cmd,()=>{
  const m=machine({cmd,network:{wire:httpWire()},files:pendingFiles()});m.boot();assert.equal(m.mem[symbols.net_config],2);
  m.press(23);assert.equal(m.netlog.open,0);m.exit();
 });
}


const processingWire=()=>httpWire('{"state":"processing"}',[],'HTTP/1.1 202 Accepted');
test('Gateway 202 preserves request/editor, creates no ACK and shows processing',()=>{
 const m=netMachine({wire:processingWire()});m.setEditor('preservar');m.press(23);
 assert.equal(m.get16(symbols.pending_id),1);assert.equal(m.mem[symbols.net_processing],1);
 assert.ok(!m.files.has('00000001.ACK'));assert.ok(!m.files.has('00000001.RSP'));assert.ok(!m.files.has('00000001.RXT'));
 assert.equal(m.text().toString(),'preservar');assert.equal(m.mem[symbols.net_owned],0);assert.equal(m.mem[symbols.net_error],9);
 savePNG(m.vram,'PREVIA-API-PROCESSANDO.png');m.exit();
});
test('Automatic gateway poll after 202 reuses request and imports final response',()=>{
 const m=netMachine({wire:processingWire()});m.press(23);const req=Buffer.from(m.files.get('00000001.REQ'));
 m.netlog.setWire(httpWire(stringify(response('Resposta da API simulada.'))));m.idle(610);
 assert.equal(m.netlog.open,2);assert.deepEqual(m.files.get('00000001.REQ'),req);assert.ok(m.files.has('00000001.ACK'));
 assert.equal(m.mem[symbols.net_processing],0);assert.equal(m.get16(symbols.pending_id),0);
 savePNG(m.vram,'PREVIA-API-RESPOSTA.png');m.exit();
});
test('Ctrl+T disables network polling while manual Ctrl+W remains available',()=>{
 const m=netMachine({wire:processingWire()});m.press(23);m.press(20);
 const opens=m.netlog.open;m.netlog.setWire(httpWire());m.idle(610);assert.equal(m.netlog.open,opens);
 m.press(23);assert.ok(m.files.has('00000001.ACK'));m.exit();
});
test('Network polling error stops automatic network retries after processing state',()=>{
 const m=netMachine({wire:processingWire()});m.press(23);
 m.netlog.setWire(httpWire('{}',[],'HTTP/1.1 503 Error'));m.idle(610);
 const opens=m.netlog.open;assert.equal(m.mem[symbols.net_processing],0);m.idle(610);assert.equal(m.netlog.open,opens);
 assert.equal(m.get16(symbols.pending_id),1);m.exit();
});
test('Local cancellation clears processing flag and never autosubmits a new question',()=>{
 const m=netMachine({wire:processingWire()});m.press(23);m.press(24);m.press(24);
 assert.equal(m.mem[symbols.net_processing],0);m.setEditor('nova pergunta');m.press(17);const opens=m.netlog.open;
 m.idle(610);assert.equal(m.netlog.open,opens);assert.equal(m.get16(symbols.pending_id),2);m.exit();
});
test('Restart keeps durable pending REQ but requires manual first gateway lookup',()=>{
 const m=netMachine({wire:processingWire()});m.press(23);m.exit();
 const r=netMachine({wire:httpWire()},Object.fromEntries(m.files));r.idle(610);
 assert.equal(r.netlog.open,0);assert.equal(r.get16(symbols.pending_id),1);r.press(23);assert.ok(r.files.has('00000001.ACK'));r.exit();
});
test('Malformed 202 status is not treated as processing',()=>{
 const m=netMachine({wire:httpWire('{}',[],'HTTP/1.1 2020 Invalid')});m.press(23);
 assert.equal(m.mem[symbols.net_error],6);assert.equal(m.mem[symbols.net_processing],0);m.exit();
});
test('Failed cleanup after 202 is reported as an outstanding owned connection',()=>{
 const m=netMachine({wire:processingWire(),abortError:2});m.press(23);
 assert.equal(m.mem[symbols.net_owned],1);assert.equal(m.mem[symbols.net_processing],0);assert.equal(m.get16(symbols.pending_id),1);m.exit();
});

test('80-column font spacing, confusables, accents and 4:3 reading sample',()=>{
 assert.ok(font.every(v=>(v&7)===0),'five ink pixels, one blank cell pixel');
 const distinct=chars=>{const patterns=chars.map(ch=>font.subarray((ch.charCodeAt(0)<128?ch.charCodeAt(0):unicodeMap[ch])*8,(ch.charCodeAt(0)<128?ch.charCodeAt(0):unicodeMap[ch])*8+8).toString('hex'));assert.equal(new Set(patterns).size,chars.length,chars.join(''));};
 for(const chars of [['O','0'],['I','l','1'],['{','[','('],['}',']',')'],['a','á','à','â','ã'],['A','Á','À','Â','Ã'],['o','ó','ô','õ'],['O','Ó','Ô','Õ']])distinct(chars);
 const m=machine();m.boot();m.setEditor('Leitura em 80 colunas: ação, coração, café, edição. O0 I1l {} [] () /\\',0);
 m.press(18);savePNG(m.vram,'PREVIA-FONTE-4X3.png',3,true);m.press(18);
 const sample=encode('MSX2 em 80 colunas: uma linha completa conserva o texto, os acentos e os espaços.');
 m.mem.set(sample,0xa000);m.mem[0xa000+sample.length]=0;m.call('term_string',{hl:0xa000});m.call('render_dirty');
 savePNG(m.vram,'PREVIA-LEITURA.png',3,true);m.exit();
});

fs.writeFileSync(path.join(base,startupOnly?'STARTUP-RESULTS.json':'TEST-RESULTS.json'),JSON.stringify({binarySha256:require('node:crypto').createHash('sha256').update(binary).digest('hex'),scope:'Real COM on Z80 CPU; simulated DOS FCB, BIOS, VRAM and TCP/IP UNAPI; no physical MSX2 or full MSX emulator',results},null,2));
console.log(JSON.stringify({passed:results.length,total:results.length,scope:'CPU/BIOS simulation'},null,2));
