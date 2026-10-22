import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Fresh process to isolate builtin substitutions. The database/copy are real;
// the close fault is explicit and unaccounted, not an operational Host fixture.
async function counter() {
  const assert = (await import('node:assert/strict')).default;
  const fs = (await import('node:fs')).default;
  const {syncBuiltinESMExports} = await import('node:module');
  const {DatabaseSync} = await import('node:sqlite');
  const {join} = await import('node:path');
  const [moduleUrl, root, role] = process.argv.slice(1);
  const source = join(root, 'source', 'journal.sqlite3');
  const sentinel = join(root, 'separate-original');
  fs.writeFileSync(sentinel, 'a separate FD original must survive cleanup retry');
  const database = new DatabaseSync(source);
  database.exec('CREATE TABLE metadata(value TEXT) STRICT; INSERT INTO metadata VALUES (\'original\')');
  database.close();
  const sourceBytes = fs.readFileSync(source);
  const open = fs.openSync, close = fs.closeSync, stat = fs.fstatSync;
  const opened = new Set();
  const closeFailure = new Error('OriginalNumericCloseOutcomeUnknown');
  const primary = new Error('OriginalFormatRefusal');
  let target, reused, sentinelIdentity, closes = 0, inspections = 0, failure;
  fs.openSync = function(path, flags, ...args) {
    const fd = Reflect.apply(open, fs, [path, flags, ...args]);
    opened.add(fd);
    if (target === undefined && (role === 'source' ? path === source : flags === 'wx')) target = fd;
    return fd;
  };
  fs.closeSync = function(fd) {
    if (fd === target) {
      closes++;
      if (closes === 1) {
        Reflect.apply(close, fs, [fd]);
        opened.delete(fd);
        reused = Reflect.apply(open, fs, [sentinel, 'r']);
        assert.equal(reused, fd, 'counter requires actual same-number FD reuse');
        sentinelIdentity = Reflect.apply(stat, fs, [reused, {bigint:true}]);
        throw closeFailure;
      }
    }
    const result = Reflect.apply(close, fs, [fd]);
    opened.delete(fd);
    return result;
  };
  syncBuiltinESMExports();
  try {
    const {inspectSqliteSnapshot} = await import(moduleUrl);
    try {
      inspectSqliteSnapshot(source, copy => {
        inspections++;
        assert.equal(copy.prepare('SELECT value FROM metadata').get().value, 'original');
        throw primary;
      }, {maxSourceBytes:65536, assertCurrent(){}});
    } catch (cause) { failure = cause; }
    assert.notEqual(reused, undefined);
    assert.equal(closes, 1, 'one numeric close attempt even during immediate cleanup');
    assert.equal(failure?.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure.primaryFailure, role === 'source' ? primary : closeFailure);
    assert.equal(inspections, role === 'source' ? 1 : 0);
    for (let index = 0; index < 3; index++) {
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.equal(failure.cleanupHandle.retry().pending, true);
      assert.equal(closes, 1);
      const current = Reflect.apply(stat, fs, [reused, {bigint:true}]);
      assert.equal(current.dev, sentinelIdentity.dev);
      assert.equal(current.ino, sentinelIdentity.ino);
      assert(failure.cleanupHandle.status().errors.every(item => item.error === closeFailure));
    }
    assert.deepEqual(fs.readFileSync(source), sourceBytes);
    console.log(JSON.stringify({role, closes, inspections, sameNumber:reused === target,
      originalOutcome:'unknown', productCleanupPending:true, ordinaryHost:false}));
  } finally {
    fs.openSync = open;
    fs.closeSync = close;
    syncBuiltinESMExports();
    // Test-owned teardown is NOT a product close acknowledgement. Preserve
    // all fixture files; the product's Unknown carrier was asserted above.
    if (reused !== undefined) {
      try {
        const current = Reflect.apply(stat, fs, [reused, {bigint:true}]);
        if (current.dev === sentinelIdentity.dev && current.ino === sentinelIdentity.ino) {
          Reflect.apply(close, fs, [reused]);
        }
      } catch (cause) { if (cause.code !== 'EBADF') throw cause; }
    }
    for (const fd of opened) Reflect.apply(close, fs, [fd]);
  }
}

for (const role of ['source', 'output']) {
  test('inspection keeps a consumed ' + role + ' numeric close Unknown without closing a reused FD', async () => {
    const scratch = await createOwnedScratch({
      parent:fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix:'sqlite-inspection-fd-', label:'same-number inspection FD counter',
    });
    mkdirSync(join(scratch.path, 'source'));
    mkdirSync(join(scratch.path, 'temporary'));
    const result = spawnSync(process.execPath,
      ['--input-type=module', '-e', '(' + counter.toString() + ')()',
        new URL('./sqlite-format-inspection.mjs', import.meta.url).href, scratch.path, role],
      {encoding:'utf8', timeout:20000, maxBuffer:1024*1024,
        env:{...process.env, TMPDIR:join(scratch.path, 'temporary')}});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const observation = JSON.parse(result.stdout.trim());
    assert.equal(observation.originalOutcome, 'unknown');
    assert.equal(observation.productCleanupPending, true);
    assert.equal(observation.closes, 1);
    assert.equal(observation.sameNumber, true);
    scratch.passed();
  });
}
