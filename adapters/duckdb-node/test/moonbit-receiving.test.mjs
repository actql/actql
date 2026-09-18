import test from 'node:test';
import assert from 'node:assert/strict';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, rm, readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeAcquisition } from '../native-acquisition.mjs';
import { runBroadAcquisition } from '../broad-acquisition.mjs';
import { matchesSourceAcquisition, releaseSourceAcquisition } from '../source-acquisition.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

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

function broadPortFor(moon, nodes = 9) {
  const state = moon.broadCreate(nodes);
  let readView;
  let metadataRows = 0;
  const metadataColumns = [[]];
  const owns = view => { if (readView) assert.equal(view, readView); else readView = view; };
  const accepted = value => { if (!value) throw new Error('MoonBit rejected broad receipt'); };
  return { state, port: {
    metadataSql: () => moon.broadSql(state, true),
    metadataParameters: () => [0, 1].map(index => JSON.parse(moon.broadParameter(state, index))),
    acceptMetadata(chunk, view) {
      owns(view); metadataRows += chunk.rowCount;
      metadataColumns[0].push(...chunk.columns[0]);
    },
    finishMetadata(fields, view) {
      owns(view); accepted(moon.broadMetadata(state, metadataRows, JSON.stringify(fields), JSON.stringify(metadataColumns)));
    },
    scanSql: () => moon.broadSql(state, false),
    beginReceipt(fields, view) { owns(view); accepted(moon.broadBegin(state, JSON.stringify(fields))); },
    acceptChunk(chunk, view) {
      owns(view); assert.equal(moon.broadIdentity(state), 'null');
      accepted(moon.broadAccept(state, chunk.rowCount, JSON.stringify(chunk.columns)));
    },
    finishReceipt(view) { owns(view); accepted(moon.broadFinish(state)); return state; },
    abort(_error, view) { owns(view); moon.broadCancel(state); },
  } };
}

test('real Node callbacks use MoonBit admission before native filtering, including discarded invalid values', async () => {
  await promisify(execFile)('moon', ['build', '--target', 'js', 'src/duckdb_conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/debug/build/duckdb_conformance/duckdb_conformance.js')));
  // Reuse the engine's adopted fixed contract fixture, not an unadmitted newer
  // registry or expected values derived from execution output.
  const residualContracts = await pinnedEngineContracts(root);
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
      const broad = broadPortFor(moon);
      const broadGrant = await authorizeLocalDatabase(path);
      const broadRun = runBroadAcquisition(broadGrant, broad.port, limits);
      assert.equal(matchesSourceAcquisition(broadRun, broadGrant, broad.port, undefined), false);
      if (succeeds) {
        const result = await broadRun;
        assert.equal(matchesSourceAcquisition(result, broadGrant, broad.port, result.value.readView), true);
        assert.equal(result.value.accepted === broad.state, true);
        const preimage = name === 'empty' ? '[]' : '[{"amount":30,"id":3},{"amount":null,"id":1},{"amount":20,"id":2}]';
        assert.equal(moon.broadIdentity(broad.state), `sha256:${createHash('sha256').update(preimage).digest('hex')}`);
        const outputPreimage = name === 'empty' ? '[]' : '[{"id":3},{"id":2}]';
        const outputCid = `sha256:${createHash('sha256').update(outputPreimage).digest('hex')}`;
        if (name !== 'empty') assert.equal(moon.broadResidual(broad.state, ...residualContracts, 1), 'null');
        // A failed residual cannot publish output or consume the retained input.
        for (let retry = 0; retry < 2; retry++) {
          assert.equal(moon.broadResidual(broad.state, ...residualContracts, 100), outputCid);
        }
        assert.equal(matchesSourceAcquisition(result, broadGrant, broad.port, result.value.readView), true);
        releaseSourceAcquisition(result);
        assert.equal(matchesSourceAcquisition(result, broadGrant, broad.port, result.value.readView), false);
      } else {
        await assert.rejects(broadRun, /MoonBit rejected broad/);
        assert.equal(moon.broadIdentity(broad.state), 'null');
      }
      await assert.rejects(runBroadAcquisition(await authorizeLocalDatabase(path), broad.port, limits), /AttemptAlreadyStarted/);
      const received = portFor(moon);
      const run = runNativeAcquisition(await authorizeLocalDatabase(path), received.port, limits);
      if (succeeds) {
        await run;
        assert.equal(moon.ready(received.state), true, name);
        assert(received.events.includes('native'));
        assert.deepEqual(JSON.parse(moon.demandUsage(received.state)), name === 'empty'
          ? [0, 0, 0, 0, 0, 0, null]
          : [3, 3, 2, 1, 0, 13, 1]);
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
    const exhausted = broadPortFor(moon, 8);
    await assert.rejects(runBroadAcquisition(validGrant, exhausted.port, limits), /MoonBit rejected broad/);
    assert.equal(moon.broadIdentity(exhausted.state), 'null');
    for (const [valueBytes, outputRows, nodes, nativeStarted] of [
      [21, 100, 1000, false], // Discarded row's record with unused NULL needs 22 bytes.
      [10000, 1, 1000, true], // Two native rows exceed the logical output ceiling.
      [10000, 100, 9, true], // Three records + six scalars consume all measurement nodes.
    ]) {
      const received = portFor(moon, moon.createGuarded(valueBytes, outputRows, nodes));
      await assert.rejects(runNativeAcquisition(validGrant, received.port, limits), /MoonBit rejected finish/);
      assert.equal(received.events.includes('native'), nativeStarted);
      assert.equal(received.events.at(-1), 'abort');
      assert.equal(moon.ready(received.state), false);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
