import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeHostQuery } from '../host.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

test('standard Node Host owns verifier and product runtime through real capture and consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], { cwd: root });
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
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
      const prepared = fixture.issuedNativeCreate(...args, 100, () => false);
      const setup = fixture.issuedNativeConfiguration(prepared);
      fixture.issuedNativeClose(prepared); // unused test issuer is not the product issuer
      const grant = await authorizeLocalDatabase(path);
      if (kind === 'invalid-unused') {
        await assert.rejects(runNativeHostQuery(grant, setup, limits), error => {
          assert.equal(error.code, 'MoonBitHostFailure');
          assert(error.cause); // Preserve the typed admission failure, not a JS ABI error.
          return true;
        });
        continue;
      }
      const captured = await runNativeHostQuery(grant, setup, limits);
      const expected = kind === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
      const observation = JSON.parse(captured.document());
      assert.equal(observation.output.rows_cid, hash(expected));
      assert.equal(observation.output.row_count, expected.length);
      const output = captured.output();
      if (expected.length) assert.equal(fixture.issuedNativeConsumeOutput(prepared, output, 0), 'null');
      assert.equal(fixture.issuedNativeConsumeOutput(prepared, output, 100), hash(expected));
      captured.close();
      assert.throws(() => captured.output(), { code: 'IssuerClosed' });
      assert.equal(fixture.issuedNativeConsumeOutput(prepared, output, 100), 'null');
      const cancelled = new AbortController();
      cancelled.abort();
      await assert.rejects(runNativeHostQuery(grant, setup, limits, cancelled.signal));
      await assert.rejects(runNativeHostQuery({}, setup, limits));
      const limited = fixture.issuedNativeCreate(...args, 0, () => true);
      if (expected.length) await assert.rejects(runNativeHostQuery(grant,
        fixture.issuedNativeConfiguration(limited), limits), { code: 'MoonBitHostFailure' });
      fixture.issuedNativeClose(limited);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
