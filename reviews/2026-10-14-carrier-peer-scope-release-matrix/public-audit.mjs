// Read-only independent comparison against the original authored fixture.
// This never runs a Client, changes a receipt or derives expected values from
// product output. Package/source identity remains the existing producer fence.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {selectReleaseCarrierPeerCases} from '../../scripts/release-carrier-peer-scope-query-cases.mjs';

const {successes, refusals} = await selectReleaseCarrierPeerCases();
import {encodeRetainedFixture} from '../../scripts/fixtures/retained-fixture-values.mjs';

const inventory = ['successes', 'refusals'].flatMap(kind =>
  ({successes, refusals})[kind].map((item, index) => JSON.stringify([
    'carrier-peer-scope', kind, index, item.name,
    createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
export function auditCarrierPeerTransport(mode, report, receipt) {
  assert.ok(['local', 'remote'].includes(mode));
  assert.equal(report.mode, mode); assert.equal(report.complete, true);
  assert.deepEqual(report.expectedInventory, inventory);
  assert.deepEqual(report.completedInventory, inventory);
  assert.equal(report.actualNormal, 11); assert.equal(report.actualRefusal, 2);
  assert.equal(receipt.version, 'actql-carrier-peer-scope-acceptance/0.1');
  assert.equal(receipt.mode, mode); assert.equal(receipt.complete, true);
  assert.deepEqual(receipt.cases.map(item => item.name), successes.map(item => item.name));
  assert.deepEqual(receipt.refusals.map(item => item.name), refusals.map(item => item.name));
  let actualRows = 0;
  for (const [index, actual] of receipt.cases.entries()) {
    const fixture = successes[index];
    assert.equal(actual.mode, mode);
    assert.ok(actual.ref && typeof actual.ref === 'object' && Object.keys(actual.ref).length > 0);
    // `unordered` is the original SQL comparison policy, not Result data.
    assert.equal(fixture.results.answer.unordered, true);
    assert.deepEqual(Object.keys(actual.results), ['answer']);
    // Original F03 texts declare no ORDER BY. Preserve duplicates as a multiset;
    // named rank, score, key values and full column order remain exact.
    const orderedKeys = value => Array.isArray(value) ? value.map(orderedKeys)
      : value !== null && typeof value === 'object'
        ? Object.fromEntries(Object.keys(value).sort().map(key => [key, orderedKeys(value[key])]))
        : value;
    const rowKey = row => encodeRetainedFixture(orderedKeys(row));
    assert.deepEqual(actual.results.answer.rows.map(rowKey).sort(),
      fixture.results.answer.rows.map(rowKey).sort());
    assert.deepEqual(actual.results.answer.columns, fixture.results.answer.columns);
    actualRows += actual.results.answer.rows.length;
    assert.equal(actual.beforeRead.acceptedRuns - actual.beforeSubmit.acceptedRuns, 1);
    for (const key of ['sourceIo', 'sourceReads', 'sourceReadSessions']) {
      assert.equal(actual.beforeRead[key] - actual.beforeSubmit[key], fixture.sourceReadSessionCount);
    }
    assert.deepEqual(actual.afterReplay, actual.beforeRead,
      'attach/resend/lookup/reread retain the original Run and acquisition');
  }
  assert.equal(actualRows, 15);
  for (const [index, actual] of receipt.refusals.entries()) {
    assert.equal(actual.mode, mode);
    assert.equal(actual.outcome.kind, 'not_accepted');
    assert.equal(actual.outcome.problem.code, refusals[index].expectedCode);
    assert.deepEqual(actual.outcome.submissionRef, actual.submissionRef);
    assert.deepEqual(actual.afterRefusal, actual.beforeSubmit);
  }
  const expectedObservations = {sourceIo: 18, sourceReads: 18, sourceReadSessions: 18,
    acceptedPages: 18, issuedGrants: 18, closedSites: 1};
  for (const [key, expected] of Object.entries(expectedObservations)) {
    assert.equal(report.observations[key], expected, key);
  }
  return {mode, complete: true, actualNormal: 11, actualRefusal: 2,
    actualNamedResults: 11, actualRows,
    inventorySha256: createHash('sha256').update(JSON.stringify(inventory)).digest('hex')};
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, ...extra] = process.argv.slice(2);
  assert.equal(extra.length, 0); assert.ok(directory);
  const read = name => readFile(join(resolve(directory), name), 'utf8').then(JSON.parse);
  const audits = [];
  for (const mode of ['local', 'remote']) {
    audits.push(auditCarrierPeerTransport(mode,
      await read(`transport-completion.${mode}.json`),
      await read(`carrier-peer-scope-receipts.${mode}.json`)));
  }
  console.log(JSON.stringify({complete: true, audits, actualNamedResults: 22, actualRows: 30}));
}
