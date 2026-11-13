import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { mutations } from './capacity/instrument.mjs';
import { capacityPartIds, capacityObligationsByPart, partRole } from './proof-parts.mjs';

const normalPart = capacityPartIds.find(id => partRole(id) === 'capacity-normal');
const supportPart = capacityPartIds.find(id => partRole(id) === 'capacity-support');
const mutantParts = capacityPartIds.filter(id => partRole(id) === 'capacity-mutants');

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
  const { calls, installs, report, checks, executions, source, observerPresent, closes, custodyProbes, parentProbes } = result.state;
  assert.deepEqual(closes, [{ afterCalls: calls.length, receipts: executions.length }]);
  assert.deepEqual(custodyProbes, [{ afterCalls: calls.length, afterClose: 1, target: targets.length === 1 ? 'js' : 'all' }]);
  assert.equal(report.custody.separateChild, true);
  assert.deepEqual(parentProbes, targets.includes('native') ? [{ afterCalls: calls.length, afterClose: 1, afterCustody: 1 }] : []);
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
  assert.deepEqual(result.state.custodyProbes, [{ afterCalls: 12, afterClose: 1, target: 'all' }]);
  assert.equal(result.state.report.custody.separateChild, true);
  assert.deepEqual(result.state.parentProbes, [{ afterCalls: 12, afterClose: 1, afterCustody: 1 }]);
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
  assert.deepEqual(result.state.closes, []); assert.deepEqual(result.state.custodyProbes, []); assert.deepEqual(result.state.parentProbes, []);
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

for (const fail of ['close', 'custody-probe', 'parent-probe']) {
  test(`${fail} preserves partial receipts and cannot claim a completed parent campaign`, () => {
    const result = run({ fail });
    assert.notEqual(result.status, 0);
    const expected = { close: /Injected executor close failure/, 'custody-probe': /Injected custody probe failure/,
      'parent-probe': /Injected parent probe failure/ };
    assert.match(result.stderr, expected[fail]);
    assert(!result.stdout.includes('Source restored byte-for-byte'));
    const { calls, executions, report, closes, custodyProbes, parentProbes, executorClosed, parentReportPresent } = result.state;
    assert.equal(result.state.source, 'healthy');
    assert.equal(result.state.observerPresent, false);
    assert(report, 'Completed child receipts remain available after handoff failure');
    assert.deepEqual(report.executions, executions);
    assert.equal(report.parentStartup, undefined);
    assert.equal(parentReportPresent, false);
    assert.deepEqual(closes, [{ afterCalls: calls.length, receipts: executions.length }]);
    assert.equal(executorClosed, fail !== 'close');
    assert.deepEqual(custodyProbes, fail === 'close' ? [] : [{ afterCalls: calls.length, afterClose: 1, target: 'all' }]);
    assert.deepEqual(parentProbes, fail === 'parent-probe' ? [{ afterCalls: calls.length, afterClose: 1, afterCustody: 1 }] : []);
  });
}



test('normal fragment retains complete corpus/boundaries and closes without claiming support or mutants', () => {
  const result = run({ part: normalPart });
  assert.equal(result.status, 0, result.stderr);
  const { calls, installs, report, closes, custodyProbes, parentProbes, restoredCloses } = result.state;
  assert.equal(result.state.checkpoint, null);
  assert.equal(report.kind, 'capacity-part'); assert.equal(report.part, normalPart); assert.equal(report.complete, true);
  assert.equal(calls.length, 12); assert.equal(installs.length, 4);
  for (const field of ['backingCore', 'backingModel', 'model', 'custody', 'parentStartup', 'mutations', 'postRestore'])
    assert.equal(report[field], undefined);
  assert.deepEqual(Object.keys(report.normal), ['js', 'wasm', 'native']);
  assert.deepEqual(closes, [{ afterCalls: 12, receipts: 12 }]);
  assert.deepEqual(custodyProbes, []); assert.deepEqual(parentProbes, []); assert.deepEqual(restoredCloses, []);
  assert.deepEqual(Object.values(report.executionOwners).map(o => o.phase), ['instrumented']);
  assert.equal(result.state.source, 'healthy'); assert.equal(result.state.observerPresent, false);
});

test('support fragment retains its independent Core/models/custody/parent receipts with no fabricated pipeline owner', () => {
  const result = run({ part: supportPart });
  assert.equal(result.status, 0, result.stderr);
  const { report, calls, installs, closes, custodyProbes, parentProbes } = result.state;
  assert.equal(report.complete, true); assert.equal(report.part, supportPart);
  assert.deepEqual(calls, []); assert.deepEqual(installs, []);
  assert.deepEqual(report.executions, []); assert.deepEqual(report.executionOwners, {});
  assert.deepEqual(closes, [{ afterCalls: 0, receipts: 0 }]);
  assert.deepEqual(custodyProbes, [{ afterCalls: 0, afterClose: 1, target: 'all' }]);
  assert.deepEqual(parentProbes, [{ afterCalls: 0, afterClose: 1, afterCustody: 1 }]);
  assert.deepEqual(report.backingCore.targets, ['js', 'wasm', 'native']);
  for (const name of ['backingModel', 'model', 'custody', 'parentStartup']) assert(report[name]);
  for (const name of ['normal', 'boundaries', 'mutations', 'postRestore']) assert.equal(report[name], undefined);
  assert.equal(result.state.checkpoint, null);
  assert.equal(result.state.source, 'healthy'); assert.equal(result.state.observerPresent, false);
});

for (const part of mutantParts) test(`${part} preserves every assigned complete search/shrink/replay/restoration atom`, () => {
  const result = run({ part });
  assert.equal(result.status, 0, result.stderr);
  const { calls, installs, report, closes, restoredCloses, custodyProbes, parentProbes, checks } = result.state;
  const names = capacityObligationsByPart[part].mutations, count = names.length;
  assert.equal(result.state.checkpoint, null);
  assert.equal(report.kind, 'capacity-part'); assert.equal(report.part, part); assert.equal(report.complete, true);
  for (const field of ['normal', 'boundaries', 'backingCore', 'model', 'backingModel', 'custody', 'parentStartup']) assert.equal(report[field], undefined);
  assert.deepEqual(report.mutations.map(m => m.name), names);
  assert.equal(installs.length, count + 1);
  assert.equal(calls.length, 12 * count); assert.equal(report.executions.length, 12 * count);
  assert.deepEqual(closes, [{ afterCalls: 9 * count, receipts: 9 * count }]);
  assert.deepEqual(restoredCloses, [{ afterCalls: 12 * count, receipts: 12 * count }]);
  assert.deepEqual(custodyProbes, []); assert.deepEqual(parentProbes, []);
  const primary = report.executionOwners['primary-owner'], restored = report.executionOwners['restored-owner'];
  assert(primary.closed && restored.closed); assert.equal(primary.paths.length, 9 * count); assert.equal(restored.paths.length, 3 * count);
  assert.equal(restored.predecessor, primary.id); assert.equal(restored.root, primary.root);
  assert.equal(report.postRestore.timings.totalMs, 30 * count);
  assert.deepEqual(Object.keys(report.postRestore.timings.replayMs), names);
  for (const [i, name] of names.entries()) {
    const slot = mutations.findIndex(m => m.name === name);
    const mutant = calls.filter(c => c.label.startsWith(`capacity-${name}-`));
    assert.deepEqual(mutant.map(c => c.label.slice(`capacity-${name}-`.length)),
      ['search', 'shrink', 'shrink', 'minimal', 'minimal', 'minimal', 'restored', 'restored', 'restored', 'post-restore', 'post-restore', 'post-restore']);
    assert(mutant.slice(0, 6).every(c => c.source === `instrumented:${name}`));
    assert(mutant.slice(6, 9).every(c => c.source === 'instrumented:healthy'));
    assert(mutant.slice(9).every(c => c.source === 'healthy' && c.correspondence));
    assert(mutant.slice(3).every(c => c.inputs.length === 1 && c.inputs[0].id === `minimum-${slot}`));
    assert.deepEqual(report.postRestore.timings.replayMs[name], { js: 10, wasm: 10, native: 10 });
    const record = report.postRestore.records[i];
    assert.equal(record.name, name); assert.deepEqual(record.minimal, report.mutations[i].minimal);
    for (const [target, observation] of Object.entries(record.observations)) {
      assert.equal(observation.target, target); assert.deepEqual(observation.faults, []);
      assert.deepEqual(checks.filter(c => c.observationId === observation.observationId).map(c => c.kind), ['semantics']);
    }
  }
});
for (const part of capacityPartIds) for (const fail of [
  ...(partRole(part) === 'capacity-support' ? [] : ['restore']), 'close',
  ...(partRole(part) === 'capacity-support' ? ['custody-probe', 'parent-probe'] : []),
  ...(partRole(part) === 'capacity-mutants'
    ? [`capacity-${capacityObligationsByPart[part].mutations[0]}-post-restore:wasm`, 'post-restore-close'] : []),
]) {
  test(`${part} ${fail} cannot emit a successful immutable fragment`, () => {
    const result = run({ part, fail });
    assert.notEqual(result.status, 0); assert.equal(result.state.report, null);
    assert(!result.stdout.includes('Source restored byte-for-byte'));
    if (fail !== 'restore') assert(result.state.checkpoint, 'Partial receipts survive owner handoff failure');
  });
}

for (const options of [{ part: 'L-C9' }, { part: normalPart, environmentPart: mutantParts[0] },
  { part: mutantParts[0], target: 'js' }, { part: 'L-C0' }, { part: 'L-C1' }]) {
  test(`capacity partition rejects invalid or conflicting selection ${JSON.stringify(options)}`, () => {
    const result = run(options);
    assert.notEqual(result.status, 0); assert.equal(result.state.report, null); assert.equal(result.state.calls.length, 0);
  });
}
