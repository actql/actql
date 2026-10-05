// Same checked 100-row benchmark and ledger limits, using the existing bounded
// example preparation. The public Client's separate fixed-100 counterexample
// remains unchanged. Broad must complete its original Local residual.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import * as app from '../../_build/js/release/build/physical_strategy_example/physical_strategy_example.js';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {retainedCase, workloads} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {exampleAuthorization} from '../../adapters/connectors/duckdb/node/examples/physical-strategy.mjs';
import {authorizeLocalDatabase} from '../../adapters/connectors/duckdb/node/session.mjs';
import {runStrategyNativeHostQuery, runBroadHostQuery} from '../../adapters/connectors/duckdb/node/host.mjs';
import {checked} from '../../adapters/host-common/runtime-result.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const text = path => readFile(join(root, path), 'utf8');

test('100 rows: bounded example planner selects Native/Broad with equivalent residual output',
  {timeout: 30000}, async () => {
    const fixture = retainedCase(workloads[0], 'narrow', 100);
    const directory = await mkdtemp(join(tmpdir(), 'actql-node-acquisition-bench-'));
    let capture;
    try {
      const database = join(directory, 'source.duckdb');
      await promisify(execFile)(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
      {cwd: root, timeout: fixture.limits.timeoutMs});
      const contracts = {
        adoptedText: await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
        query: await text('spec/contracts/actql-query-acquisition.json'),
        evidence: await text('spec/contracts/actql-query-process-evidence.json'),
        receipts: await text('spec/contracts/actql-query-two-receipt.json'),
      };
      const config = managedCaseConfiguration(fixture, contracts, database, directory);
      const input = config.input;
      const adopted = JSON.parse(contracts.adoptedText);
      const preparationStarted = performance.now();
      const prepared = checked(app.prepareApplicationWithData(
        input.programText, input.environmentText, input.environmentCid,
        input.parameterText, JSON.stringify(adopted.registry),
        JSON.stringify(adopted.values), JSON.stringify(adopted.fragment),
        contracts.query, contracts.evidence, contracts.receipts,
        'main', 'records', input.dataProfile));
      const preparationMs = performance.now() - preparationStarted;
      const select = priority => checked(app.applicationSelectAcquisition(
        prepared, contracts.query, contracts.evidence, contracts.receipts, priority));
      const describe = selected => JSON.parse(app.applicationAcquisitionSelectionDocument(selected));
      const deferred = select([]);
      assert.equal(describe(deferred).status, 'deferred');
      assert.equal(app.applicationAcquisitionSelectionNative(deferred), undefined);
      assert.equal(app.applicationAcquisitionSelectionBroad(deferred), undefined);
      // A malformed policy is rejected in pure preparation, without provider I/O.
      assert.throws(() => select([0, 0]));
      const authorization = await exampleAuthorization(input);
      const l = fixture.limits;
      const transportLimits = {
        maxRows: l.sourceRows + l.intermediateRows + 1,
        maxCells: (l.sourceRows + l.intermediateRows) * l.maxColumns + 1,
        maxTransportBytes: l.representationBytes * 3, maxSqlBytes: 10000,
        maxParameters: l.maxColumns * 128, maxColumns: l.maxColumns,
        memoryBytes: l.executionMemoryBytes / 2, threads: 1,
        maxChunkRows: 512, maxChunkBytes: Math.min(l.batchBytes, l.representationBytes),
      };
      const records = [];
      for (const [candidate, priority] of [['nativeQuery', [0, 1]], ['broadQuery', [1, 0]]]) {
        const selectionStarted = performance.now();
        const selected = select(priority);
        const selection = describe(selected);
        const selectionMs = performance.now() - selectionStarted;
        assert.equal(selection.status, 'selected');
        assert.equal(selection.selectedCandidate, candidate);
        assert.equal(selection.reason, 'HostPreferred');
        assert.deepEqual(selection.candidates.map(value => value.candidate), ['nativeQuery', 'broadQuery']);
        assert(selection.candidates.every(value => value.milliseconds === null));
        // The existing benchmark envelope is unchanged; no limit is raised to
        // turn the separate public Client policy into this experiment.
        assert.equal(selection.receiver.maxRows, l.sourceRows + l.intermediateRows);
        assert.equal(selection.receiver.maxOutputRows, l.sourceRows);
        const ledger = checked(app.applicationBoundedLedger(config.limits));
        const grant = await authorizeLocalDatabase(database, {authorization,
          connection: database, resource: 'main.records'});
        const readStarted = performance.now();
        capture = candidate === 'nativeQuery'
          ? await runStrategyNativeHostQuery(grant,
            app.applicationAcquisitionSelectionNative(selected), ledger, transportLimits)
          : await runBroadHostQuery(grant,
            app.applicationAcquisitionSelectionBroad(selected), transportLimits, undefined, moon, ledger);
        const executionMs = performance.now() - readStarted;
        const observation = JSON.parse(capture.document());
        assert.equal(observation.output.rows_cid, fixture.identity().rowsCid);
        assert.equal(observation.output.row_count, fixture.cardinalities.capture);
        const beforeClose = app.applicationLedgerUsage(ledger);
        assert.equal(beforeClose.attempts, 1);
        assert(beforeClose.held_bytes > 0n);
        assert(beforeClose.transferred_bytes > 0n);
        const closeStarted = performance.now();
        await capture.close();
        const cleanupMs = performance.now() - closeStarted;
        const afterClose = app.applicationLedgerUsage(ledger);
        for (const key of ['held_bytes', 'reserved_execution_bytes',
          'reserved_retention_bytes', 'reserved_transfer_bytes']) assert.equal(afterClose[key], 0n);
        assert.equal(afterClose.attempts, beforeClose.attempts);
        assert.equal(afterClose.transferred_bytes, beforeClose.transferred_bytes);
        await capture.close();
        assert.deepEqual(app.applicationLedgerUsage(ledger), afterClose);
        assert.throws(() => capture.source());
        records.push({host: 'node', candidate, priority, selection, observation,
          preparationMs, selectionMs, executionMs, cleanupMs, beforeClose, afterClose});
        capture = undefined;
      }
      assert.equal(records[0].selection.requirementCid, records[1].selection.requirementCid);
      assert.deepEqual(records[0].observation.output, records[1].observation.output);
      console.log('NODE_BOUNDED_ACQUISITION:' + JSON.stringify({
        caseId: fixture.id, condition: 'existing data-configured benchmark',
        ledgerLimits: config.limits, transportLimits, deferred: describe(deferred), records,
      }, (_, value) => typeof value === 'bigint' ? value.toString() : value));
    } finally {
      await capture?.close();
      await rm(directory, {recursive: true, force: true});
    }
  });
