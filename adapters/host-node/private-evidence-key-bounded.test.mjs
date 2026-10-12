// The fixed installation key contract is a physical clamp, not a complete
// original Run bootstrap profile, original-state admission or send authority.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {chmod, mkdtemp, open, readFile, rename, rm, writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {loadPrivateEvidenceKey} from './local-continuation-evidence.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

async function fixture(t, bytes) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-private-key-bound-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'private-evidence.key');
  await writeFile(path, bytes, {mode: 0o600});
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe);
  await probe.close();
  return {directory, path, prototype};
}

test('private installation key preserves its exact independently authored 32 bytes', async t => {
  const bytes = Buffer.from('0123456789abcdef0123456789abcdef', 'ascii');
  const f = await fixture(t, bytes);
  const key = await loadPrivateEvidenceKey(f.directory);
  assert.deepEqual(key.key, bytes);
  assert.equal(key.keyId, 'sha256:3eb1bd439947eb762998e566ccc2e099c791118b2'
    + 'f40579cc4f7da2b5061b7f9');
  key.key.fill(0);
  assert.deepEqual(await readFile(f.path), bytes);
});

test('private key rejects an exposed replacement after the real owner-only path observation', async t => {
  const bytes = Buffer.from('0123456789abcdef0123456789abcdef', 'ascii');
  const f = await fixture(t, bytes);
  const replacement = join(f.directory, 'replacement.key');
  await writeFile(replacement, bytes, {mode: 0o644});
  const pathStat = fs.promises.stat, fdStat = f.prototype.stat;
  let replacements = 0, original, reads = 0, closes = 0, accepted;
  t.after(() => {
    fs.promises.stat = pathStat;
    syncBuiltinESMExports();
    f.prototype.stat = fdStat;
    accepted?.key.fill(0);
  });
  fs.promises.stat = async function(path, ...args) {
    const observed = await Reflect.apply(pathStat, this, [path, ...args]);
    if (path === f.path && replacements === 0) {
      assert.equal(observed.mode & 0o077, 0);
      await rename(replacement, f.path);
      replacements++;
    }
    // This is the actual pre-replacement stat, not forged file metadata.
    return observed;
  };
  syncBuiltinESMExports();
  f.prototype.stat = async function(...args) {
    if (original === undefined) {
      original = this;
      const read = this.read, close = this.close;
      this.read = function(...args) { reads++; return Reflect.apply(read, this, args); };
      this.close = function(...args) { closes++; return Reflect.apply(close, this, args); };
    }
    const actual = await Reflect.apply(fdStat, this, args);
    assert.equal(actual.mode & 0o077n, 0o044n);
    return actual;
  };
  await assert.rejects(loadPrivateEvidenceKey(f.directory).then(value => {
    accepted = value;
    return value;
  }), {code: 'PrivateEvidenceKeyExposed'});
  assert.equal(replacements, 1);
  assert.equal(reads, 0);
  assert.equal(closes, 1);
  assert.equal(original.fd, -1);

  // A later exposure of the same acquired FD must also refuse after real
  // positive I/O. The original exact-byte and close/probe bounds still hold.
  fs.promises.stat = pathStat;
  syncBuiltinESMExports();
  f.prototype.stat = fdStat;
  await chmod(f.path, 0o600);
  let reading, positiveReads = 0, finalCloses = 0;
  f.prototype.stat = function(...args) {
    if (reading === undefined) {
      reading = this;
      const read = this.read, close = this.close;
      this.read = async function(...args) {
        const result = await Reflect.apply(read, this, args);
        if (result.bytesRead > 0) {
          positiveReads++;
          await chmod(f.path, 0o644);
        }
        return result;
      };
      this.close = function(...args) { finalCloses++; return Reflect.apply(close, this, args); };
    }
    return Reflect.apply(fdStat, this, args);
  };
  await assert.rejects(loadPrivateEvidenceKey(f.directory), {code: 'PrivateEvidenceKeyExposed'});
  assert.equal(positiveReads, 1);
  assert.equal(finalCloses, 1);
  assert.equal(reading.fd, -1);
});

test('private key one-byte excess is rejected on the same FD before any content read', async t => {
  const f = await fixture(t, Buffer.alloc(33, 7));
  const stat = f.prototype.stat;
  let reads = 0, closes = 0;
  t.after(() => { f.prototype.stat = stat; });
  f.prototype.stat = function(...args) {
    // Node's close is an own method on the actual FileHandle. Interpose at
    // the original FD observation, not an unused prototype.close property.
    const read = this.read, close = this.close;
    this.read = function(...args) { reads++; return Reflect.apply(read, this, args); };
    this.close = function(...args) { closes++; return Reflect.apply(close, this, args); };
    return Reflect.apply(stat, this, args);
  };
  await assert.rejects(loadPrivateEvidenceKey(f.directory), {code: 'InvalidPrivateEvidenceKey'});
  assert.equal(reads, 0);
  assert.equal(closes, 1);
});

test('private key short, missing and exposed files retain the existing typed refusals', async t => {
  const f = await fixture(t, Buffer.alloc(31, 7));
  await assert.rejects(loadPrivateEvidenceKey(f.directory), {code: 'InvalidPrivateEvidenceKey'});
  await chmod(f.path, 0o644);
  await assert.rejects(loadPrivateEvidenceKey(f.directory), {code: 'PrivateEvidenceKeyExposed'});
  await rm(f.path);
  await assert.rejects(loadPrivateEvidenceKey(f.directory), {code: 'PrivateEvidenceKeyUnavailable'});
});

test('private key pending original FD close is retained by the actual installed initialization cleanup', async t => {
  const f = await fixture(t, Buffer.alloc(32, 7));
  const stat = f.prototype.stat;
  let close;
  let original, closes = 0, reads = 0, allowClose = false, failure;
  const pending = Object.assign(new Error('OriginalKeyFdClosePending'), {code: 'EIO'});
  t.after(async () => {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    f.prototype.stat = stat;
    if (original?.fd >= 0) await Reflect.apply(close, original, []);
  });
  f.prototype.stat = function(...args) {
    if (original === undefined) {
      original = this;
      const read = this.read;
      close = this.close;
      this.read = function(...args) { reads++; return Reflect.apply(read, this, args); };
      this.close = function(...args) {
        assert.strictEqual(this, original);
        closes++;
        if (!allowClose) return Promise.reject(pending);
        return Reflect.apply(close, this, args);
      };
    }
    return Reflect.apply(stat, this, args);
  };
  await assert.rejects(loadPrivateEvidenceKey(f.directory), error => {
    assert.strictEqual(error, pending);
    return error.cleanupHandle.status().pending;
  });
  assert(original.fd >= 0);
  failure = await retainInstalledHostInitializationFailure(pending, {});
  assert.strictEqual(failure.primaryFailure, pending);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['initialization']);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(closes, 2);
  assert.equal(reads, 2); // 32-byte content and the separate one-byte EOF probe.
  allowClose = true;
  const retry = failure.cleanupHandle.retry();
  assert.strictEqual(failure.cleanupHandle.retry(), retry);
  assert.equal((await retry).pending, false);
  assert.equal(original.fd, -1);
  assert.equal(closes, 3);
  await failure.cleanupHandle.retry();
  assert.equal(closes, 3);
  assert.equal(reads, 2); // Cleanup does not reopen or reread the key.
});

test('raced-away key plus frozen read failure never replaces pending FD custody with unavailable', async t => {
  const f = await fixture(t, Buffer.alloc(32, 7));
  const stat = f.prototype.stat;
  let close;
  const primary = Object.freeze(Object.assign(new Error('OriginalKeyReadLost'), {code: 'ENOENT'}));
  let original, allowClose = false, failure;
  t.after(async () => {
    allowClose = true;
    if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
    f.prototype.stat = stat;
    if (original?.fd >= 0) await Reflect.apply(close, original, []);
  });
  f.prototype.stat = function(...args) {
    if (original === undefined) {
      original = this;
      close = this.close;
      this.read = function() { return Promise.reject(primary); };
      this.close = function(...args) {
        if (!allowClose) return Promise.reject(new Error('OriginalKeyCloseFailed'));
        return Reflect.apply(close, this, args);
      };
    }
    return Reflect.apply(stat, this, args);
  };
  await assert.rejects(loadPrivateEvidenceKey(f.directory), error => {
    failure = error;
    assert.strictEqual(error.cause, primary);
    assert.equal(error.cleanupHandle.status().pending, true);
    assert.notEqual(error.code, 'PrivateEvidenceKeyUnavailable');
    return true;
  });
  allowClose = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(original.fd, -1);
});
