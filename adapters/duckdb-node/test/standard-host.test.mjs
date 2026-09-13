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
import { runNativeHostQuery, runBroadHostQuery, runFixedHostCompute } from '../host.mjs';
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
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
