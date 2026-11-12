// Run only in an exact normal installed namespace. The second process reads
// the original Saved Result; it has no Program file and submits nothing.
import assert from 'node:assert/strict';
import {readFile, writeFile, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {setTimeout} from 'node:timers/promises';
import {open} from '@actql/node';
import {getSubmissionOutcome, getSubmissionInput, getSubmissionAttempt} from '@actql/sdk';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [phase, handoffPath] = process.argv.slice(2);
assert(['budget', 'memory-recovery', 'work-recovery', 'capture', 'saved'].includes(phase));
assert.equal(typeof handoffPath, 'string');
const stateDir = join(process.cwd(), phase === 'budget' || phase.endsWith('-recovery') ? phase + '-state' : 'state');
const counts = [9999, 10000, 10001, 100000];
const report = {phase, pid: process.pid, cases: [], submits: 0,
  firstClose: 'unobserved', complete: false, phases: []};
const save = (name, value) => writeFile(name, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const started = process.hrtime.bigint();
const progress = async (event, current) => {
  try {
    await save(`${phase}.progress.json`, {phase, pid: report.pid, event,
      step: current?.name ?? null, elapsedNs: Number(process.hrtime.bigint() - started),
      complete: report.complete, firstClose: report.firstClose,
      currentRunResult: report.currentRunResult ?? null,
      phases: report.phases.slice(-64)});
  } catch (error) {
    const failures = report.diagnosticErrors ??= [];
    if (failures.length < 4) failures.push({name: error?.name, code: error?.code});
  }
};
const span = async (name, action) => {
  const value = {name, startedAt: new Date().toISOString()}; report.phases.push(value);
  const started = process.hrtime.bigint(), cpu = process.cpuUsage();
  await progress('start', value);
  try {const result = await action(); value.complete = true; return result;}
  catch (error) {value.complete = false; report.firstFailedStep ??= name; throw error;}
  finally {
    const used = process.cpuUsage(cpu);
    Object.assign(value, {endedAt: new Date().toISOString(), wallNs: Number(process.hrtime.bigint() - started),
      cpuUserUs: used.user, cpuSystemUs: used.system,
      scope: 'Same collection child, inclusive operation interval; observation overhead included'});
    await progress('end', value);
  }
};
function collectionProgram(count) {
  // Small Program, 100k small rows: no enormous VALUES text.
  const digits = Array.from({length: 10}, (_, n) => `SELECT ${n} AS n`).join(' UNION ALL ');
  return `WITH d AS (${digits}) SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < ${count}`;
}
function oversizedRowProgram() {
  return `SELECT [${new Array(20000).fill('0').join(',')}] AS cells`;
}
// A long comment has no data rows or execution work. Its original request
// snapshot alone outgrows this phase's fixed 256MiB while the later query fits.
function memoryRecoveryProgram() {
  return '/*' + 'x'.repeat(8 * 1024 * 1024) + '*/ SELECT 7 AS n';
}
function originalControlWorkRefusal(observations, ref, terminal, selectedWorkLimit) {
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.result_available, false);
  assert.equal(observations.length, 1);
  const original = observations[0];
  assert.deepEqual(original.ref, ref);
  assert.equal(original.code, 'CapturedRunExecutionFailed');
  assert.equal(original.primaryCode, 'MoonBitHostFailure');
  const data = original.primaryDiagnostic;
  assert(data !== undefined && data !== null && typeof data === 'object',
    'OriginalControlWorkDiagnosticUnavailable');
  assert.equal(data.code, 'MoonBitHostFailure');
  assert.equal(data.phase, 'local_managed_advance');
  assert(Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647);
  if (data.kind === 'control_work') {
    assert.deepEqual(Object.keys(data).sort(), ['code', 'controlWorkLimit', 'kind', 'phase', 'task']);
    assert.equal(data.controlWorkLimit, selectedWorkLimit);
  } else {
    assert.equal(data.kind, 'value_capture_work');
    assert.deepEqual(Object.keys(data).sort(), ['code', 'kind', 'phase', 'step', 'task', 'workLimit']);
    assert(Number.isSafeInteger(data.step) && data.step >= 0 && data.step <= 2147483647);
    assert.equal(data.workLimit, selectedWorkLimit);
  }
  return {...data, verified: true};
}
async function sameHostSmallResult(client, report, span, save) {
  report.currentRunResult = {kind: 'source', purpose: 'small-after-refusal'};
  report.submits++;
  const run = await span('submit-small-after-refusal', () => client.startSource('SELECT 7 AS n', {format: 'sql'}));
  await save(report.phase + '-small-ref-before-wait.json', run.ref);
  report.currentRunResult = {kind: 'run', ref: run.ref, purpose: 'small-after-refusal', complete: false};
  const terminal = await span('wait-small-after-refusal', () => run.wait());
  assert.equal(terminal.status, 'succeeded');
  const names = terminal.next_action?.results;
  assert(Array.isArray(names) && names.length === 1);
  report.currentRunResult = {...report.currentRunResult, resultName: names[0]};
  const rows = await span('all-small-after-refusal', () => run.result(names[0]).all());
  assert.deepEqual(rows, [{n: 7}]);
  report.currentRunResult.complete = true;
  return {complete: true, rows, submits: 1};
}
async function createPreviousSavedResult(client, report, span, save) {
  report.currentRunResult = {kind: 'source', purpose: 'previous-Saved'};
  report.submits++;
  const run = await span('submit-previous-Saved', () => client.startSource('SELECT 41 AS n', {format: 'sql'}));
  await save(report.phase + '-previous-Saved-ref-before-wait.json', run.ref);
  report.currentRunResult = {kind: 'run', ref: run.ref, purpose: 'previous-Saved', complete: false};
  const terminal = await span('wait-previous-Saved', () => run.wait());
  assert.equal(terminal.status, 'succeeded');
  const names = terminal.next_action?.results;
  assert(Array.isArray(names) && names.length === 1);
  report.currentRunResult.resultName = names[0];
  assert.deepEqual(await span('all-previous-Saved-before-refusal', () => run.result(names[0]).all()), [{n: 41}]);
  report.currentRunResult.complete = true;
  report.previousSavedCreated = true;
  return {ref: run.ref, resultName: names[0]};
}
async function readPreviousSavedResult(client, previous, report, span) {
  report.currentRunResult = {kind: 'saved', ref: previous.ref, resultName: previous.resultName, complete: false};
  const run = await span('attach-previous-Saved-after-refusal', () => client.attach(previous.ref));
  const rows = await span('previous-Saved-FIRST-after-refusal', () => run.result(previous.resultName).all());
  assert.deepEqual(rows, [{n: 41}]);
  assert.equal((await span('previous-Saved-status-AFTER-read', () => run.status())).status, 'succeeded');
  report.currentRunResult.complete = true;
  return {complete: true, rows, submits: 0};
}
function exactRows(rows, count) {
  assert.equal(rows.length, count);
  for (const row of rows) assert.deepEqual(row, {n: 0});
}
async function drainOriginalRows(result, expected) {
  let rows = 0;
  for await (const row of result.rows()) {assert.deepEqual(row, {n: 0}); rows++;}
  assert.equal(rows, expected, 'The original stream must reach EOF with every expected row');
  return {rows, complete: true};
}
// The installed Host emits this existing typed Common projection. An error
// code, an error.capacity property, or a failed quote without amounts is not
// this witness. These comparisons check evidence, not resource admission.
function originalBudgetRefusal(observations, receipt, memory) {
  // These absences alone prove nothing. The same failed snapshot's typed
  // diagnostic below identifies the pre-exchange boundary independently.
  assert.equal(receipt.outcome, undefined);
  assert.equal(receipt.input, undefined);
  assert.equal(receipt.attempt, undefined);
  assert.equal(observations.length, 1, 'Require one actual snapshot-capacity diagnostic');
  const original = observations[0];
  assert.equal(original?.phase, 'request_snapshot');
  assert(['retention', 'execution'].includes(original.dimension));
  const fields = ['requiredRetentionBytes', 'requiredExecutionBytes',
    'availableRetentionBytes', 'availableExecutionBytes'];
  assert.deepEqual(Object.keys(original).sort(), ['phase', 'dimension', ...fields].sort());
  const amounts = fields.map(name => {
    const value = original[name];
    assert.equal(typeof value, 'string');
    assert(value.length <= 19);
    assert(/^(?:0|[1-9][0-9]*)$/u.test(value));
    const amount = BigInt(value); assert(amount <= 9223372036854775807n);
    return amount;
  });
  const [requiredRetention, requiredExecution, availableRetention, availableExecution] = amounts;
  assert(availableRetention <= BigInt(memory.retainedBytes));
  assert(availableExecution <= BigInt(memory.executionBytes));
  assert(original.dimension === 'retention' ? requiredRetention > availableRetention
    : requiredRetention <= availableRetention && requiredExecution > availableExecution);
  return {...original, outcome: 'pre_send_capture', classification: 'resource_limit', verified: true};
}
let client, failed = false, primary;
const cleanup = [], programs = [];
const capacityObservations = report.capacityObservations = [];
const workObservations = report.workObservations = [];
try {
  // Explicit finite policy for this authored SQL's measured semantic work.
  // Both capture and the same-original Saved process select the same Host input.
  report.sourceFreeMaxWork = phase === 'work-recovery' ? 100000 : 30000000;
  const memory = phase === 'budget' ? 32768 : phase === 'memory-recovery' ? 268435456 : 1073741824;
  report.requestMemory = {retainedBytes: memory, executionBytes: memory};
  client = await span('open', () => open({stateDir, installation: {
    sourceFreeMaxWork: report.sourceFreeMaxWork,
    requestMemory: report.requestMemory,
    ...(['budget', 'memory-recovery', 'work-recovery'].includes(phase) ? {authorization: {observe(name, detail) {
      // A second delivery already fails the exact-one requirement. Bound the
      // retained diagnostic input even if an implementation repeats it.
      if (name === 'preparation_capacity_refused' && capacityObservations.length < 2) {
        capacityObservations.push(detail);
      }
      if (name === 'dispatch_failed' && workObservations.length < 2) workObservations.push(detail);
    }}} : {}),
  }}));
  if (phase === 'budget') {
    await span('submit-budget-refusal', async () => {
      const document = oversizedRowProgram();
      report.budgetInput = {utf8Bytes: Buffer.byteLength(document, 'utf8'), utf16Units: document.length,
        arrayElements: 20000, original: 'budget-input-before-submit.json'};
      assert(report.budgetInput.utf8Bytes > memory);
      await save(report.budgetInput.original, {format: 'sql', document});
      let refused = false, original;
      report.submits++;
      try {
        const run = await client.startSource(document, {format: 'sql'});
        report.budgetDisposition = 'run_returned';
        report.budgetRunTerminal = 'unobserved';
        report.budgetPublicOutcome = getSubmissionOutcome(run);
        await save('budget-unexpected-ref-before-close.json', run.ref);
      } catch (error) {refused = true; original = error;}
      assert(refused, 'The input-derived case requires actual snapshot refusal, not an unobserved returned Run');
      const receipt = {outcome: getSubmissionOutcome(original), input: getSubmissionInput(original),
        attempt: getSubmissionAttempt(original)};
      report.budgetPublicOutcome = receipt.outcome;
      report.budgetPublicAttempt = receipt.attempt;
      report.budgetInputPublished = receipt.input !== undefined;
      report.budgetDisposition = receipt.outcome?.kind ?? receipt.attempt?.kind ?? 'unclassified_failure';
      try {
        report.budgetRefusal = originalBudgetRefusal(capacityObservations,
          receipt, report.requestMemory);
        report.budgetDisposition = 'pre_send_capture';
      } catch (error) {
        report.budgetControlFailure = {name: error?.name, code: error?.code};
        throw original; // Keep the actual public failure if its cause is unproved.
      }
      report.cases.push({inputUtf8Bytes: report.budgetInput.utf8Bytes,
        expectedRefusal: 'request_snapshot', complete: true});
    });
  } else if (phase === 'memory-recovery') {
    const previous = await createPreviousSavedResult(client, report, span, save);
    const document = memoryRecoveryProgram();
    report.memoryInput = {utf8Bytes: Buffer.byteLength(document), commentBytes: 8 * 1024 * 1024};
    let original, refused = false;
    report.submits++;
    await span('submit-memory-refusal', async () => {
      try {
        const run = await client.startSource(document, {format: 'sql'});
        await save('memory-unexpected-ref-before-close.json', run.ref);
      } catch (error) {original = error; refused = true;}
    });
    assert(refused, 'Require actual original memory refusal before a Run');
    const receipt = {outcome: getSubmissionOutcome(original), input: getSubmissionInput(original),
      attempt: getSubmissionAttempt(original)};
    try {report.memoryRefusal = originalBudgetRefusal(capacityObservations, receipt, report.requestMemory);}
    catch {throw original;}
    assert.equal(workObservations.length, 0);
    report.resourceRecovery = await sameHostSmallResult(client, report, span, save);
    report.previousSaved = await readPreviousSavedResult(client, previous, report, span);
    report.cases.push({expectedRefusal: 'request_snapshot', complete: true});
  } else if (phase === 'work-recovery') {
    const previous = await createPreviousSavedResult(client, report, span, save);
    report.submits++;
    const run = await span('submit-work-refusal', () => client.startSource(collectionProgram(100000), {format: 'sql'}));
    await save('work-ref-before-wait.json', run.ref);
    report.currentRunResult = {kind: 'run', ref: run.ref, purpose: 'work-refusal', complete: false};
    const terminal = await span('wait-work-refusal', () => run.wait());
    report.workRunTerminal = {status: terminal.status, result_available: terminal.result_available};
    report.workDiagnosticAvailable = workObservations[0]?.primaryDiagnostic !== undefined;
    report.workRefusal = await span('verify-work-refusal', async () =>
      originalControlWorkRefusal(workObservations, run.ref, terminal, report.sourceFreeMaxWork));
    assert.equal(capacityObservations.length, 0, 'Do not relabel memory refusal as control work');
    report.resourceRecovery = await sameHostSmallResult(client, report, span, save);
    report.previousSaved = await readPreviousSavedResult(client, previous, report, span);
    report.cases.push({expectedRefusal: report.workRefusal.kind, complete: true});
  } else if (phase === 'capture') {
    for (const count of counts) {
      const programPath = join(process.cwd(), `collection-${count}.sql`);
      await writeFile(programPath, collectionProgram(count), {flag: 'wx'}); programs.push(programPath);
      const document = await readFile(programPath, 'utf8');
      report.currentRunResult = {kind: 'source', count};
      report.submits++;
      const run = await span(`submit-${count}`, () => client.startSource(
        document, {format: 'sql'}));
      // Persist the actual original before wait, even if that wait later fails.
      await save(`ref-before-wait-${count}.json`, run.ref);
      report.currentRunResult = {kind: 'run', ref: run.ref, count, complete: false};
      const state = await span(`wait-${count}`, () => run.wait());
      assert.equal(state.status, 'succeeded');
      const names = state.next_action?.results;
      assert(Array.isArray(names) && names.length === 1, 'Require the actual sole Named Result');
      report.currentRunResult.resultName = names[0];
      const result = run.result(names[0]);
      exactRows(await span(`all-${count}`, () => count === 10001
        ? result.all({maxRows: count}) : result.all()), count);
      report.currentRunResult.complete = true;
      report.cases.push({count, ref: run.ref, resultName: names[0], complete: true});
      if (count === 100000) {
        report.fullStream = await span('rows-100000-FULL', () => drainOriginalRows(result, count));
        await assert.rejects(result.all({maxRows: 7}), {code: 'ResultRetainedLimit'});
        await assert.rejects(result.all({maxRetainedValueBytes: 500}), {code: 'ResultRetainedLimit'});
        await assert.rejects(result.all({maxWireBytes: 20}), {code: 'ResultWireLimit'});
        await assert.rejects(result.all({maxRowWireBytes: 2}), {code: 'ResultRowWireLimit'});
        await assert.rejects(result.all({maxRowRetainedValueBytes: 8}), {code: 'ResultRowRetainedLimit'});
        let validated = 0;
        const shrinking = {'~standard': {version: 1, vendor: 'collection-control', validate(row) {
          assert.deepEqual(row, {n: 0}); validated++; delete row.n; return {value: null};
        }}};
        await assert.rejects(result.all(shrinking, {maxRetainedValueBytes: 500}), {code: 'ResultRetainedLimit'});
        assert.equal(validated, 1, 'Charge the original decoded row before application mutation');
        let batches = 0;
        for await (const batch of result.batches({maxBatchRows: 2, maxBatchRetainedValueBytes: 1000})) {
          exactRows(batch, 2);
          if (++batches === 3) break;
        }
        assert.equal(batches, 3);
        await assert.rejects(async () => {
          for await (const _batch of result.batches({maxBatchRetainedValueBytes: 8})) {
            assert.fail('An oversized row cannot enter the caller batch');
          }
        }, {code: 'ResultBatchLimit'});
        let seen = 0;
        for await (const row of result.rows()) {assert.deepEqual(row, {n: 0}); seen++; break;}
        assert.equal(seen, 1);
        const controller = new AbortController(); let cancelledRows = 0;
        const cancelling = {'~standard': {version: 1, vendor: 'collection-control', validate(row) {
          assert.deepEqual(row, {n: 0}); cancelledRows++; controller.abort(); return {value: row};
        }}};
        await assert.rejects(result.all(cancelling, {signal: controller.signal}));
        assert.equal(cancelledRows, 1, 'Cancel this original reader without cancelling or resubmitting its Run');
        report.controls = {tighterRows: true, collectionBytes: true, wireBytes: true, rowWireBytes: true,
          rowBytes: true, originalChargeBeforeValidation: true, boundedBatches: true,
          batchBytes: true, earlyBreak: true, readerCancellation: true};
        await save(handoffPath, {ref: run.ref, resultName: names[0], count});
      }
    }
    assert.deepEqual(report.cases.map(value => value.count), counts);
    // Few rows can still exceed the decoded per-row budget. Keep wire small
    // while exercising the same public SQL array constructor and SDK guard.
    const oversizedProgram = join(process.cwd(), 'collection-oversized-row.sql');
    await writeFile(oversizedProgram, oversizedRowProgram(), {flag: 'wx'});
    programs.push(oversizedProgram); report.submits++;
    const document = await readFile(oversizedProgram, 'utf8');
    report.currentRunResult = {kind: 'source', purpose: 'oversized-row'};
    const run = await span('submit-oversized-row', () => client.startSource(document, {format: 'sql'}));
    await save('ref-before-wait-oversized-row.json', run.ref);
    report.currentRunResult = {kind: 'run', ref: run.ref, purpose: 'oversized-row', complete: false};
    const state = await span('wait-oversized-row', () => run.wait());
    assert.equal(state.status, 'succeeded');
    const names = state.next_action?.results;
    assert(Array.isArray(names) && names.length === 1, 'Require the actual sole oversized-row Named Result');
    report.currentRunResult.resultName = names[0];
    await span('all-oversized-row-refusal', () => assert.rejects(run.result(names[0]).all(), {code: 'ResultRowRetainedLimit'}));
    report.currentRunResult.complete = true;
    report.oversizedRow = {rows: 1, arrayElements: 20000, expectedRefusal: 'ResultRowRetainedLimit', complete: true};
  } else {
    const original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.count, 100000);
    report.currentRunResult = {kind: 'saved', ref: original.ref, resultName: original.resultName, count: original.count, complete: false};
    const run = await span('attach', () => client.attach(original.ref));
    exactRows(await span('original-Saved-FIRST', () => run.result(original.resultName).all()), original.count);
    assert.equal((await span('status-AFTER-Saved', () => run.status())).status, 'succeeded');
    assert.equal(report.submits, 0);
    report.currentRunResult.complete = true;
    report.cases.push({count: original.count, complete: true});
  }
} catch (error) {failed = true; primary = error; report.primary = {name: error?.name, code: error?.code};}
finally {
  // Persist the original failure before close can wait indefinitely. This is
  // diagnostic DATA, never a physical stop/cleanup acknowledgement.
  report.diagnosticErrors ??= [];
  report.firstClose = client ? 'pending' : 'not-attempted';
  const persist = async (path, value) => {
    try {await save(path, value);}
    catch (error) {report.diagnosticErrors.push({name: error?.name, code: error?.code});}
  };
  await persist(`${phase}.pending.json`, {...report,
    firstFailedStep: report.firstFailedStep ?? null, complete: false});
  if (client) try {
    await span('FIRST-close', () => client.close()); report.firstClose = 'returned';
  } catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  if (report.firstClose === 'returned') try {
    const before = await observeRecordApprovalDescriptors([stateDir]); await setTimeout(100);
    const after = await observeRecordApprovalDescriptors([stateDir]);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (!failed && cleanup.length === 0 && phase === 'capture') {
    report.originalProgramsRemovedAfterFirstClose = 0;
    try {
      await span('remove-original-Programs', async () => {
        for (const path of programs) {
          await unlink(path); report.originalProgramsRemovedAfterFirstClose++;
        }
      });
    } catch (error) {cleanup.push(error);}
  }
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code}));
  report.complete = !failed && cleanup.length === 0 && report.diagnosticErrors.length === 0;
  await persist(`${phase}.pending.json`, {...report,
    firstFailedStep: report.firstFailedStep ?? null, complete: false});
  report.complete &&= report.diagnosticErrors.length === 0;
  await progress('complete');
  report.complete &&= report.diagnosticErrors.length === 0;
  await persist(`${phase}.observation.json`, report);
  report.complete &&= report.diagnosticErrors.length === 0;
}
console.log(JSON.stringify(report));
if (failed) throw primary;
if (cleanup.length) throw new AggregateError(cleanup, 'CollectionCleanupUnconfirmed');
if (report.diagnosticErrors.length) throw new Error('CollectionDiagnosticsFailed');
