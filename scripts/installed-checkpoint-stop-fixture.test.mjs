// These are fixture sequencing checks, not installed Host or Run evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {waitForInstalledCheckpointPhysicalStop} from
  './fixtures/installed-effect-inventory-acceptance.mjs';

function execution(states) {
  let reads = 0;
  return {status: async () => {
    assert(reads < states.length, 'no unbounded or additional status read');
    return states[reads++];
  }, reads: () => reads};
}

test('checkpoint read baseline follows original physical stop, not early waiting', async () => {
  const before = Object.freeze({status: 'waiting_checkpoint', control:
    Object.freeze({revision: 2, physical_stop: 'unknown'})});
  const stopped = Object.freeze({status: 'waiting_checkpoint', control:
    Object.freeze({revision: 3, physical_stop: 'confirmed'})});
  const run = execution([before, stopped]);
  const baseline = await waitForInstalledCheckpointPhysicalStop(run);
  assert.equal(baseline, stopped);
  assert.equal(baseline.control.revision, 3);
  assert.equal(run.reads(), 2);
  assert.equal(before.control.revision, 2);
});

test('missing or presentation-only stop does not replace the original stop fact', async () => {
  const stopped = {status: 'waiting_checkpoint', control:
    {revision: 3, physical_stop: 'confirmed'}};
  const run = execution([
    {status: 'waiting_checkpoint', control: {revision: 2}},
    {status: 'waiting_checkpoint', control: {revision: 2,
      physical_stop: 'unknown', physicalStop: 'confirmed'}}, stopped,
  ]);
  assert.equal(await waitForInstalledCheckpointPhysicalStop(run), stopped);
  assert.equal(run.reads(), 3);
});

test('terminal or failed setup remains a rejection before the read baseline', async () => {
  for (const status of ['failed', 'cancelled', 'needs_reconciliation']) {
    const run = execution([{status, control:
      {revision: 3, physical_stop: 'confirmed'}}]);
    await assert.rejects(waitForInstalledCheckpointPhysicalStop(run),
      {code: 'ERR_ASSERTION'});
    assert.equal(run.reads(), 1);
  }
});
