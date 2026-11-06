// Compare retained actual observations with the original independent fixture.
// This read-only audit neither executes a product nor regenerates expectations.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {selectReleaseTemporalJoinQueryCases} from '../../scripts/release-temporal-join-query-cases.mjs';

export function auditTemporalJoinTransport(report) {
  const {successes, refusals} = selectReleaseTemporalJoinQueryCases();
  assert.ok(['local', 'https'].includes(report.mode));
  assert.equal(report.suite, 'temporal-join'); assert.equal(report.complete, true);
  assert.equal(report.actualNormal, 12); assert.equal(report.actualRefusal, 9);
  const names = successes.map(item => item.name), badNames = refusals.map(item => item.name);
  assert.deepEqual(report.expectedSuccessNames, names); assert.deepEqual(report.successNames, names);
  assert.deepEqual(report.expectedRefusalNames, badNames); assert.deepEqual(report.refusalNames, badNames);
  assert.deepEqual(report.completed.map(item => item.name), names);
  assert.deepEqual(report.completedRefusals.map(item => item.name), badNames);
  assert.deepEqual(report.providerObservation, {forbiddenProcesses: 0, forbiddenFetches: 0, sourceSecrets: 0});
  const fresh = report.freshProcessReread;
  assert.equal(fresh.mode, report.mode); assert.equal(fresh.suite, report.suite);
  assert.equal(fresh.phase, 'fresh-process-reread'); assert.equal(fresh.complete, true);
  assert.deepEqual(fresh.completed.map(item => item.name), names);
  assert.deepEqual(fresh.providerObservation, report.providerObservation);
  let rows = 0;
  for (const [index, actual] of report.completed.entries()) {
    assert.ok(actual.ref && Object.keys(actual.ref).length > 0);
    assert.ok(actual.submissionRef && Object.keys(actual.submissionRef).length > 0);
    assert.deepEqual(actual.observedResults, successes[index].results);
    const resultName = successes[index].format === 'json' ? 'answer' : 'main';
    rows += actual.observedResults[resultName].rows.length;
    assert.equal(actual.beforeSubmit.acceptedRuns, index);
    assert.equal(actual.beforeRead.acceptedRuns, index + 1);
    for (const key of ['sourceIo', 'sourceReads', 'sourceReadSessions']) {
      assert.equal(actual.beforeSubmit[key], 0); assert.equal(actual.beforeRead[key], 0);
    }
    assert.deepEqual(actual.afterReplay, actual.beforeRead);
    const reread = fresh.completed[index];
    assert.deepEqual(reread.ref, actual.ref); assert.deepEqual(reread.submissionRef, actual.submissionRef);
    assert.deepEqual(reread.observedResults, successes[index].results);
    assert.equal(reread.beforeAcceptedRuns, 12); assert.equal(reread.afterAcceptedRuns, 12);
  }
  for (const [index, actual] of report.completedRefusals.entries()) {
    assert.equal(actual.outcome.kind, 'not_accepted');
    assert.equal(actual.outcome.problem.code, refusals[index].expectedCode);
    assert.deepEqual(actual.outcome.submissionRef, actual.submissionRef);
    assert.deepEqual(actual.beforeSubmit,
      {acceptedRuns: 12, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0});
    assert.deepEqual(actual.afterRefusal, actual.beforeSubmit);
  }
  assert.equal(rows, 27);
  return {mode: report.mode, actualNormal: 12, actualRefusal: 9,
    actualNamedResults: 12, actualRows: rows, freshRereadNamedResults: 12, complete: true};
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [receiptPath, ...extra] = process.argv.slice(2);
  assert.equal(extra.length, 0); assert.ok(receiptPath);
  const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
  assert.equal(receipt.suite, 'temporal-join'); assert.equal(receipt.complete, true);
  assert.deepEqual(receipt.transports.map(item => item.mode), ['local', 'https']);
  assert.equal(receipt.artifacts.length, 4);
  assert.equal(receipt.records.length, 6);
  for (const command of receipt.records) {assert.equal(command.code, 0); assert.equal(command.signal, null);}
  console.log(JSON.stringify({complete: true, audits: receipt.transports.map(auditTemporalJoinTransport)}));
}
