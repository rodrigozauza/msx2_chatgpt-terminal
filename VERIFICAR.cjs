'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const base=path.resolve(__dirname);
let count=0;
for(const line of fs.readFileSync(path.join(base,'SHA256SUMS.txt'),'utf8').trim().split(/\r?\n/)){
 const match=/^([a-f0-9]{64})  (.+)$/.exec(line);if(!match)throw Error('Linha invalida');
 const file=path.resolve(base,match[2]);if(!file.startsWith(base+path.sep))throw Error('Caminho invalido');
 const actual=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
 if(actual!==match[1])throw Error('Hash divergente: '+match[2]);count++;
}
console.log(JSON.stringify({verified:count,status:'PASS'}));
