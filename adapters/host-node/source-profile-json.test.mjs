import assert from 'node:assert/strict';
import {appendFile, mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {readSourceProfileJson, readBoundedConfigurationText, captureConfigurationReaders} from './source-profile-json.mjs';

function source(bytes, {step = Infinity, readFailure, closeFailure,
  virtualBytes = bytes.length} = {}) {
  let position = 0;
  const observed = {opens: 0, closes: 0, bytes: 0, reads: 0, buffers: new Set()};
  observed.openFile = async (path, flags) => {
    assert.equal(path, '/profile.json');
    assert.equal(flags, 'r');
    observed.opens++;
    return {
      async read(buffer, offset, length, at) {
        assert.equal(at, null);
        observed.reads++;
        observed.buffers.add(buffer);
        if (readFailure && position >= 2) throw readFailure;
        const count = Math.min(length, step, virtualBytes - position);
        buffer.fill(0x20, offset, offset + count);
        if (position < bytes.length) {
          bytes.copy(buffer, offset, position, Math.min(bytes.length, position + count));
        }
        position += count;
        observed.bytes += count;
        return {bytesRead: count};
      },
      async close() {
        observed.closes++;
        if (closeFailure) throw closeFailure;
      },
    };
  };
  return observed;
}

for (const [name, length] of [['below', 15], ['exactly', 16]]) {
  test(`Source profile reader accepts valid JSON ${name} its byte limit`, async () => {
    const observed = source(Buffer.from('{"x":"é"}'.padEnd(length - 1)), {step: 1});
    assert.equal(observed.bytes, 0);
    assert.deepEqual(await readSourceProfileJson('/profile.json',
      {maxBytes: 16, openFile: observed.openFile}), {x: 'é'});
    assert.equal(observed.bytes, length);
    assert.equal(observed.opens, 1);
    assert.equal(observed.closes, 1);
    assert.equal(observed.buffers.size, 1, 'short reads fill the same bounded chunk');
  });
}

for (const [name, virtualBytes] of [['one byte over', 17], ['huge', 2 ** 40]]) {
  test(`Source profile reader rejects ${name} without reading or parsing a truncated prefix`, async () => {
    const observed = source(Buffer.from('{}'), {step: 3, virtualBytes});
    await assert.rejects(readSourceProfileJson('/profile.json',
      {maxBytes: 16, openFile: observed.openFile}),
    {name: 'TypeError', message: 'InvalidInstalledSourceProfile'});
    assert.equal(observed.bytes, 17);
    assert.equal(observed.opens, 1);
    assert.equal(observed.closes, 1);
    assert.equal(observed.buffers.size, 1);
  });
}

test('Source profile reader joins UTF-8 across bounded chunks', async () => {
  const value = ' '.repeat(65529) + '😀é';
  const bytes = Buffer.from(JSON.stringify({x: value}));
  const observed = source(bytes, {step: 11});
  assert.deepEqual(await readSourceProfileJson('/profile.json',
    {maxBytes: bytes.length, openFile: observed.openFile}), {x: value});
  assert.equal(observed.bytes, bytes.length);
  assert.equal(observed.buffers.size, 2);
  assert.equal(observed.closes, 1);
});

for (const [name, bytes] of [['empty', ''], ['malformed', '{"x":']]) {
  test(`Source profile reader preserves ${name} JSON failure and closes`, async () => {
    const observed = source(Buffer.from(bytes));
    await assert.rejects(readSourceProfileJson('/profile.json',
      {maxBytes: 16, openFile: observed.openFile}), SyntaxError);
    assert.equal(observed.closes, 1);
  });
}

test('Source profile reader preserves a partial read error and can retry', async () => {
  const error = Object.assign(new Error('fixture read failed'), {code: 'EIO'});
  const observed = source(Buffer.from('{"x":1}'), {step: 2, readFailure: error});
  await assert.rejects(readSourceProfileJson('/profile.json',
    {maxBytes: 16, openFile: observed.openFile}), value => value === error);
  assert.equal(observed.bytes, 2);
  assert.equal(observed.closes, 1);
  const retry = source(Buffer.from('{"x":1}'));
  assert.deepEqual(await readSourceProfileJson('/profile.json',
    {maxBytes: 16, openFile: retry.openFile}), {x: 1});
  assert.equal(retry.closes, 1);
});

test('Source profile reader retains both read and close failures', async () => {
  const readFailure = new Error('fixture read failed');
  const closeFailure = new Error('fixture close failed');
  const observed = source(Buffer.from('{"x":1}'),
    {step: 2, readFailure, closeFailure});
  await assert.rejects(readSourceProfileJson('/profile.json',
    {maxBytes: 16, openFile: observed.openFile}), error => {
    assert.equal(error.cause, readFailure);
    assert.deepEqual(error.errors, [readFailure, closeFailure]);
    return true;
  });
  assert.equal(observed.closes, 1);
  const successfulRead = source(Buffer.from('{}'), {closeFailure});
  await assert.rejects(readSourceProfileJson('/profile.json',
    {maxBytes: 16, openFile: successfulRead.openFile}), error => error === closeFailure);
  assert.equal(successfulRead.closes, 1);
});

test('Source profile reader preserves open failures without an acquired handle', async () => {
  const cause = Object.assign(new Error('fixture missing'), {code: 'ENOENT'});
  await assert.rejects(readSourceProfileJson('/profile.json',
    {openFile: async () => { throw cause; }}), error => error === cause);
});

test('Source profile reader bounds growth on the same real handle and releases it', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-profile-growth-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'profile.json');
  await writeFile(path, '{}');
  let handle, opens = 0, closes = 0, bytes = 0;
  const openFile = async (name, flags) => {
    handle = await open(name, flags);
    opens++;
    assert.equal((await handle.stat()).size, 2);
    return {
      async read(buffer, offset, length, position) {
        const result = await handle.read(buffer, offset, Math.min(length, 2), position);
        bytes += result.bytesRead;
        if (bytes === 2) await appendFile(path, ' '.repeat(100));
        return result;
      },
      async close() { closes++; await handle.close(); },
    };
  };
  await assert.rejects(readSourceProfileJson(path, {maxBytes: 16, openFile}),
    {message: 'InvalidInstalledSourceProfile'});
  assert.equal(bytes, 17);
  assert.equal(opens, 1);
  assert.equal(closes, 1);
  await assert.rejects(handle.stat(), {code: 'EBADF'});
  await writeFile(path, '{"retry":true}');
  assert.deepEqual(await readSourceProfileJson(path, {maxBytes: 16}), {retry: true});
});


test('configuration reader selection retains original methods receiver and pending error without I/O', async () => {
  const error = Object.assign(new Error('same pending read'), {cleanupPending: true});
  const reader = {readJson(value) {assert.equal(this, reader); return value;},
    readText() {assert.equal(this, reader); throw error;}};
  const selected = captureConfigurationReaders(reader, undefined, () => assert.fail('valid original'));
  reader.readJson = reader.readText = () => assert.fail('replaced method');
  assert.equal(selected.readJson('original'), 'original');
  assert.throws(() => selected.readText(), cause => cause === error);
  assert(Object.isFrozen(selected));
  const legacy = captureConfigurationReaders(undefined, undefined, () => assert.fail('legacy omission'));
  assert.equal(legacy.readJson, readSourceProfileJson); assert.equal(legacy.readText, readBoundedConfigurationText);
});

test('configuration reader selection refuses proxies accessors and incomplete originals without invoking them', () => {
  const error = new Error('connector-specific refusal'), reject = () => {throw error;};
  const accessor = {readJson() {assert.fail('read');}};
  Object.defineProperty(accessor, 'readText', {get() {assert.fail('getter');}});
  for (const reader of [null, [], {}, accessor, new Proxy({}, {getOwnPropertyDescriptor() {assert.fail('proxy trap');}})])
    assert.throws(() => captureConfigurationReaders(reader, undefined, reject), cause => cause === error);
  assert.throws(() => captureConfigurationReaders(undefined, 1, reject), cause => cause === error);
  assert.throws(() => captureConfigurationReaders({}, undefined, () => {}), TypeError);
});
