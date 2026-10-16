import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {readSourceProfileJson} from './source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {loadInstalledSource} from './installed-source.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';

async function fixture(t, {body = '{}', mode = 'false', failOpen = 1,
  failRead = false, readFailure,
  closeFailure = Object.freeze(new Error('OriginalProfileCloseFailure'))} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'profile-custody-', label: 'Original configuration FD cleanup counter'});
  const path = join(scratch.path, 'profile.json');
  await fs.writeFile(path, body);
  const open = fs.open;
  const primary = closeFailure;
  const state = {opens: 0, reads: 0, closes: 0, allowClose: false, handles: []};
  fs.open = async (name, ...args) => {
    const handle = await open(name, ...args);
    if (name !== path) return handle;
    state.opens++;
    if (state.opens !== failOpen) return handle;
    state.handles.push(handle);
    return {
      read(...parameters) {
        state.reads++;
        if (failRead) throw readFailure;
        return handle.read(...parameters);
      },
      async close() {
        state.closes++;
        if (!state.allowClose) {
          if (mode === 'false') return false;
          throw primary;
        }
        await handle.close();
      },
    };
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = open;
    syncBuiltinESMExports();
    // Fresh fixture handles only; never reopen/read the failed configuration.
    for (const handle of state.handles) await handle.close();
    scratch.passed();
  });
  return {path, primary, state};
}

for (const [name, primary] of [
  ['null', null],
  ['undefined', undefined],
  ['throwing message getter', Object.defineProperty({}, 'message', {
    get() { throw new Error('DiagnosticMessageUnavailable'); },
  })],
  ['non-string message', {message: {toString() { throw new Error('DoNotCoerceDiagnostic'); }}}],
]) {
  test(`thrown ${name} cannot mask the original configuration FD`, async t => {
    const f = await fixture(t, {mode: 'reject', failRead: true, readFailure: primary});
    let failure;
    await assert.rejects(readSourceProfileJson(f.path), error => {
      failure = error;
      assert.equal(error.cleanupHandle.primaryFailure, primary);
      assert.equal(error.cause, primary);
      assert.deepEqual(error.errors, [primary, f.primary]);
      assert.equal(error.cleanupPending, true);
      return true;
    });
    await f.state.handles[0].stat();
    const snapshot = failure.cleanupHandle.status();
    assert.deepEqual(snapshot.errors, [f.primary]);
    const first = failure.cleanupHandle.retry();
    assert.equal(first, failure.cleanupHandle.retry());
    await assert.rejects(first, error => error === f.primary);
    f.state.allowClose = true;
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupPending, false);
    assert.equal(snapshot.pending, true);
    assert.equal(f.state.opens, 1);
    assert.equal(f.state.reads, 1);
    await assert.rejects(f.state.handles[0].stat(), {code: 'EBADF'});
    const closes = f.state.closes;
    await failure.cleanupHandle.retry();
    assert.equal(f.state.closes, closes);
  });
}

for (const field of ['cleanupHandle', 'cleanupPending']) {
  test(`readonly ${field} cannot hide original configuration cleanup`, async t => {
    const primary = Object.defineProperty(new Error('ReadonlyProfileClose'), field,
      {value: field === 'cleanupPending' ? false : undefined});
    const f = await fixture(t, {mode: 'reject', closeFailure: primary});
    let failure;
    await assert.rejects(readSourceProfileJson(f.path), error => {
      failure = error;
      assert.equal(error.cause, primary);
      assert.equal(error.cleanupHandle.status().pending, true);
      assert.equal(primary[field], field === 'cleanupPending' ? false : undefined);
      return true;
    });
    f.state.allowClose = true;
    await failure.cleanupHandle.retry();
    await assert.rejects(f.state.handles[0].stat(), {code: 'EBADF'});
  });
}

test('inherited original cleanup facet is preserved beside the new configuration FD', async t => {
  let legacy;
  const originalCleanup = Object.freeze({
    status: () => Object.freeze({pending: legacy.fd >= 0}),
    retry: () => legacy.close(),
  });
  class OriginalCloseFailure extends Error {}
  Object.defineProperty(OriginalCloseFailure.prototype, 'cleanupHandle', {value: originalCleanup});
  const primary = new OriginalCloseFailure('OriginalPendingCleanup');
  const f = await fixture(t, {mode: 'reject', closeFailure: primary});
  const legacyPath = join(f.path, '..', 'legacy');
  await fs.writeFile(legacyPath, 'original responsibility');
  legacy = await fs.open(legacyPath, 'r');
  t.after(() => legacy.close());
  let failure;
  await assert.rejects(readSourceProfileJson(f.path), error => {
    failure = error;
    assert.notEqual(error, primary);
    assert.equal(error.cause, primary);
    assert.equal(primary.cleanupHandle, originalCleanup);
    assert.equal(Object.hasOwn(primary, 'cleanupHandle'), false);
    assert.notEqual(error.cleanupHandle, originalCleanup);
    assert.equal(error.cleanupHandle.status().pending, true);
    return true;
  });
  f.state.allowClose = true;
  await failure.cleanupHandle.retry();
  await assert.rejects(f.state.handles[0].stat(), {code: 'EBADF'});
  assert.equal(originalCleanup.status().pending, true, 'new FD ACK is not the old responsibility ACK');
  await primary.cleanupHandle.retry();
  await assert.rejects(legacy.stat(), {code: 'EBADF'});
});

for (const mode of ['false', 'reject']) {
  test(`configuration ${mode} close keeps the same real FD and single-flight retry`, async t => {
    const f = await fixture(t, {mode});
    let failure;
    await assert.rejects(readSourceProfileJson(f.path), error => {
      failure = error;
      assert.equal(error.cleanupHandle.status().pending, true);
      if (mode === 'reject') assert.equal(error.cause ?? error, f.primary);
      return true;
    });
    await f.state.handles[0].stat();
    const reads = f.state.reads;
    const first = failure.cleanupHandle.retry();
    assert.equal(first, failure.cleanupHandle.retry());
    await assert.rejects(first);
    assert.equal(failure.cleanupHandle.status().pending, true);
    const previous = failure.cleanupHandle.status();
    f.state.allowClose = true;
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(previous.pending, true);
    assert.equal(f.state.opens, 1);
    assert.equal(f.state.reads, reads);
    await assert.rejects(f.state.handles[0].stat(), {code: 'EBADF'});
    const closes = f.state.closes;
    await failure.cleanupHandle.retry();
    assert.equal(f.state.closes, closes);
  });
}

test('malformed configuration retains parse primary and original close through initialization custody', async t => {
  const f = await fixture(t, {body: '{', mode: 'reject'});
  let inner;
  await assert.rejects(readSourceProfileJson(f.path), error => {
    inner = error;
    assert(error.cause instanceof SyntaxError);
    assert.deepEqual(error.errors, [error.cause, f.primary]);
    return true;
  });
  const outer = await retainInstalledHostInitializationFailure(inner, {});
  assert.equal(outer.cleanupPending, true);
  assert.equal(outer.cause, inner);
  const reads = f.state.reads;
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  assert.equal(f.state.reads, reads);
  assert.equal(f.state.opens, 1);
  await assert.rejects(f.state.handles[0].stat(), {code: 'EBADF'});
});

test('Source profile error projection transfers its original FD to initialization custody', async t => {
  const f = await fixture(t);
  let original;
  await assert.rejects(loadInstalledSource(f.path, {}), error => {
    original = error;
    assert.equal(error.code, 'InvalidInstalledSourceProfile');
    assert.equal(error.cleanupHandle.status().pending, true);
    return true;
  });
  const outer = await retainInstalledHostInitializationFailure(original, {});
  assert.equal(outer.cleanupPending, true);
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  assert.equal(f.state.opens, 1);
});

for (const afterLoad of [false, true]) {
  test(`Source identity failure ${afterLoad ? 'after' : 'before'} adapter acquisition is not swallowed`, async t => {
    const version = 'actql-installed-custody-counter/0.1';
    const f = await fixture(t, {body: JSON.stringify({version}), failOpen: 2});
    let loads = 0, closed = 0;
    const connectorTable = createInstalledConnectorTable([{name: 'custody_counter', source: {
      profileVersion: version, load: async () => ({
        check: value => value,
        identityParts: async (profile, _provider, read) => afterLoad ? [profile]
          : [await read(f.path)],
        load: async () => { loads++; return {close() { closed++; }}; },
      }),
    }}]);
    let failure;
    await assert.rejects(loadInstalledSource(f.path, {connectorTable}), error => {
      failure = error;
      assert.equal(error.cleanupHandle.status().pending, true);
      return true;
    });
    assert.equal(loads, afterLoad ? 1 : 0);
    assert.equal(closed, 0, 'initialization retains adapter until original read retires');
    f.state.allowClose = true;
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(closed, afterLoad ? 1 : 0);
  });
}
