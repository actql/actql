import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import {DuckDBInstance} from '@duckdb/node-api';
import * as moon from '../../../../../_build/js/release/build/connectors/duckdb/host_node/host_node.js';
import * as fixture from '../../../../../_build/js/release/build/connectors/duckdb/conformance/conformance.js';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';
import {checked} from '../runtime-result.mjs';
import {finishManagedOutputReceipt} from '../managed-output-finish.mjs';
import {authorizeLocalDatabase} from '../session.mjs';
import {runNativeHostQuery} from '../host.mjs';
import {runFixedCompute, matchesFixedCompute, releaseFixedCompute} from '../fixed-compute.mjs';
import {runManagedColumnStrategyHostCompute} from '../managed-strategy-compute.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid} from '../managed-column-codec.mjs';
import {managedPhysicalRepresentation} from '../../../../store-local/managed-physical-representation.mjs';
import {registerManagedInput, withManagedInputFile} from '../../../../store-local/managed-representations.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import * as hostRuntime from '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openFundedClientPreparation} from '../../../../host-node/funded-client-preparation.fixture.mjs';
import {canonicalText} from '../../../../../scripts/check-canonical-json.mjs';

const root = fileURLToPath(new URL('../../../../../', import.meta.url));
// Acquisition transports one catalog row, 50 validation and 50 result rows.
// Both data receipts share the conformance configuration's 100-row allowance.
const limits = {maxRows: 101, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  maxChunkRows: 10, maxChunkBytes: 4096,
  memoryBytes: 128 * 1024 * 1024, threads: 1};
const fieldsFrame = fields => JSON.stringify(fields.map(({name, type}) =>
  [name, type.id, type.precision == null ? null : String(type.precision),
    type.scale == null ? null : String(type.scale)]));

test('installed DuckDB cleanup retires large admission without another native attempt', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-reclamation-'));
  let capture, run, output, body, store, result, downstream, consumer, cleanupFailure;
  let selectionCleanupFailure;
  let configured, attempt, port, consume;
  const expectedIds = Array.from({length: 50}, (_, index) => index + 3);
  const outputNames = ['id', 'n', 'n2', 'n3', 'n4'];
  try {
    const environment = canonicalText(JSON.parse(await readFile(join(root,
      'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8')));
    const args = [environment, JSON.parse(environment).evidence_bundle_cid,
      ...await pinnedEngineContracts(root),
      ...await Promise.all(['actql-query-acquisition.json',
        'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
        .map(name => readFile(join(root, 'spec/contracts', name), 'utf8')))];
    const program = {version: 'actql/0.1', id: 'managed-reclamation',
      params: {minimum: {type: 'number', nullable: false}},
      stages: [
        {id: 'a', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
          steps: [{filter: 'id > $minimum', as: 'filtered'},
            {select: ['id'], as: 'out'}],
          results: {r: {from: 'out', fields: ['id']}}},
        {id: 'seed', inputs: {x: {result: {stage: 'a', result: 'r'}}},
          steps: [{filter: 'id > 0'}, {select: ['id'], as: 'out'}],
          results: {r: {from: 'out', fields: ['id']}}},
        {id: 'grouped', inputs: {x: {result: {stage: 'seed', result: 'r'}}},
          steps: [{group: {by: ['id'], aggregates: Object.fromEntries(
            outputNames.slice(1).map(name => [name, {fn: 'count'}]))}, as: 'out'}],
          results: {r: {from: 'out', fields: outputNames}}},
        {id: 'consumer', inputs: {x: {result: {stage: 'grouped', result: 'r'}}},
          steps: [{filter: 'id > 0'}, {select: outputNames, as: 'out'}],
          results: {r: {from: 'out', fields: outputNames}}},
        {id: 'result', inputs: {x: {result: {stage: 'consumer', result: 'r'}}},
          steps: [{select: outputNames, as: 'out'}],
          results: {r: {from: 'out', fields: outputNames}}},
      ], results: {result: {from: {stage: 'result', result: 'r'}}}};
    const checkEnvironment = hostRuntime.clientProgramCheckEnvironment(
      environment, JSON.parse(environment).evidence_bundle_cid,
      false, false, true, false, false, false, false);
    assert.ok(checkEnvironment);
    const preparation = await openFundedClientPreparation({moon: hostRuntime,
      environment: checkEnvironment});
    try {
      await preparation.prepare({kind: 'aql', input: {text: JSON.stringify(program), format: 'json'},
        parameters: {minimum: 1}});
    } finally {
      await preparation.close();
    }
    configured = fixture.strategyFixtureCreate(...args, JSON.stringify(program));
    const path = join(directory, 'source.duckdb');
    const database = await DuckDBInstance.create(path);
    const connection = await database.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      await connection.run('INSERT INTO records SELECT i, i FROM range(3,53) t(i)');
    } finally { connection.closeSync(); database.closeSync(); }
    const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
    try {
      capture = await runNativeHostQuery(grant,
        fixture.strategyFixtureAcquisition(configured), limits);
    } catch (error) {
      throw new Error(`Source admission failed: ${inspect(error.cause, {depth: 6})}`,
        {cause: error});
    }
    assert.equal(fixture.strategyFixtureOpen(configured, capture.source()), true);
    const setup = fixture.strategyFixtureCompute(configured, 1);
    const profile = checked(fixture.managedFileProfile(await readFile(join(root,
      'spec/contracts/actql-managed-retained-execution.json'), 'utf8')));
    store = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 100000, maxFrameBytes: 4096, maxEntries: 1});
    const writer = store.reserve(100000);
    await writer.start();
    run = checked(moon.computeManagedRetainedStrategyHostOpen(setup,
      current => current === attempt && matchesFixedCompute(result, port, consume),
      100000n, 134217728n, 100000n, () => true, 100));
    attempt = moon.computeHostAttempt(run);
    const completion = checked(moon.computeHostManagedPrepare(run, profile, () => true));
    port = Object.freeze({
      importCount: () => moon.computeHostImportCount(run),
      rowCount: index => Number(checked(moon.computeHostCount(run, index, false))),
      columnCount: index => Number(checked(moon.computeHostCount(run, index, true))),
      createSql: index => checked(moon.computeHostSql(run, 0, index)),
      insertSql: index => checked(moon.computeHostSql(run, 1, index)),
      parameter: (index, row, column) => JSON.parse(checked(
        moon.computeHostParameter(run, row, column, false, index))),
      querySql: () => checked(moon.computeHostSql(run, 2, 0)),
      queryParameters: () => Array.from({length: moon.computeHostQueryParameterCount(run)},
        (_, index) => JSON.parse(checked(moon.computeHostParameter(run, 0, index, true, 0)))),
    });
    let rows = 0, schema, order;
    const observed = [];
    consume = async chunk => {
      if (!output) {
        schema = fieldsFrame(chunk.fields);
        output = checked(moon.computeHostManagedOutputBegin(run, schema));
        order = checked(moon.managedOutputStorageOrder(output));
        checked(moon.computeHostManagedOutputEnableIndex(output, 100));
      }
      checked(moon.managedOutputAccept(output, chunk.rowCount, JSON.stringify(chunk.columns)));
      await writer.appendBytes(encodeManagedColumnFrame(order.map(i => chunk.fields[i]),
        order.map(i => chunk.columns[i]), chunk.rowCount, rows));
      rows += chunk.rowCount;
      for (const value of chunk.columns[0]) {
        assert.match(value, /^[0-9a-f]{16}$/);
        observed.push(Buffer.from(value, 'hex').readDoubleBE());
      }
    };
    result = await runFixedCompute(port, limits, {maxRows: 100, maxCells: 1000}, consume);
    assert.deepEqual(observed, expectedIds);
    let finishPolls = 0, finishSteps = 0;
    await finishManagedOutputReceipt(quantum => {
      const poll = checked(moon.managedOutputAdvanceFinish(output, quantum));
      finishPolls++;
      finishSteps += poll._1;
      if (!poll._0) assert.equal(moon.managedOutputAvailable(output), false);
      return poll;
    });
    assert.ok(finishPolls > 1, 'selected Compute receipt must span Host yields');
    assert.ok(finishSteps > 64);
    body = await writer.sealPhysical();
    checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
    checked(moon.computeHostPhysicalSettle(run, true));
    checked(moon.managedOutputVerifyCompute(output));
    const completed = checked(moon.managedOutputCompleteStrategyCompute(output, completion));
    const material = moon.managedOutputMaterial(output);
    registerManagedInput(material, input => moon.managedInputMatchesMaterial(input, material),
      store, body, managedColumnCodecContractCid,
      managedPhysicalRepresentation(body, rows, managedColumnCodecContractCid,
        schema, order, moon).manifest);
    const request = fixture.strategyFixtureManagedRequest(configured, 2, completed);
    const configuration = fixture.strategyFixtureManagedConfiguration(
      configured, 2, request, profile, 100000n);
    downstream = await runManagedColumnStrategyHostCompute(configuration, material,
      managedColumnCodecContractCid, limits,
      {parentDirectory: directory, maxFrameBytes: 4096});
    assert.equal(downstream.diagnostics.outputValueAdmissionCells, 250);
    assert.equal(fixture.strategyFixtureNext(configured), 3);
    const reader = fixture.strategyFixtureManagedInput(configured, 3, downstream.completed);
    const actual = [];
    await withManagedInputFile(downstream.material, reader, managedColumnCodecContractCid,
      () => true, async file => {
        const frames = (await readFile(file.path, 'utf8')).trim().split('\n').map(JSON.parse);
        for (const frame of frames) for (let row = 0; row < frame.o.length; row++) {
          actual.push(Object.fromEntries(outputNames.map((name, column) =>
            [name, Number(frame[`c${column}`][row])])));
        }
      });
    assert.deepEqual(actual, expectedIds.map(id => ({id, n: 1, n2: 1, n3: 1, n4: 1})));
    // Execute the registered selection strategy as well as the computed group.
    // Its 50x5 occurrence metadata requires multiple 64-step Host polls.
    const selectedRequest = fixture.strategyFixtureManagedRequest(configured, 3, downstream.completed);
    const selectedConfiguration = fixture.strategyFixtureManagedConfiguration(
      configured, 3, selectedRequest, profile, 100000n);
    consumer = await runManagedColumnStrategyHostCompute(selectedConfiguration,
      downstream.material, managedColumnCodecContractCid, limits,
      {parentDirectory: directory, maxFrameBytes: 4096});
    assert.equal(consumer.diagnostics.outputValueAdmissionCells, 0);
    assert.equal(consumer.diagnostics.reusedMeasurementCells, 250);
    assert.equal(fixture.strategyFixtureNext(configured), 4);
    const finalReader = fixture.strategyFixtureManagedInput(configured, 4, consumer.completed);
    const selectedRows = [];
    await withManagedInputFile(consumer.material, finalReader, managedColumnCodecContractCid,
      () => true, async file => {
        const frames = (await readFile(file.path, 'utf8')).trim().split('\n').map(JSON.parse);
        for (const frame of frames) for (let row = 0; row < frame.o.length; row++) {
          selectedRows.push(Object.fromEntries(outputNames.map((name, column) =>
            [name, Number(frame[`c${column}`][row])])));
        }
      });
    assert.deepEqual(selectedRows, expectedIds.map(id => ({id, n: 1, n2: 1, n3: 1, n4: 1})));
    const selectedAttempts = fixture.strategyFixtureUsage(configured, 3);
    try { await consumer.close(); } catch (error) {
      selectionCleanupFailure = error;
      assert.equal(error.code, 'ManagedOutputCleanupPending');
      assert.equal(error.cleanupPending, true);
    }
    // Reused metadata can retire within close's initial slices. If private
    // guards remain, retain the existing handle and bounded retry contract.
    if (selectionCleanupFailure) {
      for (let poll = 0; poll < 7 && selectionCleanupFailure.cleanupHandle.status().pending; poll++) {
        await selectionCleanupFailure.cleanupHandle.retry();
        assert.equal(fixture.strategyFixtureUsage(configured, 3), selectedAttempts);
      }
      assert.equal(selectionCleanupFailure.cleanupHandle.status().pending, false);
    }
    assert.equal(fixture.strategyFixtureUsage(configured, 3), selectedAttempts);
    assert.equal(consumer.storageUsage().reservedBytes, 0);
    assert.equal(moon.managedCompletedAvailable(downstream.completed), true,
      'selected consumer cleanup must not retire its source');
    consumer = undefined;
    const attempts = fixture.strategyFixtureUsage(configured, 3);
    await assert.rejects(downstream.close(), error => {
      cleanupFailure = error;
      assert.equal(error.cleanupPending, true);
      return true;
    });
    assert.equal(downstream.storageUsage().reservedBytes, 0);
    assert.equal(cleanupFailure.cleanupHandle.status().pending, true,
      'physical release alone cannot discharge private admission roots');
    assert(fixture.strategyFixtureUsage(configured, 2) > 0n);
    // Each row owns two buffer containers and six reference-row containers.
    // Add 15 column counters and the buffer's terminal step: 416 entries.
    // Seven 64-entry passes cover this bound even before close's earlier slices.
    let pending = true;
    for (let poll = 0; poll < 7 && pending; poll++) {
      pending = (await cleanupFailure.cleanupHandle.retry()).pending;
      assert.equal(fixture.strategyFixtureUsage(configured, 3), attempts,
        'cleanup must not allocate another native attempt');
    }
    assert.equal(pending, false);
    assert.equal(fixture.strategyFixtureUsage(configured, 2), 0n);
    assert.equal(moon.managedCompletedAvailable(completed), true,
      'downstream retirement cannot revoke the retained source');
    assert.equal((await cleanupFailure.cleanupHandle.retry()).pending, false);
    assert.equal(fixture.strategyFixtureUsage(configured, 3), attempts);
  } finally {
    if (selectionCleanupFailure?.cleanupHandle) {
      for (let poll = 0; poll < 7 && selectionCleanupFailure.cleanupHandle.status().pending; poll++) {
        await selectionCleanupFailure.cleanupHandle.retry();
      }
      assert.equal(selectionCleanupFailure.cleanupHandle.status().pending, false,
        `preserve selected cleanup custody in ${directory}`);
    }
    if (cleanupFailure?.cleanupHandle) {
      for (let poll = 0; poll < 7 && cleanupFailure.cleanupHandle.status().pending; poll++) {
        await cleanupFailure.cleanupHandle.retry();
      }
      assert.equal(cleanupFailure.cleanupHandle.status().pending, false,
        `preserve pending cleanup custody in ${directory}`);
    }
    if (consumer && !selectionCleanupFailure) await consumer.close();
    if (downstream && !cleanupFailure) {
      try { await downstream.close(); } catch (error) {
        cleanupFailure = error;
        assert.equal(error.cleanupPending, true);
        for (let poll = 0; poll < 7 && error.cleanupHandle.status().pending; poll++) {
          await error.cleanupHandle.retry();
        }
        assert.equal(error.cleanupHandle.status().pending, false,
          `preserve source cleanup custody in ${directory}`);
      }
    }
    if (output) moon.managedOutputCancel(output);
    body?.close(); store?.close(); await store?.cleanup();
    if (run) {
      moon.computeHostClose(run);
      let released = false;
      for (let poll = 0; poll < 7 && !released; poll++) {
        released = checked(moon.computeHostCleanupRefresh(run));
      }
      assert.equal(released, true, 'source cleanup must confirm its own release');
      assert.equal(fixture.strategyFixtureUsage(configured, 1), 0n);
      assert.equal(fixture.strategyFixtureUsage(configured, 2), 0n);
      assert.equal(fixture.strategyFixtureUsage(configured, 4), 0n);
      assert.equal(fixture.strategyFixtureUsage(configured, 5), 0n);
    }
    if (store) {
      assert.equal(store.status().cleanupPending, false,
        `preserve pending Store custody in ${directory}`);
      assert.equal(store.status().reservedBytes, 0);
    }
    if (result) releaseFixedCompute(result);
    capture?.close(); await capture?.capture?.cleanupHandle?.retry();
    await rm(directory, {recursive: true, force: true});
  }
});
