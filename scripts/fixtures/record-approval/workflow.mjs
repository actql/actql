// Public SDK consumer fixture. The original Host supplies every Run, Review,
// approval and Effect owner. A case supplies independent Program/value oracles;
// it cannot supply a claim, current decision, credential or replacement Run.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const sha256 = text => createHash('sha256').update(text).digest('hex');
const cid = /^sha256:[0-9a-f]{64}$/u;
const text = value => typeof value === 'string' && value.length > 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const closed = (value, keys) => object(value) && Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));

export function admitAuthoredRecordApprovalCase(value) {
  const fields = ['document', 'format', 'resultName', 'parameterDeclarations', 'parameters'];
  const rows = value => Array.isArray(value) && value.every(object);
  assert(closed(value, ['name', 'effect', 'read', 'review']));
  const {effect, read, review} = value;
  assert(object(effect));
  const additional = Object.hasOwn(effect, 'additionalResults');
  assert(closed(effect, [...fields, 'expectedRows', ...(additional ? ['additionalResults'] : [])]));
  assert(closed(read, [...fields, 'beforeRows', 'afterRows']));
  assert(closed(review, ['target', 'identity', 'before', 'changes']));
  assert([effect, read].every(program => object(program.parameterDeclarations) && object(program.parameters)));
  assert(rows(effect.expectedRows) && rows(read.beforeRows) && rows(read.afterRows));
  assert(!additional || object(effect.additionalResults) && Object.values(effect.additionalResults).every(rows));
  assert(object(review.before) && object(review.changes) && Object.keys(review.changes).length > 0);
  return retainCase(value);
}

// Trusted fixture expectation, never a Program option or a permission decision.
// Each selected provider capability supplies its own two independent outcomes.
export function recordApprovalReplyLossExpectation(value) {
  if (value === undefined) return undefined;
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), ['approveStatus', 'lookupStatus']);
  for (const status of [value.approveStatus, value.lookupStatus]) {
    assert(['succeeded', 'needs_reconciliation'].includes(status));
  }
  return Object.freeze({approveStatus: value.approveStatus, lookupStatus: value.lookupStatus});
}

export function recordApprovalReplyLossExpectationFromEnvironment(env = process.env) {
  const wire = env.ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION;
  if (wire === undefined) return undefined;
  assert.equal(typeof wire, 'string');
  assert(wire.length > 0 && wire.length <= 256);
  return recordApprovalReplyLossExpectation(JSON.parse(wire));
}

function retainCase(original) {
  // Snapshot only fixture DATA before the first public await. Caller mutation
  // must not turn a returned product value into a new expected-value oracle.
  const value = structuredClone(original);
  assert(text(value?.name));
  for (const program of [value.effect, value.read]) {
    assert(text(program?.document) && ['aql', 'sql', 'json', 'yaml'].includes(program.format));
    assert(text(program.resultName));
    assert(program.parameterDeclarations && typeof program.parameterDeclarations === 'object');
    assert(program.parameters && typeof program.parameters === 'object');
  }
  assert(Array.isArray(value.effect.expectedRows));
  if (value.effect.additionalResults !== undefined) {
    assert(value.effect.additionalResults && typeof value.effect.additionalResults === 'object');
    for (const [name, rows] of Object.entries(value.effect.additionalResults)) {
      assert(text(name) && name !== value.effect.resultName && Array.isArray(rows));
    }
  }
  assert(Array.isArray(value.read.beforeRows) && Array.isArray(value.read.afterRows));
  assert(text(value.review?.target));
  assert(Object.hasOwn(value.review, 'identity'));
  assert(value.review.before && Object.keys(value.review.before).length > 0 && value.review.changes);
  return value;
}

function binding(value) {
  const {document: effect, ...effectInput} = value.effect;
  const {document: read, ...readInput} = value.read;
  return {caseName: value.name, effectSha256: sha256(effect), readSha256: sha256(read),
    effect: effectInput, read: readInput, review: value.review};
}

function checkReview(review, summary, ref, expected) {
  assert.equal(review.version, 'actql-review-projection/0.1');
  assert.equal(review.review_projection_cid, summary.reviewProjectionCid);
  assert.equal(review.effect_preview_cid, summary.requiredArtifact.cid);
  assert.equal(review.authority_scope_cid, ref.authorityScopeCid);
  assert.deepEqual(review.approval_claims, summary.requirements);
  assert.deepEqual(review.displayed_scope.effects.map(({kind, target, count}) =>
    ({kind, target, count})), [{kind: 'update', target: expected.target, count: 1}]);
  assert.equal(review.displayed_rows.length, 1);
  const row = review.displayed_rows[0];
  assert.deepEqual(row.target_row_identity, expected.identity);
  assert.equal(row.preview_strength, 'full_diff');
  assert.match(row.row_preview_cid, cid);
  assert.equal(row.target_guard.state, 'version');
  assert.match(row.target_guard.version_cid, cid);
  assert.equal(row.before.state, 'present');
  for (const [field, value] of Object.entries(expected.before)) {
    assert.deepEqual(row.before.value[field], value, 'Independent original field: ' + field);
  }
  assert.deepEqual(row.intended_changes, {state: 'present', value: expected.changes});
  assert.deepEqual(row.after, row.intended_changes);
}

async function readAdditionalResults(run, effect) {
  const retained = {};
  for (const [name, expected] of Object.entries(effect.additionalResults ?? {})) {
    const rows = await run.result(name).all();
    assert.deepEqual(rows, expected, 'Independent original Result: ' + name);
    retained[name] = rows;
  }
  return retained;
}

async function readOriginal(client, value, phase, save) {
  const program = value.read;
  const run = await client.startSource(program.document, {format: program.format,
    parameterDeclarations: program.parameterDeclarations, parameters: program.parameters});
  await save(phase + '-ref', {ref: run.ref});
  assert.equal((await run.wait()).status, 'succeeded');
  const rows = await run.result(program.resultName).all();
  assert.deepEqual(rows, phase === 'before' ? program.beforeRows : program.afterRows);
  await save(phase, {ref: run.ref, rows});
}

async function saveRunObservation(save, name, run, state) {
  // Only the original returned public reply: never a private cause, a second
  // status request, or a synthesized observation when the original await threw.
  const issue = state.terminal_error;
  await save(name, {ref: run.ref, status: state.status,
    ...(issue === undefined ? {} : {terminal_error: {
      code: issue.code.slice(0, 1024), message: issue.message.slice(0, 1024)},
      terminal_error_truncated: issue.code.length > 1024 || issue.message.length > 1024})});
}

// One invocation is one existing phase. The external ordinary consumer owns
// the separate processes, fresh installation/state, provider snapshot and alive
// FD observations. This helper does not infer cleanup ACK from process exit.
export async function runRecordUpdateApprovalPhase({phase, client,
  definition, createDefinition, load, save, approve, reject, observeClose, replyLossExpectation,
  decision = 'approved'}) {
  let failed = false, primary;
  try {
    assert(['approved', 'rejected'].includes(decision));
    const rejecting = decision === 'rejected';
    assert(['capture', rejecting ? 'reject' : 'approve', 'recover'].includes(phase));
    // A connected consumer can still reject its authored case. Keep that
    // synchronous construction inside the same failure/close lifetime.
    if (createDefinition !== undefined) {
      assert.equal(typeof createDefinition, 'function');
      assert.equal(definition, undefined, 'Supply one original case entrance');
      definition = createDefinition();
    }
    const loss = recordApprovalReplyLossExpectation(replyLossExpectation);
    assert(!rejecting || loss === undefined, 'A rejected case cannot enter the apply-then-lose-reply fixture');
    const value = retainCase(definition), originalBinding = {...binding(value),
      ...(rejecting ? {decision} : {}),
      ...(loss === undefined ? {} : {replyLossExpectation: loss})};
    if (phase === 'capture') {
      const program = value.effect;
      const run = await client.startSource(program.document, {format: program.format,
        parameterDeclarations: program.parameterDeclarations, parameters: program.parameters,
        stopBefore: 'commit'});
      // Persist the actual public reference before the first wait can fail.
      await save('submitted', {binding: originalBinding, ref: run.ref});
      const state = await run.wait();
      await saveRunObservation(save, 'capture-wait', run, state);
      assert.equal(state.status, 'waiting_checkpoint');
      const page = await client.checkpoints({checkpointId: state.checkpoint.id});
      assert.equal(page.items.length, 1);
      const summary = page.items[0];
      assert.equal(summary.checkpointCid, state.checkpoint.checkpoint_cid);
      const review = await client.reviewCheckpoint(summary);
      checkReview(JSON.parse(Buffer.from(review.bytes).toString('utf8')), summary, run.ref, value.review);
      await readOriginal(client, value, 'before', save);
      await save('captured', {binding: originalBinding, ref: run.ref,
        runId: state.run_id, checkpointId: state.checkpoint.id, summary,
        reviewBase64: Buffer.from(review.bytes).toString('base64')});
    } else {
      const captured = await load('captured');
      assert.deepEqual(captured.binding, originalBinding, 'Reopen the same Program, parameters and independent oracle');
      const run = await client.attach(captured.ref);
      assert.deepEqual(run.ref, captured.ref);
      if (phase === 'approve' || phase === 'reject') {
        const state = await run.status();
        await saveRunObservation(save, phase + '-status', run, state);
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, 'waiting_checkpoint');
        assert.equal(state.checkpoint.id, captured.checkpointId);
        if (rejecting) assert.equal(state.checkpoint.checkpoint_cid, captured.summary.checkpointCid);
        const review = await client.reviewCheckpoint(captured.summary);
        assert.equal(Buffer.from(review.bytes).toString('base64'), captured.reviewBase64);
        checkReview(JSON.parse(Buffer.from(review.bytes).toString('utf8')),
          captured.summary, run.ref, value.review);
        const resolveCheckpoint = rejecting ? reject : approve;
        assert.equal(typeof resolveCheckpoint, 'function', 'The selected resolution must be explicitly configured');
        const answer = await resolveCheckpoint(client, captured);
        if (loss !== undefined) await save('approval-answer', {ref: run.ref,
          statuses: answer.results.map(item => item.status)});
        assert.deepEqual(answer.results.map(item => item.status), ['committed']);
        if (rejecting) {
          assert.equal(answer.signed.length, 1);
          const resolution = JSON.parse(answer.signed[0].resolutionWire);
          assert.equal(resolution.decision, decision);
          assert.equal(resolution.checkpoint_id, captured.checkpointId);
          assert.equal(resolution.checkpoint_cid, captured.summary.checkpointCid);
          assert.equal(resolution.run_id, captured.runId);
          assert.equal(resolution.run_definition_cid, captured.ref.runDefinitionCid);
        }
        const terminal = await run.wait();
        await saveRunObservation(save, phase + '-wait', run, terminal);
        assert.equal(terminal.run_id, captured.runId);
        assert.equal(terminal.status, rejecting ? 'cancelled' : loss?.approveStatus ?? 'succeeded');
        if (rejecting) await save('rejected', {binding: originalBinding,
          ref: run.ref, runId: captured.runId, status: terminal.status});
        if (loss !== undefined) await save('reply-loss', {binding: originalBinding,
          ref: run.ref, runId: captured.runId, status: terminal.status});
        if (terminal.status === 'succeeded') {
          const rows = await run.result(value.effect.resultName).all();
          assert.deepEqual(rows, value.effect.expectedRows);
          const additionalResults = await readAdditionalResults(run, value.effect);
          await save('approved', {binding: originalBinding, ref: run.ref, rows,
            ...(value.effect.additionalResults === undefined ? {} : {additionalResults})});
          // The loss case observes the original operation only. Its parent
          // independently checks the provider target and complete control row.
          if (loss === undefined) await readOriginal(client, value, 'after', save);
        }
      } else if (rejecting) {
        const rejected = await load('rejected');
        assert.deepEqual(rejected, {binding: originalBinding, ref: run.ref,
          runId: captured.runId, status: 'cancelled'});
        const state = await run.status();
        await saveRunObservation(save, 'reject-lookup', run, state);
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, 'cancelled');
      } else if (loss !== undefined) {
        const observed = await load('reply-loss');
        assert.deepEqual(observed.binding, originalBinding);
        assert.deepEqual(observed.ref, run.ref);
        assert.equal(observed.runId, captured.runId);
        assert.equal(observed.status, loss.approveStatus);
        // A fresh Client attaches and looks up only the SAME original Run.
        // No startSource, approval, resume, manual reconciliation or resend.
        const state = await run.status();
        await saveRunObservation(save, 'reply-loss-lookup', run, state);
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, loss.lookupStatus);
        if (state.status === 'succeeded') {
          const rows = await run.result(value.effect.resultName).all();
          assert.deepEqual(rows, value.effect.expectedRows);
          const additionalResults = await readAdditionalResults(run, value.effect);
          await save('recovered', {binding: originalBinding, ref: run.ref, rows,
            ...(value.effect.additionalResults === undefined ? {} : {additionalResults})});
        }
      } else {
        const approved = await load('approved');
        assert.deepEqual(approved.binding, originalBinding);
        assert.deepEqual(approved.ref, run.ref);
        // The first read of the same original Run is Result, before status.
        // No startSource, approval, request recovery or provider resend occurs.
        const rows = await run.result(value.effect.resultName).all();
        assert.deepEqual(rows, value.effect.expectedRows);
        assert.deepEqual(rows, approved.rows);
        const additionalResults = await readAdditionalResults(run, value.effect);
        if (value.effect.additionalResults !== undefined) assert.deepEqual(additionalResults, approved.additionalResults);
        const state = await run.status();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, captured.runId);
        await save('recovered', {binding: originalBinding, ref: run.ref, rows,
          ...(value.effect.additionalResults === undefined ? {} : {additionalResults})});
      }
    }
  } catch (error) {failed = true;primary = error;}
  const diagnosticFailures = [];
  const failureData = cause => {
    try {
      const token = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_.-]{0,127}$/u.test(value);
      return {name: token(cause?.name) ? cause.name : undefined, code: token(cause?.code) ? cause.code : undefined};
    } catch {return {available: false};}
  };
  const recordClose = async (stage, cleanup) => {
    if (observeClose === undefined) return;
    try {await observeClose({phase, pid: process.pid, stage, primaryPresent: failed,
      ...(failed ? {primary: failureData(primary)} : {}),
      firstClose: {attempted: true, returned: stage === 'returned', state: stage === 'started' ? 'pending' : stage},
      ...(stage === 'threw' ? {cleanup: failureData(cleanup)} : {})});}
    catch (cause) {diagnosticFailures.push(cause);}
  };
  await recordClose('started');
  let cleanupFailure, closeFailed = false;
  try {await client.close();}
  catch (cleanup) {cleanupFailure = cleanup;closeFailed = true;}
  await recordClose(closeFailed ? 'threw' : 'returned', cleanupFailure);
  if (closeFailed) {
    const cleanup = cleanupFailure;
    if (failed) throw new AggregateError([primary, cleanup], 'Workflow and client close both failed', {cause: primary});
    throw cleanup;
  }
  if (failed) throw primary;
  if (diagnosticFailures.length) throw new AggregateError(diagnosticFailures, 'RecordApprovalDiagnosticsFailed');
}
