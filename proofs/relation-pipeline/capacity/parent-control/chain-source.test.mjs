import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkChainCensus} from './bounds.mjs';
import {checkChainSource} from './chain-source.mjs';
import {reviewedFunction} from './provider-construction-source-review.mjs';
import {currentOverlay} from './current-overlay.mjs';
import {parentStartupLayout} from '../backing/parent-layout.mjs';
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
test('advance captures the audited Int prefix, not its callback-local Boolean',()=>{
  const checked=checkChainSource(source);
  assert(checked.captureRoles.advance.includes('reclaimed_prefix'));
  assert(!checked.captureRoles.advance.includes('reclaims_scratch'));
  assert.throws(()=>checkChainSource(source.replace('state.position <= reclaimed_prefix',
    'state.position <= count')),/Unreviewed advance source captures/);
  const start=source.indexOf('fn bounded_relation_chain_execution_state(');
  assert(start>=0);
  const constructor=source.slice(start);
  const declaration='let reclaimed_prefix = relation_chain_reclaimed_prefix(sequence)';
  assert.equal(constructor.split(declaration).length,2,
    'Prefix mutation must reach the unique parent initializer, not the capacity function');
  const changed=source.slice(0,start)+constructor.replace(declaration,'let reclaimed_prefix = count');
  assert.throws(()=>checkChainSource(changed),/Changed reviewed reclaimed-prefix call count/);
});
test('the observer remains outside original callbacks and uses real state return',()=>{
  const overlay=currentOverlay(read);
  const actual=overlay['src/connectors/local/selected_relation_provider.mbt'];
  assert(actual.includes('let (observed_parent, original_state) = pair'));
  assert(actual.includes('    pair\n  })'));
  assert.equal(actual.split('println(current_chain_start_probe(').length,2);
  const constructor=reviewedFunction(source,'bounded_relation_chain_execution_state');
  const before=constructor.slice(constructor.indexOf('      quantum => {'),constructor.indexOf('    ),\n  ).map(active => {'));
  assert(actual.includes(before),'Observer must not add captures inside callbacks');
  const continuation = constructor.slice(constructor.indexOf('  ).map(active => {'));
  assert(actual.includes(continuation.slice(0, continuation.lastIndexOf('\n}'))),
    'Observation must retain the complete original cleanup-continuation installation');
  assert(actual.includes('max_value_bytes, reclaimed_prefix))'));
  assert(!actual.includes('max_value_bytes, reclaims_scratch))'));
  assert(overlay['src/connectors/local/current_chain_capacity_native.mbt']
    .includes('reclaimed_prefix : Int'));
  const reader=overlay['src/connectors/local/current_chain_capacity_stub.c'];
  assert(reader.includes('int32_t reclaimed_prefix'));
  assert(reader.includes('reclaimed_prefix==count?"true":"false"'),
    'Legacy all-eligible metadata must not classify a partial prefix as full');
});

// Source roles are independent from retained historical Native measurements.
test('current advance borrows its byte limit only through start-next ownership', () => {
  const checked = checkChainSource(source);
  assert(checked.captureRoles.startNext.includes('max_value_bytes'));
  assert(!checked.captureRoles.advance.includes('max_value_bytes'));
  const changed = source.replace('quantum => {\n        if quantum <= 0 || terminal.val',
    'quantum => {\n        let unexpected_limit = max_value_bytes\n        if quantum <= 0 || terminal.val');
  assert.notEqual(changed, source);
  assert.throws(() => checkChainSource(changed), /Unreviewed advance source captures/);
});

test('current provider census retains the original optional Infer prefix recipe', () => {
  const census = checkChainCensus(read);
  const provider = census.sourceFields.find(entry => entry.struct === 'ManagedProvider');
  assert.deepEqual(provider.fields.map(field => field.name),
    ['accepts', 'capacity', 'start', 'start_numeric', 'infer_relation_prefix']);
  const path = 'src/connectors/local/managed_provider.mbt';
  const original = read(path).toString();
  const changed = original.replace('infer_relation_prefix : (', 'infer_relation_prefix : Array[(');
  assert.notEqual(changed, original);
  assert.throws(() => checkChainCensus(p => p === path ? changed : read(p)),
    /Unreviewed parent\/edge field or type ManagedProvider/);
});

test('current Native observer binds all eight execution slots and separate continuation', () => {
  const fields=checkChainCensus(read).sourceFields
    .find(entry=>entry.struct==='ManagedProviderExecution').fields;
  assert.deepEqual(fields.at(-2),{name:'retained_completion',type:'(() -> Bool)?'});
  assert.deepEqual(fields.at(-1),{name:'cleanup_continuation',type:'(() -> Int64)?'});
  const reader=readFileSync(new URL('./current-reader.c',import.meta.url),'utf8');
  const shape=reader.match(/current_shape\(parent\);assert\(s\[0\]==(\d+) && s\[1\]==(\d+)\)/);
  assert(shape,'Missing exact parent layout refusal');
  assert.equal(Number(shape[1]),fields.length*2);
  assert.equal(Number(shape[2]),fields.length);
  const references=reader.match(/for\(int i=0;i<(\d+);i\+\+\)assert\(s\[2\+i\]/);
  assert.equal(Number(references[1]),fields.length);
  assert(reader.includes('current_record(j,current_pointer(parent,56))'));
  assert(reader.includes('assert(current_pointer(parent,48)==NULL);'));
  // Preserve the retained conditional arithmetic, without using it to size
  // the new owner and callback. Actual current extents are checked separately.
  assert.equal(parentStartupLayout().blocks.owner,64);
  assert.equal(checkChainSource(source).cleanupContinuation.includedInRetainedCoreBound,false);
});

for (const [name, from, to] of [
  ['active child', '!terminal.val || reclaimed.val || cleanup_index.val < 0', 'reclaimed.val || cleanup_index.val < 0'],
  ['reclaimed owner', '!terminal.val || reclaimed.val || cleanup_index.val < 0', '!terminal.val || cleanup_index.val < 0'],
  ['different child', '.get(cleanup_index.val)', '.get(0)'],
  ['invented progress', '.unwrap_or(-1L)', '.unwrap_or(1L)'],
]) test('cleanup continuation source rejects '+name, () => {
  const changed=source.replace(from,to);assert.notEqual(changed,source);
  assert.throws(()=>checkChainSource(changed),/Changed reviewed representation delta/);
});

for (const [name, replacement] of [
  ['missing', ''], ['retyped', '  mut cleanup_continuation : (() -> Bool)?\n'],
  ['additional owner', '  mut cleanup_continuation : (() -> Int64)?\n  mut extra_continuation : (() -> Int64)?\n'],
]) test('typed census rejects '+name+' cleanup continuation', () => {
  const path='src/connectors/local/managed_provider.mbt', original=read(path).toString();
  const field='  mut cleanup_continuation : (() -> Int64)?\n';
  assert.equal(original.split(field).length,2);
  assert.throws(()=>checkChainCensus(p=>p===path?original.replace(field,replacement):read(p)),
    /Unreviewed parent\/edge field or type ManagedProviderExecution/);
});

test('current generated recipe borrows one original query-time identity', () => {
  const census = checkChainCensus(read);
  const state = census.sourceFields.find(entry => entry.struct === 'GeneratedSequence');
  assert.deepEqual(state.fields.find(field => field.name === 'query_time'),
    {name: 'query_time', type: '@publication.QueryEvaluationTime?'});
  const path = 'src/execution_relation/generated_sequence.mbt';
  const original = read(path).toString();
  const changed = original.replace('query_time : @publication.QueryEvaluationTime?',
    'query_time : Array[@publication.QueryEvaluationTime]');
  assert.notEqual(changed, original);
  assert.throws(() => checkChainCensus(p => p === path ? changed : read(p)),
    /Unreviewed parent\/edge field or type GeneratedSequence/);
});

test('current metadata cursor does not regain obsolete per-operation scalar caps', () => {
  const path = 'src/connectors/local/relation_chain_input_preparation.mbt';
  const original = read(path).toString();
  for (const field of ['max_entries', 'max_value_bytes']) {
    const changed = original.replace('priv struct RelationChainInputPreparation {',
      `priv struct RelationChainInputPreparation {\n  ${field} : Int`);
    assert.notEqual(changed, original);
    assert.throws(() => checkChainCensus(p => p === path ? changed : read(p)),
      /Unreviewed parent\/edge field or type RelationChainInputPreparation/);
  }
});

// This is caller/source correspondence; the Native diagnostic owns execution.
test('current Native census transfers original completion through the selected four-argument cursor', () => {
  const overlay = currentOverlay(read);
  const fixture = overlay['src/connectors/local/current_chain_capacity_wbtest.mbt'];
  const call = fixture.match(/let transferred_preparation = start_relation_chain_inputs\(([\s\S]*?)\)\.unwrap\(\)/u);
  assert(call, 'The census must retain its original transferred-preparation call');
  assert.equal(call[1].replace(/\s+/gu, ' ').trim(),
    'sequence, 1, [managed_provider_relation_input(read)], completed,');
  const preparation = read('src/connectors/local/relation_chain_input_preparation.mbt').toString();
  assert.match(preparation, /fn start_relation_chain_inputs\(\s*sequence : @execution\.GeneratedSequence,\s*position : Int,\s*inputs : Array\[ManagedProviderInput\],\s*completed : Array\[@execution\.CompletedOutput\?\],\s*\)/u);
  assert(preparation.includes('@execution.bound_producer_read_demand(cursor.owner, bound)'));
  assert(preparation.includes('@execution.producer_read_demand_entries(demand)'));
  assert(preparation.includes('@execution.producer_read_demand_name_bytes(demand)'));
  assert(fixture.includes('physical_equal(state.completed[0].unwrap(), output)'));
  assert(fixture.includes('cancel_relation_chain_inputs(transferred_preparation)'));
  assert(fixture.includes('@execution.producer_read_available(final_read)'));
});

// Machine-code admission must recognize this same reviewed query, not any
// equal-named helper with an unreviewed body, arity or new mutable owner.
test('current reclaimed-prefix helper retains reviewed body and original sequence arity',()=>{
  checkChainSource(source);
  const start=source.indexOf('fn relation_chain_reclaimed_prefix(');
  const end=source.indexOf('\n///|',start);
  const original=source.slice(start,end);
  for(const [before,after] of [
    ['sequence : @execution.GeneratedSequence,','sequence : @execution.GeneratedSequence, extra : Int,'],
    ['return index','return index + 1'],
    [') -> Int {',') -> Int {\n  let new_owner = Ref(0)'],
  ]) {
    const changed=original.replace(before,after);assert.notEqual(changed,original);
    assert.throws(()=>checkChainSource(source.slice(0,start)+changed+source.slice(end)),/reviewed reclaimed-prefix/);
  }
  const call='let reclaimed_prefix = relation_chain_reclaimed_prefix(sequence)';
  const parent=source.indexOf('fn bounded_relation_chain_execution_state(');
  assert(parent>=0);
  const duplicate=source.slice(0,parent)+source.slice(parent).replace(call,call+'\n  let duplicate = relation_chain_reclaimed_prefix(sequence)');
  assert.throws(()=>checkChainSource(duplicate),/reviewed reclaimed-prefix call count/);
});
