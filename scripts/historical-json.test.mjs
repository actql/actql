import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {decodeSnapshot, packSnapshots, readArchive, readHistoricalJson} from './historical-json.mjs';
import {checkArchive, importSnapshots} from './historical-json-archive.mjs';

const path = 'portability/corpus/historical/pre-example-preimages.json';
const raw = value => `${JSON.stringify(value, null, 2)}\n`;
const pack = value => packSnapshots({[path]: raw(value)});
const sha = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

test('all migrated snapshots retain original bytes and canonical digests', () => {
  const archive = readArchive();
  assert.ok(checkArchive(archive) >= 15);
  for (const name of ['finite-math', 'number-extrema', 'pad-sides', 'split', 'unicode-scalars']) {
    for (const original of [`portability/corpus/historical/pre-${name}-contract-identities.json`, `portability/corpus/historical/pre-${name}-preimages.json`, `scripts/fixtures/pre-${name}-values-identities.json`]) {
      assert.ok(Object.hasOwn(archive.manifest.snapshots, original), original);
    }
  }
  for (const name of Object.keys(archive.manifest.snapshots)) {
    const value = readHistoricalJson(name);
    assert.equal(Buffer.byteLength(raw(value)), archive.manifest.snapshots[name].raw_bytes);
  }
});

test('literal tag lookalikes, JSON keys, Unicode and order round trip without collisions', () => {
  const value = JSON.parse('{"__proto__":{"polluted":true},"constructor":null,"2":"two","1":"one","z":["r","' + 'a'.repeat(64) + '"],"$dedup_sha256":"literal","unicode":"😀","surrogate":"\\ud800"}');
  assert.deepEqual(decodeSnapshot(pack(value), path), value);
  assert.equal({}.polluted, undefined);
});

test('shared subtree decoding yields independently mutable values', () => {
  const body = {text: 'x'.repeat(256)};
  const archive = pack([body, body]);
  assert.ok(Object.keys(archive.objects).length > 0);
  const decoded = decodeSnapshot(archive, path);
  decoded[0].text = 'changed';
  assert.equal(decoded[1].text, body.text);
  assert.deepEqual(decodeSnapshot(archive, path), [body, body]);
});

test('packing is deterministic regardless of input file enumeration order', () => {
  const other = 'scripts/fixtures/pre-example-values-identities.json';
  assert.deepEqual(packSnapshots({[path]: raw({x: 1}), [other]: raw({x: 2})}), packSnapshots({[other]: raw({x: 2}), [path]: raw({x: 1})}));
});

test('missing objects, invalid addresses and changed objects fail closed', () => {
  const archive = pack(['x'.repeat(256), 'x'.repeat(256)]);
  const key = Object.keys(archive.objects)[0];
  delete archive.objects[key];
  assert.throws(() => decodeSnapshot(archive, path), /reference/);
  archive.objects[key] = ['v', 'tampered'];
  assert.throws(() => decodeSnapshot(archive, path), /digest/);
  archive.manifest.snapshots[path].root = ['r', '../escape'];
  assert.throws(() => decodeSnapshot(archive, path), /reference/);
});

test('unknown tags, duplicate keys and invalid scalars fail closed', () => {
  for (const node of [['bad', null], ['o', [['a', ['v', 1]], ['a', ['v', 2]]]], ['v', {}], ['a', {}]]) {
    const archive = pack(null);
    archive.manifest.snapshots[path].root = node;
    assert.throws(() => decodeSnapshot(archive, path), /Historical JSON archive/);
  }
});

test('expanded visits, depth and pretty-byte limits apply before reconstruction', () => {
  const archive = pack({body: ['x'.repeat(256)]});
  assert.throws(() => decodeSnapshot(archive, path, {depth: 256, visits: 1, bytes: 32 * 1024 * 1024}), /limit/);
  assert.throws(() => decodeSnapshot(archive, path, {depth: 1, visits: 2_000_000, bytes: 32 * 1024 * 1024}), /limit/);
  assert.throws(() => decodeSnapshot(archive, path, {depth: 256, visits: 2_000_000, bytes: 10}), /receipt/);
});

test('root raw and canonical receipts are independently enforced', () => {
  for (const field of ['raw_sha256', 'canonical_sha256']) {
    const archive = pack({a: 1});
    archive.manifest.snapshots[path][field] = '0'.repeat(64);
    assert.throws(() => decodeSnapshot(archive, path), /digest/);
  }
});

test('append import preserves all previous receipts, roots and objects', () => {
  const previous = pack({a: 'x'.repeat(256)});
  const nextPath = 'scripts/fixtures/pre-next-values-identities.json';
  const next = importSnapshots(previous, {[nextPath]: raw({a: 'x'.repeat(256)})});
  assert.deepEqual(next.manifest.snapshots[path], previous.manifest.snapshots[path]);
  for (const [key, node] of Object.entries(previous.objects)) assert.deepEqual(next.objects[key], node);
  assert.throws(() => importSnapshots(previous, {[path]: raw({a: 2})}), /Already archived/);
  assert.throws(() => importSnapshots(previous, {'../escape': raw({})}), /Invalid snapshot path/);
});

test('unreachable object corruption is caught by full archive check', () => {
  const archive = pack(null);
  archive.objects[sha(['v', 'original'])] = ['v', 'changed'];
  assert.throws(() => checkArchive(archive), /digest/);
});


test('pretty expansion is bounded even when a corrupted receipt understates output', () => {
  let value = 'leaf';
  for (let i = 0; i < 30; i++) value = [value];
  const archive = pack(value);
  archive.manifest.snapshots[path].raw_bytes = 500;
  archive.manifest.snapshots[path].canonical_bytes = 100;
  assert.throws(() => decodeSnapshot(archive, path, {depth: 256, visits: 2_000_000, bytes: 500}), /expanded byte limit/);
});

test('full archive checking bounds stored nesting before hashing', () => {
  const archive = pack(null);
  let node = ['v', null];
  for (let i = 0; i < 1100; i++) node = ['a', [node]];
  archive.objects['0'.repeat(64)] = node;
  assert.throws(() => checkArchive(archive), /stored node limit/);
});
