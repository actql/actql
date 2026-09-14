import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeHostQuery, runBroadHostQuery, runFixedHostCompute, runStrategyHostCompute } from '../host.mjs';
import { exerciseOwnedFixedTransport } from './owned-fixed-transport.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

test('standard native and broad Node Hosts own verification through real capture and consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], { cwd: root });
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
  const publicApi = await readFile(join(root, 'src/query_planning/pkg.generated.mbti'), 'utf8');
  assert.doesNotMatch(publicApi, /pub fn duckdb_broad_attempt_output\(/);
  assert.match(publicApi, /pub fn duckdb_broad_attempt_row_count\(/);
  // Caller-controlled transport options cannot install semantic verification,
  // replacement SQL or another MoonBit runtime into either standard entry.
  const forbidden = () => assert.fail('standard Host used caller replacement');
  const suppliedLimits = { ...limits, verifier: forbidden, verify: forbidden,
    runtime: { nativeHostOpen: forbidden, broadHostOpen: forbidden }, sql: forbidden };
  // Independent fixed setup stays in conformance. The product entry loads only
  // duckdb_host_node and cannot receive these test functions as its verifier.
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const source = await readFile(join(root, 'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
  const contracts = [...source.matchAll(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/g)].map(match => JSON.parse(match[1]));
  const args = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'), 'utf8')];
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'standard-host-'));
  try {
    for (const kind of ['valid', 'empty', 'invalid-unused']) {
      const path = join(directory, `${kind}.duckdb`);
      const db = await DuckDBInstance.create(path);
      const connection = await db.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
        if (kind !== 'empty') await connection.run(kind === 'invalid-unused'
          ? "INSERT INTO records VALUES (3,30),(1,'Infinity'::DOUBLE)"
          : 'INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      } finally { connection.closeSync(); db.closeSync(); }
      const grant = await authorizeLocalDatabase(path);
      for (const strategy of ['native', 'broad']) {
        const native = strategy === 'native';
        const create = count => native ? fixture.issuedNativeCreate(...args, count, () => true)
          : fixture.issuedBroadCreate(...args.slice(0, -1), count, () => true);
        const configure = native ? fixture.issuedNativeConfiguration : fixture.issuedBroadConfiguration;
        const close = native ? fixture.issuedNativeClose : fixture.issuedBroadClose;
        const execute = native ? runNativeHostQuery : runBroadHostQuery;
        const prepared = create(100);
        const setup = configure(prepared);
        close(prepared); // unused test issuer is not the product issuer
        if (kind === 'invalid-unused') {
          await assert.rejects(execute(grant, setup, limits), error => {
            assert.equal(error.code, 'MoonBitHostFailure');
            assert(error.cause); // Preserve the typed admission failure, not a JS ABI error.
            return true;
          });
          continue;
        }
        const captured = await execute(grant, setup, suppliedLimits);
        const expected = kind === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
        const observation = JSON.parse(captured.document());
        assert.equal(observation.output.rows_cid, hash(expected));
        assert.equal(observation.output.row_count, expected.length);
        const materialize = () => native ? captured.output()
          : captured.bindInput(fixture.issuedBroadConsumer(prepared), 0);
        const consume = native ? fixture.issuedNativeConsumeOutput : fixture.issuedBroadConsumeInput;
        const output = materialize();
        let assertFixedUnavailable;
        if (native) {
          // Only our uniquely created fixture file is moved, then restored.
          // Compute must work even when the authorized source path is absent.
          const heldPath = `${path}.held`;
          await rename(path, heldPath);
          try {
            assertFixedUnavailable = await exerciseOwnedFixedTransport(
              fixture, prepared, output, contracts, limits, kind === 'empty' ? [] : [3, 3],
            );
          } finally { await rename(heldPath, path); }
        }
        if (expected.length) assert.equal(consume(prepared, output, 0), 'null');
        assert.equal(consume(prepared, output, 100), hash(expected));
        const foreign = create(100);
        assert.equal(consume(foreign, output, 100), 'null');
        if (!native) assert.throws(() => captured.bindInput(fixture.issuedBroadConsumer(foreign), 0),
          { code: 'MoonBitHostFailure' });
        close(foreign);
        assert.equal(consume(prepared, materialize(), 100), hash(expected));
        if (native) {
          const fixed = fixture.ownedFixedCreate(prepared, output, ...contracts);
          const setup = fixture.ownedFixedConfiguration(fixed);
          const result = await runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 });
          const fixedOutput = result.output();
          const expectedFixed = hash(kind === 'empty' ? [] : [{ id: 3 }, { id: 3 }]);
          try {
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            captured.close();
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            await assert.rejects(runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 }));
          } finally { result.close(); }
          assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), 'null');
        }
        captured.close();
        assertFixedUnavailable?.();
        assert.throws(materialize, { code: 'IssuerClosed' });
        assert.equal(consume(prepared, output, 100), 'null');
        const cancelled = new AbortController();
        cancelled.abort();
        await assert.rejects(execute(grant, setup, limits, cancelled.signal));
        await assert.rejects(execute({}, setup, limits));
        const limited = create(0);
        if (expected.length) await assert.rejects(execute(grant,
          configure(limited), limits), { code: 'MoonBitHostFailure' });
        close(limited);
      }
      if (kind === 'valid') await exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

async function exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits) {
  const stage = (id, producer, filter) => ({ id, inputs: { x: { result: { stage: producer, result: 'r' } } },
    steps: [{ filter }, { select: ['id'], as: 'out' }],
    results: { r: { from: 'out', fields: ['id'] } } });
  const program = JSON.stringify({ version: 'actql/0.1', id: 'p',
    params: { minimum: { type: 'number', nullable: false } },
    stages: [{ id: 'a', inputs: { remote: { connector: 'crm/main', resource: 'r' } },
      steps: [{ filter: 'id > $minimum', as: 'filtered' }, { select: ['id'], as: 'captured' }],
      results: { r: { from: 'captured', fields: ['id'] } } },
    stage('compute_a', 'a', 'id > 2'), stage('compute_b', 'a', 'id > 0'), stage('compute_c', 'compute_a', 'id < 9')],
    results: { b: { from: { stage: 'compute_b', result: 'r' } }, c: { from: { stage: 'compute_c', result: 'r' } } } });
  async function replaceRows(sql) {
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try { await connection.run('DELETE FROM records'); await connection.run(sql); }
    finally { connection.closeSync(); db.closeSync(); }
  }
  for (const layout of [[true, true, true], [true, false, true], [false, true, false]]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const held = [];
    let transferred = 0n;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      // A and B must consume one immutable observation, not read this mutation.
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (let task = 1; task <= 3; task++) {
        if (task === 3) capture.close();
        if (layout[task - 1]) {
          const setup = fixture.strategyFixtureCompute(f, task);
          if (task === 2) {
            // An unstarted oversized reservation cannot erase already spent A
            // transfer or create a DB. Retrying this unstarted configuration is
            // explicit test orchestration, not automatic failed-attempt fallback.
            const attempts = fixture.strategyFixtureUsage(f, 3);
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxTransportBytes: 300001 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            // DB memory alone fits, but the bounded transport containers do not.
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxCells: 2000000 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          }
          const completed = await runStrategyHostCompute(setup, suppliedLimits, { maxRows: 100, maxCells: 1000 });
          transferred += BigInt(completed.usage.transportBytes);
          assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
          assert.equal(fixture.strategyFixtureUsage(f, 1), 0n);
          assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          held.push([task, completed]);
          // Each task really imports into a fresh DB, including DuckDB A -> C.
          assert.equal(completed.importedRows, task === 3 ? 2 : 3);
        } else assert.equal(fixture.strategyFixtureLocal(f, task), true);
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      held.find(([task]) => task === 1)?.[1].close();
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
      const last = held.find(([task]) => task === 3)?.[1];
      if (last) {
        last.close();
        assert.equal(fixture.strategyFixtureCanBind(f, 3), false);
      }
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred); // close never refunds transfer
    } finally {
      capture.close();
      for (const [, result] of held) result.close();
    }
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const cancelledFixture = fixture.strategyFixtureCreate(...args, program);
  const captured = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(cancelledFixture), suppliedLimits);
  let first;
  try {
    assert.equal(fixture.strategyFixtureOpen(cancelledFixture, captured.source()), true);
    first = await runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 1), suppliedLimits,
      { maxRows: 100, maxCells: 1000 });
    const cancellation = new AbortController();
    cancellation.abort();
    await assert.rejects(runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 2), suppliedLimits,
      { maxRows: 100, maxCells: 1000 }, cancellation.signal));
    assert.equal(fixture.strategyFixtureNext(cancelledFixture), -1);
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 1), hash([{ id: 3 }, { id: 3 }]));
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 2), 'null');
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 3), 'null');
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 0), BigInt(first.usage.transportBytes));
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 1), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 2), 0n);
  } finally { captured.close(); first?.close(); }
  for (const initialTransferCost of [1n, 20n]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost), true);
      const firstPlacement = initialTransferCost === 1n ? 'duckdb' : 'local';
      assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 6n : 30n);
      for (let task = 1; task <= 3; task++) {
        if (task === 2) {
          const spent = fixture.strategyFixtureUsage(f, 0);
          assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost === 1n ? 20n : 1n), true);
          assert.equal(fixture.strategyFixturePlacement(f, 1), firstPlacement);
          assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
          assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 20n : 4n);
        }
        if (task === 3) capture.close();
        const placement = fixture.strategyFixturePlacement(f, task);
        assert.equal(placement, task === 1 ? firstPlacement : firstPlacement === 'local' ? 'duckdb' : 'local');
        if (placement === 'duckdb') outputs.push(await runStrategyHostCompute(
          fixture.strategyFixtureCompute(f, task), suppliedLimits, { maxRows: 100, maxCells: 1000 }));
        else assert.equal(fixture.strategyFixtureLocal(f, task), true);
      }
      assert.equal(fixture.strategyFixtureCid(f, 2), hash([{ id: 3 }, { id: 2 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally { capture.close(); for (const output of outputs) output.close(); }
  }
}
