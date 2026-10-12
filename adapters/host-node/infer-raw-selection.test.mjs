import assert from 'node:assert/strict';
import test from 'node:test';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';

function selection() {
  return {profile: {}, installation: {endpoint: 'original', sdk: {version: '4.0.91'}},
    probability: undefined, retention: {}, metadata: {}, clock: {}, data: {},
    selectedAt: 'original selection', availableUntil: 'original availability',
    deleteBy: 'original deletion', extensionCeilingAt: 'original ceiling',
    metadataDeleteBy: 'original metadata deletion', selectionAvailable: () => true};
}

test('raw selection snapshots declaration before await without copying opaque policy owners', () => {
  const original = selection(), selected = snapshotModelRawCaptureSelection(original);
  original.installation.endpoint = 'changed';
  original.installation.sdk.version = 'changed';
  original.deleteBy = 'extended';
  assert.equal(selected.installation.endpoint, 'original');
  assert.equal(selected.installation.sdk.version, '4.0.91');
  assert.equal(selected.deleteBy, 'original deletion');
  for (const name of ['profile', 'probability', 'retention', 'metadata', 'clock', 'data',
    'selectionAvailable']) assert.equal(selected[name], original[name]);
  assert.ok(Object.isFrozen(selected) && Object.isFrozen(selected.installation) &&
    Object.isFrozen(selected.installation.sdk));
  assert.equal(snapshotModelRawCaptureSelection(undefined), undefined);
});

test('raw selection refuses omitted unknown, extra input and getter callbacks before await', () => {
  const missing = selection(); delete missing.probability;
  for (const value of [null, [], missing, {...selection(), runInput: {}},
    {...selection(), selectionAvailable: false}, {...selection(), installation: []}]) {
    assert.throws(() => snapshotModelRawCaptureSelection(value), /InvalidInferRawCaptureSelection/u);
  }
  let getters = 0;
  const value = selection();
  Object.defineProperty(value, 'data', {enumerable: true, get() { getters++; return {}; }});
  assert.throws(() => snapshotModelRawCaptureSelection(value), /InvalidInferRawCaptureSelection/u);
  assert.equal(getters, 0);
});

// Explicit Core ports: callback delegation/retirement only. Actual nominal
// registration, SQLite Entry and raw Store are tested by infer-owner-checker.
function operation(rawCaptureBinder) {
  let stopped = false;
  const moon = {
    clientProgramStartScopedInferExecution: () => ({$tag: 1, _0: {}}),
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
  };
  return openNodeInferOperation({moon, provider: {}, rawCaptureBinder});
}

test('original physical operation receives exact nominal registration once and retires binder', async () => {
  const registration = {}, received = [];
  const original = operation(value => { received.push(value); });
  original.bindModelRawCapture(registration);
  assert.deepEqual(received, [registration]);
  assert.throws(() => original.bindModelRawCapture(registration), /InferRawCaptureBindingUnavailable/u);
  await original.close();
  assert.equal(original.cleanupPending(), false);
  assert.throws(() => original.bindModelRawCapture({}), /InferRawCaptureBindingUnavailable/u);
  assert.equal(received.length, 1);
});

test('physical binder throw cannot rebind or lose original cleanup responsibility', async () => {
  const issue = new Error('OriginalBinderFailure');
  let calls = 0;
  const original = operation(() => { calls++; throw issue; });
  assert.throws(() => original.bindModelRawCapture({}), error => error === issue);
  assert.equal(original.cleanupPending(), true);
  assert.throws(() => original.bindModelRawCapture({}), /InferRawCaptureBindingUnavailable/u);
  await original.close();
  assert.equal(original.cleanupPending(), false);
  assert.equal(calls, 1);
});

test('missing physical raw binder refuses without replacing the original operation', async () => {
  const original = operation(undefined);
  assert.throws(() => original.bindModelRawCapture({}), /InferRawCaptureBindingUnavailable/u);
  await original.close();
  assert.throws(() => operation({}), /InvalidInferRawCaptureBinder/u);
});

test('physical raw binder must finish synchronously before original advance or Entry', async () => {
  const original = operation(() => Promise.resolve());
  assert.throws(() => original.bindModelRawCapture({}), /InvalidInferRawCaptureBinderResult/u);
  assert.throws(() => original.bindModelRawCapture({}), /InferRawCaptureBindingUnavailable/u);
  await original.close();
});
