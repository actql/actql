import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rmdir, stat, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {exportPhysicalValue} from '../physical-values.mjs';
import {checked} from '../runtime-result.mjs';
import {createLocalRetainedStore} from '../../store-local/files.mjs';
import {consumePhysicalManifestFiles} from '../../store-local/managed-manifest.mjs';

const sha = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const quote = value => `'${value.replaceAll("'", "''")}'`;
const root = fileURLToPath(new URL('../../..', import.meta.url));
let fixturePromise;
function managedFixture() {
  return fixturePromise ??= (async () => {
    await promisify(execFile)('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], {cwd: root});
    await promisify(execFile)('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/host_node'], {cwd: root});
    const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
    const runtime = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/host_node/host_node.js')));
    return {fixture, runtime};
  })();
}
const managedFields = JSON.stringify([['id', 'DOUBLE', null, null], ['label', 'VARCHAR', null, null]]);
const openManaged = ({fixture, runtime}) => checked(runtime.managedOutputOpen(
  fixture.managedFileValues(), managedFields, fixture.managedFilePhysicalLimits(),
  fixture.managedFileTransportLimits(), 100));
const managedColumns = row => JSON.stringify([
  [exportPhysicalValue(row.id, {id: 'DOUBLE'})], [row.label],
]);

test('native Parquet bytes retain order and duplicates through physical Store and manifest consumption', async () => {
  const modules = await managedFixture(), {runtime} = modules;
  const admitted = openManaged(modules);
  const directory = await mkdtemp(join(tmpdir(), 'actql-manifest-parquet-'));
  const store = await createLocalRetainedStore({parentDirectory: directory, capacityBytes: 1048576, maxFrameBytes: 4096});
  const database = await DuckDBInstance.create(':memory:');
  const connection = await database.connect();
  const output = join(directory, 'native.parquet');
  try {
    const writer = store.reserve(1048576);
    await writer.start();
    await connection.run(`COPY (
      SELECT ordinal, id::DOUBLE AS id, label::VARCHAR AS label
      FROM (VALUES (0,1,NULL),(1,2,'é'),(2,1,NULL)) AS t(ordinal,id,label)
      ORDER BY ordinal
    ) TO ${quote(output)} (FORMAT PARQUET)`);
    // One physical copy in this fixture, not a zero-copy/direct-output claim.
    // DuckDB COPY replaces an existing destination inode; the old delegated
    // writer intentionally cannot admit that as the same preopened holding.
    const bytes = await readFile(output);
    await writer.appendBytes(bytes);
    const body = await writer.sealPhysical();
    const expected = {schema_contract_cid: sha('fixture-number-nullable-text'),
      view_contract_cid: sha('fixture-ordinal-order-id-label'),
      codec_contract_cid: sha('fixture-parquet-with-ordinal')};
    const manifest = {version: 'actql-managed-physical-manifest/0.1', ...expected,
      row_count: 3, chunks: [{cid: body.cid, byte_length: body.bytes, row_count: 3}]};
    const expectedRows = [{id: 1, label: null}, {id: 2, label: 'é'}, {id: 1, label: null}];
    for (let consumer = 0; consumer < 2; consumer++) {
      let observed;
      const report = await consumePhysicalManifestFiles(store, manifest, [body], expected,
        {maxChunks: 1, maxManifestBytes: 4096, maxReferencedBytes: 1048576},
        `fixture-reader-${consumer}`, async file => {
          observed = (await connection.runAndReadAll(`SELECT id,label FROM read_parquet(${quote(file.path)}) ORDER BY ordinal`)).getRowObjects();
          if (consumer === 0) {
            for (const row of observed) checked(runtime.managedOutputAccept(admitted, 1, managedColumns(row)));
          }
          return observed.length;
        });
      assert.deepEqual(observed, expectedRows);
      assert.equal(report.rowCount, 3);
      assert.equal(report.integrityReadBytes, bytes.length);
      if (consumer === 0) {
        checked(runtime.managedOutputFinish(admitted));
        checked(runtime.managedOutputRetain(admitted, BigInt(body.bytes), () => body.available()));
      }
      assert.equal(runtime.managedOutputAvailable(admitted), true);
      assert.deepEqual(checked(runtime.managedOutputMeasurements(admitted)), [3, 9, 15, 6]);
    }
    assert.notEqual(body.cid, sha(JSON.stringify(expectedRows)));
    assert.equal(body.available(), true);
    runtime.managedOutputCancel(admitted);
    assert.equal(runtime.managedOutputAvailable(admitted), false);
    // Revocation does not pretend physical cleanup has completed.
    assert.equal(body.available(), true);
  } finally {
    connection.closeSync(); database.closeSync();
    store.close(); await store.cleanup();
    assert.equal(runtime.managedOutputAvailable(admitted), false);
    assert.equal(store.status().reservedBytes, 0);
    await unlink(output).catch(error => { if (error.code !== 'ENOENT') throw error; });
    await rmdir(directory);
  }
});

test('managed Node transport rejection is terminal and cannot be followed by retention', async () => {
  const modules = await managedFixture(), {runtime} = modules;
  for (const frame of ['not-json', '[["3ff0000000000000"],', ' '.repeat(10001)]) {
    const admitted = openManaged(modules);
    assert.throws(() => checked(runtime.managedOutputAccept(admitted, 1, frame)));
    assert.throws(() => checked(runtime.managedOutputAccept(admitted, 1, managedColumns({id: 1, label: null}))));
    assert.throws(() => checked(runtime.managedOutputFinish(admitted)));
    assert.throws(() => checked(runtime.managedOutputRetain(admitted, 1n, () => true)));
    assert.equal(runtime.managedOutputAvailable(admitted), false);
  }
});

test('value-only managed holding cannot masquerade as selected Compute execution', async () => {
  const modules = await managedFixture(), {runtime} = modules;
  const admitted = openManaged(modules);
  checked(runtime.managedOutputFinish(admitted));
  checked(runtime.managedOutputRetain(admitted, 0n, () => true));
  assert.equal(runtime.managedOutputAvailable(admitted), true);
  assert.equal(runtime.managedOutputComputeVerified(admitted), false);
  assert.throws(() => checked(runtime.managedOutputVerifyCompute(admitted)));
  assert.equal(runtime.managedOutputAvailable(admitted), false);
});

test('real Parquet invalid later value and cancelled reception cannot issue retained value evidence', async () => {
  const modules = await managedFixture(), {runtime} = modules;
  const database = await DuckDBInstance.create(':memory:');
  const connection = await database.connect();
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-invalid-'));
  const output = join(directory, 'invalid.parquet');
  try {
    await connection.run(`COPY (SELECT ordinal, id, NULL::VARCHAR AS label
      FROM (VALUES (0,1::DOUBLE),(1,'Infinity'::DOUBLE)) AS t(ordinal,id)
      ORDER BY ordinal) TO ${quote(output)} (FORMAT PARQUET)`);
    const rows = (await connection.runAndReadAll(`SELECT id,label FROM read_parquet(${quote(output)}) ORDER BY ordinal`)).getRowObjects();
    for (const cancel of [false, true]) {
      const admitted = openManaged(modules);
      checked(runtime.managedOutputAccept(admitted, 1, managedColumns(rows[0])));
      if (cancel) runtime.managedOutputCancel(admitted);
      assert.throws(() => checked(runtime.managedOutputAccept(admitted, 1, managedColumns(rows[1]))));
      assert.throws(() => checked(runtime.managedOutputFinish(admitted)));
      assert.throws(() => checked(runtime.managedOutputRetain(admitted, 1n, () => true)));
      assert.equal(runtime.managedOutputAvailable(admitted), false);
    }
  } finally {
    connection.closeSync(); database.closeSync();
    await unlink(output).catch(error => { if (error.code !== 'ENOENT') throw error; });
    await rmdir(directory);
  }
});

test('native COPY inode replacement is rejected rather than weakening delegated holding identity', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-copy-inode-'));
  const store = await createLocalRetainedStore({parentDirectory: directory, capacityBytes: 1048576, maxFrameBytes: 4096});
  const database = await DuckDBInstance.create(':memory:');
  const connection = await database.connect();
  let output, generated;
  try {
    const writer = store.reserve(1048576);
    await writer.start();
    const delegation = writer.delegate('fixture-native-writer');
    output = delegation.path;
    await connection.run(`COPY (SELECT 1 AS id) TO ${quote(output)} (FORMAT PARQUET)`);
    generated = await stat(output);
    assert.notEqual(generated.ino, delegation.inode);
    const bytes = await readFile(output);
    await assert.rejects(writer.finishDelegated({version: delegation.version,
      session: delegation.session, token: delegation.token, bytes: bytes.length, cid: sha(bytes)}), {code: 'StoreIdentityMismatch'});
  } finally {
    connection.closeSync(); database.closeSync();
    // This fixture created the replacement. Remove only that observed inode;
    // the Store itself correctly refuses to unlink an unowned replacement.
    if (generated) {
      const current = await stat(output);
      assert.equal(current.ino, generated.ino); assert.equal(current.dev, generated.dev);
      await unlink(output);
    }
    store.close(); await store.cleanup(); await rmdir(directory);
  }
});
