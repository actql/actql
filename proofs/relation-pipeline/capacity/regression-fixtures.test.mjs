import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { gunzipSync } from 'node:zlib';
import { retainCapacityRegressionFixture } from './regression-fixtures.mjs';

// Small transport/lifetime controls only. Real target, source/digest, byte,
// edge, shrink and compiler validation still run in the original audit.
const fixture = t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-capacity-regression-fixture-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return name => join(directory, `${name}.json`);
};

test('every archived substitution retains exact complete bytes without accumulated plain reports', t => {
  const path = fixture(t);
  const source = { dictionary: 'original Source bytes\n'.repeat(4096) };
  const original = { source, targets: ['js', 'wasm', 'native'], negative: null };
  const before = structuredClone(original);
  const archives = [];
  for (const negative of ['healthy', 'js', 'wasm', 'bytes', 'edge', 'history', 'compiler',
    'core-js', 'core-wasm', 'custody-js', 'custody-wasm']) {
    const report = { ...original, negative };
    const retained = retainCapacityRegressionFixture(path(negative), report);
    const bytes = Buffer.from(JSON.stringify(report) + '\n');
    assert.deepEqual(gunzipSync(readFileSync(retained.archivePath)), bytes);
    assert.equal(retained.bytes, bytes.length);
    assert.equal(retained.compressedBytes, readFileSync(retained.archivePath).length);
    archives.push(retained);
    retained.withUncompressed(actual => {
      assert.deepEqual(readFileSync(actual), bytes);
      for (const other of archives.slice(0, -1)) {
        assert.equal(existsSync(other.archivePath.slice(0, -3)), false);
      }
    });
    assert.equal(existsSync(path(negative)), false);
  }
  assert.deepEqual(original, before);
  for (const archive of archives) assert(existsSync(archive.archivePath));
});

test('actual child consumes the same full plain fixture while its compressed original stays intact', t => {
  const path = fixture(t)('healthy');
  const report = { source: { digest: 'original' }, targets: ['js', 'wasm', 'native'] };
  const retained = retainCapacityRegressionFixture(path, report);
  const before = readFileSync(retained.archivePath);
  const result = retained.withUncompressed(actual => spawnSync(process.execPath,
    ['--input-type=module', '-e', 'import{readFileSync}from"node:fs";process.stdout.write(readFileSync(process.argv[1]));', actual],
    { encoding: 'utf8', timeout: 10000 }));
  assert.ifError(result.error);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, JSON.stringify(report) + '\n');
  assert.equal(existsSync(path), false);
  assert.deepEqual(readFileSync(retained.archivePath), before);
});

test('failed validation keeps its exact original failure and archive while retiring only the temporary copy', t => {
  const path = fixture(t)('negative');
  const retained = retainCapacityRegressionFixture(path, { complete: false });
  const before = readFileSync(retained.archivePath);
  const failure = new Error('OriginalSemanticRefusal');
  assert.throws(() => retained.withUncompressed(() => { throw failure; }), error => error === failure);
  assert.equal(existsSync(path), false);
  assert.deepEqual(readFileSync(retained.archivePath), before);
  const result = retained.withUncompressed(actual => spawnSync(process.execPath,
    ['--input-type=module', '-e', 'import{readFileSync}from"node:fs";JSON.parse(readFileSync(process.argv[1]));process.exitCode=17;', actual],
    { encoding: 'utf8', timeout: 10000 }));
  assert.ifError(result.error);
  assert.equal(result.status, 17);
  assert.equal(existsSync(path), false);
  assert.deepEqual(readFileSync(retained.archivePath), before);
});

test('existing originals are never overwritten or removed when a temporary name is occupied', t => {
  const path = fixture(t)('occupied');
  const retained = retainCapacityRegressionFixture(path, { target: 'js' });
  writeFileSync(path, 'existing original');
  let consumed = false;
  assert.throws(() => retained.withUncompressed(() => { consumed = true; }), { code: 'EEXIST' });
  assert.equal(consumed, false);
  assert.equal(readFileSync(path, 'utf8'), 'existing original');
  const before = readFileSync(retained.archivePath);
  assert.throws(() => retainCapacityRegressionFixture(path, { target: 'foreign' }), { code: 'EEXIST' });
  assert.deepEqual(readFileSync(retained.archivePath), before);
});
