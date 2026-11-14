// SAME ordinary project/Host, genuine request-memory refusal, then small work.
// This is a Request snapshot budget control, not a Model metadata budget claim.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {getSubmissionOutcome, getSubmissionInput, getSubmissionAttempt} from '@actql/sdk';
import {workflowWorkObservation} from './work-observation.fixture.mjs';
import {assertModelRequestSnapshotRefusal} from './model-control-observations.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';
const report = {kind: 'model-registry-budget', phase: 'budget', pid: process.pid,
  registeredMetadata: Object.keys(JSON.parse(await readFile('model-tasks.json', 'utf8')).tasks).length,
  selectedModelTasks: 0, submits: 0, firstClose: {attempted: false, returned: false},
  requestMemory: {retainedBytes: 268435456, executionBytes: 268435456}};
const work = workflowWorkObservation(), capacity = [];
const save = () => writeFile('budget.pending.json', JSON.stringify(report) + '\n', {mode: 0o600});
let client, primary, cleanup, diagnostic;
try {
  assert.equal(report.registeredMetadata, 129);
  client = await connect({mode: 'local', profile: 'mock', installation: {directory: '.actql',
    requestMemory: report.requestMemory, observation: work.connection,
    authorization: {observe(name, detail) {
      if (name === 'preparation_capacity_refused' && capacity.length < 2) capacity.push(detail);
    }}}});
  const document = '/*' + 'x'.repeat(8 * 1024 * 1024) + '*/ SELECT 7 AS n';
  report.budgetInputBytes = Buffer.byteLength(document);
  await writeFile('budget-original.sql', document, {flag: 'wx', mode: 0o600});
  let refusal;
  report.submits++;
  try {
    const unexpected = await client.startSource(document, {format: 'sql'});
    report.unexpectedRef = unexpected.ref;
    await writeFile('budget-unexpected-ref.json', JSON.stringify(unexpected.ref), {flag: 'wx', mode: 0o600});
  } catch (error) {refusal = error;}
  assert(refusal, 'Require the actual pre-send original Request snapshot refusal');
  report.expectedRefusalCode = refusal.code;
  try {report.budgetRefusal = assertModelRequestSnapshotRefusal(capacity, {
    outcome: getSubmissionOutcome(refusal), input: getSubmissionInput(refusal),
    attempt: getSubmissionAttempt(refusal)}, report.requestMemory);}
  catch (error) {report.controlFailureCode = error.code; throw refusal;}
  report.submits++;
  const run = await client.startSource('SELECT 7 AS n', {format: 'sql'});
  report.recoveryRef = run.ref;
  await save(); // Accepted original survives a failed wait or first close.
  const state = await run.wait();
  report.smallTerminal = {status: state.status, code: state.terminal_error?.code};
  await save();
  assert.equal(state.status, 'succeeded');
  const names = state.next_action?.results;
  assert(Array.isArray(names) && names.length === 1);
  assert.deepEqual(await run.result(names[0]).all(), [{n: 7}]);
  report.sameHostSmallResult = true;
} catch (error) {primary = error; report.primaryCode = error?.code; report.primaryName = error?.name;}
report.firstClose = {attempted: client !== undefined, returned: false, state: client ? 'pending' : 'not-attempted'};
report.status = primary ? 'failed' : 'closing'; report.workObservation = work.snapshot();
try {await save();} catch (error) {diagnostic = error;}
if (client) try {await client.close(); report.firstClose = {attempted: true, returned: true};}
catch (error) {cleanup = error; report.cleanupCode = error?.code; report.firstClose.state = 'threw';}
try {
  const fd = await observeRecordApprovalDescriptors([resolve('.actql'), resolve('mock')]);
  report.aliveScopedFD = {after: fd.openPaths.length}; assert.equal(fd.openPaths.length, 0);
  report.workObservation = work.snapshot();
  assert.equal(report.workObservation.complete, true);
  for (const name of ['sourceAcquisitionStarts', 'modelCallStarts', 'effectReplacementReturns']) {
    assert.equal(report.workObservation[name], 0);
  }
} catch (error) {diagnostic ??= error;}
report.status = primary || cleanup || diagnostic ? 'failed' : 'passed';
report.diagnosticCode = diagnostic?.code;
try {await save();} catch (error) {diagnostic ??= error; report.status = 'failed';}
console.log(JSON.stringify(report));
if (primary) throw primary;
if (cleanup) throw cleanup;
if (diagnostic) throw diagnostic;
