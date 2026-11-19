// RC fixture logic over the actual public Client. Injected ports in its tests
// prove sequencing/error custody, not installed Host or Native execution.
import assert from 'node:assert/strict';

export async function runReleaseProjectNodeAction({connect, request, readProgram, retainAccepted,
  assertPendingTarget, retainClose}) {
  assert(['static', 'start', 'resolve', 'status', 'result'].includes(request.kind));
  assert(request.decision === undefined || ['approved', 'rejected'].includes(request.decision));
  let client, primary, failed = false, closeFailure, closeFailed = false, response;
  try {
    client = await connect({mode: 'local', installation: {directory: '.actql'}, profile: 'mock'});
    if (request.kind === 'static') {
      const source = await readProgram();
      response = {check: await client.check(source, {format: 'aql'}),
        plan: await client.plan(source, {format: 'aql'})};
    } else {
      let execution, original = request.original;
      if (request.kind === 'start') {
        execution = await client.startSource(await readProgram(), {format: 'aql', stopBefore: 'commit'});
        // Preserve the public accepted original before a failing wait or close.
        await retainAccepted({ref: execution.ref});
        const waiting = await execution.wait();
        assert.equal(waiting.status, 'waiting_checkpoint');
        const checkpointId = waiting.checkpoint?.id;
        assert.equal(typeof checkpointId, 'string');
        original = {ref: execution.ref, runId: waiting.run_id, checkpointId,
          checkpointCid: waiting.checkpoint.checkpoint_cid};
        // Immediate approval must not gain an extra asynchronous lookup,
        // review, filesystem read or sleep between wait() and approve().
        const pending = assertPendingTarget();
        assert(!pending || typeof pending.then !== 'function', 'Pending target observation must be synchronous');
        response = {original, state: waiting};
      } else {
        assert(original && typeof original.runId === 'string');
        execution = await client.attach(original.ref);
        assert.deepEqual(execution.ref, original.ref);
        response = {original};
        if (request.kind !== 'result') {
          response.state = await execution.status();
          assert.equal(response.state.run_id, original.runId);
        }
      }
      if (request.kind === 'resolve' || request.kind === 'start' && request.decision) {
        assert.equal(response.state.status, 'waiting_checkpoint');
        assert.equal(response.state.checkpoint.id, original.checkpointId);
        assert.equal(response.state.checkpoint.checkpoint_cid, original.checkpointCid);
        if (request.kind === 'resolve') {
          const page = await client.checkpoints({checkpointId: original.checkpointId});
          assert.equal(page.items.length, 1);
          const summary = page.items[0];
          assert.equal(summary.checkpointId, original.checkpointId);
          assert.equal(summary.checkpointCid, original.checkpointCid);
          assert.equal(summary.subject.kind, 'run_unit');
          assert.equal(summary.subject.runId, original.runId);
          assert.equal(summary.subject.runDefinitionCid, original.ref.runDefinitionCid);
          const review = await client.reviewCheckpoint(summary);
          if (original.reviewBase64 !== undefined)
            assert.equal(Buffer.from(review.bytes).toString('base64'), original.reviewBase64);
          // An original CLI checkpoint can be selected by its public exact ID
          // and CID; no missing namespace/scope or new checkpoint is invented.
          original = {...original, summary, reviewBase64: Buffer.from(review.bytes).toString('base64')};
          response.original = original;
          await assertPendingTarget();
        }
        // Exactly one resolution. No sleep, second signing or retry on error.
        const answer = await client[request.decision === 'approved' ? 'approve' : 'reject'](original.checkpointId);
        assert.equal(answer.results.length, 1); assert.equal(answer.results[0].status, 'committed');
        assert.equal(answer.signed.length, 1);
        const resolution = JSON.parse(answer.signed[0].resolutionWire);
        assert.equal(resolution.decision, request.decision);
        assert.equal(resolution.run_id, original.runId);
        assert.equal(resolution.run_definition_cid, original.ref.runDefinitionCid);
        response.state = await execution.wait();
        assert.equal(response.state.run_id, original.runId);
        assert.equal(response.state.status, request.decision === 'approved' ? 'succeeded' : 'cancelled');
      }
      if (request.kind === 'result') {
        // A new process reads the Named Result before asking status. Do not
        // let a preceding status hide a missing cold Result implementation.
        const result = await execution.result('updates');
        response.rows = await result.all();
        response.description = await result.describe();
        response.state = await execution.status();
        assert.equal(response.state.run_id, original.runId);
      }
    }
  } catch (cause) {primary = cause; failed = true;}
  // This pending observation cannot itself prove cleanup/physical stop.
  try {await retainClose({attempted: client !== undefined, returned: false});} catch (cause) {
    if (!failed) {primary = cause; failed = true;}
  }
  if (client) try {await client.close();} catch (cause) {closeFailure = cause; closeFailed = true;}
  try {await retainClose({attempted: client !== undefined, returned: client !== undefined && !closeFailed,
    outcome: closeFailed ? 'threw' : client ? 'returned' : 'not-attempted'});} catch (cause) {
    if (!failed) {primary = cause; failed = true;}
  }
  if (failed) throw primary;
  if (closeFailed) throw closeFailure;
  return {...response, firstClose: {attempted: true, returned: true}, pid: process.pid};
}
