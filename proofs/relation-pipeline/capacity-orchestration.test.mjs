import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { mutations } from './capacity/instrument.mjs';

// These check the real CLI's scheduling and failure propagation with explicit
// synthetic observations. Product/source/binary/oracle acceptance stays in CI.
function run(options = {}) {
  const root = mkdtempSync(join(tmpdir(), 'actql-capacity-orchestration-'));
  try {
    const result = spawnSync(process.execPath, ['--experimental-test-module-mocks',
      fileURLToPath(new URL('./fixtures/capacity-driver.mjs', import.meta.url)), root, JSON.stringify(options)], { encoding: 'utf8' });
    return { ...result, state: JSON.parse(readFileSync(join(root, 'state.json'))) };
  } finally { rmSync(root, { recursive: true, force: true }); }
}
function coverage(result, targets = ['js', 'wasm', 'native']) {
  assert.equal(result.status, 0, result.stderr);
  const { calls, installs, report, checks, executions, source, observerPresent, closes, parentProbes } = result.state;
  assert.deepEqual(closes, [{ afterCalls: calls.length, receipts: executions.length }]);
  assert.deepEqual(parentProbes, targets.includes('native') ? [{ afterCalls: calls.length, afterClose: 1 }] : []);
  if (targets.includes('native')) assert.equal(report.parentStartup.separateChild, true);
  else assert.equal(report.parentStartup, undefined);
  assert.equal(source, 'healthy'); assert.equal(observerPresent, false);
  assert.equal(mutations.length, 5, 'Explicitly review a changed capacity mutation scope');
  assert.deepEqual(report.mutations.map(m => m.name), mutations.map(m => m.name));
  assert.equal(new Set(executions.map(e => e.path)).size, executions.length);
  const restored = calls.filter(c => c.label.endsWith('-restored'));
  assert.equal(restored.length, mutations.length * targets.length);
  const firstRestored = calls.indexOf(restored[0]);
  assert(calls.slice(firstRestored).every(c => c.label.endsWith('-restored')));
  assert(installs.at(-1).afterCalls === firstRestored);
  assert.equal(installs.length, 4 + mutations.length + 1, 'Exactly one shared healthy installation');
  const expected = [];
  for (const [slot, variant] of mutations.entries()) {
    const record = report.mutations[slot];
    assert.equal(record.minimal.id, `minimum-${slot}`);
    const mutationCalls = calls.filter(c => c.label.startsWith(`capacity-${variant.name}-`) && !c.label.endsWith('-restored'));
    assert.deepEqual(mutationCalls.map(c => c.label), ['search', 'shrink', 'shrink', ...targets.map(() => 'minimal')].map(s => `capacity-${variant.name}-${s}`));
    assert(mutationCalls.every(c => c.source === `instrumented:${variant.name}`));
    assert.deepEqual(mutationCalls[0].inputs.map(c => c.id), mutations.map((_, i) => `search-${i}`));
    assert.deepEqual(mutationCalls.slice(-targets.length).map(c => c.target), targets);
    assert.deepEqual(Object.keys(record.replay), targets); assert.deepEqual(Object.keys(record.healthy), targets);
    for (const target of targets) {
      expected.push({ label: `capacity-${variant.name}-restored`, target, id: `minimum-${slot}` });
      const observation = record.healthy[target];
      assert.equal(observation.caseId, record.minimal.id); assert.equal(observation.target, target);
      assert.equal(observation.correspondence, true);
      const matching = executions.filter(e => e.receipt.cases.some(c => c.observation.observationId === observation.observationId));
      assert.equal(matching.length, 1); assert.equal(matching[0].receipt.target, target);
      assert.deepEqual(matching[0].receipt.cases.map(c => c.testCase), [record.minimal]);
      assert.deepEqual(checks.filter(c => c.observationId === observation.observationId).map(c => c.kind), ['semantics', 'events', 'backing']);
      assert.equal(record.timings.replayMs[target], 10); assert.equal(record.timings.restoredMs[target], 10);
    }
    assert.equal(record.timings.searchMs, 10); assert.equal(record.timings.shrinkMs, 30);
    assert.equal(record.activeDurationMs, 40 + 20 * targets.length);
    const ownRestored = restored.filter(c => c.label === `capacity-${variant.name}-restored`);
    assert.equal(record.durationMs, ownRestored.at(-1).ended - mutationCalls[0].started);
    assert(record.durationMs > record.activeDurationMs);
  }
  assert.deepEqual(restored.map(c => ({ label: c.label, target: c.target, id: c.inputs[0].id })), expected);
  assert(restored.every(c => c.inputs.length === 1 && c.source === 'instrumented:healthy' && c.correspondence));
  assert.deepEqual(Object.keys(report.normal), targets);
  assert.deepEqual(Object.keys(report.boundaries), ['0', '1', '-1']);
  for (const target of targets) {
    assert.equal(report.normal[target].length, 5);
    for (const offset of [-1, 0, 1]) assert.equal(report.boundaries[offset][target].length, 5);
  }
}
test('all five verified minima have fifteen independent healthy executions in one restored block', () => coverage(run()));
test('JS-only mode retains each mutation and its independent healthy replay', () => coverage(run({ target: 'js' }), ['js']));
test('normal-only mode retains normal corpus and all workspace boundaries without mutations', () => {
  const result = run({ normal: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.state.calls.length, 12); assert.equal(result.state.installs.length, 4);
  assert.deepEqual(result.state.report.mutations, []);
  assert.deepEqual(result.state.closes, [{ afterCalls: 12, receipts: 12 }]);
  assert.deepEqual(result.state.parentProbes, [{ afterCalls: 12, afterClose: 1 }]);
  assert.equal(result.state.report.parentStartup.separateChild, true);
  assert.equal(result.state.source, 'healthy'); assert.equal(result.state.observerPresent, false);
});
for (const fail of [
  `capacity-${mutations[0].name}-search:js`, `capacity-${mutations[2].name}-shrink:js`,
  `capacity-${mutations[4].name}-minimal:native`, `capacity-${mutations[0].name}-restored:wasm`,
  `capacity-${mutations[4].name}-restored:native`, 'semantics', 'events', 'backing',
  'input-association', 'restored-fault', 'restore',
]) test(`${fail} cannot produce a completed campaign or restoration claim`, () => {
  const result = run({ fail });
  assert.notEqual(result.status, 0); assert.equal(result.state.report, null);
  assert.deepEqual(result.state.closes, []); assert.deepEqual(result.state.parentProbes, []);
  assert(!result.stdout.includes('Source restored byte-for-byte'));
  assert.equal(result.state.source, fail === 'restore' ? 'contaminated' : 'healthy');
  assert.equal(result.state.observerPresent, false);
  if (fail.includes(':')) assert(!result.state.calls.at(-1).receipt, 'Failed execution is not a killed-mutant receipt');
});
for (const runnerFault of ['omit-wasm', 'duplicate-input', 'wrong-result', 'omit-semantics', 'span-as-active']) {
  test(`independent coverage checks reject runner mutation: ${runnerFault}`, () => {
    const result = run({ runnerFault });
    if (runnerFault === 'duplicate-input') {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Wrong input\/observation association/);
      assert.equal(result.state.report, null);
    } else {
      assert.equal(result.status, 0, result.stderr);
      assert(result.state.report, 'Negative control must reach the independent coverage check');
    }
    assert.throws(() => coverage(result));
  });
}

for (const fail of ['close', 'parent-probe']) {
  test(`${fail} preserves partial receipts and cannot claim a completed parent campaign`, () => {
    const result = run({ fail });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, fail === 'close' ? /Injected executor close failure/ : /Injected parent probe failure/);
    assert(!result.stdout.includes('Source restored byte-for-byte'));
    const { calls, executions, report, closes, parentProbes, executorClosed, parentReportPresent } = result.state;
    assert.equal(result.state.source, 'healthy');
    assert.equal(result.state.observerPresent, false);
    assert(report, 'Completed child receipts remain available after handoff failure');
    assert.deepEqual(report.executions, executions);
    assert.equal(report.parentStartup, undefined);
    assert.equal(parentReportPresent, false);
    assert.deepEqual(closes, [{ afterCalls: calls.length, receipts: executions.length }]);
    assert.equal(executorClosed, fail === 'parent-probe');
    assert.deepEqual(parentProbes, fail === 'parent-probe' ? [{ afterCalls: calls.length, afterClose: 1 }] : []);
  });
}
