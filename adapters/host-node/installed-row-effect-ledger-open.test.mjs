// Execute the actual shared caller body with explicit ports. Real numerical
// admission is tested on the original MoonBit Ledger; this is not an allocator
// or physical SQLite acceptance claim.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
const source=readFileSync(new URL('./installed-row-effect.mjs',import.meta.url),'utf8'),found=[];
function walk(node){if(!node||typeof node!=='object')return;if(node.type==='VariableDeclarator'&&node.id.name==='openLedger')found.push(node.init);for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}}
walk(parse(source,{ecmaVersion:'latest',sourceType:'module'}));assert.equal(found.length,1);
const body=found[0],load=compileFunction('return '+source.slice(body.start,body.end),['ledgerRoot','moon','controlEntryBytes','openEffectLedger']);
test('actual Ledger open caller retains original request policy and uses its same control frame',()=>{
  const root='/original/ledger',identity={},ledger={},authority='sha256:'+'a'.repeat(64),request='original';let opened=0,selected=0,active=false;
  const open=load(root,{clientRequestAuthorityScopeCid(value){assert.strictEqual(value,identity);return authority;},clientRequestCallerId(value){assert.strictEqual(value,identity);return request;}},4096,options=>{assert.equal(active,true);assert.equal(options.root,root);assert.equal(options.authorityScopeCid,authority);assert.equal(options.callerRequestId,request);assert.equal(options.maxEntryBytes,4096);assert.strictEqual(options.controlConstruction,work);opened++;return ledger;});
  const work=()=>assert.fail('full generic used for supported Ledger-open frame');
  work.ledgerOpen=(actual,receiver,method,args)=>{assert.equal(actual,root);assert.equal(receiver,undefined);selected++;active=true;try{return Reflect.apply(method,receiver,args);}finally{active=false;}};
  assert.strictEqual(open(identity,work),ledger);assert.equal(opened,1);assert.equal(selected,1);
});
test('actual Ledger open caller keeps unmanaged and legacy paths and original native failure',()=>{
  const root='/original/ledger',identity={},primary=Object.assign(new Error('original'),{cleanupPending:true}),moon={clientRequestAuthorityScopeCid:()=>'',clientRequestCallerId:()=>''};let calls=0;
  const open=load(root,moon,4096,()=>{calls++;throw primary;});
  assert.throws(()=>open(identity),cause=>cause===primary);
  const work=(receiver,method,args)=>Reflect.apply(method,receiver,args);
  assert.throws(()=>open(identity,work),cause=>cause===primary);assert.equal(calls,2);
});
