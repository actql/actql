// A distinct fresh ordinary Mock consumer, following the original capture
// phase without approval. Copy this file and its existing record-approval
// descriptor observer into the fresh Project, preserving their relative paths.
// No internal Host, signer, resubmit or retry port.
import assert from 'node:assert/strict';
import {readFile, writeFile, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [handoffPath] = process.argv.slice(2);
assert.equal(typeof handoffPath, 'string');
const original = JSON.parse(await readFile(handoffPath, 'utf8'));
assert.equal(original.template, 'deal-review-mock');
assert.ok(['two-models', 'two-models-whole'].includes(original.variant));
const roots = [resolve('.actql'), resolve('mock')];
const descriptorsBefore = await observeRecordApprovalDescriptors(roots);
assert.equal(descriptorsBefore.openPaths.length, 0);
let client, failed = false, primary, closeFailed = false, closeFailure, closeReturned = false;
let diagnosticFailed = false, diagnosticFailure;
try {
  client = await connect({mode: 'local', installation: {directory: '.actql'}, profile: 'mock'});
  const execution = await client.attach(original.ref);
  assert.deepEqual(execution.ref, original.ref);
  const before = await execution.status();
  assert.equal(before.run_id, original.runId);
  assert.equal(before.status, 'waiting_checkpoint');
  assert.equal(before.checkpoint.id, original.checkpointId);
  const cancellation = await execution.cancel();
  // Retain this exact returned operation before any wait or assertion on its
  // outcome. An uncertain cancellation is never resubmitted or called a pass.
  await writeFile(handoffPath + '.cancellation.json', JSON.stringify(cancellation) + '\n',
    {mode: 0o600, flag: 'wx'});
  assert.equal(cancellation.kind, 'accepted');
  const terminal = await execution.wait();
  assert.equal(terminal.run_id, original.runId);
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.control.physical_stop, 'confirmed');
  assert.equal(terminal.result_available, false);
  const info = await stat('mock/data.json', {bigint: true});
  assert.deepEqual({bytes: await readFile('mock/data.json', 'utf8'), file: {
    dev: String(info.dev), ino: String(info.ino), size: String(info.size), mtimeNs: String(info.mtimeNs),
  }}, original.before);
} catch (error) {failed = true; primary = error;}
// Preserve the original outcome BEFORE the FIRST close await. A slow or
// failed close cannot replace that outcome or erase the cancellation receipt.
try {
  await writeFile(handoffPath + '.cancel.before-close.json', JSON.stringify({
    phase: 'cancel', failed, primaryCode: primary?.code,
    firstClose: {attempted: false, returned: false},
  }) + '\n', {mode: 0o600, flag: 'wx'});
} catch (error) {diagnosticFailed = true; diagnosticFailure = error;}
if (client !== undefined) {
  try {await client.close(); closeReturned = true;}
  catch (error) {closeFailed = true; closeFailure = error;}
}
const descriptorsAfter = await observeRecordApprovalDescriptors(roots);
const fdClosed = descriptorsAfter.openPaths.length === 0;
console.log(JSON.stringify({phase: 'cancel', status: failed || closeFailed || diagnosticFailed || !fdClosed ? 'failed' : 'passed',
  code: primary?.code, cleanupCode: closeFailure?.code,
  diagnosticCode: diagnosticFailure?.code,
  firstClose: {attempted: client !== undefined, returned: closeReturned},
  aliveScopedFD: {before: descriptorsBefore.openPaths.length, after: descriptorsAfter.openPaths.length},
  qualification: 'Public cancellation/first close; descriptor observation alone is not cleanup acknowledgement'}));
if (failed || closeFailed || diagnosticFailed || !fdClosed) process.exitCode = 1;
