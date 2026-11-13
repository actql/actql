// Fresh ordinary controls on one original captured Run. The existing default
// remains public cancellation; no internal Host, resubmit, signer or retry.
import assert from 'node:assert/strict';
import {readFile, writeFile, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {workflowWorkObservation} from './work-observation.fixture.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [handoffPath, mode = 'paused-cancel'] = process.argv.slice(2);
assert.equal(typeof handoffPath, 'string');
assert(['approve-deny', 'paused-cancel', 'changed-current'].includes(mode));
const original = JSON.parse(await readFile(handoffPath, 'utf8'));
assert.equal(original.template, 'deal-review-mock');
assert.ok(['two-models', 'two-models-whole'].includes(original.variant));
const roots = [resolve('.actql'), resolve('mock')];
const descriptorsBefore = await observeRecordApprovalDescriptors(roots);
assert.equal(descriptorsBefore.openPaths.length, 0);
const targetState = async () => {
  const info = await stat('mock/data.json', {bigint: true});
  return {bytes: await readFile('mock/data.json', 'utf8'), file: {
    dev: String(info.dev), ino: String(info.ino), size: String(info.size), mtimeNs: String(info.mtimeNs)}};
};
const save = (suffix, value) => writeFile(handoffPath + suffix,
  JSON.stringify(value) + '\n', {mode: 0o600, flag: 'wx'});
const workObservation = workflowWorkObservation({trackOriginal: true});
const actual = {mode, pid: process.pid, originalRun: false, targetUnchanged: false};
let client, failed = false, primary, closeFailed = false, closeFailure, closeReturned = false;
let diagnosticFailed = false, diagnosticFailure;
try {
  assert.deepEqual(await targetState(), original.before);
  let expectedTarget = original.before;
  if (mode === 'approve-deny') {
    // Restrict only the existing operator-owned signing rule, as in the real
    // Local Account control. Reopen must observe Deny without rewriting it.
    const path = '.actql/mock-account/account.json';
    const account = JSON.parse(await readFile(path, 'utf8'));
    const rules = account.entries.filter(entry => entry.operation?.any_of?.includes('sign'));
    assert.equal(rules.length, 1); rules[0].outcome = 'deny';
    actual.accountWire = JSON.stringify(account);
    await writeFile(path, actual.accountWire, {mode: 0o600});
  } else if (mode === 'changed-current') {
    // Change BOTH captured rows so no untouched sibling can legitimately be
    // written. Preserve these external edits rather than restoring old bytes.
    const document = JSON.parse(original.before.bytes), rows = document.salesforce.Opportunity.rows;
    assert.deepEqual(rows.map(row => row.id).sort(), ['006Acme', '006Globex']);
    for (const row of rows) row.StageName = 'Closed Won';
    await writeFile('mock/data.json', JSON.stringify(document, null, 2) + '\n');
    expectedTarget = await targetState();
    assert.notEqual(expectedTarget.bytes, original.before.bytes);
    actual.currentChanged = true;
  }
  client = await connect({mode: 'local', installation: {directory: '.actql',
    observation: workObservation.connection}, profile: 'mock'});
  const execution = await client.attach(original.ref);
  assert.deepEqual(execution.ref, original.ref);
  const before = await execution.status();
  assert.equal(before.run_id, original.runId);
  assert.equal(before.status, 'waiting_checkpoint');
  assert.equal(before.checkpoint.id, original.checkpointId);
  actual.originalRun = true;
  if (mode === 'paused-cancel') {
    const cancellation = await execution.cancel();
    // Keep the exact returned operation before any outcome assertion/wait.
    await save('.cancellation.json', cancellation);
    assert.equal(cancellation.kind, 'accepted'); actual.cancellationKind = cancellation.kind;
    const terminal = await execution.wait();
    assert.equal(terminal.run_id, original.runId); assert.equal(terminal.status, 'cancelled');
    assert.equal(terminal.control.physical_stop, 'confirmed'); assert.equal(terminal.result_available, false);
    Object.assign(actual, {runStatus: terminal.status, physicalStop: terminal.control.physical_stop,
      resultAvailable: terminal.result_available});
  } else {
    assert.equal(Buffer.from((await client.reviewCheckpoint(original.summary)).bytes).toString('base64'),
      original.reviewBase64);
    if (mode === 'approve-deny') {
      assert.equal(await readFile('.actql/mock-account/account.json', 'utf8'), actual.accountWire);
      await assert.rejects(client.approve(original.checkpointId), cause => {
        actual.refusal = {code: cause.code, action: cause.authorization?.action,
          operation: cause.authorization?.tuple?.operation};
        assert.equal(cause.code, 'ExecutionAuthorizationDenied');
        assert.equal(cause.authorization?.action, 'deny');
        assert.equal(cause.authorization?.tuple?.operation, 'sign');
        return true;
      });
      const state = await execution.status();
      assert.equal(state.run_id, original.runId); assert.equal(state.status, 'waiting_checkpoint');
      actual.runStatus = state.status;
    } else {
      const answer = await client.approve(original.checkpointId);
      await save('.approval.json', answer);
      assert.equal(answer.results.length, 1); assert.equal(answer.results[0].status, 'committed');
      assert.equal(answer.signed.length, 1);
      const resolution = JSON.parse(answer.signed[0].resolutionWire);
      assert.equal(resolution.decision, 'approved'); assert.equal(resolution.run_id, original.runId);
      assert.equal(resolution.checkpoint_cid, original.summary.checkpointCid);
      const terminal = await execution.wait();
      Object.assign(actual, {runStatus: terminal.status, terminalCode: terminal.terminal_error?.code});
      assert.equal(terminal.run_id, original.runId); assert.equal(terminal.status, 'failed');
      // The actual failed preflight's typed cause is observed separately.
      // A generic failed Run or opaque MoonBitHostFailure cannot supply it.
    }
  }
  assert.deepEqual(await targetState(), expectedTarget); actual.targetUnchanged = true;
} catch (error) {failed = true; primary = error;}
// Preserve this original primary BEFORE FIRST close. Do not retry the public
// action or convert an unobserved/pending close into successful cleanup.
try {
  await save('.cancel.before-close.json', {phase: 'cancel', mode, pid: process.pid,
    failed, primaryCode: primary?.code, firstClose: {attempted: false, returned: false}});
} catch (error) {diagnosticFailed = true; diagnosticFailure = error;}
if (client !== undefined) {
  try {await client.close(); closeReturned = true;}
  catch (error) {closeFailed = true; closeFailure = error;}
}
let descriptorsAfter;
try {descriptorsAfter = await observeRecordApprovalDescriptors(roots);}
catch (error) {diagnosticFailed = true; diagnosticFailure ??= error;}
const fdClosed = descriptorsAfter?.openPaths.length === 0;
const work = workObservation.forOriginal(original.ref);
let workFailed = false;
try {
  assert.equal(work.complete, true); assert.equal(work.sourceAcquisitionStarts, 0);
  assert.equal(work.modelCallStarts, 0); assert.equal(work.effectReplacementReturns, 0);
  if (mode === 'changed-current') {
    assert.deepEqual(work.effectPreflightFailure, {available: true, code: 'EffectTargetVersionMismatch',
      kind: 'target_version_mismatch', phase: 'effect_apply_preflight'});
    actual.refusal = work.effectPreflightFailure; actual.staleApprovalRefused = true;
  }
} catch {workFailed = true;}
delete actual.accountWire;
console.log(JSON.stringify({...actual, phase: 'cancel',
  status: failed || closeFailed || diagnosticFailed || !fdClosed || workFailed ? 'failed' : 'passed',
  primaryCode: primary?.code, cleanupCode: closeFailure?.code, diagnosticCode: diagnosticFailure?.code,
  firstClose: {attempted: client !== undefined, returned: closeReturned}, workObservation: work,
  aliveScopedFD: {before: descriptorsBefore.openPaths.length, after: descriptorsAfter?.openPaths.length},
  qualification: 'Actual public control and FIRST close; descriptor snapshot is not cleanup acknowledgement'}));
if (failed || closeFailed || diagnosticFailed || !fdClosed || workFailed) process.exitCode = 1;
