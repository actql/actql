import test from 'node:test';
import assert from 'node:assert/strict';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeAcquisition } from '../native-acquisition.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };

function portFor(moon, state = moon.create()) {
  const ports = new Map();
  const events = [];
  let readView;
  let metadataRows = 0;
  let metadataColumns = [[]];
  const owns = view => { if (readView) assert.equal(view, readView); else readView = view; };
  const requireAccepted = (accepted, phase) => {
    if (!accepted) throw new Error(`MoonBit rejected ${phase}`);
  };
  const port = {
    metadataSql: () => moon.sql(state, 0),
    metadataParameters: () => [0, 1].map(index => JSON.parse(moon.parameter(state, 0, index))),
    acceptMetadata(chunk, view) {
      owns(view); metadataRows += chunk.rowCount;
      metadataColumns = chunk.columns;
    },
    finishMetadata(fields, view) {
      owns(view);
      requireAccepted(moon.metadata(state, metadataRows, JSON.stringify(fields), JSON.stringify(metadataColumns)), 'metadata');
    },
    validationSql: () => moon.sql(state, 1),
    nativeSql: () => { events.push('native'); return moon.sql(state, 2); },
    nativeParameters: () => [JSON.parse(moon.parameter(state, 1, 0))],
    beginReceipt(role, fields, view) {
      owns(view); ports.set(role, moon.begin(state, role === 'validation_scan' ? 0 : 1, JSON.stringify(fields)));
    },
    acceptChunk(role, chunk, view) {
      owns(view); events.push(role);
      requireAccepted(moon.accept(state, ports.get(role), chunk.rowCount, JSON.stringify(chunk.columns)), role);
    },
    finishReceipt(role, view) {
      owns(view); requireAccepted(moon.finish(state, ports.get(role)), `finish ${role}`);
    },
    abort(_error, view) { owns(view); moon.cancel(state); events.push('abort'); },
  };
  return { state, port, events };
}

test('real Node callbacks use MoonBit admission before native filtering, including discarded invalid values', async () => {
  await promisify(execFile)('moon', ['build', '--target', 'js', 'src/duckdb_conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/debug/build/duckdb_conformance/duckdb_conformance.js')));
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'moon-receiving-'));
  try {
    const cases = [
      ['valid', 'CREATE TABLE records(id DOUBLE, amount DOUBLE)', 'INSERT INTO records VALUES (3,30),(1,NULL),(2,20)', true],
      ['empty', 'CREATE TABLE records(id DOUBLE, amount DOUBLE)', undefined, true],
      ['unused-invalid', 'CREATE TABLE records(id DOUBLE, amount DOUBLE)', "INSERT INTO records VALUES (3,30),(1,'Infinity'::DOUBLE)", false],
      ['null-id', 'CREATE TABLE records(id DOUBLE, amount DOUBLE)', 'INSERT INTO records VALUES (NULL,30)', false],
      ['integer-loss', 'CREATE TABLE records(id BIGINT, amount DOUBLE)', 'INSERT INTO records VALUES (9223372036854775807,30)', false],
      ['view', 'CREATE VIEW records AS SELECT 3::DOUBLE AS id, 30::DOUBLE AS amount', undefined, false],
    ];
    for (const [name, schema, insert, succeeds] of cases) {
      const path = join(directory, `${name}.duckdb`);
      const db = await DuckDBInstance.create(path);
      const connection = await db.connect();
      try { await connection.run(schema); if (insert) await connection.run(insert); }
      finally { connection.closeSync(); db.closeSync(); }
      const received = portFor(moon);
      const run = runNativeAcquisition(await authorizeLocalDatabase(path), received.port, limits);
      if (succeeds) {
        await run;
        assert.equal(moon.ready(received.state), true, name);
        assert(received.events.includes('native'));
        // Fixed canonical row preimages, not reconstructed from returned values.
        const preimages = name === 'empty' ? ['[]', '[]'] : [
          '[{"amount":30,"id":3},{"amount":null,"id":1},{"amount":20,"id":2}]',
          '[{"id":3},{"id":2}]',
        ];
        const digests = JSON.parse(moon.receiptIdentities(received.state));
        for (let role = 0; role < 2; role++) {
          assert.equal(digests[role][0], `sha256:${createHash('sha256').update(preimages[role]).digest('hex')}`);
          assert.equal(digests[role][1], Buffer.byteLength(preimages[role]));
          assert.equal(digests[role][2], name === 'empty' ? 1 : [10, 5][role]);
          assert.equal(digests[role][3], name === 'empty' ? 0 : [3, 2][role]);
        }
      } else {
        await assert.rejects(run, /MoonBit rejected/, name);
        assert.equal(moon.ready(received.state), false, name);
        assert(!received.events.includes('native'), name);
        assert.equal(received.events.at(-1), 'abort');
        assert.equal(moon.receiptIdentities(received.state), 'null');
      }
    }
    const validGrant = await authorizeLocalDatabase(join(directory, 'valid.duckdb'));
    for (const [valueBytes, outputRows, nodes, nativeStarted] of [
      [3, 100, 1000, false], // Discarded row's unused NULL needs four canonical bytes.
      [10000, 1, 1000, true], // Two native rows exceed the logical output ceiling.
      [10000, 100, 6, true], // Scan consumes every measurement node; native has none left.
    ]) {
      const received = portFor(moon, moon.createGuarded(valueBytes, outputRows, nodes));
      await assert.rejects(runNativeAcquisition(validGrant, received.port, limits), /MoonBit rejected finish/);
      assert.equal(received.events.includes('native'), nativeStarted);
      assert.equal(received.events.at(-1), 'abort');
      assert.equal(moon.ready(received.state), false);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
