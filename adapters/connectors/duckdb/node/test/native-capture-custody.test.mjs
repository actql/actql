import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {authorizeLocalDatabase} from '../session.mjs';
import {runStrategyNativeHostQuery, runRetainedStrategyNativeHostQuery,
  nativeSourceIdentityMatches, issueNativeSourceEvidence} from '../host.mjs';
import {checked} from '../runtime-result.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {acquisitionOutcome} from '../../../../host-common/acquisition-outcome.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = {maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1};
const program = JSON.stringify({version: 'actql/0.1', id: 'native-custody',
  params: {minimum: {type: 'number', nullable: false}},
  stages: [{id: 'a', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > $minimum', as: 'filtered'}, {select: ['id'], as: 'captured'}],
    results: {r: {from: 'captured', fields: ['id']}}},
  {id: 'compute', inputs: {x: {result: {stage: 'a', result: 'r'}}},
    steps: [{filter: 'id > 2'}, {select: ['id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}}}],
  results: {r: {from: {stage: 'compute', result: 'r'}}}});

async function fixture(t) {
  for (const pkg of ['connectors/duckdb/host_node', 'connectors/duckdb/conformance', 'physical_strategy_example']) {
    execFileSync('moon', ['build', '--target', 'js', '--release', `src/${pkg}`],
      {cwd: root, stdio: ['ignore', 'ignore', 'pipe']});
  }
  const conformance = await import(pathToFileURL(join(root,
    '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
  const physical = await import(pathToFileURL(join(root,
    '_build/js/release/build/physical_strategy_example/physical_strategy_example.js')));
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const args = [JSON.parse(catalog[1]), catalog[2], ...await pinnedEngineContracts(root),
    ...await Promise.all(['actql-query-acquisition', 'actql-query-process-evidence', 'actql-query-two-receipt']
      .map(name => readFile(join(root, `spec/contracts/${name}.json`), 'utf8'))), program];
  await mkdir(join(root, '_build/duckdb-fixtures'), {recursive: true});
  const directory = await mkdtemp(join(root, '_build/duckdb-fixtures/native-custody-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'source.duckdb');
  const database = await DuckDBInstance.create(path);
  const connection = await database.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE); INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  } finally { connection.closeSync(); database.closeSync(); }
  const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
  const prepared = () => conformance.strategyFixtureAccounted(conformance.strategyFixtureCreate(...args));
  const ledger = (retained = 1000000000n) => checked(physical.applicationBoundedLedger({
    planning_work: 10000, attempts: 10, holdings: 10, transfer_bytes: 1000000n,
    retained_bytes: retained, execution_bytes: 536870912n,
  }));
  return {conformance, prepared, directory, grant, ledger,
    usage: physical.applicationLedgerUsage};
}

function noReservations(usage) {
  assert.equal(usage.reserved_transfer_bytes, 0n);
  assert.equal(usage.reserved_retention_bytes, 0n);
  assert.equal(usage.reserved_execution_bytes, 0n);
}

test('original NativePhysical holds each capture on one ledger through second acquisition failure', async t => {
  const f = await fixture(t);
  for (const mode of ['success', 'failure', 'cancel', 'budget', 'cleanup']) {
    await t.test(mode, async t => {
      const prepared = f.prepared();
      const setup = f.conformance.strategyFixtureAcquisition(prepared);
      const ledger = f.ledger(mode === 'budget' ? 200000000n : undefined);
      const first = await runStrategyNativeHostQuery(f.grant, setup, ledger, limits);
      const firstSource = first.source();
      const firstUsage = f.usage(ledger);
      assert(firstUsage.held_bytes > 0n);
      noReservations(firstUsage);
      let second, failure, mock;
      let allowClose = false;
      try {
        const controller = new AbortController();
        if (mode === 'cancel') controller.abort();
        if (mode === 'cleanup') {
          const original = DuckDBInstance.prototype.closeSync;
          mock = t.mock.method(DuckDBInstance.prototype, 'closeSync', function () {
            if (!allowClose) throw new Error('SecondNativeCloseFailed');
            return original.call(this);
          });
        }
        const run = runStrategyNativeHostQuery(f.grant, setup, ledger,
          mode === 'failure' || mode === 'cleanup' ? {...limits, maxRows: 1} : limits,
          controller.signal);
        if (mode === 'success') {
          second = await run;
          assert.notEqual(first.source(), second.source());
          assert.equal(first.source(), firstSource);
          assert.equal(f.usage(ledger).held_bytes,
            firstUsage.held_bytes + second.physicalCapacity.retentionBytes);
          const dag = first.openDAG(f.conformance.strategyFixtureGraph(prepared));
          // Equal rows and even the same checked Query owner do not authorize
          // substituting another acquisition's original physical handle.
          assert.throws(() => second.retainTask(dag, 0));
          assert.throws(() => first.retainTask(dag, 0));
          assert.throws(() => second.retainTask(dag, 1));
          second.close();
          assert.equal(f.usage(ledger).held_bytes, firstUsage.held_bytes);
        } else {
          await assert.rejects(run, error => { failure = error; return true; });
          assert.equal(f.usage(ledger).held_bytes, firstUsage.held_bytes);
          assert.equal(first.source(), firstSource);
          if (mode === 'cleanup') {
            const outcome = acquisitionOutcome(failure);
            assert.equal(outcome.outcome, 'unknown');
            assert.equal(outcome.recovery.cleanupPending(), true);
            const pending = f.usage(ledger);
            const primary = failure.primaryFailure;
            assert(primary, 'the acquisition failure survives cleanup wrapping');
            assert(pending.reserved_execution_bytes > 0n);
            allowClose = true;
            await outcome.recovery.close();
            assert.equal(await outcome.recovery.cleanup(), true);
            assert.equal(await outcome.recovery.cleanup(), true);
            assert.equal(outcome.recovery.cleanupPending(), false);
            assert.equal(failure.primaryFailure, primary);
            assert.equal(f.usage(ledger).attempts, pending.attempts);
            assert.equal(f.usage(ledger).transferred_bytes, pending.transferred_bytes);
            assert.equal(f.usage(ledger).held_bytes, firstUsage.held_bytes);
          }
        }
        noReservations(f.usage(ledger));
      } finally {
        allowClose = true;
        mock?.mock.restore();
        await failure?.cleanupHandle?.retry();
        second?.close();
        first.close();
      }
      const final = f.usage(ledger);
      assert.equal(final.held_bytes, 0n);
      noReservations(final);
      first.close(); second?.close();
      assert.deepEqual(f.usage(ledger), final);
      assert.throws(() => first.source(), {code: 'IssuerClosed'});
      assert.equal(nativeSourceIdentityMatches(first, undefined), false);
      await assert.rejects(issueNativeSourceEvidence(first, {}), {code: 'IssuerClosed'});
      assert.equal(f.conformance.strategyFixtureOpen(prepared, firstSource), false);
    });
  }
});

test('adopted source custody requires issuer close and exact retained inode cleanup', async t => {
  const f = await fixture(t);
  for (const retained of [false, true]) {
    const prepared = f.prepared();
    const ledger = f.conformance.strategyFixtureLedger(prepared);
    const parentDirectory = await mkdtemp(join(f.directory, 'retained-'));
    const capture = retained
      ? await runRetainedStrategyNativeHostQuery(f.grant,
        f.conformance.strategyFixtureAcquisition(prepared), ledger, limits, {
          parentDirectory, maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000},
        })
      : await runStrategyNativeHostQuery(f.grant,
        f.conformance.strategyFixtureAcquisition(prepared), ledger, limits);
    const source = capture.source();
    const held = f.usage(ledger).held_bytes;
    assert(held > 0n);
    const dag = capture.openDAG(f.conformance.strategyFixtureGraph(prepared));
    assert.equal(f.conformance.strategyFixtureAttach(prepared, dag), true);
    f.conformance.strategyFixtureCloseOutput(prepared, 0);
    assert.equal(f.usage(ledger).held_bytes, held,
      'DAG close must not free an allocation still exposed by its source issuer');
    assert.equal(capture.source(), source);
    let path, moved;
    if (retained) {
      const directory = join(parentDirectory, (await readdir(parentDirectory))[0]);
      path = join(directory, (await readdir(directory))[0]);
      moved = `${path}.original`;
      await rename(path, moved);
      await writeFile(path, '[]');
    }
    try {
      capture.close();
      if (retained) {
        assert.equal(capture.cleanupHandle.status().pending, true);
        await assert.rejects(capture.cleanupHandle.retry());
        assert.equal(f.usage(ledger).held_bytes, held);
        const pending = f.usage(ledger);
        const cleanupOwner = capture.cleanupHandle;
        assert.throws(() => capture.source(), {code: 'IssuerClosed'});
        await assert.rejects(issueNativeSourceEvidence(capture, {}), {code: 'IssuerClosed'});
        await rm(path);
        await rename(moved, path);
        moved = undefined;
        await cleanupOwner.retry();
        await cleanupOwner.retry();
        assert.equal(capture.cleanupHandle, cleanupOwner);
        assert.equal(f.usage(ledger).attempts, pending.attempts);
        assert.equal(f.usage(ledger).transferred_bytes, pending.transferred_bytes);
        assert.equal(capture.cleanupHandle.status().pending, false);
      }
      assert.equal(f.usage(ledger).held_bytes, 0n);
      noReservations(f.usage(ledger));
      const final = f.usage(ledger);
      capture.close();
      await capture.cleanupHandle?.retry();
      assert.deepEqual(f.usage(ledger), final);
      assert.throws(() => capture.source(), {code: 'IssuerClosed'});
    } finally {
      if (moved) { await rm(path, {force: true}); await rename(moved, path); }
      capture.close();
      await capture.cleanupHandle?.retry();
    }
  }
});
