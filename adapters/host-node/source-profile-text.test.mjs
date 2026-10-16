import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {readBoundedConfigurationText, readSourceProfileJson} from './source-profile-json.mjs';

function bytesSource(bytes, {virtualBytes = bytes.length, failClose = false} = {}) {
  let position = 0;
  const state = {reads: 0, bytes: 0, opens: 0, closes: 0, allowClose: !failClose};
  state.openFile = async () => {
    state.opens++;
    return {
      async read(buffer, offset, length) {
        state.reads++;
        const count = Math.min(length, virtualBytes - position);
        buffer.fill(0x20, offset, offset + count);
        if (position < bytes.length) {
          bytes.copy(buffer, offset, position, Math.min(position + count, bytes.length));
        }
        position += count;
        state.bytes += count;
        return {bytesRead: count};
      },
      async close() { state.closes++; if (!state.allowClose) return false; },
    };
  };
  return state;
}

test('bounded publication text preserves exact UTF-8, whitespace, order and identity above JSON ceiling', async () => {
  const prefix = ' {"z":"e\u0301","a":1.00}  \n';
  const original = prefix + ' '.repeat(16_000_000 - Buffer.byteLength(prefix));
  const bytes = Buffer.from(original);
  assert.equal(bytes.length, 16_000_000);
  const source = bytesSource(bytes);
  const actual = await readBoundedConfigurationText('/publication',
    {maxBytes: 16_000_000, openFile: source.openFile});
  assert.equal(actual, original);
  assert.equal(createHash('sha256').update(actual, 'utf8').digest('hex'),
    createHash('sha256').update(bytes).digest('hex'));
  assert.equal(source.bytes, bytes.length);
  assert.equal(source.closes, 1);
  const notOpened = bytesSource(bytes);
  await assert.rejects(readSourceProfileJson('/publication',
    {maxBytes: 16_000_000, openFile: notOpened.openFile}),
  {message: 'InvalidInstalledSourceProfileByteLimit'});
  assert.equal(notOpened.opens, 0);
});

test('publication text exact limit and growth lookahead retain its declared ceiling', async () => {
  for (const length of [0, 8, 9, 2 ** 40]) {
    const source = bytesSource(Buffer.from('x'), {virtualBytes: length});
    const reading = readBoundedConfigurationText('/publication',
      {maxBytes: 8, openFile: source.openFile});
    if (length <= 8) assert.equal((await reading).length, length);
    else await assert.rejects(reading, {message: 'InvalidInstalledSourceProfile'});
    assert.equal(source.bytes, Math.min(length, 9));
    assert.equal(source.closes, 1);
  }
});

test('publication text requires an explicit finite ceiling before acquisition', async () => {
  const source = bytesSource(Buffer.from('{}'));
  for (const maxBytes of [undefined, null, -1, 1.5, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(readBoundedConfigurationText('/publication',
      {maxBytes, openFile: source.openFile}),
    {message: 'InvalidInstalledSourceProfileByteLimit'});
  }
  assert.equal(source.opens, 0);
});

test('publication text close failure returns no text and retries without rereading', async () => {
  const source = bytesSource(Buffer.from(' {"x":1.00}\n'), {failClose: true});
  let failure;
  await assert.rejects(readBoundedConfigurationText('/publication',
    {maxBytes: 100, openFile: source.openFile}), error => {
    failure = error;
    assert.equal(error.cleanupPending, true);
    return true;
  });
  const reads = source.reads;
  source.allowClose = true;
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupPending, false);
  assert.equal(source.reads, reads);
  assert.equal(source.opens, 1);
});
