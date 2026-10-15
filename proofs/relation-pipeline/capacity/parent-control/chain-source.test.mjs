import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkChainCensus} from './bounds.mjs';
import {checkChainSource} from './chain-source.mjs';
import {currentOverlay} from './current-overlay.mjs';
const source=readFileSync(new URL('../../../../src/connectors/local/selected_relation_provider.mbt',import.meta.url),'utf8');
const read=p=>readFileSync(new URL('../../../../'+p,import.meta.url));
test('current aggregated state and both retained preparation cursors are independently typed',()=>{
  const census=checkChainCensus(read);
  assert.deepEqual(census.chainReferences,['used','cancelled','terminal','reclaimed','cleanup_index']);
  for(const name of ['RelationChainExecutionState','RelationChainInputPreparation','ProducerReadPreparation'])
    assert(census.sourceFields.some(s=>s.struct===name));
  assert.throws(()=>checkChainCensus(p=>p==='src/connectors/local/selected_relation_provider.mbt'?
    source.replace('mut input_preparation : RelationChainInputPreparation?','mut input_preparation : Array[RelationChainInputPreparation]'):read(p)),/field or type/);
});
test('current selected context explicitly retains the adopted Calendar ceiling field',()=>{
  const census=checkChainCensus(read);
  const state=census.sourceFields.find(entry=>entry.struct==='GeneratedSequence');
  assert.deepEqual(state.fields.find(field=>field.name==='calendar_output_ceilings'),
    {name:'calendar_output_ceilings',type:'Array[(Int, Int64)]'});
});
for(const [name,replacement] of [
  ['missing Calendar ceiling field',''],
  ['changed Calendar ceiling type','  calendar_output_ceilings : Array[(Int, Int)]\n'],
  ['additional Calendar owner','  calendar_output_ceilings : Array[(Int, Int64)]\n  extra_calendar_owner : Int\n'],
]) test('typed source census rejects '+name,()=>{
  const path='src/execution_relation/generated_sequence.mbt';
  const original=read(path).toString();
  const declaration='  calendar_output_ceilings : Array[(Int, Int64)]\n';
  assert.equal(original.split(declaration).length,2,'Mutation must reach the unique adopted declaration');
  const changed=original.replace(declaration,replacement);
  assert.throws(()=>checkChainCensus(p=>p===path?changed:read(p)),
    /Unreviewed parent\/edge field or type GeneratedSequence/);
});
test('source capture and cleanup admission reject lost or added responsibilities',()=>{
  checkChainSource(source);
  assert.throws(()=>checkChainSource(source.replace('fn() { terminal.val }','fn() { cancelled.val || terminal.val }')),/stopped source captures/);
  assert.throws(()=>checkChainSource(source.replace('state.completed[state.position] = Some(output)','state.completed[state.position] = None')),/output occurrence custody/);
  assert.throws(()=>checkChainSource(source.replace('Ok(false) => return Ok(false)','Ok(false) => state.children = []')),/succeed before dropping custody/);
  assert.throws(()=>checkChainSource(source.replace('cancelled.val = true\n        if state.current','cancelled.val = true\n        state.input_preparation = None\n        if state.current')),/drops pending input custody/);
});
test('the observer remains outside original callbacks and uses real state return',()=>{
  const overlay=currentOverlay(read);
  const actual=overlay['src/connectors/local/selected_relation_provider.mbt'];
  assert(actual.includes('Ok((observed_parent, state))'));
  assert.equal(actual.split('println(current_chain_start_probe(').length,2);
  const constructor=source.slice(source.indexOf('fn bounded_relation_chain_execution_state('));
  const before=constructor.slice(constructor.indexOf('      quantum => {'),constructor.indexOf('    ),\n  ).map(active => (active, state))'));
  assert(actual.includes(before),'Observer must not add captures inside callbacks');
});
