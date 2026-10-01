import assert from 'node:assert/strict';
import { inspect, oracle, program } from './engine.mjs';
import { hash, checkBaseline } from './inventory.mjs';
import { premises } from '../relation-chain/evidence.mjs';
import { baseRegistry, registry as reviewedRegistry } from './registry.mjs';
export { premises };
export const profile = 'finite successful numeric/NULL Relation pipelines; owned Values occurrence order; no candidate key assertion';
export const inherited = ['reported work is child work plus attempted handoff charges',
  'remaining budget preserves consumed work across children',
  'started child cleanup responsibility survives failure and cancellation',
  'terminal and cleanup retry do not restart Compute'];
export function compareSemantics(testCase, observation, registry) {
  const expected = oracle(testCase, registry);
  assert.equal(observation.kind, 'complete', 'Success domain reached failure');
  assert.deepEqual(observation.columns, expected.columns, 'Projection/schema columns differ');
  assert.deepEqual(observation.schemaColumns, [...expected.columns].sort(), 'Canonical schema differs');
  for (const row of observation.wireRows) assert.deepEqual(Object.keys(row), expected.columns, 'Authored wire projection order differs');
  assert.deepEqual(observation.rows, expected.rows, 'Ordered row values differ');
  return expected;
}
export function validate(report, current, registry) {
  assert([baseRegistry, reviewedRegistry].some(approved => approved.length === registry.length &&
    registry.every((descriptor, i) => descriptor === approved[i])), 'Unreviewed operation/variant registry');
  assert.equal(report.version, 'actql-relation-pipeline-evidence/0.1');
  assert.equal(report.profile, profile, 'Unreviewed scope profile');
  assert.deepEqual(report.source, current, 'Stale source');
  assert.equal(hash(JSON.stringify(report.source.sources)), report.source.digest);
  assert.deepEqual(report.inherited, inherited);
  assert.deepEqual(report.premises, premises);
  assert.deepEqual(report.evidenceKinds, ['formal-model', 'tested-refinement', 'independent-semantic-check']);
  assert(report.residual.includes('No arbitrary registry/length implementation refinement; capacity remains conditional'));
  assert.deepEqual(report.registry, registry.map(d => d.name));
  assert(['js', 'wasm', 'native'].includes(report.target));
  for (const [id, file] of [['session', 'proofs/bounded-session/check.mjs'], ['chain', 'proofs/relation-chain/check.mjs']]) {
    const run = report.models[id];
    assert(run?.passed && run.exit === 0 && run.sourceDigest === current.digest);
    assert.deepEqual(run.command.slice(1), [file]);
  }
  assert(report.executions.length > 0);
  let count = 0;
  const ids = new Set();
  for (const execution of report.executions) {
    const run = execution.receipt;
    assert.equal(execution.digest, hash(JSON.stringify(run)), 'Changed execution record');
    assert.equal(run.sourceDigest, current.digest, 'Unrelated execution source');
    assert.equal(run.compiler, report.toolchain.moonc);
    assert.equal(run.target, report.target, 'Target mismatch');
    assert.equal(run.correspondence, true, 'Missing actual selected adapter correspondence');
    assert.equal(run.exit, 0);
    assert.deepEqual(run.command, ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', report.target, '--deny-warn']);
    assert(Object.keys(run.artifacts).length > 0);
    for (const [path, digest] of Object.entries(run.artifacts)) {
      assert(path.startsWith(`_build/${report.target}/debug/test/query_integration/`));
      assert.match(digest, /^[0-9a-f]{64}$/);
    }
    for (const entry of run.cases) {
      const states = inspect(entry.testCase, registry);
      assert.equal(entry.caseDigest, hash(JSON.stringify(entry.testCase)));
      assert.deepEqual(entry.program, program(entry.testCase, registry), 'Requested case/program mismatch');
      const actual = entry.observation;
      // These strings and the order origin come from the real MoonBit harness
      // arguments/checker, independently of a requested label or derived claim.
      assert.equal(actual.source, entry.program.source, 'Executed input scope differs');
      assert.equal(actual.steps, entry.program.steps, 'Executed sequence scope differs');
      assert.equal(actual.id, entry.id);
      assert(actual.checked && actual.registered && actual.correspondence);
      assert.equal(actual.stepCount, entry.testCase.steps.length);
      const origin = states.at(-1).order.origin;
      assert.equal(actual.orderOrigin, origin === 'prior' ? 'input:0' : `step:${origin.slice(1)}`);
      assert.equal(actual.work, actual.referenceWork);
      assert.equal(actual.cancelConfirmedChildren + actual.alreadyTerminalChildren, actual.stepCount);
      assert(actual.cancelConfirmedChildren >= 0 && actual.alreadyTerminalChildren >= 0);
      assert.deepEqual(actual.faults, []);
      compareSemantics(entry.testCase, actual, registry);
      assert.deepEqual(actual.tableRows, actual.wireRows.map(row => actual.schemaColumns.map(field => row[field])), 'Cell/wire observation differs');
      assert(!ids.has(entry.testCase.id), 'Duplicate case identity');
      ids.add(entry.testCase.id);
      count++;
    }
  }
  assert(count > 0);
  assert.equal(report.caseCount, count);
  assert.deepEqual(report.requested, report.executions.flatMap(e => e.receipt.cases.map(c => c.caseDigest)), 'Requested/independently executed scope mismatch');
  return { target: report.target, finiteCases: count, inherited: [...inherited], profile };
}
export function reviewRoute(root) {
  checkBaseline(root);
  // checkBaseline freezes the common laws; production connection checking is
  // supported by the newly executed registered child/kernel/chain witness.
}
