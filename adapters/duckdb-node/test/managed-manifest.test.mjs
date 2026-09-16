import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rmdir, stat, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {DuckDBInstance} from '@duckdb/node-api';
import {createLocalRetainedStore} from '../../store-local/files.mjs';
import {consumePhysicalManifestFiles} from '../../store-local/managed-manifest.mjs';

const sha = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const quote = value => `'${value.replaceAll("'", "''")}'`;

test('native Parquet bytes retain order and duplicates through physical Store and manifest consumption', async () => {
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
          return observed.length;
        });
      assert.deepEqual(observed, expectedRows);
      assert.equal(report.rowCount, 3);
      assert.equal(report.integrityReadBytes, bytes.length);
    }
    assert.notEqual(body.cid, sha(JSON.stringify(expectedRows)));
    assert.equal(body.available(), true);
  } finally {
    connection.closeSync(); database.closeSync();
    store.close(); await store.cleanup();
    assert.equal(store.status().reservedBytes, 0);
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
