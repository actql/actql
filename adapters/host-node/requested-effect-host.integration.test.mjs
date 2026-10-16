// Source-qualified public HTTPS Client/Host acceptance with real Common,
// SQLite, encrypted Store and a stateful loopback Salesforce provider. This is
// not a pristine packed consumer or a live-service/Model qualification.
import assert from 'node:assert/strict';
import test from 'node:test';
import {approveHeldSet, expectedOrgAfterSuccess, expectedUpdates,
  readComputeEffectInstallation, waitFor} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

test('requested first Effect pauses Account Allow and completes only the same approved Run after Host reopen', async t => {
  // The Allow is selected before the original Site/profile is published. No
  // current configuration or retained original is rewritten after admission.
  const setup = await readComputeEffectInstallation(t, {effect: 'allow'});
  const first = await setup.openHost();
  const owner = await first.as('owner-token');
  const submissionRef = await setup.persistSubmission(owner.newSubmission({
    nonce: 'requested-effect-allow'}));
  const execution = await owner.startSource(setup.program(), {
    format: 'json', submissionRef, stopBefore: 'commit'});
  const originalRef = execution.ref;
  const waiting = await waitFor(async () => {
    const state = await execution.status();
    return state.status === 'waiting_checkpoint' ? state : undefined;
  });
  assert.equal(waiting.run_id, originalRef.runId);
  assert.equal(setup.queries(), 1);
  assert.equal(setup.writes().length, 0, 'Account Allow cannot bypass the requested stop');
  const before = await owner.checkpoints();
  assert.equal(before.items.length, 1);
  assert.equal(before.items[0].kind, 'effect_set');
  await first.close();

  const reviewHost = await setup.openHost();
  const recoveredOwner = await reviewHost.as('owner-token');
  const lookup = await recoveredOwner.lookupSubmission(submissionRef);
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual(lookup.admission.ref, originalRef);
  const sameRun = await recoveredOwner.attach(originalRef);
  const checkpoint = await approveHeldSet(reviewHost, sameRun);
  assert.equal(checkpoint.checkpointCid, before.items[0].checkpointCid);
  assert.equal(setup.writes().length, 0, 'the answer is not a physical send');
  await reviewHost.close();

  const resumedHost = await setup.openHost();
  const resumedOwner = await resumedHost.as('owner-token');
  const resumed = await resumedOwner.attach(originalRef);
  const succeeded = await waitFor(async () => {
    const state = await resumed.status();
    return ['succeeded', 'failed', 'needs_reconciliation', 'cancelled'].includes(state.status)
      ? state : undefined;
  });
  assert.equal(succeeded.status, 'succeeded', JSON.stringify(succeeded));
  assert.equal(succeeded.run_id, originalRef.runId);
  assert.deepEqual(await resumed.result('updates').all(), expectedUpdates);
  assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
  assert.equal(setup.writes().length, 2);
  assert.equal(setup.queries(), 1, 'the original acquisition/Compute is not repeated');
  assert.equal((await resumedOwner.checkpoints()).items.length, 1,
    'fulfillment stays in the existing Checkpoint/Resolution rather than repeating the stop');
  await resumedHost.close();

  const finalHost = await setup.openHost();
  const finalOwner = await finalHost.as('owner-token');
  const final = await finalOwner.attach(originalRef);
  assert.equal((await final.status()).status, 'succeeded');
  assert.deepEqual(await final.result('updates').all(), expectedUpdates);
  assert.equal(setup.queries(), 1);
  assert.equal(setup.writes().length, 2, 'a later Host cannot resend the completed Effect');
  assert.equal((await finalOwner.checkpoints()).items.length, 1);
  await finalHost.close();
});
