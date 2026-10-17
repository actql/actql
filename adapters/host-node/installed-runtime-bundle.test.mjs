import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {installedRuntimeBundleCid} from './source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {loadInstalledSource, publishInstalledSourceProfile} from './installed-source.mjs';
import {loadInstalledEffect, publishInstalledEffectProfile} from './installed-effect.mjs';

const expected = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
function reader(bytes, {step = Infinity, readFailure, closeFailure, closePending = false} = {}) {
  let offset = 0, failClose = true;
  const observed = {opens: 0, reads: 0, closes: 0, buffers: new Set(), total: 0};
  observed.releaseClose = () => {failClose = false;};
  observed.openFile = async (path, flags) => {
    assert.equal(path, '/runtime.js'); assert.equal(flags, 'r'); observed.opens++;
    return {
      async read(buffer, start, length, position) {
        observed.reads++; observed.buffers.add(buffer);
        assert.equal(start, 0); assert.equal(position, null);
        assert.equal(buffer.length, 64 * 1024); assert.equal(length, buffer.length);
        if (readFailure !== undefined && offset > 0) throw readFailure;
        const count = Math.min(step, length, bytes.length - offset);
        bytes.copy(buffer, start, offset, offset + count);
        offset += count; observed.total += count;
        return {bytesRead: count};
      },
      async close() {
        observed.closes++;
        if (failClose && closeFailure !== undefined) throw closeFailure;
        if (failClose && closePending) return false;
      },
    };
  };
  return observed;
}

for (const [name, bytes, step] of [
  ['empty', Buffer.alloc(0), Infinity],
  ['binary and partial reads', Buffer.from([0, 255, 128, 13, 10, 0, 195, 169]), 1],
  ['multiple chunks', Buffer.alloc(4 * 65536 + 19, 0xA7), 32771],
]) {
  test(`runtime hash preserves ${name} without accumulating input buffers`, async () => {
    const actual = reader(bytes, {step});
    assert.equal(await installedRuntimeBundleCid('/runtime.js', actual), expected(bytes));
    assert.equal(actual.opens, 1); assert.equal(actual.closes, 1);
    assert.equal(actual.buffers.size, 1); assert.equal(actual.total, bytes.length);
  });
}

test('each real selected runtime is reread after same-path byte replacement', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-runtime-hash-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'runtime.js');
  const first = Buffer.from('export const original = 1;\r\n');
  const second = Buffer.from('export const original = 2;\r\n');
  await writeFile(path, first);
  assert.equal(await installedRuntimeBundleCid(path), expected(first));
  await writeFile(path, second);
  assert.equal(await installedRuntimeBundleCid(path), expected(second));
  assert.notEqual(expected(first), expected(second));
  assert.deepEqual(await readFile(path), second);
});

test('a selected real handle remains original across path replacement during a read', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-runtime-hash-original-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'runtime.js'), replacement = join(root, 'replacement.js');
  const before = Buffer.alloc(65536 + 7, 0x41), after = Buffer.from('replacement');
  await writeFile(path, before); await writeFile(replacement, after);
  let original, closes = 0, firstRead = true;
  const openFile = async (name, flags) => {
    original = await open(name, flags);
    // The real original FD is retained. Replacement changes only the next
    // acquisition, not the source of the in-progress hash.
    return {
      async read(...args) {
        const result = await original.read(...args);
        if (firstRead) {
          firstRead = false;
          const {rename} = await import('node:fs/promises');
          await rename(replacement, path);
        }
        return result;
      },
      async close() {closes++; await original.close();},
    };
  };
  assert.equal(await installedRuntimeBundleCid(path, {openFile}), expected(before));
  assert.equal(closes, 1); await assert.rejects(original.stat(), {code: 'EBADF'});
  assert.equal(await installedRuntimeBundleCid(path), expected(after));
});

test('read/open failures never publish a partial runtime digest', async () => {
  const cause = new Error('original read failed'), bytes = Buffer.from('original');
  const actual = reader(bytes, {step: 2, readFailure: cause});
  await assert.rejects(installedRuntimeBundleCid('/runtime.js', actual), e => e === cause);
  assert.equal(actual.total, 2); assert.equal(actual.closes, 1);
  await assert.rejects(installedRuntimeBundleCid('/runtime.js', {
    openFile: async () => {throw cause;},
  }), e => e === cause);
});

for (const kind of ['throw', 'false']) {
  test(`runtime close ${kind} retains the same handle without returning a successful digest`, async () => {
    const closeFailure = new Error('original close failed');
    const actual = reader(Buffer.from('original'), kind === 'throw'
      ? {closeFailure} : {closePending: true});
    let failure;
    await assert.rejects(installedRuntimeBundleCid('/runtime.js', actual), e => {
      failure = e; assert.equal(e.cleanupPending, true); return true;
    });
    assert.equal(actual.opens, 1); assert.equal(actual.closes, 1);
    const reads = actual.reads;
    await assert.rejects(failure.cleanupHandle.retry());
    assert.equal(failure.cleanupHandle.status().pending, true);
    actual.releaseClose();
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(actual.opens, 1); assert.equal(actual.reads, reads);
    assert.equal(actual.closes, 3);
    await failure.cleanupHandle.retry(); assert.equal(actual.closes, 3);
  });
}

test('frozen original read failure and close failure retain both causes and initializer custody', async () => {
  const readFailure = Object.freeze(new Error('frozen original read'));
  const closeFailure = new Error('original close');
  const actual = reader(Buffer.from('original'), {step: 2, readFailure, closeFailure});
  let failure;
  await assert.rejects(installedRuntimeBundleCid('/runtime.js', actual), e => {
    failure = e;
    assert.equal(e.cause, readFailure);
    assert.deepEqual(e.errors, [readFailure, closeFailure]);
    return true;
  });
  let childCloses = 0;
  const retained = await retainInstalledHostInitializationFailure(failure,
    {sourceProfile: {close() {childCloses++;}}});
  assert.equal(retained.cleanupPending, true); assert.equal(childCloses, 0);
  actual.releaseClose();
  assert.equal((await retained.cleanupHandle.retry()).pending, false);
  assert.equal(childCloses, 1); assert.equal(actual.opens, 1); assert.equal(actual.total, 2);
  await retained.cleanupHandle.retry(); assert.equal(childCloses, 1);
});

test('one pending runtime file does not close or retire a sibling verification', async () => {
  const a = reader(Buffer.from('a'), {closePending: true});
  const b = reader(Buffer.from('b'));
  let failure;
  await assert.rejects(installedRuntimeBundleCid('/runtime.js', a), e => {failure = e; return true;});
  assert.equal(await installedRuntimeBundleCid('/runtime.js', b), expected(Buffer.from('b')));
  a.releaseClose(); await failure.cleanupHandle.retry();
  assert.equal(a.opens, 1); assert.equal(a.closes, 2); assert.equal(b.closes, 1);
});

test('actual Source/Effect loaders and publication bind each reread exact digest', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-runtime-loader-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const runtime = join(root, 'runtime.js');
  const profiles = Object.fromEntries(['source', 'effect'].map(role =>
    [role, {version: `actql-installed-runtime-${role}-fixture/0.1`}]));
  const observed = [], originalMoon = Object.freeze({});
  const module = role => ({
    check: value => value, identityParts: value => [value],
    load(profile, options) {
      assert.equal(profile.version, profiles[role].version);
      assert.equal(options.moon, originalMoon);
      observed.push([role, 'load', options.runtimeBundleCid]);
      return {environmentWire: '{}', prepareCaptured() {}, prepareRecovered() {}, close() {}};
    },
    publish(profile, options) {
      assert.equal(profile.version, profiles[role].version);
      assert.equal(options.moon, originalMoon);
      observed.push([role, 'publish', options.runtimeBundleCid]);
    },
  });
  const connectorTable = createInstalledConnectorTable([{name: 'runtime_fixture',
    source: {profileVersion: profiles.source.version, load: async () => module('source')},
    effect: {profileVersion: profiles.effect.version, load: async () => module('effect')},
  }]);
  const options = {root, principalId: 'runtime-fixture', moon: originalMoon,
    runtimeUrl: new URL(`file://${runtime}`), connectorTable};
  for (const role of ['source', 'effect']) {
    await writeFile(join(root, `${role}.json`), JSON.stringify(profiles[role]));
  }
  const calls = [
    () => loadInstalledSource(join(root, 'source.json'), options),
    () => publishInstalledSourceProfile(join(root, 'source.json'), options),
    () => loadInstalledEffect(join(root, 'effect.json'), options),
    () => publishInstalledEffectProfile(join(root, 'effect.json'), options),
  ];
  for (let i = 0; i < calls.length; i++) {
    const bytes = Buffer.from(`export const generation = ${i};\r\n`);
    await writeFile(runtime, bytes);
    const adapter = await calls[i]();
    assert.equal(observed.at(-1)[2], expected(bytes));
    await adapter?.close();
  }
  assert.deepEqual(observed.map(value => value.slice(0, 2)),
    [['source', 'load'], ['source', 'publish'], ['effect', 'load'], ['effect', 'publish']]);
});
