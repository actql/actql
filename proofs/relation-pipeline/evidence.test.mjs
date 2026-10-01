import assert from 'node:assert/strict';
import { test } from 'node:test';
import { generate, oracle, program, clone } from './engine.mjs';
import { baseRegistry } from './registry.mjs';
import { profile, inherited, premises, validate } from './evidence.mjs';
import { hash } from './inventory.mjs';
import { connectionAnchor, connectionMismatch, orderMismatch } from './mismatch.mjs';

// Gate unit fixture only: no claim that these synthetic records executed.
function fixture() {
  const testCase = generate(baseRegistry)[1];
  const expected = oracle(testCase, baseRegistry);
  const p = program(testCase, baseRegistry);
  const source = { sources: { 'example': hash('source') } };
  source.digest = hash(JSON.stringify(source.sources));
  const origin = expected.states.at(-1).order.origin;
  const observation = { id: 'executed:0', source: p.source, steps: p.steps,
    kind: 'complete', checked: true, registered: true, correspondence: true,
    columns: expected.columns, schemaColumns: [...expected.columns].sort(), rows: expected.rows,
    wireRows: expected.rows.map(row => Object.fromEntries(expected.columns.map((f, i) => [f, row[i]]))),
    tableRows: expected.occurrences.map(row => [...expected.columns].sort().map(f => row.values[f])),
    stepCount: testCase.steps.length, orderOrigin: origin === 'prior' ? 'input:0' : `step:${origin.slice(1)}`,
    work: 3, referenceWork: 3, cancelConfirmedChildren: 2, alreadyTerminalChildren: 0, faults: [] };
  const receipt = { target: 'js', correspondence: true, compiler: 'unit-test-only', sourceDigest: source.digest,
    exit: 0, command: ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', 'js', '--deny-warn'],
    artifacts: { '_build/js/debug/test/query_integration/unit.js': hash('binary') },
    cases: [{ id: observation.id, testCase, program: p, caseDigest: hash(JSON.stringify(testCase)), observation }] };
  const report = { version: 'actql-relation-pipeline-evidence/0.1', profile, source, target: 'js',
    registry: baseRegistry.map(d => d.name), inherited, premises,
    models: Object.fromEntries(['session', 'chain'].map(id => [id, {
      passed: true, exit: 0, sourceDigest: source.digest,
      command: ['node', `proofs/${id === 'session' ? 'bounded-session' : 'relation-chain'}/check.mjs`],
    }])), toolchain: { moonc: 'unit-test-only' },
    evidenceKinds: ['formal-model', 'tested-refinement', 'independent-semantic-check'],
    residual: ['No arbitrary registry/length implementation refinement; capacity remains conditional'],
    caseCount: 1, requested: [receipt.cases[0].caseDigest],
    executions: [{ receipt, digest: hash(JSON.stringify(receipt)) }] };
  return { report, source };
}
function reseal(report) {
  const execution = report.executions[0];
  execution.digest = hash(JSON.stringify(execution.receipt));
}
test('finite gate accepts its exact independently observed request', () => {
  const { report, source } = fixture();
  assert.equal(validate(report, source, baseRegistry).finiteCases, 1);
});
test('copied operation names cannot substitute an unreviewed variant/oracle', () => {
  const { report, source } = fixture();
  const copied = baseRegistry.map(d => ({ ...d, profile: 'UNCHECKED arbitrary field types' }));
  assert.throws(() => validate(report, source, copied), /Unreviewed/);
});
for (const [name, change] of [
  ['profile widened on both requested/derived sides', r => { r.profile = 'UNCHECKED arbitrary field types'; }],
  ['target relabeled', r => { r.target = 'native'; }],
  ['unreviewed premise substituted', r => { r.premises = ['any provider is stopped after cancel']; }],
  ['connection and derived program relabeled together while execution stays fixed', r => {
    const entry = r.executions[0].receipt.cases[0];
    entry.testCase.steps[0].args = { mode: 'true' };
    entry.program = program(entry.testCase, baseRegistry);
    entry.caseDigest = hash(JSON.stringify(entry.testCase));
    r.requested = [entry.caseDigest];
  }],
  ['order origin relabeled', r => { r.executions[0].receipt.cases[0].observation.orderOrigin = 'physical enumeration'; }],
  ['selected adapter correspondence absent', r => { r.executions[0].receipt.correspondence = false; }],
  ['registered execution absent', r => { r.executions[0].receipt.cases[0].observation.registered = false; }],
  ['consumed budget reset', r => { r.executions[0].receipt.cases[0].observation.work++; }],
  ['models substituted', r => { r.models.chain.command = ['node', 'proofs/bounded-session/check.mjs']; }],
  ['cell/wire observations inconsistent', r => { r.executions[0].receipt.cases[0].observation.tableRows = [[99]]; }],
]) test(`reject ${name}, including resealed execution metadata`, () => {
  const { report, source } = fixture(); change(report); reseal(report);
  assert.throws(() => validate(report, source, baseRegistry));
});
test('shrinking connection witness cannot change to a different failed edge', () => {
  const c = generate(baseRegistry)[1];
  const anchor = connectionAnchor(c);
  const observation = { checked: true, registered: true, kind: 'failed', faults: [
    { kind: anchor.kind, receiver: 1, expectedPort: 0, usedPort: 1 },
  ] };
  assert(connectionMismatch(c, observation, anchor));
  const different = clone(c); different.steps[0].id = 'other';
  assert(!connectionMismatch(different, observation, anchor));
  assert(!connectionMismatch(c, { ...observation, faults: [] }, anchor));
});
test('order mismatch requires the same distinguishable equal-key occurrence pair', () => {
  const c = { id: 'pair', rows: [
    { id: 'a', values: { extra: 0, k: null, tag: 1 } },
    { id: 'b', values: { extra: 0, k: null, tag: -1 } },
  ], steps: [{ id: 's', op: 'sort', args: { field: 'k', dir: 'asc', nulls: 'first' } }] };
  const expected = oracle(c, baseRegistry);
  const anchor = { sort: 's', field: 'k', rows: ['a', 'b'] };
  const actual = { checked: true, registered: true, kind: 'complete', columns: expected.columns, rows: [...expected.rows].reverse() };
  assert(orderMismatch(c, actual, anchor, baseRegistry));
  assert(!orderMismatch(c, actual, { ...anchor, sort: 'another sort' }, baseRegistry));
  const changed = clone(c); changed.rows[1].values.k = 1;
  assert(!orderMismatch(changed, actual, anchor, baseRegistry));
});
