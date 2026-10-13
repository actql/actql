import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {selectReleaseNearestRequiredCases} from '../../scripts/release-nearest-required-query-cases.mjs';
import {encodeRetainedFixture} from '../../scripts/fixtures/retained-fixture-values.mjs';
const {successes, refusals} = selectReleaseNearestRequiredCases();
const inventory = ['successes', 'refusals'].flatMap(kind => ({successes, refusals})[kind].map((item, index) =>
  JSON.stringify(['nearest-required', kind, index, item.name,
    createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
const orderedKeys = value => Array.isArray(value) ? value.map(orderedKeys)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, orderedKeys(value[key])])) : value;
const rowKey = value => encodeRetainedFixture(orderedKeys(value));
export function auditNearestRequiredTransport(mode, report, receipt) {
  assert.ok(['local', 'remote'].includes(mode));
  assert.equal(report.mode, mode); assert.equal(report.complete, true);
  assert.deepEqual(report.expectedInventory, inventory); assert.deepEqual(report.completedInventory, inventory);
  assert.equal(report.actualNormal, 9); assert.equal(report.actualRefusal, 10);
  assert.equal(receipt.version, 'actql-nearest-required-acceptance/0.1');
  assert.equal(receipt.mode, mode); assert.equal(receipt.complete, true);
  assert.deepEqual(receipt.cases.map(item => item.name), successes.map(item => item.name));
  assert.deepEqual(receipt.refusals.map(item => item.name), refusals.map(item => item.name));
  let actualRows = 0;
  for (const [index, item] of receipt.cases.entries()) {
    const fixture = successes[index], expected = fixture.results.answer;
    assert.equal(item.mode, mode); assert.ok(item.ref && Object.keys(item.ref).length > 0);
    assert.deepEqual(Object.keys(item.results), ['answer']);
    if (expected.unordered) {
      assert.deepEqual(item.results.answer.rows.map(rowKey).sort(), expected.rows.map(rowKey).sort());
    } else { assert.deepEqual(item.results.answer.rows, expected.rows); }
    assert.deepEqual(item.results.answer.columns, expected.columns);
    actualRows += item.results.answer.rows.length;
    assert.equal(item.beforeRead.acceptedRuns - item.beforeSubmit.acceptedRuns, 1);
    for (const key of ['sourceIo', 'sourceReads', 'sourceReadSessions']) {
      assert.equal(item.beforeRead[key] - item.beforeSubmit[key], fixture.sourceReadSessionCount);
    }
    assert.deepEqual(item.afterReplay, item.beforeRead);
  }
  assert.equal(actualRows, 9);
  for (const [index, item] of receipt.refusals.entries()) {
    assert.equal(item.mode, mode); assert.equal(item.outcome.kind, 'not_accepted');
    assert.equal(item.outcome.problem.code, refusals[index].expectedCode);
    assert.deepEqual(item.outcome.submissionRef, item.submissionRef);
    assert.deepEqual(item.afterRefusal, item.beforeSubmit);
  }
  for (const [key, expected] of Object.entries({sourceIo: 10, sourceReads: 10,
    sourceReadSessions: 10, issuedGrants: 10, acceptedPages: 10, closedSites: 1})) {
    assert.equal(report.observations[key], expected, key);
  }
  return {mode, complete: true, actualNormal: 9, actualRefusal: 10, actualRows,
    actualNamedResults: 9, inventorySha256: createHash('sha256').update(JSON.stringify(inventory)).digest('hex')};
}
if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, ...extra] = process.argv.slice(2); assert.ok(directory); assert.equal(extra.length, 0);
  const read = name => readFile(join(resolve(directory), name), 'utf8').then(JSON.parse);
  const audits = [];
  for (const mode of ['local', 'remote']) audits.push(auditNearestRequiredTransport(mode,
    await read(`transport-completion.${mode}.json`), await read(`nearest-required-receipts.${mode}.json`)));
  console.log(JSON.stringify({complete: true, audits}));
}
