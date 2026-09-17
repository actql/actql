import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {retainedCase, workloads} from
  '../../../benchmarks/retained-results/fixtures.mjs';
import {runMatchedEquivalentPair} from
  '../bench/matched-equivalent-pair.mjs';

const checkout = new URL('../../../', import.meta.url).pathname;

test('matched pair alternates fresh legs and cannot promote diagnostics', async () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const directory = await mkdtemp(join(tmpdir(), 'actql-matched-pair-'));
  const database = join(directory, 'source.duckdb');
  await writeFile(database, 'immutable fixture');
  try {
    for (const index of [0, 1]) {
      const calls = [];
      const accounting = {
        nativeSemanticRows: 10,
        nativeSemanticCells: 20,
        nativeSemanticBytes: 30,
        jsMaterializedCells: 20,
        identityPasses: 4,
        identityPreimageBytes: 40,
        retainedStoreBytes: 20,
        measuredGuardWork: 30,
        measuredGuardBytes: 40,
        measuredGuardNodes: 20,
        reusedGuardWork: 10,
        reusedGuardBytes: 12,
        reusedGuardNodes: 6,
        logicalGuardWork: 40,
        logicalGuardBytes: 52,
        logicalGuardNodes: 26,
        comparisonWork: 15,
        comparisonBytes: 20,
        comparisonNodes: 10,
      };
      const acquisitionEvidenceMetadata = Object.freeze({
        sourceRef: 'connector://fixture/source#view',
        validationScan: Object.freeze({rows: 10}),
        nativeResult: Object.freeze({rows: 2}),
      });
      const usage = Object.freeze({
        planning_work: 10,
        attempts: 5,
        transferred_bytes: '20',
        uncertain_transfer_bytes: '0',
        reserved_transfer_bytes: '0',
        held_bytes: '0',
        reserved_retention_bytes: '0',
        reserved_execution_bytes: '0',
      });
      const directRetention = Object.freeze({
        ...usage,
        planning_work: 0,
        attempts: 4,
        transferred_bytes: '0',
        held_bytes: '10',
      });
      const directExecution = Object.freeze({
        ...usage,
        planning_work: 0,
        attempts: 1,
        transferred_bytes: '0',
        reserved_execution_bytes: '100',
      });
      const released = Object.freeze({
        ...usage,
        planning_work: 0,
        attempts: 0,
        transferred_bytes: '0',
      });
      const runChild = async (label, arguments_, timeoutMs, script) => {
        calls.push({label, arguments_, timeoutMs, script});
        if (label === 'retained-actql') {
          return Object.freeze({
            status: 'completed',
            executionMs: 10,
            warmMs: 7,
            coldMs: 12,
            cleanupMs: 1,
            processCycleMs: 13,
            acceptanceEligible: false,
            report: {
              status: 'completed',
              executionMs: 10,
              warmMs: 7,
              cleanupMs: 1,
              accounting,
              acquisitionEvidenceMetadata,
              usage,
            },
          });
        }
        return Object.freeze({
          status: 'diagnostic-completed',
          executionMs: 8,
          warmMs: 5,
          coldMs: 10,
          cleanupMs: 1,
          processCycleMs: 11,
          acceptanceEligible: false,
          report: {
            status: 'diagnostic-completed',
            executionMs: 8,
            warmMs: 5,
            cleanupMs: 1,
            accounting: {...accounting, nativeSemanticRows: 8},
            acquisitionEvidenceMetadata,
            retentionLedger: directRetention,
            executionLedger: directExecution,
            releasedRetentionLedger: released,
            releasedExecutionLedger: released,
            missing: [
              'matched process/cold timing boundaries',
              'guard parity',
            ],
          },
        });
      };
      const report = await runMatchedEquivalentPair({
        fixture,
        checkout,
        database,
        directory,
        index,
        runChild,
        inspectCheckout: async () => ({revision: 'fixed', dirty: false}),
      });
      assert.deepEqual(report.order, index === 0
        ? ['direct-duckdb-with-identical-obligations-and-independent-holding',
          'retained-actql']
        : ['retained-actql',
          'direct-duckdb-with-identical-obligations-and-independent-holding']);
      assert.deepEqual(calls.map(call => call.label), report.order);
      assert(calls.every(call => call.timeoutMs === 180000));
      assert(calls.every(call => call.script.startsWith(checkout)));
      assert(calls[0].script.endsWith(report.order[0] === 'retained-actql'
        ? 'retained-case.mjs'
        : 'equivalent-case.mjs'));
      assert.equal(report.status, 'diagnostic-completed');
      assert.equal(report.logicalAccountingEquivalent, true);
      assert.equal(report.acquisitionMetadataEquivalent, true);
      assert.equal(report.transferWorkAccountingEquivalent, true);
      assert.equal(report.acceptanceEligible, false);
      assert(report.missing.includes('guard parity'));
      assert(!report.missing.includes(
        'matched process/cold timing boundaries',
      ));
      assert.deepEqual(report.closed, [
        'matched process/cold timing boundaries',
        'matched warm timing boundary',
        'finite expression-demand and negative conformance',
        'acquisition evidence metadata parity',
        'transfer and logical-work accounting equivalence',
      ]);
      assert(report.missing.includes('equivalent-obligation admission'));
      assert.equal(report.provenance.processBoundary, 'fresh child per leg');
      assert.deepEqual(report.accountingComparison.nativeSemanticRows,
        {retained: 10, equivalent: 8, difference: 2});
      assert.deepEqual(report.accountingComparison.identityPasses,
        {retained: 4, equivalent: 4, difference: 0});
      assert.deepEqual(report.transferWorkComparison.attempts,
        {retained: 5, equivalent: 5});
      assert.deepEqual(report.transferWorkComparison.logical, {
        retainedWork: 55,
        equivalentWork: 55,
        retainedBytes: 72,
        equivalentBytes: 72,
        retainedNodes: 36,
        equivalentNodes: 36,
      });
    }
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('matched pair rejects source mutation between legs', async () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const directory = await mkdtemp(join(tmpdir(), 'actql-matched-pair-'));
  const database = join(directory, 'source.duckdb');
  await writeFile(database, 'immutable fixture');
  try {
    let calls = 0;
    await assert.rejects(runMatchedEquivalentPair({
      fixture,
      checkout,
      database,
      directory,
      index: 0,
      runChild: async label => {
        calls++;
        await writeFile(database, `mutated by ${label}`);
        return {status: 'failed', acceptanceEligible: false};
      },
      inspectCheckout: async () => ({revision: 'fixed', dirty: false}),
    }), /MatchedPairSourceChanged/);
    assert.equal(calls, 1);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
