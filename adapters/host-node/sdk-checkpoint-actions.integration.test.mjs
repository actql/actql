// Real installed Common/SQLite/encrypted Store/HTTPS, with an explicit fixture
// reviewer signer. No default Local key, pristine installation or live service.
import assert from 'node:assert/strict';
import test from 'node:test';
import {expectedUpdates, readComputeEffectInstallation, signer, waitFor} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

for (const decision of ['approve', 'reject']) {
  test(`public ${decision}(id) binds the original Checkpoint and same Run without acquisition replay`, async t => {
    const setup = await readComputeEffectInstallation(t);
    let host = await setup.openHost();
    const owner = await host.as('owner-token');
    const submissionRef = await setup.persistSubmission(owner.newSubmission({nonce: 'public-' + decision}));
    const execution = await owner.startSource(setup.program(), {format: 'json', submissionRef});
    const waiting = await waitFor(async () => {
      const observed = await execution.status();
      return observed.status === 'waiting_checkpoint' ? observed : undefined;
    });
    assert.ok(waiting.checkpoint);
    assert.equal(waiting.checkpoint.id, waiting.checkpoint.checkpoint_id);
    assert.equal(Object.hasOwn(JSON.parse(JSON.stringify(waiting)).checkpoint, 'id'), false);
    assert.equal(setup.queries(), 1); assert.equal(setup.writes().length, 0);
    const selected = {...signer, authorityScopeCid: execution.ref.authorityScopeCid};
    const reviewer = await host.as('reviewer-token');
    await assert.rejects(reviewer[decision](waiting.checkpoint.id), {code: 'CheckpointSignerUnavailable'});
    const [summary] = (await reviewer.checkpoints({checkpointId: waiting.checkpoint.id})).items;
    assert.ok(summary); assert.equal(summary.checkpointCid, waiting.checkpoint.checkpoint_cid);
    // A legitimate signer does not let the wrong authenticated caller resolve.
    await assert.rejects(owner[decision](waiting.checkpoint.id, {signer: selected}),
      {code: 'CheckpointAnswerDenied'});
    assert.equal(setup.writes().length, 0);
    const answer = await reviewer[decision](waiting.checkpoint.id, {signer: selected});
    assert.equal(answer.results[0].status, 'committed');
    const resolution = JSON.parse(answer.signed[0].resolutionWire);
    assert.equal(resolution.run_id, waiting.run_id);
    assert.equal(resolution.run_definition_cid, execution.ref.runDefinitionCid);
    assert.equal(resolution.checkpoint_cid, waiting.checkpoint.checkpoint_cid);
    assert.equal(resolution.required_artifact_cid, summary.requiredArtifact.cid);
    assert.equal(resolution.review_projection_cid, summary.reviewProjectionCid);
    assert.equal(resolution.decision, decision === 'approve' ? 'approved' : 'rejected');
    const ref = execution.ref;
    // This existing installation explicitly selects resumeAfterAnswer:false.
    // Reopen drives the original durable continuation, not another submission.
    await host.close(); host = await setup.openHost();
    const resumed = await (await host.as('owner-token')).attach(ref);
    const terminal = await waitFor(async () => {
      const observed = await resumed.status();
      return ['succeeded', 'cancelled', 'failed', 'needs_reconciliation'].includes(observed.status)
        ? observed : undefined;
    });
    assert.equal(terminal.run_id, waiting.run_id);
    assert.equal(terminal.status, decision === 'approve' ? 'succeeded' : 'cancelled');
    assert.equal(terminal.checkpoint, undefined);
    assert.equal(setup.queries(), 1);
    assert.equal(setup.writes().length, decision === 'approve' ? 2 : 0);
    if (decision === 'approve') assert.deepEqual(await resumed.result('updates').all(), expectedUpdates);
    await host.close();
  });
}
