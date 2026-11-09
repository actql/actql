import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedParentCoreBound,checkParentCensus} from '../parent-control/bounds.mjs';
import {inspectCurrentChain} from '../parent-control/current-inspect.mjs';
import {currentChainSyntheticFixture} from '../parent-control/current-chain.synthetic.fixture.mjs';
import {reviewedFunction} from '../parent-control/provider-construction-source-review.mjs';
import {hash} from '../../inventory.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const read=p=>readFileSync(join(root,p));
// Current-source inputs are explicitly synthetic. The archived Native capture
// remains unchanged at its original execution revision and is not relabelled.
const records=()=>currentChainSyntheticFixture().records;
test('conditional core uses five Refs plus state and input-derived overlap',()=>{
  assert.equal(retainedParentCoreBound(2).bytes,816n);assert.equal(retainedParentCoreBound(10).bytes,1072n);
  assert(retainedParentCoreBound(2147483647).bytes<9223372036854775807n);
  for(const n of [0,1,-1,2147483648,1.5])assert.throws(()=>retainedParentCoreBound(n));
  assert.equal(retainedParentCoreBound(2).fullParentUpper,false);
});
test('current census binds state, metadata preparation and all provider construction',()=>{
  const census=checkParentCensus(read);
  assert.deepEqual(census.chainReferences,['used','cancelled','terminal','reclaimed','cleanup_index']);
  assert.equal(census.providerConstructors.length,11);
  assert.deepEqual(census.sourceFields.find(state=>state.struct==='GeneratedSequence')
    .fields.find(field=>field.name==='working'),{name:'working',type:'WorkspaceGrowth?'});
  const p='src/connectors/local/selected_relation_provider.mbt',source=read(p).toString();
  // Fixed preimages from the reviewed 6c46216736 Source: the singleton Set
  // retirement and bounded Join quote change neither candidate construction
  // nor the parent state/callback owner, and add no constructor allocation.
  assert.equal(hash(reviewedFunction(source,'selected_relation_provider')),
    'f100dd3ac842dd087b494382c42be9dfb613184a35f26164f2788ba8ed6544b5');
  assert.equal(hash(reviewedFunction(source,'bounded_relation_chain_execution_state')),
    '509b289d59148096c04e8676a739df325281648d03f58fdabdac6ecb25d95695');
  assert.throws(()=>checkParentCensus(path=>path===p?source.replace('Array::make(count, None)','Array::make(count - 1, None)'):read(path)));
  const joined='Some(@lower.JoinStep(_)) | Some(@lower.CrossJoinStep(_)) => ()';
  assert.equal(source.split(joined).length,2,'Reach the reviewed CrossJoin scratch branch');
  assert.throws(()=>checkParentCensus(path=>path===p?
    source.replace(joined,'Some(@lower.JoinStep(_)) => ()'):read(path)),
    /Changed reviewed reclaimed-prefix source body or arity/);
  const window='Some(@lower.WindowStep(_)) => ()';
  assert.equal(source.split(window).length,2,'Reach the reviewed Window scratch branch');
  assert.throws(()=>checkParentCensus(path=>path===p?
    source.replace(window,'Some(@lower.WindowStep(_)) => return index'):read(path)),
    /Changed reviewed reclaimed-prefix source body or arity/);
  const singletonSet='Some(@lower.SetStep(_)) if @execution.generated_sequence_step_count(\n          sequence,\n        ) ==\n        1 => ()';
  assert.equal(source.split(singletonSet).length,2,'Reach the reviewed singleton Set guard');
  assert.throws(()=>checkParentCensus(path=>path===p?
    source.replace(singletonSet,singletonSet.replace('1 => ()','2 => ()')):read(path)),
    /Changed reviewed reclaimed-prefix source body or arity/);
  const generated='src/execution_relation/generated_sequence.mbt';
  assert.throws(()=>checkParentCensus(path=>path===generated?read(path).toString().replace('traversal_ceilings : Array[(Int, Int64, Int64)]','traversal_ceilings : Array[(Int, String, Int64)]'):read(path)));
});
for(const [name,replacement] of [
  ['missing borrowed workspace growth',''],
  ['retyped borrowed workspace growth','  working : Array[WorkspaceGrowth]\n'],
  ['additional workspace owner','  working : WorkspaceGrowth?\n  extra_working : WorkspaceGrowth?\n'],
]) test('current census rejects '+name,()=>{
  const path='src/execution_relation/generated_sequence.mbt';
  const original=read(path).toString(),declaration='  working : WorkspaceGrowth?\n';
  assert.equal(original.split(declaration).length,2,'Mutation must reach the unique borrowed field');
  const changed=original.replace(declaration,replacement);
  assert.throws(()=>checkParentCensus(file=>file===path?changed:read(file)),
    /Unreviewed parent\/edge field or type GeneratedSequence/);
});
test('synthetic current source/ABI inputs bind capture roles and every lifecycle phase',()=>{
  assert.match(currentChainSyntheticFixture().role,/^synthetic-current-source-abi;/);
  // actualPhases is the verifier's accepted input count, not observed execution.
  const result=inspectCurrentChain(records());assert.equal(result.actualPhases,7);assert.equal(result.completePhysicalUpper,false);
  for(const mutate of [r=>r[0].callbacks[0].requestedBytes=88,
    r=>r[0].callbacks[0].captures[0].id=r[0].roots.state,
    r=>r[0].environments[0].captures.pop(),r=>r.splice(4,1),
    r=>r[1].callbacks[0].captures[0].id='1']) {
    const r=records(),before=structuredClone(r);mutate(r);assert.notDeepEqual(r,before);assert.throws(()=>inspectCurrentChain(r));
  }
});
test('pending/error cleanup cannot lose the completed occurrence or nested cursor',()=>{
  for(const mutate of [r=>r[3].preparation=null,r=>r[4].read=null,
    r=>r[3].completed.elements[0]=null,r=>r[4].completed.completions[0]='1',
    r=>r[3].completed.slots=0,r=>r[3].children.elements[0]='1',
    r=>r[3].completed.backing=r[3].children.backing,
    r=>r[5].preparation=r[1].preparation,r=>r[6].children.length=1,
    r=>r[1].state.captures.find(c=>c.offset===8).id='1',
    r=>r[6].state.captures.find(c=>c.offset===8).id='1',
    r=>r[7].state.captures.find(c=>c.offset===8).id='1']) {
    const r=records(),before=structuredClone(r);mutate(r);assert.notDeepEqual(r,before);assert.throws(()=>inspectCurrentChain(r));
  }
});
