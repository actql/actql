import assert from 'node:assert/strict';
import {mkdtemp, mkdir, open, writeFile, symlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {readContinuationLedgerBounded} from './bounded-continuation-metadata.mjs';
import {readBoundedLocalMetadata} from '../store-local/publication-store.mjs';

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
  for (const content of [Buffer.from([0xff]), Buffer.from('{broken')]) {
    await writeFile(path, content);
    await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
      {maxWireBytes: 273, maxLedgerEntries: 0}), {code: 'InvalidContinuationLedger'});
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

test('bounded continuation metadata retains the same failed original FD until cleanup retry', async t => {
  const {path} = await fixture(t);
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe);
  const stat = prototype.stat;
  await probe.close();
  let original, close, attempts = 0;
  let rejectClose = true;
  const primary = Object.assign(new Error('OriginalContinuationMetadataClosePending'), {code: 'EIO'});
  t.after(async () => {
    prototype.stat = stat;
    rejectClose = false;
    if (primary.cleanupHandle?.status().pending) await primary.cleanupHandle.retry();
    else if (original?.fd >= 0) await Reflect.apply(close, original, []);
  });
  prototype.stat = function(...args) {
    if (new Error().stack.includes('at readBounded ') && original === undefined) {
      original = this;
      close = this.close;
      this.close = async function() {
        attempts++;
        if (rejectClose) throw primary;
        await Reflect.apply(close, this, []);
      };
    }
    return Reflect.apply(stat, this, args);
  };
  await assert.rejects(readContinuationLedgerBounded(path, 'original-run',
    {maxWireBytes: 273, maxLedgerEntries: 0}), error => error === primary);
  prototype.stat = stat;
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
