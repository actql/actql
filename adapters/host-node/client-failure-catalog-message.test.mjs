import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

// Explicit catalogue and physical-cleanup ports. The companion Core test
// supplies the actual canonical conversion cause and Common explanation.
async function retainedFailure(error, control) {
  let pending = true, starts = 0, cleanups = 0;
  const ref = {runDefinitionCid: 'catalog-owner-component'};
  const owner = installNodeClientDispatchOwner({control,
    journal: {lookupRunDefinition: () => undefined}});
  const physical = {close() {}, cleanup() {cleanups++; return !pending;},
    cleanupPending: () => pending};
  await assert.rejects(owner.track(ref, {
    run({beginPhysicalWork, retainExecution}) {
      starts++; beginPhysicalWork(); retainExecution(physical); throw error;
    },
    observeStopped() {},
  }), actual => actual === error);
  const message = owner.failureMessage(ref);
  pending = false;
  await owner.drain();
  assert.equal(starts, 1);
  assert.ok(cleanups > 0);
  assert.equal(owner.operation(ref), undefined);
  return message;
}

test('actual dispatch owner forwards only the installed Common catalogue method', async () => {
  const primary = Object.assign(new Error('MoonBitHostFailure'), {code: 'MoonBitHostFailure',
    primaryDiagnostic: Object.freeze({code: 'MoonBitHostFailure',
      phase: 'local_managed_advance', kind: 'row_failure', task: 1, step: 2,
      cause: 'evaluation.timestamp_canonical_required'})});
  let reads = 0;
  const message = await retainedFailure(primary, {executionFailureExplanation(cause) {
    assert.equal(cause, 'evaluation.timestamp_canonical_required');
    reads++; return 'Original Common catalogue text.';
  }});
  assert.ok(reads > 0);
  assert.ok(message.endsWith(' Original Common catalogue text.'));
});

test('generic failures and legacy controls do not acquire a catalogue requirement', async () => {
  let reads = 0;
  const unknown = Object.assign(new Error('evaluation.timestamp_canonical_required'), {
    cause: {code: 'evaluation.timestamp_canonical_required'},
  });
  assert.equal(await retainedFailure(unknown, {executionFailureExplanation() {
    reads++; throw new Error('GenericFailureCannotSelectCatalogue');
  }}), undefined);
  assert.equal(reads, 0);
  assert.equal(await retainedFailure(new Error('legacy'), undefined), undefined);
});
