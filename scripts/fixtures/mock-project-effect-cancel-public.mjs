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
assert(['approve-deny', 'paused-cancel'].includes(mode));
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
const workObservation = workflowWorkObservation();
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
const work = workObservation.snapshot();
let workFailed = false;
try {
  assert.equal(work.complete, true); assert.equal(work.sourceAcquisitionStarts, 0);
  assert.equal(work.modelCallStarts, 0); assert.equal(work.effectReplacementReturns, 0);
} catch {workFailed = true;}
delete actual.accountWire;
console.log(JSON.stringify({...actual, phase: 'cancel',
  status: failed || closeFailed || diagnosticFailed || !fdClosed || workFailed ? 'failed' : 'passed',
  primaryCode: primary?.code, cleanupCode: closeFailure?.code, diagnosticCode: diagnosticFailure?.code,
  firstClose: {attempted: client !== undefined, returned: closeReturned}, workObservation: work,
  aliveScopedFD: {before: descriptorsBefore.openPaths.length, after: descriptorsAfter?.openPaths.length},
  qualification: 'Actual public control and FIRST close; descriptor snapshot is not cleanup acknowledgement'}));
if (failed || closeFailed || diagnosticFailed || !fdClosed || workFailed) process.exitCode = 1;
