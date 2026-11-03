import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import {readFileSync} from 'node:fs';
import {executableMoonSource, checkedInputFunction} from '../relation-chain/evidence.mjs';
import { modelExecution, modelObservationUnits, bindings, checkBindings, coverage, fixture, identityFixture, snapshot, validate } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
function evidence(target = 'js') {
  const source = snapshot(root), artifact = { 'test.js': 'digest' };
  const runs = { lean: { passed: true, exit: 0, target: 'model', count: 14, sourceDigest: source.digest,
    command: [process.execPath, 'proofs/relation-capacity/check.mjs'] } };
  for (const [kind, path] of [['capacity', fixture], ['identity', identityFixture], ['ledger', 'src/physical_resources/ledger_wbtest.mbt']]) {
    runs[`${kind}-${target}`] = { passed: true, exit: 0, sourceDigest: source.digest, target,
      count: kind === 'capacity' ? 3 : 1, artifacts: artifact,
      command: ['moon', 'test', path, '--target', target, '--deny-warn'] };
  }
  return { requested: bindings(), report: { source, target, coverage: coverage(), runs },
    current: { ...source, builtArtifacts: artifact } };
}
test('reviewed inventory and conditional bounds accept all executed targets', () => {
  checkBindings(root, bindings());
  for (const target of ['js', 'wasm', 'native']) {
    const e = evidence(target);
    assert.equal(validate(e.requested, e.report, e.current, target).length, 3);
  }
});
for (const [name, change] of [
  ['profile', x => { x.profile = 'UNCHECKED arbitrary field types'; }],
  ['provider', x => { x.provider = 'delayed-stop/custom-provider'; }],
  ['child callback', x => { x.children[0] = 'delayed-stop/custom-provider'; }],
  ['length', x => { x.length = 100; }],
  ['physical observation', x => { x.observation = 'process heap/RSS'; }],
  ['removed parent premise', x => { x.premises.pop(); }],
  ['discharged parent assumption', x => { x.unresolved.splice(1, 1); }],
  ['unconditional guarantee', x => { x.guarantee = 'all chain live bytes proved bounded'; }],
]) test(`cannot relabel requested capacity ${name} while retaining source and execution`, () => {
  const e = evidence(); change(e.requested[0]);
  assert.throws(() => checkBindings(root, e.requested));
  assert.throws(() => validate(e.requested, e.report, e.current, 'js'));
});
for (const [name, change] of [
  ['stale source', e => { e.current.digest = 'changed'; }],
  ['stale artifact', e => { e.current.builtArtifacts = { 'test.js': 'changed' }; }],
  ['native substitution', e => { e.report.runs['capacity-js'].target = 'native'; }],
  ['wrong fixture', e => { e.report.runs['capacity-js'].command[2] = identityFixture; }],
  ['no executed capacity tests', e => { e.report.runs['capacity-js'].count = 0; }],
  ['missing identity proof', e => { delete e.report.runs['identity-js']; }],
  ['coverage relabeling', e => { e.report.coverage.scopes[0].profile = '*'; }],
  ['shrunk inventory', e => { e.report.source.sources['proofs/relation-capacity/allocations.json'] = 'narrowed'; }],
]) test(`reject ${name}`, () => {
  const e = evidence(); change(e);
  assert.throws(() => validate(e.requested, e.report, e.current, 'js'));
});

for (const [label, change] of [
  ['zero laws', r => { r.count = 0; }],
  ['missing count', r => { delete r.count; }],
  ['null count', r => { r.count = null; }],
  ['partial laws', r => { r.count = 13; }],
  ['extra laws', r => { r.count = 15; }],
  ['string count', r => { r.count = '14'; }],
  ['runtime target', r => { r.target = 'js'; }],
  ['missing target', r => { delete r.target; }],
]) test(`capacity refuses ${label} without discharging physical sizing premises`, () => {
  const e = evidence(); change(e.report.runs.lean);
  assert.throws(() => validate(e.requested, e.report, e.current, 'js'), /model target or theorem count/);
});
test('capacity observes its own 14 conditional laws, not a Session/chain summary', () => {
  const summary = 'Checked 14 capacity theorems, expected types and axiom dependencies; child/parent bounds are premises';
  assert.equal(modelObservationUnits(`audit lines\n${summary}\n`, 0), 14);
  for (const [output, exit] of [
    ['', 0], [summary.replace('14', '13'), 0], [summary.replace('14', '15'), 0],
    ['Checked 14 theorems, expected claim types and axiom dependencies', 0],
    [summary, 1], [summary, null], [`quoted: ${summary}`, 0],
    [`${summary}\n${summary}`, 0], [`sorryAx\n${summary}`, 0],
  ]) assert.throws(() => modelObservationUnits(output, exit), /typed model observation/);
  assert.equal(modelExecution.count, 14);
});

for (const [label, from, to] of [
  ['completed output dropped on pending cleanup', 'Ok(false) => return Ok(false)', 'Ok(false) => { state.completed = []; return Ok(false) }'],
  ['metadata dropped on cleanup error', 'Err(issue) => return Err(issue)', 'Err(issue) => { state.input_preparation = None; return Err(issue) }'],
  ['cursor not cancelled before clear', 'cancel_relation_chain_inputs(cursor)', 'if false { cancel_relation_chain_inputs(cursor) }'],
]) test(`current inventory refuses ${label}, even with all constructor symbols present`, () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const source = readFileSync(root + path, 'utf8');
  assert(source.includes(from));
  // Replace all matching returns/calls: the exact cleanup body must still fail.
  const changed = source.replaceAll(from, to);
  assert.throws(() => checkBindings(root, bindings(), {
    read: p => p === path ? changed : readFileSync(root + p),
  }), /capacity\/cleanup custody connection/);
});


test('current retained quote refuses substituted dimensions inside the real constructor', () => {
  const path = 'src/execution_relation/execution_capacity.mbt';
  const original = readFileSync(root + path, 'utf8');
  for (const [from, to] of [
    ['rows.retained_entries.to_int64()', 'rows.operation_entries.to_int64()'],
    ['rows.metadata_entries.to_int64()', 'rows.operation_entries.to_int64()'],
    ['count: retained_roots', 'count: metadata_scratch'],
    ['count: metadata_scratch', 'count: retained_roots'],
    ['limits.rows.metadata_entries.to_int64(),\n    false,', 'limits.rows.metadata_entries.to_int64(),\n    true,'],
    ['rows.output_values.max_nodes.to_int64()', 'rows.input_values.max_nodes.to_int64()'],
    ['rows.output_values.max_text_bytes.to_int64()', 'rows.input_values.max_text_bytes.to_int64()'],
    ['retained_bytes: retained, execution_bytes: execution', 'retained_bytes: execution, execution_bytes: execution'],
  ]) {
    const changed = original.replace(from, to);
    assert.notEqual(changed, original, 'actual selected mutation site');
    assert.throws(() => checkBindings(root, bindings(), {
      read: p => p === path ? changed : readFileSync(root + p),
    }), /inventory connection|retained capacity quote connection/);
  }
});

test('retained quote comments or another function cannot replace its actual connection', () => {
  const path = 'src/execution_relation/execution_capacity.mbt';
  const original = readFileSync(root + path, 'utf8');
  const from = 'count: retained_roots';
  const unrelated = 'fn unrelated_capacity_quote() ' + checkedInputFunction(
    executableMoonSource(original), 'generated_sequence_capacity_with_roots')
    .replaceAll('count:', 'count: ');
  for (const extra of ['\n// ' + original.replaceAll('\n', '\n// ') + '\n',
    '\n' + unrelated]) {
    const changed = original.replace(from, 'count: rows.operation_entries.to_int64()') + extra;
    assert.throws(() => checkBindings(root, bindings(), {
      read: p => p === path ? changed : readFileSync(root + p),
    }), /retained capacity quote connection/);
  }
});
