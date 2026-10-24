import test from 'node:test';
import assert from 'node:assert/strict';
import {completedPublicationCapacity} from './publication-capacity.mjs';
const contract = id => ({identity:id,wire:JSON.stringify({id})});
function fixture(n=1) {
  const retention=contract('retention');
  return {plan:{runDefinition:contract('run'),invocation:contract('invocation'),
    results:Array.from({length:n},()=>({retention,evidenceContext:{inputRelationCids:[]}})),
    outputLimits:{maxWireBytes:68,maxSchemaBytes:65536},contractLimits:{maxWireBytes:1000000}},
    definitions:Array.from({length:n},(_,i)=>contract('definition'+i)),
    request:contract('request'),attempt:contract('attempt'),bounds:Array.from({length:n},()=>[1000,1000,400,67000])};
}
const size=f=>completedPublicationCapacity(f.plan,f.definitions,f.request,f.attempt,f.bounds);
test('100 Results sum per-kind objects rather than every object at payload ceiling',()=>{
  const f=fixture(100), result=size(f);
  assert.ok(result.requiredBytes < 23000000);
  assert.equal(result.maxObjectBytes,1000000);
  // 100 definitions + one shared retention + four known roots +600 unknown
  // per-Result objects +nine independent global obligations (including a foreign winner terminal).
  assert.equal(result.objectCount,714);
  const supports=budget=>budget>=result.requiredBytes;
  assert.equal(supports(result.requiredBytes),true);
  assert.equal(supports(result.requiredBytes-1),false);
});
test('unknown payloads coexist and are never deduplicated by alias',()=>{
  const f=fixture(2), before=size(f);f.plan.outputLimits.maxWireBytes+=123;
  assert.equal(size(f).requiredBytes-before.requiredBytes,246);
});
test('known identity dedup matches persistence, conflicting bodies are rejected',()=>{
  const f=fixture(2), before=size(f); f.definitions[1]=f.definitions[0];
  const after=size(f);assert.equal(before.objectCount-after.objectCount,1);
  assert.equal(before.requiredBytes-after.requiredBytes,new TextEncoder().encode(JSON.stringify({id:'definition1'})).length);
  f.definitions[1]={...f.definitions[0],wire:'different'};
  assert.throws(()=>size(f),/ConflictingPublicationContractIdentity/);
});
test('input evidence list sizing and Unicode known-wire byte counting',()=>{
  const f=fixture(),before=size(f);f.bounds[0][1]+=147;
  assert.equal(size(f).requiredBytes-before.requiredBytes,147);
  const old=f.plan.runDefinition.wire;f.plan.runDefinition.wire='漢😀';
  assert.equal(size(f).requiredBytes-before.requiredBytes,147+7-new TextEncoder().encode(old).length);
});
test('arithmetic overflow fails before accepting an under-sized budget',()=>{
  const f=fixture(2);f.plan.outputLimits.maxWireBytes=Number.MAX_SAFE_INTEGER;
  assert.throws(()=>size(f),/CapacityOverflow/);
});

test('Common projection must have exact arity and bounded integral entries',()=>{const f=fixture();f.bounds=[];assert.throws(()=>size(f),/InvalidPublicationContractByteBounds/);f.bounds=[[1,2,3]];assert.throws(()=>size(f),/InvalidPublicationContractByteBounds/);f.bounds=[[1,2,3,1000001]];assert.throws(()=>size(f),/InvalidPublicationContractByteBounds/);});


test('frontier sums current and foreign winner obligations, including exact/one-short budget',()=>{
 const f=fixture();const frontier={index:1075,current:{preparing:447,committing:448,publicationUnknown:457,terminal:546},possibleForeignWinnerTerminal:546};
 const generic=size(f),actual=completedPublicationCapacity(f.plan,f.definitions,f.request,f.attempt,f.bounds,frontier);
 assert.equal(generic.requiredBytes-actual.requiredBytes,6000000-3519);
 assert.equal(actual.objectCount,generic.objectCount);
 const withoutForeign={...frontier,possibleForeignWinnerTerminal:0};
 assert.equal(actual.requiredBytes-completedPublicationCapacity(f.plan,f.definitions,f.request,f.attempt,f.bounds,withoutForeign).requiredBytes,546);
 const supports=budget=>budget>=actual.requiredBytes;
 assert.equal(supports(actual.requiredBytes),true);assert.equal(supports(actual.requiredBytes-1),false);
 assert.throws(()=>completedPublicationCapacity(f.plan,f.definitions,f.request,f.attempt,f.bounds,{...frontier,current:{}}),/InvalidPublicationFrontierByteBounds/);
});
