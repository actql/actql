import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {auditVectorScalarTransport} from '../reviews/2026-10-13-vector-scalar-installed-source/public-audit.mjs';
import {vectorScalarSourceSuccesses as successes, vectorScalarSourceRefusals as refusals}
  from './fixtures/vector-scalar-source-input.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {createVerifiedCaseReceipts} from './fixtures/cte-value-table-receipts.mjs';

// Synthetic verifier controls, never product execution or retained public data.
function controls(mode) {
  let acceptedRuns = 0, reads = 0;
  const counters = () => ({acceptedRuns, sourceIo: reads, sourceReads: reads, sourceReadSessions: reads});
  const cases = successes.map((fixture, index) => {
    const beforeSubmit = counters(); acceptedRuns++; reads += fixture.sourceReadSessionCount;
    const beforeRead = counters();
    return {name: fixture.name, mode, ref: {synthetic: index},
      results: structuredClone(fixture.results), beforeSubmit, beforeRead, afterReplay: counters()};
  });
  const rejections = refusals.map(fixture => ({name: fixture.name, mode,
    submissionRef: {synthetic: fixture.name},
    outcome: {kind: 'not_accepted', problem: {code: fixture.expectedCode}, submissionRef: {synthetic: fixture.name}},
    beforeSubmit: counters(), afterRefusal: counters()}));
  const inventory = ['successes', 'refusals'].flatMap(kind =>
    ({successes, refusals})[kind].map((item, index) => JSON.stringify(['vector-scalar', kind, index,
      item.name, createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')])));
  return {report: {mode, complete: true, expectedInventory: inventory, completedInventory: inventory,
    actualNormal: 12, actualRefusal: 8, observations: {sourceIo: 8, sourceReads: 8,
      sourceReadSessions: 8, acceptedPages: 8, issuedGrants: 8, closedSites: 1}},
    receipt: {version: 'actql-vector-scalar-acceptance/0.1', mode, complete: true, cases, refusals: rejections}};
}

test('independent Vector audit accepts only the original complete transport inventory and observations', () => {
  for (const mode of ['local', 'remote']) {
    const {report, receipt} = controls(mode);
    const audited = auditVectorScalarTransport(mode, report, receipt);
    assert.equal(audited.actualRows, 36); assert.equal(audited.actualNamedResults, 12);
  }
});

test('Vector audit rejects wrong values/types/order refusal codes reacquisition and incomplete cleanup', () => {
  const mutations = [
    ({receipt}) => { receipt.cases[0].results.answer.rows[2].value = 0; },
    ({receipt}) => { receipt.cases[0].results.answer.rows.reverse(); },
    ({receipt}) => { receipt.cases[0].results.answer.columns.reverse(); },
    ({receipt}) => { receipt.cases[9].results.answer.columns[1].contract.dimensions = 2; },
    ({receipt}) => { receipt.cases[0].afterReplay.sourceReads++; },
    ({receipt}) => { receipt.refusals[0].outcome.problem.code = 'UnrelatedFailure'; },
    ({receipt}) => { receipt.refusals[0].afterRefusal.sourceIo++; },
    ({report}) => { report.observations.closedSites = 0; },
    ({report}) => { report.completedInventory.pop(); },
    ({receipt}) => { receipt.cases.push(receipt.cases[0]); },
    ({receipt}) => { receipt.complete = false; },
  ];
  for (const mutate of mutations) {
    const input = controls('local'); mutate(input);
    assert.throws(() => auditVectorScalarTransport('local', input.report, input.receipt));
  }
});

test('existing receipt collector retains verified replay/refusal snapshots without Client I/O', async () => {
  const writes = [];
  const collector = createVerifiedCaseReceipts('local', async (path, wire) => {
    writes.push({path, receipt: JSON.parse(wire)});
  }, {prefix: 'vector-scalar', version: 'actql-vector-scalar-acceptance/0.1'});
  const {receipt} = controls('local');
  const first = receipt.cases[0];
  await collector.record({...first, observedResults: first.results});
  await collector.recordRefusal(receipt.refusals[0]);
  assert.equal(writes.at(-1).receipt.complete, false);
  await collector.complete();
  const saved = writes.at(-1).receipt;
  assert.equal(saved.complete, true);
  assert.deepEqual(saved.cases[0].afterReplay, first.afterReplay);
  assert.deepEqual(saved.refusals[0], receipt.refusals[0]);
});
