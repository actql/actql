import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, symlink, rm} from 'node:fs/promises';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {readContinuationLedgerBounded as readBounded} from './bounded-continuation-metadata.mjs';
import {readBoundedLocalMetadata} from '../store-local/publication-store.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// The matching installed parser is real Core, not a shape/authority double.
// Prepare this single runtime before this focused Node selection.
const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
const control = runtimeCore(moon).publicationControl;
const readContinuationLedgerBounded = (path, id, limits, signal) =>
  readBounded(path, id, limits, signal, control);

// Hand-written metadata vector, not obtained from the product writer, a Store
// issuer, current journal or Model. Shape validity is not resource authority.
const text = '{"version":"actql-local-continuation-retention/0.1","prepare_attempt_id":"original-run","request_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","key_id":"sha256:2222222222222222222222222222222222222222222222222222222222222222","holdings":[]}';
const held = {name: 'captured_input',
  semantic_cid: 'sha256:' + '3'.repeat(64), holding_cid: 'sha256:' + '4'.repeat(64),
  key_id: 'sha256:' + '2'.repeat(64), state: 'held'};

async function fixture(t, content = text) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-continuation-metadata-'));
  const path = join(directory, 'original-run.json');
  await writeFile(path, content);
  t.after(() => rm(directory, {recursive: true, force: true}));
  return {directory, path};
}

test('bounded continuation metadata exact wire fit and one-short use the shared real FD reader', async t => {
  const {path} = await fixture(t);
  const length = Buffer.byteLength(text);
  assert.equal(length, 273);
  const value = await readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0});
  assert.deepEqual(value, JSON.parse(text));
  await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: 272, maxLedgerEntries: 0}), {code: 'InvalidPublicationStoreObject'});
  assert.deepEqual(await readBoundedLocalMetadata(path, 273), Buffer.from(text));
});

test('private retention alone rejects decoded duplicate keys instead of native last-wins', async t => {
  const {path} = await fixture(t);
  const entry = JSON.stringify(held);
  const wires = [
    text.replace('"holdings":[]', '"holdings":[null],"holdings":[]'),
    text.replace('"holdings":[]', '"holdings":[],"holdings":[]'),
    text.replace('"holdings":[]', '"\\u0068oldings":[],"holdings":[]'),
    text.replace('"holdings":[]', `"holdings":[${entry.replace('"state":"held"', '"state":"retired","state":"held"')}]`),
  ];
  for (const wire of wires) {
    // Independent legacy/public JSON control. It is NOT the new reader's
    // expectation generator: the normative refusal is fixed below.
    const old = JSON.parse(wire);
    assert.deepEqual(old.holdings, wire.includes('"state"') ? [held] : []);
    await writeFile(path, wire);
    await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 2048, maxLedgerEntries: 1}), {code: 'InvalidContinuationLedger'});
    assert.equal(await import('node:fs/promises').then(fs => fs.readFile(path, 'utf8')), wire);
  }
  assert.deepEqual(JSON.parse('{"x":1,"x":2}'), {x: 2});
});

test('malformed trees never enter native metadata materialization', async t => {
  const {path} = await fixture(t);
  const parse = JSON.parse;
  let materializations = 0;
  JSON.parse = function(...args) { materializations++; return Reflect.apply(parse, this, args); };
  t.after(() => { JSON.parse = parse; });
  for (const wire of ['['.repeat(8192) + ']'.repeat(8192),
    '[' + '0,'.repeat(8000) + '0]',
    '[{' + Array.from({length: 100}, (_, i) => `"p${i}":0`).join(',') + '},{"p0":0}]']) {
    await writeFile(path, wire);
    await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 16384, maxLedgerEntries: 40}), {code: 'InvalidContinuationLedger'});
  }
  assert.equal(materializations, 0);
});

test('missing installed private parser refuses before I/O without a JSON fallback', async () => {
  await assert.rejects(readBounded('/not-an-original-path', 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), {code: 'ContinuationMetadataUnavailable'});
});

test('Core Int derivation preserves large safe-integer Host ceilings for a small actual record', async t => {
  const {path} = await fixture(t);
  const value = await readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: Number.MAX_SAFE_INTEGER, maxLedgerEntries: Number.MAX_SAFE_INTEGER});
  assert.deepEqual(value, JSON.parse(text));
});

test('bounded continuation metadata separates actual entry count from encrypted object limits', async t => {
  const body = {...JSON.parse(text), holdings: Array.from({length: 64}, () => ({...held}))};
  const {path} = await fixture(t, JSON.stringify(body));
  const maxWireBytes = Buffer.byteLength(JSON.stringify(body));
  await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes, maxLedgerEntries: 63}), {code: 'ContinuationLedgerEntriesLimit'});
  const value = await readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes, maxLedgerEntries: 64});
  assert.equal(value.holdings.length, 64);
  assert.deepEqual(value.holdings, body.holdings);
});

test('bounded continuation metadata missing malformed or extra limits refuse without opening the path', async () => {
  for (const limits of [undefined, {}, {maxWireBytes: 273},
    {maxWireBytes: 0, maxLedgerEntries: 0}, {maxWireBytes: 273, maxLedgerEntries: -1},
    {maxWireBytes: 273, maxLedgerEntries: 0, grant: true}]) {
    await assert.rejects(readContinuationLedgerBounded('/not-a-real-path', 'original-run', limits),
      {code: 'InvalidContinuationMetadataBounds'});
  }
});

test('bounded continuation metadata rejects wrong origin unknown fields and malformed entry data', async t => {
  const {path} = await fixture(t);
  const original = JSON.parse(text);
  for (const body of [
    {...original, prepare_attempt_id: 'foreign-run'},
    {...original, ignored: 'x'.repeat(4096)},
    {...original, key_id: 'not-a-cid'},
    {...original, request_cid: [original.request_cid]},
    {...original, abandoned: null},
    {...original, holdings: [{...held, name: '\ud800'}]},
    {...original, holdings: [{...held, state: 'completed'}]},
    {...original, holdings: [{...held, extra: true}]},
  ]) {
    await writeFile(path, JSON.stringify(body));
    await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 8192, maxLedgerEntries: 1}), {code: 'InvalidContinuationLedger'});
  }
});

test('bounded continuation metadata preserves retirement and raw Unicode cleanup data without a grant', async t => {
  const body = {...JSON.parse(text), abandoned: true,
    holdings: [{...held, state: 'retiring', cleanup_error: 'e\u0301\r\nclose pending'}]};
  const {path} = await fixture(t, JSON.stringify(body));
  const value = await readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: 1024, maxLedgerEntries: 1});
  assert.deepEqual(value, body);
  assert.equal(value.holdings[0].cleanup_error, 'e\u0301\r\nclose pending');
});

test('bounded continuation metadata invalid UTF8 JSON nonregular symlink and missing files stay distinct', async t => {
  const {path, directory} = await fixture(t);
  for (const content of [Buffer.from([0xff]), Buffer.from('{broken'), Buffer.from('\ufeff' + text)]) {
    await writeFile(path, content);
    await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 276, maxLedgerEntries: 0}), {code: 'InvalidContinuationLedger'});
  }
  await writeFile(path, text);
  const link = join(directory, 'link');
  await symlink(path, link);
  await assert.rejects(readContinuationLedgerBounded(link, 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), {code: 'ELOOP'});
  const folder = join(directory, 'folder');
  await mkdir(folder);
  await assert.rejects(readContinuationLedgerBounded(folder, 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), {code: 'InvalidPublicationStoreObject'});
  await assert.rejects(readContinuationLedgerBounded(join(directory, 'absent'), 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), error =>
    error.code === 'ContinuationMetadataUnavailable' && error.cause.code === 'ENOENT');
});

test('bounded continuation metadata captures supplied bounds before await and counts retired entries', async t => {
  const body = {...JSON.parse(text), holdings: [{...held, state: 'retired'}]};
  const {path} = await fixture(t, JSON.stringify(body));
  const limits = {maxWireBytes: 1024, maxLedgerEntries: 0};
  const pending = readContinuationLedgerBounded(path, 'original-run', limits);
  limits.maxWireBytes = 8192;
  limits.maxLedgerEntries = 1;
  await assert.rejects(pending, {code: 'ContinuationLedgerEntriesLimit'});
});

test('bounded continuation metadata pre-abort preserves original reason without missing-ledger inference', async () => {
  const abort = new AbortController();
  const reason = Object.assign(new Error('OriginalScopeCancelled'), {code: 'ENOENT'});
  abort.abort(reason);
  await assert.rejects(readContinuationLedgerBounded('/not-an-original-path', 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}, abort.signal), error => error === reason);
  await assert.rejects(readContinuationLedgerBounded('/not-an-original-path', 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}, {aborted: false}),
    {code: 'InvalidPublicationMetadataSignal'});
});

test('bounded continuation metadata retains the same failed original FD until cleanup retry', async t => {
  const {path} = await fixture(t);
  const openOriginal = fs.open;
  let original, close, attempts = 0;
  let rejectClose = true;
  const primary = Object.assign(new Error('OriginalContinuationMetadataClosePending'), {code: 'EIO'});
  t.after(async () => {
    fs.open = openOriginal; syncBuiltinESMExports();
    rejectClose = false;
    if (primary.cleanupHandle?.status().pending) await primary.cleanupHandle.retry();
    else if (original?.fd >= 0) await Reflect.apply(close, original, []);
  });
  // Install the fault before the reader captures its original close, not
  // later from stat after that acquisition/capture boundary has passed.
  fs.open = async function(originalPath, ...args) {
    const handle = await Reflect.apply(openOriginal, this, [originalPath, ...args]);
    if (originalPath === path && original === undefined) {
      original = handle;
      close = handle.close;
      handle.close = async function() {
        attempts++;
        if (rejectClose) throw primary;
        await Reflect.apply(close, this, []);
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), error => error === primary);
  fs.open = openOriginal; syncBuiltinESMExports();
  assert(original.fd >= 0);
  assert.equal(attempts, 1);
  const cleanup = primary.cleanupHandle;
  assert.equal(cleanup.status().pending, true);
  const flight = cleanup.retry();
  assert.strictEqual(cleanup.retry(), flight);
  await assert.rejects(flight, error => error === primary);
  assert.equal(attempts, 2);
  assert.equal(cleanup.status().pending, true);
  // Retry the original FD, never replace a failed read from another pathname.
  await rm(path);
  await writeFile(path, 'replacement');
  rejectClose = false;
  assert.equal((await cleanup.retry()).pending, false);
  assert.equal(original.fd, -1);
  assert.equal(attempts, 3);
  await cleanup.retry();
  assert.equal(attempts, 3);
});

// Hook only the original reader's real FileHandle. No substitute pathname
// read, Store issuer, Ledger, publication or permission is supplied here.
async function interruptedReader(t, {failedClose = false, readFailure = false, closeAbort = false} = {}) {
  const {path} = await fixture(t);
  const openOriginal = fs.open;
  const abort = new AbortController();
  const primary = new Error(readFailure ? 'OriginalMetadataReadFailed' : 'OriginalScopeCancelled');
  if (failedClose && !readFailure) Object.freeze(primary);
  const closeFailure = new Error('OriginalFdClosePending');
  let original, close, failure, reads = 0, closes = 0, released = 0;
  let rejectClose = failedClose;
  t.after(async () => {
    fs.open = openOriginal; syncBuiltinESMExports();
    rejectClose = false;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    else if (original?.fd >= 0) await Reflect.apply(close, original, []);
  });
  fs.open = async function(originalPath, ...args) {
    const handle = await Reflect.apply(openOriginal, this, [originalPath, ...args]);
    if (originalPath === path && original === undefined) {
      original = handle;
      const read = handle.read;
      close = handle.close;
      handle.read = async function(bytes, offset, length, position) {
        reads++;
        if (readFailure && reads === 2) throw primary;
        const result = await Reflect.apply(read, this,
          [bytes, offset, readFailure ? Math.min(1, length) : length, position]);
        if (!readFailure && !closeAbort && result.bytesRead > 0) abort.abort(primary);
        return result;
      };
      handle.close = async function() {
        closes++;
        if (closeAbort) abort.abort(primary);
        if (rejectClose) throw closeFailure;
        await Reflect.apply(close, this, []);
        released++;
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    await readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 273, maxLedgerEntries: 0}, abort.signal);
    assert.fail('An interrupted read must not return parsed metadata');
  } catch (error) { failure = error; }
  fs.open = openOriginal; syncBuiltinESMExports();
  return {path, original, failure, primary, closeFailure,
    counts: () => ({reads, closes, released}),
    allowClose: () => { rejectClose = false; }};
}

test('bounded continuation metadata cancellation after real positive I/O closes the original FD without another read', async t => {
  const f = await interruptedReader(t);
  assert.strictEqual(f.failure, f.primary);
  assert.deepEqual(f.counts(), {reads: 1, closes: 1, released: 1});
  assert.equal(f.original.fd, -1);
  assert.equal(f.failure.cleanupHandle, undefined);
});

test('bounded continuation metadata frozen cancellation and failed close keep the same cleanup custody', async t => {
  const f = await interruptedReader(t, {failedClose: true});
  assert.strictEqual(f.failure.cause, f.primary);
  assert.strictEqual(f.failure.cleanupError, f.closeFailure);
  assert.equal(f.failure.cleanupPending, true);
  assert.deepEqual(f.counts(), {reads: 1, closes: 1, released: 0});
  assert(f.original.fd >= 0);
  const cleanup = f.failure.cleanupHandle;
  const flight = cleanup.retry();
  assert.strictEqual(cleanup.retry(), flight);
  await assert.rejects(flight, error => error === f.closeFailure);
  assert.equal(cleanup.status().pending, true);
  await rm(f.path);
  await writeFile(f.path, 'not the original metadata');
  f.allowClose();
  assert.equal((await cleanup.retry()).pending, false);
  assert.equal(f.original.fd, -1);
  assert.deepEqual(f.counts(), {reads: 1, closes: 3, released: 1});
  await cleanup.retry();
  assert.deepEqual(f.counts(), {reads: 1, closes: 3, released: 1});
});

test('bounded continuation metadata mid-read failure preserves primary and original FD pending close', async t => {
  const f = await interruptedReader(t, {readFailure: true, failedClose: true});
  assert.strictEqual(f.failure, f.primary);
  assert.strictEqual(f.failure.cleanupError, f.closeFailure);
  assert.deepEqual(f.counts(), {reads: 2, closes: 1, released: 0});
  assert(f.original.fd >= 0);
  f.allowClose();
  assert.equal((await f.failure.cleanupHandle.retry()).pending, false);
  assert.equal(f.original.fd, -1);
  assert.deepEqual(f.counts(), {reads: 2, closes: 2, released: 1});
});

test('bounded continuation metadata cancellation during successful close precedes UTF8 parse', async t => {
  const f = await interruptedReader(t, {closeAbort: true});
  assert.strictEqual(f.failure, f.primary);
  assert.equal(f.original.fd, -1);
  assert.deepEqual(f.counts(), {reads: 2, closes: 1, released: 1});
});
