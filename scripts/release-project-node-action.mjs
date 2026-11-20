// RC fixture logic over the actual public Client. Injected ports in its tests
// prove sequencing/error custody, not installed Host or Native execution.
import assert from 'node:assert/strict';

export function projectStaticCheckControls(program, source) {
  const variable = {'churn-risk.aql': 'risk', 'deal-review.aql': 'review'}[program];
  assert(variable, 'Use an existing authored Mock template');
  const original = variable + ".outcome = 'ok'";
  assert.equal(source.split(original).length, 2, 'Use one exact original published comparison');
  return [
    {name: 'known-outcome-type-error', text: source.replace(original, variable + '.outcome = 1')},
    {name: 'unknown-update-target', text: 'SELECT 1 AS id |> RESULT out |> EFFECT UPDATE private.unknown FROM RESULT out ID id SET (Name = 1)'},
  ];
}

export function assertProjectStaticCheckControls(controls) {
  assert.deepEqual(controls?.map(value => value.name), ['known-outcome-type-error', 'unknown-update-target']);
  for (const {check} of controls) {
    assert.equal(check.outcome, 'completed');
    assert.equal(check.report?.scope?.kind, 'bound_input');
    assert(!JSON.stringify(check).includes('check_unclassified'));
  }
  const invalid = controls[0].check.report, unknown = controls[1].check.report;
  assert.equal(invalid.verdict, 'invalid');
  assert(invalid.reasons.some(value => value.code === 'expression_domain_mismatch' &&
    value.facts?.domain === 'key_comparable_operands'));
  assert.equal(invalid.requirements.length, 0, 'A known type error must not fabricate a policy/value Requirement');
  assert.equal(unknown.verdict, 'undetermined');
  assert(JSON.stringify(unknown.coverage).includes('unresolved_protected'));
}

export async function runReleaseProjectNodeAction({connect, request, readProgram, retainAccepted,
  assertPendingTarget, retainClose, getCheckInput}) {
  assert(['static', 'start', 'read', 'resolve', 'status', 'result'].includes(request.kind));
  assert(request.resultName === undefined || request.resultName === 'main');
  assert(request.kind !== 'read' || request.decision === undefined);
  assert(request.decision === undefined || ['approved', 'rejected'].includes(request.decision));
  let client, primary, failed = false, closeFailure, closeFailed = false, response;
  try {
    // CLI init already adopts .actql. This independent Node owner never opens
    // or converts that Native Store, including during static analysis.
    client = await connect({mode: 'local', installation: {directory: '.actql-node'}, profile: 'mock'});
    if (request.kind === 'static') {
      const source = await readProgram();
      response = {check: await client.check(source, {format: 'aql'}),
        plan: await client.plan(source, {format: 'aql'})};
      response.staticChecks = [];
      for (const control of projectStaticCheckControls(request.program, source)) {
        const check = await client.check(control.text, {kind: 'text', format: 'aql', scope: 'bound_input'});
        const received = getCheckInput(check, 'source');
        assert.equal(received?.kind, 'text');
        assert.equal(received.text, control.text, 'Preserve the original public check text');
        response.staticChecks.push({name: control.name, check});
      }
      assertProjectStaticCheckControls(response.staticChecks);
    } else {
      let execution, original = request.original;
      if (request.kind === 'start' || request.kind === 'read') {
        const source = await readProgram();
        if (request.kind === 'read') {
          const check = await client.check(source, {format: 'aql'});
          assert.equal(check.outcome, 'completed');
          assert.equal(check.report?.verdict, 'verified');
          assert.equal(check.report.runnable?.verdict, 'yes');
          response = {check};
        }
        execution = await client.startSource(source, request.kind === 'read'
          ? {format: 'aql'} : {format: 'aql', stopBefore: 'commit'});
        // Preserve the public accepted original before a failing wait or close.
        await retainAccepted({ref: execution.ref});
        const waiting = await execution.wait();
        if (request.kind === 'read') {
          assert.equal(waiting.status, 'succeeded');
          original = {ref: execution.ref, runId: waiting.run_id};
          response = {...response, original, state: waiting};
        } else {
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
        }
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
        assert.equal(resolution.checkpoint_id, original.checkpointId);
        assert.equal(resolution.checkpoint_cid, original.checkpointCid);
        assert.equal(resolution.run_id, original.runId);
        assert.equal(resolution.run_definition_cid, original.ref.runDefinitionCid);
        response.state = await execution.wait();
        assert.equal(response.state.run_id, original.runId);
        assert.equal(response.state.status, request.decision === 'approved' ? 'succeeded' : 'cancelled');
      }
      if (request.kind === 'result' || request.kind === 'read') {
        // A new process reads the Named Result before asking status. Do not
        // let a preceding status hide a missing cold Result implementation.
        const result = await execution.result(request.kind === 'read' ? 'main' : request.resultName ?? 'updates');
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
    // A later observation failure cannot replace the actual first-close issue.
    if (!failed && !closeFailed) {primary = cause; failed = true;}
  }
  if (failed) throw primary;
  if (closeFailed) throw closeFailure;
  return {...response, firstClose: {attempted: true, returned: true}, pid: process.pid};
}
