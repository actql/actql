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
