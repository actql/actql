import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import * as fs from 'node:fs';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import implementation from './initial-control-image-source.cjs';

const require = createRequire(import.meta.url);
const source = fs.readFileSync(new URL('./initial-control-image-source.cjs', import.meta.url), 'utf8');
const fact = bytes => ({bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')});
function fixture(t, bytes = Buffer.from('export const original = "independent image";\n')) {
  const directory = fs.mkdtempSync(join(tmpdir(), 'actql-initial-control-source-'));
  t.after(() => fs.rmSync(directory, {recursive: true}));
  const path = join(directory, 'original.mjs');
  fs.writeFileSync(path, bytes);
  return {directory, path, bytes, expected: fact(bytes)};
}
function controlled(nativeFs) {
  // This private primitive and explicit syscall controls do not create the
  // actual preload, operational admission, Host or a physical funding issuer.
  const module = {exports: {}};
  runInNewContext(source, {module, require(name) { return name === 'node:fs' ? nativeFs : require(name); }});
  return module.exports.captureInitialControlImageSource;
}

test('same-FD bounded image capture retains exact immutable UTF8 Source without issuing authority', t => {
  const text = '\ufeffexport const original = "opaque 日本語";\n' + '// original\n'.repeat(12000);
  const f = fixture(t, Buffer.from(text));
  const value = implementation.captureInitialControlImageSource(f.path, f.expected);
  assert.equal(value.source, text);
  assert.equal(value.bytes, f.bytes.length);
  assert.equal(value.sha256, f.expected.sha256);
  assert.ok(Object.isFrozen(value));
  assert.deepEqual(Object.keys(value).sort(), ['bytes', 'sha256', 'source']);
  fs.writeFileSync(f.path, 'export const replacement = true;\n');
  assert.equal(value.source, text);
  // Retaining the old Source does not claim that its mutable pathname is current.
});

test('image fact accessors and invalid extents refuse before any open or caller getter', t => {
  const f = fixture(t);
  let opens = 0, getters = 0;
  const capture = controlled({...fs, openSync() { opens++; throw new Error('MustNotOpen'); }});
  for (const bytes of [-1, 1.5, NaN, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => capture(f.path, {...f.expected, bytes}), {code: 'InvalidInitialControlImageFact'});
  }
  const expected = Object.defineProperty({...f.expected}, 'bytes', {get() { getters++; return 1; }});
  assert.throws(() => capture(f.path, expected), {code: 'InvalidInitialControlImageFact'});
  assert.equal(opens, 0);
  assert.equal(getters, 0);
});

test('foreign size or digest never returns Source and closes the same original descriptor', t => {
  const f = fixture(t);
  let opened, closes = 0;
  const capture = controlled({...fs,
    openSync(...args) { opened = fs.openSync(...args); return opened; },
    closeSync(fd) { assert.equal(fd, opened); closes++; return fs.closeSync(fd); }});
  assert.throws(() => capture(f.path, {...f.expected, bytes: f.bytes.length - 1}),
    {code: 'InitialControlImageChanged'});
  assert.throws(() => fs.fstatSync(opened), {code: 'EBADF'});
  assert.throws(() => capture(f.path, {...f.expected, sha256: '0'.repeat(64)}),
    {code: 'InitialControlImageChanged'});
  assert.throws(() => fs.fstatSync(opened), {code: 'EBADF'});
  assert.equal(closes, 2);
});

test('growth is detected by the one-byte lookahead without reading the expanded image', t => {
  const f = fixture(t);
  let reads = 0, requested = 0;
  const capture = controlled({...fs, readSync(...args) {
    requested += args[3];
    const count = fs.readSync(...args);
    if (reads++ === 0) fs.appendFileSync(f.path, 'foreign trailing image');
    return count;
  }});
  assert.throws(() => capture(f.path, f.expected), {code: 'InitialControlImageChanged'});
  assert.equal(requested, f.bytes.length + 1);
  assert.equal(reads, 2);
});

test('changed same-FD identity observation and invalid UTF8 refuse instead of normalizing Source', t => {
  const f = fixture(t);
  let stats = 0;
  const capture = controlled({...fs, fstatSync(...args) {
    const value = fs.fstatSync(...args);
    return stats++ === 0 ? value : {...value, ctimeNs: value.ctimeNs + 1n};
  }});
  assert.throws(() => capture(f.path, f.expected), {code: 'InitialControlImageChanged'});
  const malformed = Buffer.from([0x65, 0x78, 0xff]);
  fs.writeFileSync(f.path, malformed);
  assert.throws(() => implementation.captureInitialControlImageSource(f.path, fact(malformed)),
    {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
});

test('a symbolic-link final component cannot supply an original image', t => {
  const f = fixture(t), link = join(f.directory, 'aliased.mjs');
  fs.symlinkSync(f.path, link);
  assert.throws(() => implementation.captureInitialControlImageSource(link, f.expected),
    error => error.code === 'ELOOP' || error.code === 'EMLINK');
});

test('read failure keeps its original cause when the original descriptor closes normally', t => {
  const f = fixture(t), primary = Object.freeze(new Error('OriginalImageReadFailure'));
  let opened, reads = 0, closes = 0;
  const capture = controlled({...fs,
    openSync(...args) { opened = fs.openSync(...args); return opened; },
    readSync(...args) { fs.readSync(...args); reads++; throw primary; },
    closeSync(fd) { assert.equal(fd, opened); closes++; return fs.closeSync(fd); }});
  assert.throws(() => capture(f.path, f.expected), error => error === primary);
  assert.equal(reads, 1);
  assert.equal(closes, 1);
  assert.throws(() => fs.fstatSync(opened), {code: 'EBADF'});
});

test('a pre-close refusal stays pending without retrying the original integer or read', t => {
  const f = fixture(t), primary = Object.freeze(new Error('OriginalImageReadFailure'));
  const closeFailure = Object.freeze(new Error('OriginalImageCloseUnknown'));
  let fd, reads = 0, closes = 0, carrier;
  t.after(() => { if (fd !== undefined) fs.closeSync(fd); });
  const functions = {...fs, openSync(...args) { fd = fs.openSync(...args); return fd; },
    readSync(...args) { fs.readSync(...args); reads++; throw primary; },
    closeSync(original) { assert.equal(original, fd); closes++; throw closeFailure; }};
  const capture = controlled(functions);
  try { capture(f.path, f.expected); } catch (cause) { carrier = cause; }
  assert.equal(carrier.code, 'InitialControlImageCleanupPending');
  assert.equal(carrier.cause, primary);
  assert.equal(carrier.closeFailure, closeFailure);
  const original = carrier.cleanupHandle;
  assert.equal(original.primaryFailure, primary);
  assert.ok(Object.isFrozen(original));
  functions.closeSync = () => { throw new Error('ReplacementMustNotRun'); };
  for (let index = 0; index < 2; index++) {
    assert.equal(original.retry().pending, true);
    const status = original.status();
    assert.equal(status.pending, true);
    assert.equal(status.errors.length, 1);
    assert.equal(status.errors[0], closeFailure);
    assert.ok(Object.isFrozen(status));
    assert.ok(Object.isFrozen(status.errors));
    assert.ok(fs.fstatSync(fd).isFile());
  }
  assert.equal(closes, 1);
  assert.equal(reads, 1);
});

for (const failure of ['read', 'hash']) {
  test(`${failure} failure and close-then-throw never close a foreign file reusing the same FD`, t => {
    const f = fixture(t), primary = Object.freeze(new Error('OriginalImageReadFailure'));
    const closeFailure = Object.freeze(new Error('OriginalImageCloseUnknown'));
    const foreignPath = join(f.directory, 'foreign');
    fs.writeFileSync(foreignPath, 'foreign original bytes');
    let fd, foreign, reads = 0, closes = 0, carrier;
    t.after(() => {
      if (foreign === undefined) return;
      try { fs.closeSync(foreign); } catch (error) { if (error.code !== 'EBADF') throw error; }
    });
    const capture = controlled({...fs,
      openSync(...args) { fd = fs.openSync(...args); return fd; },
      readSync(...args) {
        const count = fs.readSync(...args); reads++;
        if (failure === 'read') throw primary;
        return count;
      },
      closeSync(original) {
        assert.equal(original, fd); closes++;
        fs.closeSync(original);
        if (closes === 1) {
          foreign = fs.openSync(foreignPath, 'r');
          assert.equal(foreign, fd, 'the real OS must reuse the released numeric descriptor');
        }
        throw closeFailure;
      }});
    const expected = failure === 'hash' ? {...f.expected, sha256: '0'.repeat(64)} : f.expected;
    try { capture(f.path, expected); } catch (cause) { carrier = cause; }
    assert.equal(carrier.code, 'InitialControlImageCleanupPending');
    if (failure === 'read') assert.equal(carrier.cause, primary);
    else assert.equal(carrier.cause.code, 'InitialControlImageChanged');
    assert.equal(carrier.cleanupHandle.primaryFailure, carrier.cause);
    assert.equal(carrier.closeFailure, closeFailure);
    const before = reads, identity = fs.fstatSync(foreign, {bigint: true});
    for (let index = 0; index < 2; index++) {
      assert.equal(carrier.cleanupHandle.retry().pending, true);
      const after = fs.fstatSync(foreign, {bigint: true});
      assert.equal(after.dev, identity.dev);
      assert.equal(after.ino, identity.ino);
    }
    const actual = Buffer.alloc(22);
    assert.equal(fs.readSync(foreign, actual, 0, actual.length, 0), actual.length);
    assert.equal(actual.toString(), 'foreign original bytes');
    assert.equal(closes, 1);
    assert.equal(reads, before);
  });
}

test('an unconfirmed close cannot return valid Source or become confirmed from EBADF', t => {
  const f = fixture(t);
  let fd, reads = 0, closes = 0, carrier;
  const capture = controlled({...fs,
    openSync(...args) { fd = fs.openSync(...args); return fd; },
    readSync(...args) { reads++; return fs.readSync(...args); },
    closeSync(original) {
      assert.equal(original, fd); closes++;
      fs.closeSync(original);
      return false;
    }});
  try { capture(f.path, f.expected); } catch (cause) { carrier = cause; }
  assert.equal(carrier.code, 'InitialControlImageCleanupPending');
  assert.equal(carrier.cleanupHandle.primaryFailure, carrier.closeFailure);
  assert.throws(() => fs.fstatSync(fd), {code: 'EBADF'});
  const before = reads;
  assert.equal(carrier.cleanupHandle.retry().pending, true);
  assert.equal(carrier.cleanupHandle.retry().pending, true);
  assert.equal(carrier.cleanupHandle.status().pending, true);
  assert.equal(closes, 1);
  assert.equal(reads, before);
});
