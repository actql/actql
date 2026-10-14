// Actual consumeObject body and OS FD. Store/Run authority is not issued here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdtemp, writeFile, open, rm} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {join} from 'node:path';
import {tmpdir} from 'node:os';

const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  const consumeObject = async (');
const end = source.indexOf('\n  const withCommittedResult = async (', start);
assert.ok(start >= 0 && end > start);
const body = source.slice(start, end);

async function exercise(t, {original = 'abcd', changed, injected} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-object-read-extent-'));
  const path = join(directory, 'original');
  await writeFile(path, original);
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let stats = 0, streams = 0, passed = false;
  const accepted = [], allocations = [];
  const slow = Buffer.allocUnsafeSlow;
  Buffer.allocUnsafeSlow = function(length) {
    const bytes = Reflect.apply(slow, Buffer, [length]);
    if (new Error().stack.includes('internal/fs/streams')) allocations.push(length);
    return bytes;
  };
  const restore = () => { Buffer.allocUnsafeSlow = slow; };
  t.after(async () => {
    restore();
    if (handle.fd >= 0) await handle.close();
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved object read extent failure: ${directory}`);
  });
  const consume = runInNewContext(`(() => {${body} return consumeObject;})()`, {
    constants, createHash, configuration: {maxObjectBytes: 16384},
    active() {}, quantity: n => Number.isSafeInteger(n) && n >= 0,
    fail(code) { throw Object.assign(new Error(code), {code}); },
    objectPath: () => path, cidHex: () => createHash('sha256').update(original).digest('hex'),
    async open() {
      return {
        async stat() {
          const result = await handle.stat();
          if (stats++ === 0 && changed !== undefined) await writeFile(path, changed);
          return result;
        },
        createReadStream(options) {
          streams++;
          if (injected !== undefined) return (async function*() { yield injected; })();
          return handle.createReadStream(options);
        },
        close: () => handle.close(),
      };
    },
  });
  let result, failure;
  try {
    result = await consume('original', bytes => { accepted.push(Buffer.from(bytes)); });
  } catch (error) { failure = error; }
  finally { restore(); }
  assert.equal(handle.fd, -1, 'same actual FD closes on both success and refusal');
  const received = Buffer.concat(accepted);
  return {result, failure, received, allocations, streams, stats,
    pass() {
      t.diagnostic(JSON.stringify({expectedBytes: Buffer.byteLength(original),
        receivedBytes: received.length, allocations, streams,
        qualification: injected === undefined ? 'Actual original FD and ReadStream' : 'Actual FD, injected oversize stream',
        normalNumericProfile: null, publicE2E: 0}));
      passed = true;
    }};
}

test('small fixed object read allocates no default64KiB backing before accept', async t => {
  const f = await exercise(t);
  assert.equal(f.failure, undefined);
  assert.equal(f.result.bytes, 4);
  assert.equal(f.received.toString(), 'abcd');
  assert.ok(f.allocations.length > 0, 'observe the actual stream allocator');
  assert.ok(f.allocations.every(n => n <= 4), 'original four-byte envelope precedes allocation');
  f.pass();
});

test('actual FD growth after stat cannot deliver tail bytes before version refusal', async t => {
  const f = await exercise(t, {changed: 'abcdefghijklmnop'});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.toString(), 'abcd');
  assert.ok(f.allocations.every(n => n <= 4));
  f.pass();
});

test('empty object skips the stream but retains original stat hash and FD close', async t => {
  const f = await exercise(t, {original: ''});
  assert.equal(f.failure, undefined);
  assert.equal(f.result.bytes, 0);
  assert.equal(f.received.length, 0);
  assert.equal(f.streams, 0);
  assert.equal(f.stats, 2);
  assert.deepEqual(f.allocations, []);
  f.pass();
});

test('truncated original object remains corrupt within its admitted read extent', async t => {
  const f = await exercise(t, {changed: 'ab'});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.toString(), 'ab');
  assert.ok(f.allocations.every(n => n <= 4));
  f.pass();
});

test('oversize stream chunk is refused before the consumer callback', async t => {
  const f = await exercise(t, {injected: Buffer.from('abcdef')});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.length, 0);
  f.pass();
});
