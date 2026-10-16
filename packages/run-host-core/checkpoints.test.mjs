import assert from 'node:assert/strict';
import test from 'node:test';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import './checkpoint-resolution.test.mjs';
import {buildSync} from 'esbuild';
import {checkpointAdmit, checkpointWaitingState, prepareRunStateObservation,
  runStateObservationKey, nextRunStateRevision, runStateObservationWire, runWaitDecision} from
  '@actql/run-host-core/checkpoints';
import {checkpointSealBody} from './dist/checkpoint_runtime_node.js';

// Independent request facts, not a physical Effect or approval receipt.
const cid = digit => `sha256:${digit.repeat(64)}`;
const body = {
  version: 'actql-execution-checkpoint/0.1',
  checkpoint_id: 'resident-effect-review', run_id: 'original-run',
  run_definition_cid: cid('1'), continuation_state_cid: cid('2'),
  subject: {kind: 'run_unit', run_id: 'original-run', unit_id: 'compute',
    continuation: 'resume_unit'},
  phase: 'commit', kind: 'effect_set',
  required_artifact: {artifact_type: 'effect_set_preview', artifact_cid: cid('3')},
  review_projection_cid: cid('4'), requirements: ['effect_scope_approved'],
  reason_code: 'effect_review_required', human_summary: 'Update identity 3',
  created_at: '2026-09-25T10:00:00.000Z',
  expires_at: '2026-09-26T10:00:00.000Z',
};
const sealed = JSON.parse(checkpointSealBody(JSON.stringify(body)));
assert.equal(sealed.ok, true);

test('formal checkpoint subpath admits the original Owner wire and rejects a changed identity', () => {
  const admitted = JSON.parse(checkpointAdmit(sealed.checkpoint_wire));
  assert.equal(admitted.ok, true);
  assert.equal(admitted.checkpoint_wire, sealed.checkpoint_wire);
  assert.equal(admitted.run_id, 'original-run');
  assert.equal(admitted.checkpoint_cid, sealed.checkpoint_cid);
  const altered = {...JSON.parse(sealed.checkpoint_wire), run_id: 'another-run'};
  assert.equal(JSON.parse(checkpointAdmit(JSON.stringify(altered))).ok, false);
  assert.equal(JSON.parse(checkpointAdmit('{}')).ok, false);
});

test('waiting is projected only after exact persisted-byte confirmation', () => {
  const at = '2026-09-25T11:00:00.000Z';
  const waiting = JSON.parse(checkpointWaitingState(sealed.checkpoint_wire,
    sealed.checkpoint_wire, at, '["answer"]'));
  assert.equal(waiting.ok, true);
  const state = JSON.parse(waiting.run_state_wire);
  assert.equal(state.run_id, 'original-run');
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(state.checkpoint.checkpoint_cid, sealed.checkpoint_cid);
  const changed = JSON.stringify({...JSON.parse(sealed.checkpoint_wire),
    human_summary: 'Different proposal'});
  const refused = JSON.parse(checkpointWaitingState(sealed.checkpoint_wire,
    changed, at, '["answer"]'));
  assert.equal(refused.ok, false);
  assert.equal(refused.issue, 'PersistedWireMismatch');
});

test('checkpoint subpath bundles for a Worker without Node or Local runtime imports', () => {
  const result = buildSync({stdin: {contents:
    "export {checkpointAdmit, checkpointWaitingState} from '@actql/run-host-core/checkpoints';",
  resolveDir: import.meta.dirname}, bundle: true, write: false,
  platform: 'browser', format: 'esm', target: 'es2022', metafile: true});
  const inputs = Object.keys(result.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/dist/checkpoint_runtime_node.js')));
  assert(inputs.every(path => !path.includes('client_values_host_abi') &&
    !path.includes('local-node') && !path.includes('host-node') &&
    !path.startsWith('node:')));
});

const runLimits = Object.freeze({maxWireBytes: 65536, maxNodes: 1024, maxDepth: 16});
const observedRun = (status = 'succeeded', at = '2026-10-17T00:00:00.000Z') => ({
  version: 'actql-run-state/0.1', run_id: 'same-run', status, updated_at: at,
  result_available: false, result_availability: {},
  next_action: status === 'needs_reconciliation'
    ? {kind: 'reconcile_run', reason: 'execution_unknown'} : {kind: 'none'},
});

test('actual Run observation Owner keeps one original token and does not advance on read clocks', async () => {
  const first = prepareRunStateObservation(JSON.stringify(observedRun()), 'same-run', 0, runLimits);
  const later = prepareRunStateObservation(JSON.stringify(observedRun('succeeded',
    '2026-10-17T00:00:01.000Z')), 'same-run', 0, runLimits);
  assert.equal(nextRunStateRevision(first, null, 0), 0);
  assert.equal(runStateObservationKey(first), runStateObservationKey(later));
  assert.equal(nextRunStateRevision(later, runStateObservationKey(first), 0), 0);
  assert.equal(JSON.stringify(first), '{}');
  assert.ok(Object.isFrozen(first));
  const repeated = await import('@actql/run-host-core/checkpoints');
  assert.equal(repeated.runStateObservationKey(first), runStateObservationKey(first));
  for (const copied of [{}, {...first}, Object.create(first), [], null]) {
    assert.throws(() => runStateObservationKey(copied), /ForeignRunStateObservation/u);
  }
  assert.throws(() => prepareRunStateObservation(JSON.stringify(observedRun()),
    'other-run', 0, runLimits), {code: 'ForeignRunStateObservation'});
});

test('actual Run observation Owner advances only changed facts with original prior and safe exhaustion', () => {
  const initial = prepareRunStateObservation(JSON.stringify(observedRun('running')), 'same-run', 4, runLimits);
  const next = prepareRunStateObservation(JSON.stringify(observedRun()), 'same-run', 4, runLimits);
  assert.equal(nextRunStateRevision(next, runStateObservationKey(initial), 4), 5);
  assert.equal(JSON.parse(runStateObservationWire(next, 5)).revision, 5);
  assert.throws(() => nextRunStateRevision(next, null, 4), {code: 'InvalidPriorRunStateObservation'});
  assert.throws(() => nextRunStateRevision(next, runStateObservationKey(initial), Number.MAX_SAFE_INTEGER),
    {code: 'RunStateRevisionExhausted'});
  for (const invalid of [-1, 1.5, Number.MAX_SAFE_INTEGER + 1, NaN]) {
    assert.throws(() => runStateObservationWire(next, invalid), {code: 'InvalidRunStateRevision'});
  }
});

test('actual Run wait Owner enforces original stable since future rejection and missing revision', () => {
  for (const status of ['needs_reconciliation', 'succeeded', 'failed', 'cancelled']) {
    const view = prepareRunStateObservation(JSON.stringify(observedRun(status)), 'same-run', 7, runLimits);
    const wire = runStateObservationWire(view, 7);
    assert.equal(runWaitDecision(wire, null, runLimits), 'ready');
    assert.equal(runWaitDecision(wire, 6, runLimits), 'ready');
    assert.equal(runWaitDecision(wire, 7, runLimits), 'pending');
    assert.throws(() => runWaitDecision(wire, 8, runLimits), {code: 'InvalidWaitRevision'});
  }
  const running = runStateObservationWire(prepareRunStateObservation(
    JSON.stringify(observedRun('running')), 'same-run', 7, runLimits), 7);
  assert.equal(runWaitDecision(running, 6, runLimits), 'pending');
  assert.throws(() => runWaitDecision(JSON.stringify(observedRun()), null, runLimits),
    {code: 'InvalidRunWaitState'});
  assert.throws(() => runWaitDecision(running, undefined, runLimits), {code: 'InvalidWaitRevision'});
  assert.throws(() => runWaitDecision(42, null, runLimits), {code: 'InvalidRunWaitState'});
});

test('actual Run observation Owner refuses malformed current input and independent encoding bounds', () => {
  for (const revision of [null, '0', -1, 1.25, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => prepareRunStateObservation(JSON.stringify({...observedRun(), revision}),
      'same-run', 0, runLimits), {code: 'InvalidRunStateRevision'});
  }
  for (const limits of [{...runLimits, maxWireBytes: 1}, {...runLimits, maxNodes: 1},
    {...runLimits, maxDepth: 1}]) {
    assert.throws(() => prepareRunStateObservation(JSON.stringify(observedRun()),
      'same-run', 0, limits), {code: 'InvalidRunStateObservation'});
  }
  assert.throws(() => prepareRunStateObservation(JSON.stringify(observedRun()),
    'same-run', 0, {...runLimits, maxNodes: 0}), /InvalidRunStateObservationLimits/u);
  assert.throws(() => prepareRunStateObservation(JSON.stringify(observedRun()),
    'same-run', 0, Object.assign([], runLimits)), /InvalidRunStateObservationLimits/u);
});

test('Run observation ABI export removal refuses before any durable caller can accept a row', async t => {
  // Genuine single-export surface mutation of the normal deferred compiled
  // runtime. It is not a legacy artifact or a normal installed acceptance.
  const parent = new URL('../../_build/run-state-abi-negative/', import.meta.url);
  mkdirSync(parent, {recursive: true});
  const root = mkdtempSync(join(parent.pathname, 'missing-'));
  mkdirSync(join(root, 'dist'));
  writeFileSync(join(root, 'package.json'), '{"type":"module"}\n');
  copyFileSync(new URL('./checkpoints.mjs', import.meta.url), join(root, 'checkpoints.mjs'));
  copyFileSync(new URL('./compiler-binding.generated.mjs', import.meta.url),
    join(root, 'compiler-binding.generated.mjs'));
  const runtime = readFileSync(new URL('./dist/checkpoint_runtime_node.js', import.meta.url), 'utf8');
  const needle = 'export function runStateObservationPrepare(';
  assert.equal(runtime.split(needle).length, 2);
  writeFileSync(join(root, 'dist/checkpoint_runtime_node.js'),
    runtime.replace(needle, 'function runStateObservationPrepare('));
  const missing = await import(pathToFileURL(join(root, 'checkpoints.mjs')).href);
  let accepted = 0;
  assert.throws(() => {
    missing.prepareRunStateObservation(JSON.stringify(observedRun()), 'same-run', 0, runLimits);
    accepted++;
  }, {code: 'RunStateObservationRuntimeUnavailable'});
  assert.equal(accepted, 0);
  t.diagnostic(`Retained original missing-export fixture: ${root}`);
});

test('genuine original Checkpoint waiting projection reaches the same Run revision and since Owner', () => {
  const projected = JSON.parse(checkpointWaitingState(sealed.checkpoint_wire,
    sealed.checkpoint_wire, '2026-09-25T11:00:00.000Z', '["answer"]'));
  assert.equal(projected.ok, true);
  const view = prepareRunStateObservation(projected.run_state_wire,
    'original-run', 2, runLimits);
  const wire = runStateObservationWire(view, 2);
  const state = JSON.parse(wire);
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(state.checkpoint.checkpoint_cid, sealed.checkpoint_cid);
  assert.equal(state.revision, 2);
  assert.equal(runWaitDecision(wire, 1, runLimits), 'ready');
  assert.equal(runWaitDecision(wire, 2, runLimits), 'pending');
});
