// Real original Dir with controlled false close acknowledgements. This is a
// physical adapter witness, not Core funding, authority or installed INFER.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, opendir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {listContinuationLedgerNamesBounded} from './bounded-continuation-directory.mjs';

for (const cancelled of [false, true]) {
  test(`bounded ledger directory false close keeps the same ${cancelled ? 'cancelled' : 'completed'} scan pending`,
    async t => {
      const path = await mkdtemp(join(tmpdir(), 'actql-c-directory-false-close-'));
      await writeFile(join(path, 'a.json'), '');
      const probe = await opendir(path);
      const prototype = Object.getPrototypeOf(probe);
      const read = prototype.read, close = prototype.close;
      await probe.close();
      const abort = new AbortController();
      const reason = Object.freeze(new Error('OriginalDirectoryCancelled'));
      let original, failure, reads = 0, closes = 0, falseClose = true;
      let physicallyClosed = false, passed = false;
      t.after(async () => {
        prototype.read = read;
        prototype.close = close;
        falseClose = false;
        if (failure?.cleanupHandle?.status().pending) {
          await failure.cleanupHandle.retry();
          physicallyClosed = true;
        } else if (original !== undefined && !physicallyClosed) {
          await Reflect.apply(close, original, []);
          physicallyClosed = true;
        }
        if (passed && physicallyClosed) await rm(path, {recursive: true});
        else t.diagnostic(`Preserved original directory failure: ${path}`);
      });
      prototype.read = async function(...args) {
        if (this.path !== path) return Reflect.apply(read, this, args);
        if (original === undefined) original = this;
        assert.strictEqual(this, original);
        reads++;
        const value = await Reflect.apply(read, this, args);
        if (cancelled) abort.abort(reason);
        return value;
      };
      prototype.close = function(...args) {
        // Native Dir.close's Promise overload re-enters its callback overload.
        if (typeof args[0] === 'function' || this.path !== path) {
          return Reflect.apply(close, this, args);
        }
        assert.strictEqual(this, original);
        closes++;
        if (falseClose) return Promise.resolve(false);
        return Reflect.apply(close, this, args).then(result => {
          physicallyClosed = true;
          return result;
        });
      };
      try {
        await listContinuationLedgerNamesBounded(path,
          {maxDirectoryEntries: 1, maxWireBytes: 6}, abort.signal);
      } catch (error) { failure = error; }
      assert.notEqual(failure, undefined, 'false close is not publication of completed names');
      if (cancelled) assert.strictEqual(failure.cause, reason);
      else assert.equal(failure.code, 'ContinuationDirectoryCleanupPending');
      assert.equal(failure.cleanupPending, true);
      const cleanup = failure.cleanupHandle;
      assert.equal(cleanup.status().pending, true);
      const expectedReads = cancelled ? 1 : 2;
      assert.equal(reads, expectedReads);
      assert.equal(closes, 1);
      assert.equal(physicallyClosed, false);
      const flight = cleanup.retry();
      assert.strictEqual(cleanup.retry(), flight);
      await assert.rejects(flight, {code: 'ContinuationDirectoryCleanupPending'});
      assert.equal(cleanup.status().pending, true);
      assert.equal(physicallyClosed, false);
      assert.equal(reads, expectedReads, 'retry must not rescan the directory');
      assert.equal(closes, 2);
      falseClose = false;
      assert.equal((await cleanup.retry()).pending, false);
      assert.equal(physicallyClosed, true);
      assert.equal(reads, expectedReads);
      assert.equal(closes, 3);
      await cleanup.retry();
      assert.equal(closes, 3, 'confirmed original close settles once');
      passed = true;
    });
}
