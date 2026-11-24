// Read-only independent comparison against the original authored fixture.
// This never runs a Client, changes a receipt or derives expected values from
// product output. Package/source identity remains the existing producer fence.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {vectorScalarSourceSuccesses as successes, vectorScalarSourceRefusals as refusals}
  from '../../scripts/fixtures/vector-scalar-source-input.mjs';
import {encodeRetainedFixture} from '../../scripts/fixtures/retained-fixture-values.mjs';
import type {createVerifiedCaseReceipts} from '../../scripts/fixtures/cte-value-table-receipts.mjs';

type ReceiptWriter = ReturnType<typeof createVerifiedCaseReceipts>;
type CaseReceipt = Parameters<ReceiptWriter['record']>[0];
type RefusalReceipt = Parameters<ReceiptWriter['recordRefusal']>[0];
type ObservedCase = Pick<CaseReceipt, 'name' | 'beforeSubmit' | 'beforeRead' | 'afterReplay'> & {
  mode: unknown; ref: unknown; results: {answer: {rows: readonly unknown[]}};
};
type ObservedRefusal = Pick<RefusalReceipt, 'name' | 'beforeSubmit' | 'afterRefusal'> & {
  mode: unknown; submissionRef: unknown;
  outcome: {kind: unknown; problem: {code: unknown}; submissionRef: unknown};
};
type ObservedReceipt = {
  version: unknown; mode: unknown; complete: unknown;
  cases: readonly ObservedCase[]; refusals: readonly ObservedRefusal[];
};
type TransportReport = {
  mode: unknown; complete: unknown; expectedInventory: unknown; completedInventory: unknown;
  actualNormal: unknown; actualRefusal: unknown; observations: Readonly<Record<string, unknown>>;
};


const inventory = (['successes', 'refusals'] as const).flatMap(kind =>
  ({successes, refusals})[kind].map((item, index) => JSON.stringify([
    'vector-scalar', kind, index, item.name,
    createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
export function auditVectorScalarTransport(mode: string, report: TransportReport, receipt: ObservedReceipt) {
  assert.ok(['local', 'remote'].includes(mode));
  assert.equal(report.mode, mode); assert.equal(report.complete, true);
  assert.deepEqual(report.expectedInventory, inventory);
  assert.deepEqual(report.completedInventory, inventory);
  assert.equal(report.actualNormal, 12); assert.equal(report.actualRefusal, 8);
  assert.equal(receipt.version, 'actql-vector-scalar-acceptance/0.1');
  assert.equal(receipt.mode, mode); assert.equal(receipt.complete, true);
  assert.deepEqual(receipt.cases.map(item => item.name), successes.map(item => item.name));
  assert.deepEqual(receipt.refusals.map(item => item.name), refusals.map(item => item.name));
  let actualRows = 0;
  for (const [index, actual] of receipt.cases.entries()) {
    const fixture = successes[index];
    assert.equal(actual.mode, mode);
    assert.ok(actual.ref && typeof actual.ref === 'object' && Object.keys(actual.ref).length > 0);
    assert.deepEqual(actual.results, fixture.results);
    actualRows += actual.results.answer.rows.length;
    assert.equal(actual.beforeRead.acceptedRuns - actual.beforeSubmit.acceptedRuns, 1);
    for (const key of ['sourceIo', 'sourceReads', 'sourceReadSessions'] as const) {
      assert.equal(actual.beforeRead[key]! - actual.beforeSubmit[key]!, fixture.sourceReadSessionCount);
    }
    assert.deepEqual(actual.afterReplay, actual.beforeRead,
      'attach/resend/lookup/reread retain the original Run and acquisition');
  }
  assert.equal(actualRows, 36);
  for (const [index, actual] of receipt.refusals.entries()) {
    assert.equal(actual.mode, mode);
    assert.equal(actual.outcome.kind, 'not_accepted');
    assert.equal(actual.outcome.problem.code, refusals[index].expectedCode);
    assert.deepEqual(actual.outcome.submissionRef, actual.submissionRef);
    assert.deepEqual(actual.afterRefusal, actual.beforeSubmit);
  }
  const expectedObservations = {sourceIo: 8, sourceReads: 8, sourceReadSessions: 8,
    acceptedPages: 8, issuedGrants: 8, closedSites: 1};
  for (const [key, expected] of Object.entries(expectedObservations)) {
    assert.equal(report.observations[key], expected, key);
  }
  return {mode, complete: true, actualNormal: 12, actualRefusal: 8,
    actualNamedResults: 12, actualRows,
    inventorySha256: createHash('sha256').update(JSON.stringify(inventory)).digest('hex')};
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, ...extra] = process.argv.slice(2);
  assert.equal(extra.length, 0); assert.ok(directory);
  const read = (name: string) => readFile(join(resolve(directory!), name), 'utf8').then(JSON.parse);
  const audits = [];
  for (const mode of ['local', 'remote']) {
    audits.push(auditVectorScalarTransport(mode,
      await read(`transport-completion.${mode}.json`),
      await read(`vector-scalar-receipts.${mode}.json`)));
  }
  console.log(JSON.stringify({complete: true, audits, actualNamedResults: 24, actualRows: 72}));
}
