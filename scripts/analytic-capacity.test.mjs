import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {canonicalText} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';

const corpus = JSON.parse(readFileSync('portability/corpus/analytic-capacity.json','utf8'));
// Independent occurrence model, not an evaluator or product lowerer.
function memberships(size, start, end, calls) {
  let count=0;
  for(let row=0;row<size;row++)
    count += Math.max(0,Math.min(size-1,row+end)-Math.max(0,row+start)+1)*calls;
  return count;
}
test('analytic wire scopes preserve occurrences and JSON framing',()=>{
  for(const c of corpus.wire) {
    assert.equal(Buffer.byteLength(canonicalText(c.rows)),c.bytes);
    assert.equal(Buffer.byteLength(canonicalText(c.rows.map(r=>Object.fromEntries(Object.entries(r).reverse())))),c.bytes);
    assert.equal(c.bytes<=c.exact_limit,true);
    assert.equal(c.bytes<=c.exact_limit-1,false);
  }
});
test('logical memberships are clipped, per call, and independent of reuse or filtering',()=>{
  for(const c of corpus.frames) {
    const n=memberships(c.rows,c.start,c.end,c.calls);
    assert.equal(n,c.memberships);
    // Predicate false changes evaluation demand, not the frame membership scope.
    for(const execution of ['uncached','cached','filter_false','prefix']) assert.equal(n,c.memberships,execution);
  }
  assert.equal(memberships(3,1,2,1),3); // last frame is empty, not clamped to last row
  assert.equal(memberships(0,-1,1,4),0);
  assert.equal([3,2].reduce((n,size)=>n+memberships(size,-1,0,2),0),16);
  assert.equal([0,1,2].filter(i=>i-1>=0).length,2); // navigation offset one
});
test('partition wire ceilings are per partition while input and output scopes are whole sequences',()=>{
  const partitions=[[{id:1}],[{id:2}]];
  const bytes=v=>Buffer.byteLength(canonicalText(v));
  assert.deepEqual(partitions.map(bytes),[10,10]);
  assert.equal(bytes(partitions.flat()),19);
  assert(partitions.every(p=>bytes(p)<=10));
  assert(bytes(partitions.flat())>10);
  assert.equal(bytes([{id:1,rank:1},{id:2,rank:1}]),37);
  // Limits are exact; a missing bound is not a default or a completed check.
  const accepts=(value,cap)=>Number.isSafeInteger(cap)&&cap>0&&value<=cap;
  assert(accepts(37,37)); assert(!accepts(37,36)); assert(!accepts(37,undefined));
});
test('optional analytic policy fields affect identity without reinterpreting old policies',()=>{
  const contract=JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json','utf8'));
  const base=Object.fromEntries(contract.schema.required.map(k=>[k,k==='version'?'actql-capacity-host-policy/0.1':1]));
  assert.equal(machineCid(base),'sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63');
  const names=Object.keys(contract.schema.properties).filter(k=>k.startsWith('max_analytic_'));
  assert.equal(names.length,4);
  assert.equal(new Set(names.map(k=>machineCid({...base,[k]:7}))).size,4);
  for(const k of names) {
    assert(!contract.schema.required.includes(k));
    assert(!Object.hasOwn(contract.host_witness_laws,k));
  }
});
