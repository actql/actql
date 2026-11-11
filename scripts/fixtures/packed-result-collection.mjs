// Run only in an exact normal installed namespace. The second process reads
// the original Saved Result; it has no Program file and submits nothing.
import assert from 'node:assert/strict';
import {readFile, writeFile, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {setTimeout} from 'node:timers/promises';
import {open} from '@actql/node';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [phase, handoffPath] = process.argv.slice(2);
assert(['capture', 'saved'].includes(phase));
assert.equal(typeof handoffPath, 'string');
const stateDir = join(process.cwd(), 'state');
const counts = [9999, 10000, 10001, 100000];
const report = {phase, pid: process.pid, cases: [], submits: 0,
  firstClose: 'unobserved', complete: false, phases: []};
const save = (name, value) => writeFile(name, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const span = async (name, action) => {
  const value = {name, startedAt: new Date().toISOString()}; report.phases.push(value);
  try {return await action();}
  catch (error) {report.firstFailedStep ??= name; throw error;}
  finally {value.endedAt = new Date().toISOString();}
};
function collectionProgram(count) {
  // Small Program, 100k small rows: no enormous VALUES text.
  const digits = Array.from({length: 10}, (_, n) => `SELECT ${n} AS n`).join(' UNION ALL ');
  return `WITH d AS (${digits}) SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < ${count}`;
}
function exactRows(rows, count) {
  assert.equal(rows.length, count);
  for (const row of rows) assert.deepEqual(row, {n: 0});
}
let client, failed = false, primary;
const cleanup = [], programs = [];
try {
  // Explicit finite policy for this authored SQL's measured semantic work.
  // Both capture and the same-original Saved process select the same Host input.
  report.sourceFreeMaxWork = 30000000;
  report.requestMemory = {retainedBytes: 1073741824, executionBytes: 1073741824};
  client = await span('open', () => open({stateDir, installation: {
    sourceFreeMaxWork: report.sourceFreeMaxWork,
    requestMemory: report.requestMemory,
  }}));
  if (phase === 'capture') {
    for (const count of counts) {
      const programPath = join(process.cwd(), `collection-${count}.sql`);
      await writeFile(programPath, collectionProgram(count), {flag: 'wx'}); programs.push(programPath);
      const document = await readFile(programPath, 'utf8');
      report.submits++;
      const run = await span(`submit-${count}`, () => client.startSource(
        document, {format: 'sql'}));
      // Persist the actual original before wait, even if that wait later fails.
      await save(`ref-before-wait-${count}.json`, run.ref);
      const state = await span(`wait-${count}`, () => run.wait());
      assert.equal(state.status, 'succeeded');
      const names = state.next_action?.results;
      assert(Array.isArray(names) && names.length === 1, 'Require the actual sole Named Result');
      const result = run.result(names[0]);
      exactRows(await span(`all-${count}`, () => count === 10001
        ? result.all({maxRows: count}) : result.all()), count);
      report.cases.push({count, ref: run.ref, resultName: names[0], complete: true});
      if (count === 100000) {
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
    await writeFile(oversizedProgram, `SELECT [${new Array(20000).fill('0').join(',')}] AS cells`, {flag: 'wx'});
    programs.push(oversizedProgram); report.submits++;
    const document = await readFile(oversizedProgram, 'utf8');
    const run = await span('submit-oversized-row', () => client.startSource(document, {format: 'sql'}));
    await save('ref-before-wait-oversized-row.json', run.ref);
    const state = await span('wait-oversized-row', () => run.wait());
    assert.equal(state.status, 'succeeded');
    const names = state.next_action?.results;
    assert(Array.isArray(names) && names.length === 1, 'Require the actual sole oversized-row Named Result');
    await assert.rejects(run.result(names[0]).all(), {code: 'ResultRowRetainedLimit'});
    report.oversizedRow = {rows: 1, arrayElements: 20000, expectedRefusal: 'ResultRowRetainedLimit', complete: true};
  } else {
    const original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.count, 100000);
    const run = await span('attach', () => client.attach(original.ref));
    exactRows(await span('original-Saved-FIRST', () => run.result(original.resultName).all()), original.count);
    assert.equal((await span('status-AFTER-Saved', () => run.status())).status, 'succeeded');
    assert.equal(report.submits, 0);
    report.cases.push({count: original.count, complete: true});
  }
} catch (error) {failed = true; primary = error; report.primary = {name: error?.name, code: error?.code};}
finally {
  // Persist the original failure before close can wait indefinitely. This is
  // diagnostic DATA, never a physical stop/cleanup acknowledgement.
  report.diagnosticErrors = [];
  report.firstClose = client ? 'pending' : 'not-attempted';
  const persist = async (path, value) => {
    try {await save(path, value);}
    catch (error) {report.diagnosticErrors.push({name: error?.name, code: error?.code});}
  };
  await persist(`${phase}.pending.json`, {phase, pid: report.pid,
    firstFailedStep: report.firstFailedStep ?? null, primary: report.primary,
    submits: report.submits, firstClose: report.firstClose, complete: false});
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
  await persist(`${phase}.pending.json`, {phase, pid: report.pid,
    firstFailedStep: report.firstFailedStep ?? null, primary: report.primary,
    submits: report.submits, firstClose: report.firstClose, complete: false});
  report.complete &&= report.diagnosticErrors.length === 0;
  await persist(`${phase}.observation.json`, report);
  report.complete &&= report.diagnosticErrors.length === 0;
}
console.log(JSON.stringify(report));
if (failed) throw primary;
if (cleanup.length) throw new AggregateError(cleanup, 'CollectionCleanupUnconfirmed');
if (report.diagnosticErrors.length) throw new Error('CollectionDiagnosticsFailed');
