// Public Mock lifecycle consumer. Each phase runs in a separate process from
// the same Project and ordinary installed @actql/node package namespace.
// No internal Host port, application signer or replacement submission is used.
import assert from 'node:assert/strict';
import {readFile, writeFile, stat} from 'node:fs/promises';
import {connect} from '@actql/node';
import {getSubmissionCheckObservation} from '@actql/sdk';
import {createHostObservationConnection} from '@actql/local-node/observation';

const [phase, handoffPath, template = 'churn-risk-mock', variant = 'readme'] = process.argv.slice(2);
assert.ok(['capture', 'approve', 'recover'].includes(phase));
assert.equal(typeof handoffPath, 'string');
assert.ok(['churn-risk-mock', 'deal-review-mock'].includes(template));
const dealReview = template === 'deal-review-mock';
assert.ok(variant === 'readme' || ['two-models', 'two-models-whole'].includes(variant) && dealReview);
const twoModels = variant !== 'readme', wholeProducer = variant === 'two-models-whole';
const C = /^sha256:[0-9a-f]{64}$/u;
const expected = Object.freeze(dealReview ? {
  '006Acme': {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
  '006Globex': {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
} : {
  '001Acme': {level: 'high', reason: 'falling usage and a competitor evaluation'},
  '001Globex': {level: 'high', reason: 'support tickets about pricing'},
});
const originalRisk = Object.freeze({'001Acme': 'low', '001Globex': 'medium'});
const originalDeal = Object.freeze({
  '006Acme': {StageName: 'Proposal', NextStep: null},
  '006Globex': {StageName: 'Negotiation', NextStep: 'Legal review'},
});
let client, firstFailedStep, activeStep, primary, checkDiagnostic, runObservation, failed = false;
function workflowWorkObservation() {
  const counts = {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0};
  const connection = createHostObservationConnection({
    include: ['source', 'infer', 'effect'], correlation: false, events: {level: 'diagnostic'},
    deliver(record) {
      if (record.operation === 'source' && record.event === 'attempt_started') counts.sourceAcquisitionStarts++;
      if (record.operation === 'infer' && record.event === 'attempt_started') counts.modelCallStarts++;
      if (record.operation === 'effect' && record.event === 'write_observed') counts.effectReplacementReturns++;
    },
  });
  return {connection, snapshot() {
    let status;
    try {status = connection.status();} catch {return {...counts, complete: false, unavailable: true};}
    return {...counts, scope: 'Actual starts and returned Mock replacements; not durability ACK', status,
      complete: status !== undefined && status.closed === true && status.cleanupPending === false &&
        ['dropped', 'budgetUnavailable', 'queueOverflow', 'deliveryFailed', 'limited', 'repeated',
          'queued', 'active', 'activeSegments'].every(name => status[name] === 0) &&
        status.loss !== undefined && Object.values(status.loss).every(value => value === 0)};
  }};
}
function checkWorkflowWork(observed, selectedPhase, writes) {
  assert.equal(observed.complete, true, 'Lost, pending or unavailable observation cannot prove zero work');
  if (selectedPhase === 'capture') {
    assert(observed.sourceAcquisitionStarts > 0); assert(observed.modelCallStarts > 0);
    assert.equal(observed.effectReplacementReturns, 0);
  } else {
    assert.equal(observed.sourceAcquisitionStarts, 0, 'Completed Source must not be reacquired');
    assert.equal(observed.modelCallStarts, 0, 'Completed Model calls must not restart');
    assert.equal(observed.effectReplacementReturns, selectedPhase === 'approve' ? writes : 0);
  }
}
const workObservation = workflowWorkObservation();
const stepDiagnosticFailures = [];
async function step(name, operation) {
  activeStep = name;
  const startedAt = new Date().toISOString(), started = process.hrtime.bigint(), cpu = process.cpuUsage();
  let status = 'failed';
  try {
    const result = await operation();
    status = 'passed';
    return result;
  } catch (cause) {
    firstFailedStep ??= name;
    throw cause;
  } finally {
    const used = process.cpuUsage(cpu);
    const timing = {startedAt, endedAt: new Date().toISOString(),
      wallNs: Number(process.hrtime.bigint() - started), cpuUserUs: used.user, cpuSystemUs: used.system,
      scope: 'Same workflow child, inclusive operation interval; observation overhead included'};
    try {console.log(JSON.stringify({phase, step: name, status, timing}));}
    catch (cause) {stepDiagnosticFailures.push({name: cause?.name, code: cause?.code});}
  }
}
// Read this exact call's retained SDK observation, never check or submit again.
// Facts, input bodies, context/revision IDs and submission references stay private.
function submissionCheckDiagnostic(error) {
  try {
    const original = getSubmissionCheckObservation(error);
    if (original === undefined) return {available: false};
    const report = original.report ?? original.partial_report;
    const token = value => typeof value === 'string' && /^[a-z][a-z0-9_.-]{0,127}$/u.test(value);
    const entries = [...(report?.reasons ?? []), ...(report?.requirements ?? []),
      ...(report?.coverage?.limits ?? []), ...(report?.coverage?.unresolved ?? [])];
    const reasons = entries.slice(0, 32).filter(entry => token(entry.code)).map(entry => {
      const result = {code: entry.code}, source = entry.location;
      if (!source || !['text', 'structured'].includes(source.kind)) return result;
      const location = {kind: source.kind};
      if (['program', 'source', 'parameters', 'parameter_declarations'].includes(source.document_id)) {
        location.document = source.document_id;
      }
      if (source.kind === 'text' && Number.isSafeInteger(source.start_byte) && source.start_byte >= 0 &&
          Number.isSafeInteger(source.end_byte) && source.end_byte >= source.start_byte) {
        location.start_byte = source.start_byte; location.end_byte = source.end_byte;
      }
      if (source.kind === 'structured' && typeof source.pointer === 'string' &&
          source.pointer.length <= 512 && /^(?:\/[A-Za-z0-9_~.-]*)*$/u.test(source.pointer)) {
        location.pointer = source.pointer;
      }
      result.location = location;
      return result;
    });
    return {available: true, ...(token(original.outcome) ? {outcome: original.outcome} : {}),
      ...(token(report?.verdict) ? {verdict: report.verdict} : {}), reasons, truncated: entries.length > 32};
  } catch {return {available: false};} // Diagnostics never replace the original refusal or close.
}
// Only the exact public response already returned to this call. Do not poll,
// reconstruct a cause from status, or print private Run/Checkpoint identities,
// messages, authored input, rows or Source material into the step report.
function publicRunObservation(state) {
  try {
    if (!['preparing', 'running', 'waiting_checkpoint', 'resuming',
      'needs_reconciliation', 'succeeded', 'failed', 'cancelled'].includes(state?.status)) {
      return {available: false};
    }
    const code = state.terminal_error?.code;
    const result = {available: true, status: state.status,
      ...(typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_.-]{0,127}$/u.test(code)
        ? {terminalCode: code} : {})};
    if (['resolve_checkpoint', 'reconcile', 'read_result', 'refresh_availability',
      'none', 'reconcile_run'].includes(state.next_action?.kind)) {
      result.nextAction = state.next_action.kind;
    }
    if (['unknown', 'confirmed'].includes(state.control?.physical_stop)) {
      result.physicalStop = state.control.physical_stop;
    }
    if (typeof state.control?.cancellation_requested === 'boolean') {
      result.cancellationRequested = state.control.cancellation_requested;
    }
    return result;
  } catch {return {available: false};}
}
const snapshot = info => ({dev: String(info.dev), ino: String(info.ino),
  size: String(info.size), mtimeNs: String(info.mtimeNs)});
const dataPath = 'mock/data.json';
const targetState = async () => ({bytes: await readFile(dataPath, 'utf8'),
  file: snapshot(await stat(dataPath, {bigint: true}))});
const save = (path, value) => writeFile(path, JSON.stringify(value) + '\n',
  {encoding: 'utf8', mode: 0o600, flag: 'wx'});

function checkRows(rows) {
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(row => row.id).sort(), Object.keys(expected).sort());
  for (const row of rows) {
    if (dealReview) {
      assert.equal(row.review.outcome, 'ok');
      assert.deepEqual(row.review.value, expected[row.id]);
      assert.equal(row.StageName, originalDeal[row.id].StageName);
      assert.equal(row.NextStep, originalDeal[row.id].NextStep);
      if (twoModels) {
        assert.equal(row.confirmation.outcome, 'ok');
        assert.deepEqual(row.confirmation.value, {confirmed: true,
          stage: expected[row.id].stage, next_step: expected[row.id].next_step});
      }
    } else {
      assert.equal(row.risk.outcome, 'ok');
      assert.deepEqual(row.risk.value, expected[row.id]);
      assert.equal(row.active_users, row.id === '001Acme' ? '4' : '12');
    }
  }
}
async function readWholeResults(execution, updates) {
  const sourceRows = await execution.result('source_rows').all();
  assert.deepEqual([...sourceRows].sort((left, right) => left.id.localeCompare(right.id)), [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ]);
  const reviewed = await execution.result('reviewed').all();
  const confirmed = await execution.result('confirmed').all();
  const ordered = rows => [...rows].sort((left, right) => left.id.localeCompare(right.id));
  assert.deepEqual(ordered(reviewed), ordered(updates.map(({confirmation, ...row}) => row)));
  assert.deepEqual(ordered(confirmed), ordered(updates));
  return {source_rows: sourceRows, reviewed, confirmed};
}

function checkReview(review, summary, ref) {
  assert.deepEqual(Object.keys(review).sort(), ['version', 'review_projection_cid',
    'effect_preview_cid', 'authority_scope_cid', 'approval_claims', 'authoring_context_cid',
    'redaction_policy_cid', 'sensitivity', 'retention_class', 'encryption_required',
    'displayed_scope', 'displayed_permissions', 'displayed_rows',
    'displayed_authoring_context'].sort());
  assert.equal(review.version, 'actql-review-projection/0.1');
  assert.equal(review.review_projection_cid, summary.reviewProjectionCid);
  assert.equal(review.effect_preview_cid, summary.requiredArtifact.cid);
  assert.equal(review.authority_scope_cid, ref.authorityScopeCid);
  assert.deepEqual(review.approval_claims, summary.requirements);
  assert.equal(review.sensitivity, 'restricted');
  assert.equal(review.retention_class, 'approval-evidence');
  assert.equal(review.encryption_required, true);
  assert.deepEqual(review.displayed_scope.effects.map(({kind, target, count}) =>
    ({kind, target, count})), [{kind: 'update', target: dealReview
      ? 'connector://salesforce/Opportunity' : 'connector://salesforce/Account', count: 2}]);
  assert.equal(review.displayed_rows.length, 2);
  assert.deepEqual(review.displayed_rows.map(row => row.target_row_identity).sort(),
    Object.keys(expected).sort());
  for (const row of review.displayed_rows) {
    const id = row.target_row_identity, answer = expected[id];
    assert.match(row.row_preview_cid, C);
    assert.equal(row.preview_strength, 'full_diff');
    assert.equal(row.target_guard.state, 'version');
    assert.match(row.target_guard.version_cid, C);
    assert.equal(row.before.state, 'present');
    assert.equal(row.before.value.id, id);
    if (dealReview) {
      assert.equal(row.before.value.StageName, originalDeal[id].StageName);
      assert.equal(row.before.value.NextStep, originalDeal[id].NextStep);
      const changes = {StageName: answer.stage, NextStep: answer.next_step};
      assert.deepEqual(row.intended_changes, {state: 'present', value: changes});
      assert.deepEqual(row.after, {state: 'present', value: changes});
    } else {
      assert.equal(row.before.value.Churn_Risk__c, originalRisk[id]);
      assert.equal(row.before.value.Risk_Reason__c, null);
      assert.deepEqual(row.intended_changes, {state: 'present', value: {
        Churn_Risk__c: answer.level, Risk_Reason__c: answer.reason}});
      // The original full-diff after/change omits unchanged fields. The sealed
      // review preserves that original value rather than expanding the row.
      assert.deepEqual(row.after, {state: 'present', value: {
        Churn_Risk__c: answer.level, Risk_Reason__c: answer.reason}});
    }
  }
}
function expectedBytes(before) {
  if (dealReview) {
    // Select each edit in the original authored bytes. Acme's new stage is
    // Globex's old stage; a sequential search in changed bytes would edit it twice.
    const edits = [];
    for (const id of Object.keys(expected)) {
      for (const [field, value] of Object.entries({StageName: expected[id].stage,
        NextStep: expected[id].next_step})) {
        const prior = JSON.stringify(field) + ': ' + JSON.stringify(originalDeal[id][field]);
        assert.equal(before.split(prior).length, 2);
        edits.push({start: before.indexOf(prior), length: prior.length,
          next: JSON.stringify(field) + ': ' + JSON.stringify(value)});
      }
    }
    return edits.sort((a, b) => b.start - a.start).reduce((bytes, edit) =>
      bytes.slice(0, edit.start) + edit.next + bytes.slice(edit.start + edit.length), before);
  }
  let result = before;
  for (const id of Object.keys(expected)) {
    const prior = `"Churn_Risk__c": "${originalRisk[id]}"`;
    assert.equal(result.split(prior).length, 2);
    result = result.replace(prior, '"Churn_Risk__c": "high"');
    const reason = '"Risk_Reason__c": null';
    assert.ok(result.includes(reason));
    result = result.replace(reason, '"Risk_Reason__c": ' + JSON.stringify(expected[id].reason));
  }
  return result;
}

try {
  client = await step('connect', () => connect({mode: 'local',
    installation: {directory: '.actql', observation: workObservation.connection}, profile: 'mock'}));
  if (phase === 'capture') {
    const before = await step('read authored target before submission', targetState);
    const source = await step('read original README program', () =>
      readFile(twoModels ? 'deal-review.program.json' : dealReview ? 'deal-review.aql' : 'churn-risk.aql', 'utf8'));
    const execution = await step('README startSource', () =>
      client.startSource(source, {format: twoModels ? 'json' : 'aql', stopBefore: 'commit'}));
    // This accepted reference must survive a failed wait/review/first close.
    // The complete Checkpoint/review handoff below remains a separate file.
    await step('retain original accepted reference before wait', () =>
      save(handoffPath + '.started', {ref: execution.ref, template, variant}));
    const state = await step('wait for original Checkpoint', async () => {
      const state = await execution.wait();
      runObservation = publicRunObservation(state);
      assert.equal(state.status, 'waiting_checkpoint');
      assert.ok(state.checkpoint);
      assert.equal(state.checkpoint.id, state.checkpoint.checkpoint_id);
      return state;
    });
    const summary = await step('exact Checkpoint lookup', async () => {
      const page = await client.checkpoints({checkpointId: state.checkpoint.id});
      assert.equal(page.items.length, 1);
      assert.equal(page.items[0].checkpointCid, state.checkpoint.checkpoint_cid);
      return page.items[0];
    });
    const review = await step('read original sealed review', async () => {
      const review = await client.reviewCheckpoint(summary);
      await writeFile(handoffPath + '.review', review.bytes, {mode: 0o600, flag: 'wx'});
      checkReview(JSON.parse(Buffer.from(review.bytes).toString('utf8')), summary, execution.ref);
      return review;
    });
    await step('no write before approval', async () => assert.deepEqual(await targetState(), before));
    await step('retain original recovery reference', () => save(handoffPath,
      {ref: execution.ref, runId: state.run_id,
      checkpointId: state.checkpoint.id, summary,
      reviewBase64: Buffer.from(review.bytes).toString('base64'), before,
      expectedBytes: expectedBytes(before.bytes), ...(dealReview ? {template} : {}), ...(twoModels ? {variant} : {})}));
  } else {
    const captured = await step('read original public recovery reference', async () => {
      const captured = JSON.parse(await readFile(handoffPath, 'utf8'));
      assert.equal(captured.template ?? 'churn-risk-mock', template);
      assert.equal(captured.variant ?? 'readme', variant);
      return captured;
    });
    const execution = await step('attach same original Run', async () => {
      const execution = await client.attach(captured.ref);
      assert.deepEqual(execution.ref, captured.ref);
      return execution;
    });
    if (phase === 'approve') {
      await step('recover original Checkpoint', async () => {
        const state = await execution.status();
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, 'waiting_checkpoint');
        assert.ok(state.checkpoint);
        assert.equal(state.checkpoint.id, captured.checkpointId);
      });
      await step('recover identical sealed review', async () => {
        const review = await client.reviewCheckpoint(captured.summary);
        assert.equal(Buffer.from(review.bytes).toString('base64'), captured.reviewBase64);
      });
      await step('still no write before approval', async () =>
        assert.deepEqual(await targetState(), captured.before));
      await step('explicit default-Local approval', async () => {
        const answer = await client.approve(captured.checkpointId);
        assert.equal(answer.results.length, 1);
        assert.equal(answer.results[0].status, 'committed');
        assert.equal(answer.signed.length, 1);
        const resolution = JSON.parse(answer.signed[0].resolutionWire);
        assert.equal(resolution.decision, 'approved');
        assert.equal(resolution.run_id, captured.runId);
        assert.equal(resolution.run_definition_cid, captured.ref.runDefinitionCid);
        assert.equal(resolution.checkpoint_cid, captured.summary.checkpointCid);
        assert.equal(resolution.review_projection_cid, captured.summary.reviewProjectionCid);
      });
      const terminal = await step('same Run explicit UPDATE completion', async () => {
        const state = await execution.wait();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, captured.runId);
        return state;
      });
      let allResults;
      const rows = await step('original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows);
        if (wholeProducer) allResults = await readWholeResults(execution, rows);
        return rows;
      });
      const after = await step('exact conditional target bytes', async () => {
        const after = await targetState();
        assert.equal(after.bytes, captured.expectedBytes); return after;
      });
      await step('retain approved recovery reference', () => save(handoffPath + '.approved.json',
        {ref: execution.ref, runId: terminal.run_id, rows, after,
          ...(wholeProducer ? {allResults} : {}),
          ...(dealReview ? {template} : {}), ...(twoModels ? {variant} : {})}));
    } else {
      const approved = await step('read approved public recovery reference', async () => {
        const approved = JSON.parse(await readFile(handoffPath + '.approved.json', 'utf8'));
        assert.equal(approved.template ?? 'churn-risk-mock', template);
        assert.equal(approved.variant ?? 'readme', variant);
        assert.deepEqual(execution.ref, approved.ref);
        return approved;
      });
      // Saved Result must work before status can reopen a computation path.
      await step('recover original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows); assert.deepEqual(rows, approved.rows);
        if (wholeProducer) assert.deepEqual(await readWholeResults(execution, rows), approved.allResults);
      });
      await step('recover completed same Run', async () => {
        const state = await execution.status();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, approved.runId);
      });
      // Same bytes and physical inode/mtime show that completed recovery did
      // not replace this target again. This does not count Source acquisitions.
      await step('no repeated target replacement on recovery', async () =>
        assert.deepEqual(await targetState(), approved.after));
    }
  }
} catch (cause) {
  failed = true; primary = cause; firstFailedStep ??= activeStep;
  checkDiagnostic = submissionCheckDiagnostic(cause);
  try {
    if (runObservation === undefined && cause?.observation !== undefined) {
      runObservation = publicRunObservation(cause.observation);
    }
  } catch { /* Diagnostic getters cannot replace the original failure. */ }
}
let closeFailure, closeFailed = false, closeReturned = false;
const diagnosticFailures = [...stepDiagnosticFailures];
const pending = {phase, pid: process.pid, firstFailedStep: firstFailedStep ?? null,
  status: failed ? 'failed' : 'closing', code: primary?.code,
  workObservation: workObservation.snapshot(),
  firstClose: {attempted: client !== undefined, returned: false,
    state: client === undefined ? 'not-attempted' : 'pending'},
  ...(runObservation === undefined ? {} : {runObservation}),
  ...(checkDiagnostic === undefined ? {} : {checkObservation: checkDiagnostic})};
const persistCloseObservation = async () => {
  try {await writeFile(`${phase}.pending.json`, JSON.stringify(pending) + '\n', {mode: 0o600});}
  catch (cause) {diagnosticFailures.push({name: cause?.name, code: cause?.code});}
};
// This receipt precedes the FIRST close await. A pending receipt never proves
// cleanup or physical stop, even if its owning process later exits.
await persistCloseObservation();
if (client !== undefined) {
  try {await client.close(); closeReturned = true;}
  catch (cause) {closeFailure = cause; closeFailed = true; firstFailedStep ??= 'close';}
}
pending.firstClose = {attempted: client !== undefined, returned: closeReturned,
  state: closeReturned ? 'returned' : closeFailed ? 'threw' : 'not-attempted'};
pending.firstFailedStep = firstFailedStep ?? null;
pending.status = failed || closeFailed ? 'failed' : 'closed';
pending.cleanupCode = closeFailure?.code;
pending.workObservation = workObservation.snapshot();
let workFailure;
if (!failed && closeReturned) try {
  checkWorkflowWork(pending.workObservation, phase, Object.keys(expected).length);
} catch (cause) {workFailure = cause; firstFailedStep ??= 'observe actual Source Model and Effect work';}
await persistCloseObservation();
console.log(JSON.stringify({phase, firstFailedStep: firstFailedStep ?? null,
  status: failed || closeFailed || workFailure || diagnosticFailures.length ? 'failed' : 'passed',
  code: primary?.code, cleanupCode: closeFailure?.code,
  workObservation: pending.workObservation, workObservationCode: workFailure?.code,
  ...(diagnosticFailures.length ? {diagnosticFailures} : {}),
  firstClose: {attempted: client !== undefined, returned: closeReturned},
  ...(runObservation === undefined ? {} : {runObservation}),
  ...(checkDiagnostic === undefined ? {} : {checkObservation: checkDiagnostic})}));
if (failed) throw primary;
if (closeFailed) throw closeFailure;
if (workFailure) throw workFailure;
if (diagnosticFailures.length) throw new Error('WorkflowDiagnosticsFailed');
