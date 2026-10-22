// Actual Store/FD/process boundaries; contract admission is the explicit test
// control. No genuine Core admission, existing Run, Provider or grant is used.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const configuration = directory => ({directory,
  storeAuthorityCid: cid('prepared custody publication authority'), capacityBytes: 65536,
  maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32});
const openStore = directory => openLocalPublicationStore(configuration(directory),
  createPublicationContractControlFixture());
const syncDirectory = async path => {
  const handle = await fs.open(path, 'r');
  try { await handle.sync(); }
  finally { await handle.close(); }
};
async function scratchFor(label) {
  return createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'prepared-custody-atomic-', label});
}

for (const mode of ['empty', 'partial']) {
  test(`interrupted ${mode} original custody metadata never occupies a final record`, async t => {
    const scratch = await scratchFor('original prepared custody interrupted publication');
    const directory = join(scratch.path, 'store');
    const child = spawn(process.execPath, [new URL('./fixtures/prepared-custody-interrupted.fixture.mjs',
      import.meta.url).pathname, directory, mode], {stdio: ['ignore', 'pipe', 'pipe']});
    const stdout = [], stderr = [];
    child.stdout.on('data', bytes => stdout.push(bytes));
    child.stderr.on('data', bytes => stderr.push(bytes));
    const [code, signal] = await once(child, 'close');
    assert.equal(signal, null);
    assert.equal(code, 77, Buffer.concat(stderr).toString('utf8'));
    const observation = JSON.parse(Buffer.concat(stdout).toString('utf8'));
    assert.equal(observation.boundary, 'original-custody-record-write');
    const original = await fs.readFile(observation.path);
    assert.deepEqual(original, mode === 'empty' ? Buffer.alloc(0) : Buffer.from('{"version":'));
    assert.deepEqual(await fs.readdir(join(directory, 'prepared-custody')), [],
      'Final recovery names must contain complete synced original records only');
    const store = await openStore(directory);
    t.after(async () => { if (!store.status().closed) await store.close(); });
    assert.deepEqual(await fs.readdir(join(directory, 'staging')), []);
    assert.deepEqual(await fs.readdir(join(directory, 'objects')), []);
    assert.equal(store.status().storedBytes, 0);
    await store.close();
    scratch.passed();
  });
}

test('healthy simultaneous prepared writers retain distinct exact original custody records', async t => {
  const scratch = await scratchFor('parallel original prepared custody');
  const directory = join(scratch.path, 'store'), store = await openStore(directory);
  let stored = [];
  t.after(async () => {
    for (const value of stored) await value.prepared.release();
    if (!store.status().closed) await store.close();
  });
  const payloads = ['original first', 'original second'];
  const writers = payloads.map(bytes => store.createPreparedObjectWriter(Buffer.byteLength(bytes)));
  await Promise.all(writers.map((writer, i) => writer.append(payloads[i])));
  stored = await Promise.all(writers.map((writer, i) => writer.seal(cid(payloads[i]))));
  const paths = await fs.readdir(join(directory, 'prepared-custody'));
  assert.equal(paths.length, 2);
  const records = await Promise.all(paths.map(async name => JSON.parse(
    await fs.readFile(join(directory, 'prepared-custody', name), 'utf8'))));
  assert.deepEqual(records.map(value => value.material_generation_cid).sort(), payloads.map(cid).sort());
  assert.equal(store.status().storedBytes, payloads.reduce((n, value) => n + Buffer.byteLength(value), 0));
  for (const value of stored) await value.prepared.release();
  assert.equal(store.status().storedBytes, 0);
  await store.close();
  scratch.passed();
});

for (const mode of ['false', 'rejected']) {
  test(`original prepared custody retains its ${mode}-close FD and close-only retry`, async () => {
    const scratch = await scratchFor('original prepared custody failed-close publication');
    const directory = join(scratch.path, 'store'), store = await openStore(directory);
    const bytes = Buffer.from('original prepared bytes\n');
    const writer = store.createPreparedObjectWriter(bytes.length);
    await writer.append(bytes);
    const originalOpen = fs.open;
    const primary = Object.freeze(Object.assign(new Error('Original custody FD close failure'), {code:'EIO'}));
    let refusing = true, closes = 0, writes = 0, fd, failure, escaped, originalClose;
    fs.open = async (...args) => {
      const handle = await originalOpen(...args);
      const write = handle.write.bind(handle), close = handle.close.bind(handle);
      let custody = false;
      handle.write = async (...values) => {
        if (Buffer.isBuffer(values[0]) && values[0].toString('utf8').startsWith(
          '{"version":"actql-local-prepared-custody/0.1"')) {
          custody = true;
          assert.equal(fd ??= handle.fd, handle.fd);
          originalClose = () => handle.fd < 0 ? undefined : close();
          writes++;
        }
        return write(...values);
      };
      handle.close = async () => {
        if (custody) {
          assert.equal(handle.fd, fd);
          closes++;
          if (refusing) {
            if (mode === 'false') return false;
            throw primary;
          }
        }
        return close();
      };
      return handle;
    };
    syncBuiltinESMExports();
    try {
      await assert.rejects(writer.seal(cid(bytes)).then(value => { escaped = value; return value; }), error => {
        failure = error;
        return error.code === 'PublicationStoreCleanupPending';
      });
      assert.equal(failure.cleanupHandle.status().pending, true);
      if (mode === 'rejected') assert.equal(failure.primaryFailure, primary);
      assert.deepEqual(await fs.readdir(join(directory, 'prepared-custody')), []);
      assert.equal(writes, 1);
      await assert.rejects(store.close(), {code:'PublicationStoreCleanupPending'});
      assert.equal(store.status().closed, false);
      refusing = false;
      if (mode === 'false') {
        await store.close();
        assert.equal(failure.cleanupHandle.status().pending, false);
      } else {
        const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
        assert.equal(first, second);
        assert.equal((await first).pending, false);
      }
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(writes, 1, 'FD cleanup cannot repeat custody writes or seal again');
      assert.ok(closes >= 3);
      assert.equal(store.status().storedBytes, 0);
      assert.deepEqual(await fs.readdir(join(directory, 'staging')), []);
      await store.close();
      scratch.passed();
    } finally {
      refusing = false;
      fs.open = originalOpen;
      syncBuiltinESMExports();
      if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
      await originalClose?.();
      if (escaped?.prepared.status().pending) await escaped.prepared.release();
      await writer.cancel();
      if (!store.status().closed) await store.close();
    }
  });
}

test('an already corrupt final custody record is not deleted or reinterpreted as absent', async () => {
  const scratch = await scratchFor('existing corrupt original custody refusal');
  const directory = join(scratch.path, 'store'), store = await openStore(directory);
  await store.close();
  const path = join(directory, 'prepared-custody', '00000000-0000-4000-8000-000000000000.json');
  await fs.writeFile(path, Buffer.alloc(0), {flag:'wx',mode:0o600});
  const before = await fs.lstat(path);
  await assert.rejects(openStore(directory), {code:'InvalidPublicationPreparedCustody'});
  const after = await fs.lstat(path);
  assert.equal(after.ino, before.ino);
  assert.deepEqual(await fs.readFile(path), Buffer.alloc(0));
  scratch.passed();
});

test('prepared custody acknowledges its final name without a redundant staging directory ACK', async () => {
  const scratch = await scratchFor('prepared custody final name acknowledgement');
  const directory = join(scratch.path, 'store'), observed = [];
  const store = await openLocalPublicationStore(configuration(directory),
    createPublicationContractControlFixture(), {syncDirectory: async path => {
      observed.push(path);
      await syncDirectory(path);
    }});
  let stored;
  try {
    const payload = Buffer.from('bounded prepared payload');
    const writer = store.createPreparedObjectWriter(payload.length);
    await writer.append(payload);
    observed.length = 0;
    stored = await writer.seal(cid(payload));
    assert.deepEqual(observed, [join(directory, 'prepared-custody'), join(directory, 'objects')],
      'The real custody-name ACK precedes installation; a temporary alias adds no durable object');
    const names = await fs.readdir(join(directory, 'prepared-custody'));
    assert.equal(names.length, 1);
    const record = JSON.parse(await fs.readFile(join(directory, 'prepared-custody', names[0]), 'utf8'));
    const state = await fs.lstat(join(directory, 'objects', cid(payload).slice(7)));
    assert.equal(record.device, String(state.dev));
    assert.equal(record.inode, String(state.ino));
    assert.equal(record.byte_count, payload.length);
    assert.deepEqual(await fs.readdir(join(directory, 'staging')), []);
    assert.deepEqual(await fs.readFile(join(directory, 'objects', cid(payload).slice(7))), payload);
    await stored.prepared.release();
    assert.equal(store.status().storedBytes, 0);
    await store.close();
    scratch.passed();
  } finally {
    if (stored?.prepared.status().pending) await stored.prepared.release();
    if (!store.status().closed) await store.close();
  }
});

test('failed final custody directory ACK cannot install the payload and remains recoverable', async () => {
  const scratch = await scratchFor('prepared custody final acknowledgement failure');
  const directory = join(scratch.path, 'store');
  const primary = Object.freeze(Object.assign(new Error('Original custody directory ACK failure'), {code: 'EIO'}));
  let refusing = false, escaped, writer;
  const store = await openLocalPublicationStore(configuration(directory),
    createPublicationContractControlFixture(), {syncDirectory: async path => {
      if (refusing && path === join(directory, 'prepared-custody')) throw primary;
      await syncDirectory(path);
    }});
  try {
    writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    refusing = true;
    await assert.rejects(writer.seal(cid('payload')).then(value => { escaped = value; }),
      error => error === primary);
    assert.equal(escaped, undefined);
    assert.deepEqual(await fs.readdir(join(directory, 'objects')), []);
    assert.deepEqual(await fs.readdir(join(directory, 'staging')), []);
    assert.equal(store.status().storedBytes, 0);
    await writer.cancel();
    refusing = false;
    await store.close();
    const reopened = await openStore(directory);
    try {
      await reopened.recoverPreparedCustodies();
      assert.deepEqual(await fs.readdir(join(directory, 'prepared-custody')), []);
      assert.equal(reopened.status().storedBytes, 0);
    } finally { await reopened.close(); }
    scratch.passed();
  } finally {
    refusing = false;
    await writer?.cancel();
    if (!store.status().closed) await store.close();
  }
});

test('a final-ACKed custody retains the same failed temporary unlink without repeating its ACK', async () => {
  const scratch = await scratchFor('prepared custody original temporary unlink duty');
  const directory = join(scratch.path, 'store'), originalLink = fs.link, originalUnlink = fs.unlink;
  let temporary, refusing = true, custodyAcks = 0, failure, writer;
  const primary = Object.freeze(Object.assign(new Error('Original temporary unlink failure'), {code: 'EIO'}));
  const store = await openLocalPublicationStore(configuration(directory),
    createPublicationContractControlFixture(), {syncDirectory: async path => {
      await syncDirectory(path);
      if (path === join(directory, 'prepared-custody')) custodyAcks++;
    }});
  fs.link = async (source, target) => {
    if (target.startsWith(join(directory, 'prepared-custody') + '/')) temporary = source;
    return originalLink(source, target);
  };
  fs.unlink = async path => {
    if (refusing && path === temporary) throw primary;
    return originalUnlink(path);
  };
  syncBuiltinESMExports();
  try {
    custodyAcks = 0;
    writer = store.createPreparedObjectWriter(7);
    await writer.append('payload');
    await assert.rejects(writer.seal(cid('payload')), error => {
      failure = error;
      return error.code === 'PublicationStoreCleanupPending';
    });
    assert.equal(failure.primaryFailure, primary);
    assert.equal(custodyAcks, 1, 'Final metadata custody was really acknowledged before temporary retirement');
    const [name] = await fs.readdir(join(directory, 'prepared-custody'));
    const finalPath = join(directory, 'prepared-custody', name), before = await fs.lstat(finalPath);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    refusing = false;
    const first = failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.retry(), first);
    assert.equal((await first).pending, false);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(custodyAcks, 1, 'Cleanup reuses only the same already-held final-name ACK');
    const after = await fs.lstat(finalPath);
    assert.equal(after.dev, before.dev);
    assert.equal(after.ino, before.ino);
    assert.deepEqual(await fs.readdir(join(directory, 'staging')), []);
    await writer.cancel();
    await store.close();
    const reopened = await openStore(directory);
    try { await reopened.recoverPreparedCustodies(); }
    finally { await reopened.close(); }
    scratch.passed();
  } finally {
    refusing = false;
    fs.link = originalLink; fs.unlink = originalUnlink; syncBuiltinESMExports();
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    await writer?.cancel();
    if (!store.status().closed) await store.close();
  }
});
