import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
// Exercise the exact Store pre-persistence admission body. The control here is
// an independent structural oracle, NOT a replacement Common contract issuer.
const source=readFileSync(new URL('./publication-store.mjs',import.meta.url),'utf8');
const body=source.slice(source.indexOf('  const admitContract ='),source.indexOf('  const parseContract ='));
const cid='sha256:'+'0'.repeat(64);
function admission(nodes,bytes=200000) {
  const observed=[];
  const control={admit(name,wire,limits){
    observed.push(limits);
    const value=JSON.parse(wire);let count=0;
    const visit=x=>{count++;if(x!==null&&typeof x==='object')for(const child of Object.values(x))visit(child);};
    visit(value);
    if(count>limits.maxNodes)throw new Error('NodeLimit');
    return {name,identityField:'id',identity:cid,wire};
  }};
  const fail=(code,cause)=>{throw Object.assign(new Error(code,{cause}),{code});};
  const invoke=compileFunction(body+'return admitContract;',['configuration','contractControl','contractLimits','fail','exactKeys','cidPattern','Buffer'])
    ({maxObjectBytes:bytes},control,{maxWireBytes:bytes,maxNodes:nodes,maxDepth:64},fail,
      (x,keys)=>Object.keys(x).length===keys.length&&keys.every(k=>Object.hasOwn(x,k)),/^sha256:[0-9a-f]{64}$/,Buffer);
  return {invoke,observed};
}
test('wire-derived support crosses former10000 without replacing explicit narrower policy',()=>{
  const wire=JSON.stringify({id:cid,values:Array(10001).fill(1)});
  const old=admission(10000);assert.throws(()=>old.invoke('captured_run',wire),/InvalidPublicationContract/);
  const derived=admission(200000);assert.equal(derived.invoke('captured_run',wire).wire,wire);
  assert.equal(derived.observed[0].maxNodes,Buffer.byteLength(wire));
  const narrow=admission(100);assert.throws(()=>narrow.invoke('captured_run',wire),/InvalidPublicationContract/);
  assert.equal(narrow.observed[0].maxNodes,100);
});
test('object-byte refusal precedes control; malformed wire cannot be admitted',()=>{
  const narrow=admission(200000,4);assert.throws(()=>narrow.invoke('captured_run','[1,2]'),/InvalidPublicationContractWire/);
  assert.equal(narrow.observed.length,0);
  const malformed=admission(200000);assert.throws(()=>malformed.invoke('captured_run','{"broken":'),/InvalidPublicationContract/);
});
test('multibyte bound uses UTF8 extent, does not change depth or explicit byte policy',()=>{
 const a=admission(200000);const wire=JSON.stringify({id:cid,text:'数値'});a.invoke('captured_run',wire);
 assert.equal(a.observed[0].maxNodes,Buffer.byteLength(wire));assert.equal(a.observed[0].maxDepth,64);
 assert.equal(a.observed[0].maxWireBytes,200000);
});
