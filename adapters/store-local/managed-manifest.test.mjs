import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rmdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalRetainedStore} from './files.mjs';
import {snapshotPhysicalManifest, consumePhysicalManifestFiles} from './managed-manifest.mjs';

const sha = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const expected = Object.freeze({schema_contract_cid: sha('fixture-schema'),
  view_contract_cid: sha('fixture-ordered-view'), codec_contract_cid: sha('fixture-newline-codec')});
const limits = Object.freeze({maxChunks: 10, maxManifestBytes: 4096, maxReferencedBytes: 1000});
const manifest = chunks => ({version: 'actql-managed-physical-manifest/0.1', ...expected,
  row_count: chunks.reduce((n, c) => n + c.row_count, 0), chunks});
const chunk = body => ({cid: body.cid, byte_length: body.bytes, row_count: 1});
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])])) : value;

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-manifest-'));
  const store = await createLocalRetainedStore({parentDirectory: directory, capacityBytes: 100, maxFrameBytes: 4, ...options});
  t.after(async () => { store.close(); await store.cleanup(); await rmdir(directory); });
  const bodies = [];
  for (const text of ['α\n', 'b\n']) {
    const writer = store.reserve(10);
    await writer.start(); await writer.appendBytes(Buffer.from(text));
    bodies.push(await writer.sealPhysical());
  }
  return {store, bodies};
}

test('bounded snapshot hashes canonical metadata, preserves duplicates and detaches caller arrays', () => {
  const a = {cid: sha('a'), byte_length: 1, row_count: 1};
  const input = manifest([a, {...a, cid: sha('b')}, a]);
  const text = JSON.stringify(canonical(input));
  const accepted = snapshotPhysicalManifest(input, limits);
  assert.equal(accepted.cid, sha(text));
  assert.equal(accepted.bytes, Buffer.byteLength(text));
  assert.equal(accepted.referencedBytes, 3);
  assert.equal(snapshotPhysicalManifest(input, {...limits, maxManifestBytes: accepted.bytes}).cid, accepted.cid);
  assert.throws(() => snapshotPhysicalManifest(input, {...limits, maxManifestBytes: accepted.bytes - 1}), {code: 'PhysicalManifestLimit'});
  const reordered = manifest([input.chunks[1], a, a]);
  assert.notEqual(snapshotPhysicalManifest(reordered, limits).cid, accepted.cid);
  a.row_count = 99; input.chunks.length = 0;
  assert.equal(accepted.manifest.chunks.length, 3);
  assert.equal(accepted.manifest.chunks[0].row_count, 1);
  assert.ok(Object.isFrozen(accepted.manifest.chunks[0]));
});

test('snapshot rejects invalid shapes, counts, overflow and hostile metadata without invoking getters', () => {
  const a = {cid: sha('a'), byte_length: 1, row_count: 1};
  for (const input of [
    {...manifest([]), row_count: 1},
    {...manifest([a]), logical_result_cid: sha('logical')},
    manifest([{...a, byte_length: -1}]),
    manifest([{...a, row_count: 0.5}]),
    {...manifest([a]), codec_contract_cid: 'native'},
    {...manifest([]), chunks: new Array(1)},
    {...manifest([a]), chunks: [{...a, path: '/not-admitted'}]},
  ]) assert.throws(() => snapshotPhysicalManifest(input, limits));
  assert.throws(() => snapshotPhysicalManifest(manifest([a]), {...limits, maxChunks: 0}), {code: 'PhysicalManifestLimit'});
  assert.throws(() => snapshotPhysicalManifest(manifest([a]), {...limits, maxReferencedBytes: 0}), {code: 'PhysicalManifestLimit'});
  assert.throws(() => snapshotPhysicalManifest(manifest([]), {...limits, maxChunks: -1}), {code: 'InvalidPhysicalManifestLimits'});
  const overflow = {...manifest([]), chunks: [{...a, row_count: Number.MAX_SAFE_INTEGER}, a]};
  assert.throws(() => snapshotPhysicalManifest(overflow, limits), {code: 'PhysicalManifestCountOverflow'});
  let invoked = false;
  const hostile = manifest([]);
  Object.defineProperty(hostile, 'chunks', {enumerable: true, get() { invoked = true; return []; }});
  assert.throws(() => snapshotPhysicalManifest(hostile, limits), {code: 'InvalidPhysicalManifest'});
  assert.equal(invoked, false);
});

test('actual sealed physical chunks are consumed in occurrence order without logical row encoding', async t => {
  const {store, bodies: [a, b]} = await fixture(t);
  const input = manifest([chunk(a), chunk(b), chunk(a)]), seen = [], charged = [];
  const result = await consumePhysicalManifestFiles(store, input, [a, b, a], expected, limits,
    'owned-session', async (file, index) => {
      seen.push([index, await readFile(file.path, 'utf8')]); return 1;
    }, undefined, bytes => charged.push(bytes));
  assert.deepEqual(seen, [[0, 'α\n'], [1, 'b\n'], [2, 'α\n']]);
  assert.deepEqual(charged, [3, 2, 3]);
  assert.equal(result.integrityReadBytes, 8); assert.equal(result.rowCount, 3);
  assert.equal(store.status().reservedBytes, 5); // unique physical holdings, not occurrences
  assert.equal(result.manifestCid, snapshotPhysicalManifest(input, limits).cid);
  assert.equal(Object.hasOwn(result, 'logical_result_cid'), false);
  const next = b.delegateRead('next-consumer'); next.confirmStopped();
});

test('equal hashes, forged bodies and foreign interpretation do not authorize the read', async t => {
  const {store, bodies} = await fixture(t);
  const other = await fixture(t);
  const input = manifest([chunk(bodies[0])]);
  let calls = 0;
  const read = () => { calls++; return 1; };
  for (const body of [{...bodies[0]}, other.bodies[0]]) {
    await assert.rejects(consumePhysicalManifestFiles(store, input, [body], expected, limits, 'session', read), {code: 'ForeignPhysicalManifestHolding'});
  }
  await assert.rejects(consumePhysicalManifestFiles(store, input, [bodies[0]], {...expected, view_contract_cid: sha('other-view')}, limits, 'session', read), {code: 'ForeignPhysicalManifestInterpretation'});
  assert.equal(calls, 0);
  // Failure after acquiring an earlier chunk must return that borrow too.
  await assert.rejects(consumePhysicalManifestFiles(store,
    manifest([chunk(bodies[0]), chunk(other.bodies[1])]),
    [bodies[0], other.bodies[1]], expected, limits, 'session', read),
  {code: 'ForeignPhysicalManifestHolding'});
  const held = bodies[0].delegateRead('still-available'); held.confirmStopped();
});

test('decoded row mismatch and budget refusal preserve the original physical holding', async t => {
  const {store, bodies: [body]} = await fixture(t);
  const input = manifest([chunk(body)]);
  await assert.rejects(consumePhysicalManifestFiles(store, input, [body], expected, limits, 'session', () => 2), {code: 'PhysicalManifestDecodedCountMismatch'});
  const budget = Error('budget'); let calls = 0;
  await assert.rejects(consumePhysicalManifestFiles(store, input, [body], expected, limits, 'session', () => { calls++; return 1; }, undefined, () => { throw budget; }), error => error === budget);
  assert.equal(calls, 0); assert.equal(body.available(), true);
  const held = body.delegateRead('after-failure'); held.confirmStopped();
});

test('corruption before or during native access revokes the affected generation', async t => {
  for (const during of [false, true]) {
    const {store, bodies: [body]} = await fixture(t);
    const held = body.delegateRead('get-physical-path');
    const path = held.descriptor.path; held.confirmStopped();
    if (!during) await writeFile(path, 'x!\n');
    let calls = 0;
    await assert.rejects(consumePhysicalManifestFiles(store, manifest([chunk(body)]), [body], expected, limits,
      'session', async () => { calls++; await writeFile(path, 'x!\n'); return 1; }), {code: 'RetainedBodyChanged'});
    assert.equal(calls, during ? 1 : 0);
    assert.equal(body.available(), false);
  }
});

test('cancellation releases acquired borrows and does not revoke an otherwise valid source', async t => {
  const {store, bodies} = await fixture(t);
  const controller = new AbortController(), reason = Error('cancelled');
  let calls = 0;
  await assert.rejects(consumePhysicalManifestFiles(store, manifest(bodies.map(chunk)), bodies, expected, limits,
    'session', () => { calls++; controller.abort(reason); return 1; }, controller.signal), error => error === reason);
  assert.equal(calls, 1);
  for (const body of bodies) {
    assert.equal(body.available(), true);
    const held = body.delegateRead('next'); held.confirmStopped();
  }
});

test('later chunks are held before dispatch and reclamation waits for confirmed read termination', async t => {
  const {store, bodies} = await fixture(t);
  await assert.rejects(consumePhysicalManifestFiles(store, manifest(bodies.map(chunk)), bodies, expected, limits,
    'session', async () => {
      bodies[1].close();
      await store.cleanup();
      assert.equal(store.status().reservedBytes, 5);
      assert.equal(store.status().cleanupPending, true);
      return 1;
    }), {code: 'RetainedUnavailable'});
  await store.cleanup();
  assert.equal(store.status().reservedBytes, 3);
  assert.equal(bodies[0].available(), true);
});

test('empty result still requires an exact live Store and cancellation is checked', async t => {
  const {store} = await fixture(t);
  let calls = 0;
  const read = () => { calls++; return 0; };
  const result = await consumePhysicalManifestFiles(store, manifest([]), [], expected, limits, 'session', read);
  assert.equal(result.rowCount, 0); assert.equal(result.integrityReadBytes, 0); assert.equal(calls, 0);
  const cancelled = new AbortController(), reason = Error('cancelled-empty');
  cancelled.abort(reason);
  await assert.rejects(consumePhysicalManifestFiles(store, manifest([]), [], expected, limits,
    'session', read, cancelled.signal), error => error === reason);
  await assert.rejects(consumePhysicalManifestFiles({}, manifest([]), [], expected, limits, 'session', read), {code: 'ForeignPhysicalManifestHolding'});
  store.close();
  await assert.rejects(consumePhysicalManifestFiles(store, manifest([]), [], expected, limits, 'session', read), {code: 'ForeignPhysicalManifestHolding'});
});

test('two manifest consumers hold the same generation independently within reader capacity', {timeout: 3000}, async t => {
  const {store, bodies} = await fixture(t, {maxReadersPerBody: 2, maxReadBufferBytes: 10});
  const input = manifest(bodies.map(chunk));
  let release, bothEntered, entered = 0;
  const gate = new Promise(resolve => { release = resolve; });
  const ready = new Promise(resolve => { bothEntered = resolve; });
  const consume = session => consumePhysicalManifestFiles(store, input, bodies, expected, limits,
    session, async (_file, index) => {
      if (index === 0) {
        if (++entered === 2) bothEntered();
        await gate;
      }
      return 1;
    });
  const first = consume('first'), second = consume('second');
  try {
    await ready;
    assert.equal(store.status().activeReaders, 4);
    assert.equal(store.status().reservedReadBufferBytes, 10);
    release();
    const results = await Promise.all([first, second]);
    assert.deepEqual(results.map(value => value.rowCount), [2, 2]);
    assert.equal(results[0].manifestCid, results[1].manifestCid);
    assert.equal(store.status().activeReaders, 0);
    assert.equal(store.status().reservedReadBufferBytes, 0);
    assert.equal(store.status().reservedBytes, 5);
  } finally {
    release(); await Promise.allSettled([first, second]);
  }
});
