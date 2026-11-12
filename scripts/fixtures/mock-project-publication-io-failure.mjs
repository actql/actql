// Copy into one fresh authored two-Model Project with the original scoped-FD
// observer. Only public installed SDK/observation APIs are imported. The fault
// is an actual permission change to this Project's own Store staging directory,
// never an installed module patch or replacement Store/Model callback.
import assert from 'node:assert/strict';
import {chmodSync, closeSync, lstatSync, openSync, realpathSync, unlinkSync} from 'node:fs';
import {lstat, mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {createHostObservationConnection} from '@actql/local-node/observation';
import {workflowObservationComplete} from './work-observation.fixture.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [receiptPath] = process.argv.slice(2);
assert.equal(typeof receiptPath, 'string');
assert.equal(typeof process.getuid, 'function');
assert.notEqual(process.getuid(), 0, 'Root permissions cannot exercise this refusal');
const save = (suffix, value) => writeFile(receiptPath + suffix,
  JSON.stringify(value, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
const snapshot = info => ({dev: String(info.dev), ino: String(info.ino),
  size: String(info.size), mtimeNs: String(info.mtimeNs)});
const target = async () => ({bytes: await readFile('mock/data.json', 'utf8'),
  file: snapshot(await lstat('mock/data.json', {bigint: true}))});
const roots = [resolve('.actql'), resolve('mock')];
await mkdir('.actql'); // A distinct empty directory, never a prior Run/state.
const descriptorBefore = await observeRecordApprovalDescriptors(roots);
assert.equal(descriptorBefore.openPaths.length, 0);
const before = await target();
const counts = {sourceStarts: 0, modelStarts: 0, modelResponses: 0, modelSuccesses: 0, effectWrites: 0};
const responseCoordinates = new Map();
let originalDirectory, armed = false, restored = false, faultFailure, faultFailed = false, probeCode;
let originalRun = false, targetUnchanged = false;
let client, execution, primary, failed = false, terminal;
let closeFailure, closeFailed = false, closeReturned = false;
let reportFailure, reportFailed = false;
const staging = resolve('.actql/publication/staging');
function restoreStaging() {
  if (!armed || restored) return;
  const current = lstatSync(staging);
  assert(current.isDirectory() && !current.isSymbolicLink());
  assert.equal(current.dev, originalDirectory.dev);
  assert.equal(current.ino, originalDirectory.ino);
  chmodSync(staging, originalDirectory.mode & 0o777);
  restored = true;
}
function armStagingFailure() {
  assert.equal(realpathSync(staging), staging);
  const original = lstatSync(staging);
  assert(original.isDirectory() && !original.isSymbolicLink());
  assert.equal(original.uid, process.getuid());
  assert((original.mode & 0o200) !== 0);
  originalDirectory = original;
  chmodSync(staging, original.mode & 0o555);
  armed = true;
  // Independently verify that this same process really lacks create permission.
  // A successful probe is a fixture failure, never evidence of Store refusal.
  const probe = resolve(staging, `publication-failure-probe-${process.pid}`);
  let refusal;
  try {
    const fd = openSync(probe, 'wx', 0o600);
    closeSync(fd); unlinkSync(probe);
  } catch (error) {refusal = error;}
  probeCode = refusal?.code;
  assert.equal(probeCode, 'EACCES');
}
const observation = createHostObservationConnection({
  include: ['source', 'infer', 'effect', 'run'], correlation: {include: ['task', 'attempt']},
  events: {level: 'diagnostic'},
  deliver(record) {
    if (record.operation === 'source' && record.event === 'attempt_started') counts.sourceStarts++;
    if (record.operation === 'effect' && record.event === 'write_observed') counts.effectWrites++;
    if (record.operation !== 'infer') return;
    if (record.event === 'attempt_started') counts.modelStarts++;
    if (record.event !== 'attempt_observed') return;
    counts.modelResponses++;
    if (record.attributes?.['actql.outcome'] === 'succeeded') {
      counts.modelSuccesses++;
      const task = record.attributes['actql.task.ordinal'];
      const slot = record.attributes['actql.model.slot.ordinal'];
      const attempt = record.attributes['actql.attempt.ordinal'];
      if ([task, slot, attempt].every(value => Number.isSafeInteger(value) && value >= 0) &&
          responseCoordinates.size < 4) responseCoordinates.set(`${task}:${slot}:${attempt}`, task);
    }
    // Exactly two independently authored rows in each of two Model Units.
    // This count only selects an external fault time; it grants no admission.
    if (counts.modelResponses === 4 && responseCoordinates.size === 4 &&
        new Set(responseCoordinates.values()).size === 2) {
      try {armStagingFailure();}
      catch (error) {faultFailed = true; faultFailure = error;}
    }
  },
});
const publicState = state => state === undefined ? undefined : ({
  status: state.status, resultAvailable: state.result_available,
  physicalStop: state.control?.physical_stop,
  cancellationRequested: state.control?.cancellation_requested,
  terminalCode: state.terminal_error?.code,
});
try {
  client = await connect({mode: 'local', profile: 'mock',
    installation: {directory: '.actql', observation}});
  const source = await readFile('deal-review.program.json', 'utf8');
  execution = await client.startSource(source, {format: 'json', stopBefore: 'commit'});
  await save('.started.json', {ref: execution.ref}); // Original, before wait.
  terminal = await execution.wait();
  await save('.wait.json', {ref: execution.ref, state: terminal});
  assert.equal(faultFailed, false);
  assert.equal(armed, true, 'No delivered fault is not a failed-publication test');
  assert.equal(counts.sourceStarts, 2);
  assert.equal(counts.modelStarts, 4);
  assert.equal(counts.modelResponses, 4);
  assert.equal(responseCoordinates.size, 4);
  assert.equal(new Set(responseCoordinates.values()).size, 2);
  assert.equal(counts.modelSuccesses, 4);
  assert.equal(terminal.status, 'failed', 'Unknown/reconciliation is not expected refusal');
  assert.equal(terminal.result_available, false);
  assert.equal(terminal.control.physical_stop, 'confirmed');
  assert.equal(counts.effectWrites, 0);
  assert.deepEqual(await target(), before);
  const same = await execution.status();
  assert.equal(same.run_id, terminal.run_id);
  assert.equal(same.status, 'failed');
  assert.equal(same.result_available, false);
  assert.equal(same.terminal_error?.code, terminal.terminal_error?.code);
  await save('.same-status.json', {ref: execution.ref, state: same});
  originalRun = true;
} catch (error) {failed = true; primary = error;}
// Restore the original same-inode directory BEFORE the first close. Cleanup
// receives no repeated close, alternate owner, or manually removed Store data.
try {restoreStaging();}
catch (error) {faultFailed = true; faultFailure ??= error;}
try {
  await save('.before-close.json', {phase: 'publication-io-failure', pid: process.pid, failed,
    primaryCode: primary?.code, state: publicState(terminal), counts,
    fault: {armed, restored, failed: faultFailed, code: faultFailure?.code, probeCode},
    firstClose: {attempted: false, returned: false}});
} catch (error) {reportFailed = true; reportFailure = error;}
if (client !== undefined) {
  try {await client.close(); closeReturned = true;}
  catch (error) {closeFailed = true; closeFailure = error;}
}
const descriptorsAfter = await observeRecordApprovalDescriptors(roots);
const status = observation.status();
const observationComplete = workflowObservationComplete(status);
try {assert.deepEqual(await target(), before); targetUnchanged = true;}
catch (error) {failed = true; primary ??= error;}
const passed = !failed && !closeFailed && !faultFailed && !reportFailed && closeReturned && restored &&
  descriptorsAfter.openPaths.length === 0 && observationComplete && originalRun && targetUnchanged;
const outcome = {mode: 'publication-io-failure', phase: 'publication-io-failure', pid: process.pid,
  originalRun, targetUnchanged, modelUnits: new Set(responseCoordinates.values()).size, modelOccurrences: responseCoordinates.size, status: passed ? 'passed' : 'failed',
  primaryCode: primary?.code, cleanupCode: closeFailure?.code, state: publicState(terminal), counts,
  reportCode: reportFailure?.code,
  fault: {armed, restored, failed: faultFailed, code: faultFailure?.code, probeCode},
  firstClose: {attempted: client !== undefined, returned: closeReturned},
  aliveScopedFD: {before: descriptorBefore.openPaths.length, after: descriptorsAfter.openPaths.length},
  observationComplete, observationStatus: status,
  qualification: 'Real filesystem permission fault and public failure/first close. Generic public status does not localize an internal primary cause; original component evidence remains separate.'};
await save('.outcome.json', outcome);
console.log(JSON.stringify(outcome));
if (!passed) process.exitCode = 1;
