import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedParentCoreBound,checkParentCensus} from '../parent-control/bounds.mjs';
import {inspectCurrentChain} from '../parent-control/current-inspect.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const read=p=>readFileSync(join(root,p));
// Extracted point observations exercise the validator; they do not authenticate
// a binary, assert a new execution, or prove whole-owner lifetime coverage.
const records=()=>structuredClone(JSON.parse(read('proofs/relation-pipeline/capacity/parent-control/chain-records.fixture.json')).records);
test('conditional core uses five Refs plus state and input-derived overlap',()=>{
  assert.equal(retainedParentCoreBound(2).bytes,808n);assert.equal(retainedParentCoreBound(10).bytes,1064n);
  assert(retainedParentCoreBound(2147483647).bytes<9223372036854775807n);
  for(const n of [0,1,-1,2147483648,1.5])assert.throws(()=>retainedParentCoreBound(n));
  assert.equal(retainedParentCoreBound(2).fullParentUpper,false);
});
test('current census binds state, metadata preparation and all provider construction',()=>{
  const census=checkParentCensus(read);
  assert.deepEqual(census.chainReferences,['used','cancelled','terminal','reclaimed','cleanup_index']);
  assert.equal(census.providerConstructors.length,11);
  const p='src/connectors/local/selected_relation_provider.mbt',source=read(p).toString();
  assert.throws(()=>checkParentCensus(path=>path===p?source.replace('Array::make(count, None)','Array::make(count - 1, None)'):read(path)));
  const generated='src/execution_relation/generated_sequence.mbt';
  assert.throws(()=>checkParentCensus(path=>path===generated?read(path).toString().replace('traversal_ceilings : Array[(Int, Int64, Int64)]','traversal_ceilings : Array[(Int, String, Int64)]'):read(path)));
});
test('actual capture roles and padded Native layouts bind every lifecycle phase',()=>{
  const result=inspectCurrentChain(records());assert.equal(result.actualPhases,7);assert.equal(result.completePhysicalUpper,false);
  for(const mutate of [r=>r[0].callbacks[0].requestedBytes=96,
    r=>r[0].callbacks[0].captures[0].id=r[0].roots.state,
    r=>r[0].environments[0].captures.pop(),r=>r.splice(4,1),
    r=>r[1].callbacks[0].captures[0].id='1']) {
    const r=records();mutate(r);assert.throws(()=>inspectCurrentChain(r));
  }
});
test('pending/error cleanup cannot lose the completed occurrence or nested cursor',()=>{
  for(const mutate of [r=>r[3].preparation=null,r=>r[4].read=null,
    r=>r[3].completed.elements[0]=null,r=>r[4].completed.completions[0]='1',
    r=>r[3].completed.slots=0,r=>r[3].children.elements[0]='1',
    r=>r[3].completed.backing=r[3].children.backing,
    r=>r[5].preparation=r[1].preparation,r=>r[6].children.length=1]) {
    const r=records();mutate(r);assert.throws(()=>inspectCurrentChain(r));
  }
});
