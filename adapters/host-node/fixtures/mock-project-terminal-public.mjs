// Two public terminal consumers of the SAME ordinary Mock Project installation.
// DATA oracles and injected command ports are component-testable without Core.
import assert from 'node:assert/strict';
import {access, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {types as nodeTypes} from 'node:util';
import {workflowWorkObservation} from './work-observation.fixture.mjs';
import {assertInstalledFamilyCompleteContent} from './installed-family-content.fixture.mjs';
import {observeRecordApprovalDescriptors} from '../../../scripts/fixtures/record-approval/scoped-fds.fixture.mjs';
import {resolveInstalledCompletionModules} from '../../../scripts/fixtures/external-rest/timed-installed-context.fixture.mjs';

const contentBytes = Buffer.from('{"id":1}\n{"id":2}\n');
const inferRows = [
  {id: '001Acme', risk: {input_key: {id: '001Acme'}, outcome: 'ok', value: {level: 'high', reason: 'falling usage and a competitor evaluation'}}},
  {id: '001Globex', risk: {input_key: {id: '001Globex'}, outcome: 'ok', value: {level: 'high', reason: 'support tickets about pricing'}}},
];

const ownDiagnosticData = (value, key) => {
  if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) return undefined;
  const field = Object.getOwnPropertyDescriptor(value, key);
  return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
};

// Caller-owned projection of the existing optional callback. Never copy an
// exception message, stack, input, reference, arbitrary member or secret.
export function terminalMockFailureDiagnostic(event, detail) {
  if (!['content_preparation_rejected', 'dispatch_failed'].includes(event)) return undefined;
  const record = {event}, code = ownDiagnosticData(detail, 'code');
  if (typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(code)) record.code = code;
  const boundary = ownDiagnosticData(detail, 'boundary');
  if (boundary === 'task_compilation') record.boundary = boundary;
  const primary = ownDiagnosticData(detail, 'primaryDiagnostic');
  for (const key of ['phase', 'kind']) {
    const value = ownDiagnosticData(primary, key);
    if (typeof value === 'string' && value.length <= 96 && /^[a-z_]+(?:\.[a-z_]+)*$/u.test(value)) {
      (record.primary ??= {})[key] = value;
    }
  }
  let issue = ownDiagnosticData(detail, 'cause');
  for (const key of ['issueTag', 'nestedIssueTag', 'leafIssueTag']) {
    const supplied = ownDiagnosticData(detail, key);
    const tag = supplied ?? (typeof issue === 'number' ? issue : ownDiagnosticData(issue, '$tag'));
    if (Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535) record[key] = tag;
    issue = ownDiagnosticData(issue, '_0');
  }
  return record;
}

export function terminalMockScenario(variant) {
  assert(['terminal-infer', 'terminal-content'].includes(variant));
  if (variant === 'terminal-infer') return {path: 'terminal.aql', format: 'aql', result: 'updates',
    source: `SELECT a.id AS id, a.description AS notes, u.active_users, u.trend
FROM salesforce.accounts AS a
JOIN snowflake.usage_30d AS u ON a.id = u.account_id
|> INFER \`model-task:churn-risk.v1\` INPUT (notes, active_users, trend) AS risk
|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
|> SELECT id, risk
|> RESULT updates;`, sourceStarts: 2, modelStarts: 2};
  return {path: 'terminal.program.json', format: 'json', result: 'file', sourceStarts: 0, modelStarts: 0,
    source: JSON.stringify({version: 'actql/0.1', id: 'mock-terminal-content', stages: [{id: 'main', inputs: {},
      steps: [{values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}, {id: 2}]}, as: 'seed'},
        {serialize: {format: 'jsonl', fields: ['id'], name: 'two.jsonl', preserve_order: true,
          bounds: {max_rows: 2, max_bytes: 64}}, as: 'file'}],
      results: {file: {from: 'file', fields: ['name', 'content', 'media_type', 'size_bytes', 'row_count']}}}],
    results: {file: {from: {stage: 'main', result: 'file'}}}})};
}

export function checkTerminalMockRows(variant, rows) {
  terminalMockScenario(variant);
  if (variant === 'terminal-infer') {
    assert.deepEqual([...rows].sort((a, b) => a.id.localeCompare(b.id)), inferRows);
    return;
  }
  assert.equal(rows.length, 1);
  assert.deepEqual(Object.keys(rows[0]).sort(), ['content', 'media_type', 'name', 'row_count', 'size_bytes']);
  const {content, ...metadata} = rows[0];
  assert.deepEqual(metadata, {name: 'two.jsonl', media_type: 'application/x-ndjson', size_bytes: 18, row_count: 2});
  // Independent literal bytes-derived metadata, NOT an actual Store byte read.
  // No issuer/ref/grant is manufactured by this assertion.
  assert.equal(contentBytes.length, 18);
  assertInstalledFamilyCompleteContent(content,
    {bytes: contentBytes, mediaType: 'application/x-ndjson', issuerKind: 'content_derivation'});
}

export function checkTerminalMockSavedRows(variant, rows, originalRows) {
  checkTerminalMockRows(variant, rows);
  assert.deepEqual(rows, originalRows, 'Saved preserves the complete original rows/envelope, not only Content bytes');
}

export function assertTerminalMockObservation(value, {variant, phase, pid, capturedPid, fromStarted = false}) {
  const selected = terminalMockScenario(variant);
  assert.equal(value.variant, variant);assert.equal(value.phase, phase);
  assert.equal(value.pid, pid);assert(Number.isSafeInteger(pid) && pid > 0);
  assert.equal(value.status, 'passed');assert.equal(value.complete, true);
  assert.deepEqual(value.firstClose, {attempted: true, returned: true, calls: 1});
  assert.deepEqual(value.aliveScopedFD, {before: 0, after: 0, pid});
  assert.equal(value.submits, phase === 'capture' ? 1 : 0);
  assert.equal(value.resultReads, 1);assert.equal(value.lookupOriginal, true);
  assert.equal(value.originalRefBeforeWait, phase === 'capture');
  assert.equal(value.savedFirst, phase === 'recover');
  assert.equal(value.workObservation.complete, true);
  assert.equal(value.workObservation.sourceAcquisitionStarts, phase === 'capture' ? selected.sourceStarts : 0);
  assert.equal(value.workObservation.modelCallStarts, phase === 'capture' ? selected.modelStarts : 0);
  assert.equal(value.workObservation.effectReplacementReturns, 0);
  if (phase === 'recover') {
    assert(Number.isSafeInteger(capturedPid) && capturedPid > 0);assert.notEqual(pid, capturedPid);
    assert.equal(value.originalInputsAbsent, true);
    if (fromStarted) {
      assert.equal(variant, 'terminal-infer');
      assert.equal(value.recoveryOrigin, 'started');
      assert.equal(value.originalRowsCompared, false);
      assert.equal(value.normalCaptureComplete, false);
    } else assert.notEqual(value.recoveryOrigin, 'started', 'Started-only evidence cannot qualify the complete capture workflow');
  } else assert.equal(phase, 'capture');
}

export async function runTerminalMockWorkflow({phase, variant, handoffPath, connect,
  fromStarted = false, directory = process.cwd(), createWorkObservation = workflowWorkObservation,
  observeDescriptors = observeRecordApprovalDescriptors}) {
  assert(['capture', 'recover'].includes(phase));
  assert.equal(typeof fromStarted, 'boolean');
  if (fromStarted) {assert.equal(phase, 'recover');assert.equal(variant, 'terminal-infer');}
  const selected = terminalMockScenario(variant), state = resolve(directory, '.actql');
  const roots = [state, resolve(directory, 'mock')];
  const report = {phase, variant, pid: process.pid, status: 'running', complete: false,
    submits: 0, resultReads: 0, originalRefBeforeWait: false, savedFirst: false, lookupOriginal: false,
    firstClose: {attempted: false, returned: false, calls: 0}};
  const recordPhase = fromStarted ? 'recover-from-started' : phase;
  if (fromStarted) Object.assign(report, {recoveryOrigin: 'started', originalRowsCompared: false,
    normalCaptureComplete: false, qualification: 'SAME started original Saved only; independent complete rows, not a successful capture handoff'});
  const save = (path, value, exclusive = false) => writeFile(path, JSON.stringify(value) + '\n',
    {mode: 0o600, ...(exclusive ? {flag: 'wx'} : {})});
  let client, failed = false, primary, closeFailed = false, closeFailure;
  const work = createWorkObservation();
  report.originalDiagnostics = [];
  const observe = (event, detail) => {
    const selected = terminalMockFailureDiagnostic(event, detail);
    if (selected === undefined) return;
    if (report.originalDiagnostics.length === 2) {report.diagnosticOverflow = true;return;}
    report.originalDiagnostics.push(selected);
  };
  try {
    await mkdir(state, {recursive: true});
    const before = await observeDescriptors(roots);assert.equal(before.pid, process.pid);assert.equal(before.openPaths.length, 0);
    client = await connect({mode: 'local', profile: 'mock',
      installation: {directory: state, observation: work.connection, authorization: {observe}}});
    if (phase === 'capture') {
      const submissionRef = client.newSubmission({nonce: variant});
      await save(handoffPath + '.submission', {variant, submissionRef, pid: process.pid}, true);
      report.submissionRecordedBeforeStart = true;
      report.submits++;
      const run = await client.startSource(await readFile(resolve(directory, selected.path), 'utf8'),
        {format: selected.format, submissionRef});
      await save(handoffPath + '.started', {variant, ref: run.ref, submissionRef, pid: process.pid}, true);
      report.originalRefBeforeWait = true;
      assert.equal((await run.wait()).status, 'succeeded');
      const rows = await run.result(selected.result).all();report.resultReads++;
      checkTerminalMockRows(variant, rows);
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');assert.deepEqual(lookup.admission.ref, run.ref);report.lookupOriginal = true;
      await save(handoffPath, {variant, ref: run.ref, submissionRef, rows, pid: process.pid}, true);
    } else {
      const original = JSON.parse(await readFile(handoffPath + (fromStarted ? '.started' : ''), 'utf8'));
      assert.equal(original.variant, variant);
      await assert.rejects(access(resolve(directory, selected.path)), {code: 'ENOENT'});
      await assert.rejects(access(resolve(directory, 'mock/churn-risk.v1.answers.yaml')), {code: 'ENOENT'});
      report.originalInputsAbsent = true;
      const run = await client.attach(original.ref);assert.deepEqual(run.ref, original.ref);
      // No wait/status/lookup before this SAME original Saved Result.
      const rows = await run.result(selected.result).all();report.resultReads++;report.savedFirst = true;
      if (fromStarted) checkTerminalMockRows(variant, rows);
      else {
        checkTerminalMockSavedRows(variant, rows, original.rows);
        report.recoveryOrigin = 'complete-capture';report.originalRowsCompared = true;
      }
      assert.equal((await run.status()).status, 'succeeded');
      const lookup = await client.lookupSubmission(original.submissionRef);
      assert.equal(lookup.kind, 'ready');assert.deepEqual(lookup.admission.ref, original.ref);report.lookupOriginal = true;
      report.capturedPid = original.pid;
    }
  } catch (cause) {failed = true;primary = cause;}
  if (failed) {
    const code = ownDiagnosticData(primary, 'code');
    try {await save(resolve(directory, `${recordPhase}.primary.json`), {
      publicCode: typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(code) ? code : null,
      thrownUndefined: primary === undefined, originalDiagnostics: report.originalDiagnostics,
    }, true);} catch { /* The diagnostic cannot replace the original failure. */ }
  }
  if (client !== undefined) {report.firstClose.attempted = true;report.firstClose.calls++;}
  // Persist pending BEFORE the first close. Exit never acknowledges cleanup.
  try {await save(resolve(directory, `${recordPhase}.pending.json`), report);}
  catch (cause) {if (!failed) {failed = true;primary = cause;}}
  if (client !== undefined) {
    try {await client.close();report.firstClose.returned = true;}
    catch (cause) {closeFailed = true;closeFailure = cause;}
  }
  try {
    report.workObservation = work.snapshot();
    if (report.firstClose.returned) {
      const after = await observeDescriptors(roots);
      assert.equal(after.pid, process.pid);
      report.aliveScopedFD = {before: 0, after: after.openPaths.length, pid: process.pid};
    }
    if (!failed && !closeFailed) {
      report.status = 'passed';report.complete = true;
      assertTerminalMockObservation(report, {variant, phase, pid: process.pid, capturedPid: report.capturedPid, fromStarted});
    }
  } catch (cause) {if (!failed) {failed = true;primary = cause;}}
  if (failed || closeFailed) {report.status = 'failed';report.complete = false;}
  report.code = primary?.code;report.cleanupCode = closeFailure?.code;
  try {await save(resolve(directory, `${recordPhase}.pending.json`), report);}
  catch (cause) {
    if (!failed && !closeFailed) {failed = true;primary = cause;report.status = 'failed';report.complete = false;}
  }
  if (failed) throw Object.assign(new Error('TerminalMockWorkflowFailed', {cause: primary}), {observation: report});
  if (closeFailed) throw Object.assign(new Error('TerminalMockFirstCloseFailed', {cause: closeFailure}), {observation: report});
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  // The harness owns the one project alias to its verified normal consumer.
  // Reuse the existing installed-only public resolver BEFORE any product runs.
  const modules = await realpath(resolve('node_modules'));
  const original = await resolveInstalledCompletionModules(dirname(modules), {observation: true});
  const {connect} = await import(pathToFileURL(original.node));
  const [selectedPhase, variant, handoffPath] = process.argv.slice(2);
  const fromStarted = selectedPhase === 'recover-from-started', phase = fromStarted ? 'recover' : selectedPhase;
  try {console.log(JSON.stringify(await runTerminalMockWorkflow({phase, variant, handoffPath, connect, fromStarted})));}
  catch (cause) {if (cause.observation) console.log(JSON.stringify(cause.observation));throw cause;}
}
