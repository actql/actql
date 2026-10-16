// Real Common, request journal, installed Host and loopback Salesforce Source.
// This is source-qualified integration, not a pristine installed campaign.
import assert from 'node:assert/strict';
import test from 'node:test';
import {expectedUpdates, readComputeEffectInstallation, signer, waitFor} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

test('original read-only submit refuses the checked Effect before acquisition while ordinary policy remains', async t => {
  const setup = await readComputeEffectInstallation(t);
  const host = await setup.openHost();
  const owner = await host.as('owner-token');
  const program = setup.program();
  const submissionRef = await setup.persistSubmission(owner.newSubmission({nonce: 'read-only-original'}));
  await assert.rejects(owner.startSource(program, {format: 'json', submissionRef, readOnly: true}),
    {code: 'SubmissionNotAccepted'});
  assert.equal(setup.queries(), 0);
  assert.equal(setup.targetReads(), 0);
  assert.equal(setup.writes().length, 0);
  assert.deepEqual((await owner.checkpoints()).items, [], 'no Effect Preview or approval is created');
  const retained = await owner.lookupSubmission(submissionRef);
  assert.equal(retained.kind, 'not_accepted');
  await assert.rejects(owner.startSource(program, {format: 'json', submissionRef}),
    {code: 'SubmissionConflict'});
  await assert.rejects(owner.startSource(program, {format: 'json', readOnly: true, stopBefore: 'commit'}),
    {code: 'SubmissionNotAccepted'});
  assert.equal(setup.queries(), 0);
  assert.equal(setup.writes().length, 0);

  const effectFree = JSON.parse(program);
  for (const stage of effectFree.stages) delete stage.effects;
  const read = await owner.startSource(JSON.stringify(effectFree), {format: 'json', readOnly: true});
  await waitFor(async () => (await read.status()).status === 'succeeded');
  assert.deepEqual(await read.result('updates').all(), expectedUpdates);
  assert.equal(setup.queries(), 1, 'the authorized effect-free Source still executes normally');
  assert.equal(setup.writes().length, 0);

  // Absence still follows the original Source/Effect policy, not a new Allow.
  const ordinary = await owner.startSource(program, {format: 'json'});
  await waitFor(async () => (await ordinary.status()).status === 'waiting_checkpoint');
  assert.equal(setup.queries(), 2);
  assert.equal(setup.writes().length, 0);
  const reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  assert.equal(checkpoint.kind, 'effect_set');
  const answer = await reviewer.resolveCheckpoints([{checkpoint, decision: 'rejected'}],
    {signer: {...signer, authorityScopeCid: ordinary.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
  await waitFor(async () => ['failed', 'cancelled'].includes((await ordinary.status()).status));
  assert.equal(setup.writes().length, 0);
  await host.close();
});
