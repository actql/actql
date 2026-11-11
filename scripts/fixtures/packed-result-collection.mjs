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
  try {return await action();} finally {value.endedAt = new Date().toISOString();}
};
function collectionProgram(count) {
  // Small Program, 100k small rows: no enormous VALUES text or special budget.
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
  client = await span('open', () => open({stateDir}));
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
      exactRows(await span(`all-${count}`, () => result.all({maxRows: count})), count);
      report.cases.push({count, ref: run.ref, resultName: names[0], complete: true});
      if (count === 100000) {
        await assert.rejects(result.all({maxRows: 7}), {code: 'ResultRetainedLimit'});
        await assert.rejects(result.all({maxRetainedValueBytes: 500}), {code: 'ResultRetainedLimit'});
        let seen = 0;
        for await (const row of result.rows()) {assert.deepEqual(row, {n: 0}); seen++; break;}
        assert.equal(seen, 1);
        await save(handoffPath, {ref: run.ref, resultName: names[0], count});
      }
    }
    assert.deepEqual(report.cases.map(value => value.count), counts);
  } else {
    const original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.count, 100000);
    const run = await span('attach', () => client.attach(original.ref));
    exactRows(await span('original-Saved-FIRST', () => run.result(original.resultName).all(
      {maxRows: original.count})), original.count);
    assert.equal((await span('status-AFTER-Saved', () => run.status())).status, 'succeeded');
    assert.equal(report.submits, 0);
    report.cases.push({count: original.count, complete: true});
  }
} catch (error) {failed = true; primary = error; report.primary = {name: error?.name, code: error?.code};}
finally {
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
    for (const path of programs) await unlink(path);
    report.originalProgramsRemovedAfterFirstClose = programs.length;
  }
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code}));
  report.complete = !failed && cleanup.length === 0;
  await save(`${phase}.observation.json`, report);
}
if (failed) throw primary;
if (cleanup.length) throw new AggregateError(cleanup, 'CollectionCleanupUnconfirmed');
console.log(JSON.stringify(report));
