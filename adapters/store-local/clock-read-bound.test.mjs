import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';

const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const original = JSON.parse(await readFile(new URL('./clock-read-original.fixture.json',
  import.meta.url), 'utf8'));
function section(from, to) {
  const start = source.indexOf(from), end = source.indexOf(to, start);
  assert(start >= 0 && end > start);
  return source.slice(start, end);
}
const bounded = section('async function readBounded(path, maximum, closed, signal, ownerOnly = false) {',
  '\nasync function processIsAlive(');
const keys = section('const exactKeys =', '\nasync function syncDirectoryPath(');
const current = section('  let lastClockObservation;', '\n  const observeTrustedClock =');
const clock = `sha256:${'c'.repeat(64)}`;
const time = '2026-10-12T00:00:00.000Z';
const wire = observedAt => Buffer.from(JSON.stringify({clockContractCid: clock, observedAt}));
const fail = code => { throw Object.assign(new Error(code), {code}); };
const invalid = error => error?.code === 'InvalidPublicationStoreObject';
function load(body, overrides) {
  return runInNewContext(`(() => {${keys}\n${bounded}\n${body}\nreturn readClockObservation;})()`, {
    constants, Buffer, fail, AbortSignal,
    quantity: value => Number.isSafeInteger(value) && value >= 0,
    configuration: {maxObjectBytes: 512},
    clockObservationPath: () => 'original-clock',
    contractControl: {trustedClockNotBefore: (_prior, value) => value === time},
    ...overrides,
  });
}
function fixture(body = current, options = {}) {
  let bytes = wire(time), tick = 1n, closes = 0, opens = 0, readFiles = 0;
  const allocations = [];
  const state = () => ({isFile: () => true, dev: 1n, ino: 2n,
    size: BigInt(bytes.length), mtimeNs: tick, ctimeNs: tick});
  const grow = () => { bytes = Buffer.concat([bytes, Buffer.alloc(256, 32)]); tick++; };
  const read = load(body, {
    async lstat() { return state(); },
    async open() {
      opens++;
      if (options.growth) grow();
      return {
        async stat() { return state(); },
        async read(output, offset, length, position) {
          const count = Math.min(length, Math.max(0, bytes.length - position));
          bytes.copy(output, offset, position, position + count);
          return {bytesRead: count};
        },
        async close() { closes++; if (options.closeError) throw options.closeError; },
      };
    },
    async readFile() {
      readFiles++;
      if (options.growth) grow();
      allocations.push(bytes.length);
      return Buffer.from(bytes);
    },
    Buffer: {allocUnsafeSlow(size) {
      allocations.push(size); return Buffer.allocUnsafeSlow(size);
    }},
  });
  return {read, allocations, counts: () => ({closes, opens, readFiles}),
    mutate(value) { bytes = wire(value); tick++; }};
}

test('clock read uses original exact-size allocation and preserves its cache', async () => {
  // Authored closed clock JSON is independently 134 ASCII bytes.
  assert.equal(wire(time).length, 134);
  const f = fixture();
  const first = await f.read(clock);
  assert.equal(first.clockContractCid, clock);
  assert.equal(first.observedAt, time);
  assert.strictEqual(await f.read(clock), first);
  assert.deepEqual(f.allocations, [134, 1]);
  assert.deepEqual(f.counts(), {closes: 1, opens: 1, readFiles: 0});
});

test('fixed clock baseline allocates growth before refusal; new reader refuses before allocation', async () => {
  assert.equal(original.source, '2e8fa9308f13de328a6e1eae43b9c16090f4c982');
  assert.equal(createHash('sha256').update(original.body).digest('hex'),
    '3b7a3b21cf31ccd6815260814ce99b3a6047f215ec7bb7e5884a44919d2c1b85');
  assert.equal(original.sha256, '3b7a3b21cf31ccd6815260814ce99b3a6047f215ec7bb7e5884a44919d2c1b85');
  const previous = fixture(original.body, {growth: true});
  await assert.rejects(previous.read(clock), error => error?.code === 'PublicationClockUncertain');
  assert.deepEqual(previous.allocations, [390]);
  const fixed = fixture(current, {growth: true});
  await assert.rejects(fixed.read(clock), invalid);
  assert.deepEqual(fixed.allocations, []);
  assert.deepEqual(fixed.counts(), {closes: 1, opens: 1, readFiles: 0});
});

test('clock cache never hides changed invalid bytes or failed close', async () => {
  const f = fixture();
  await f.read(clock);
  f.mutate('not-a-timestamp');
  await assert.rejects(f.read(clock), error => error?.code === 'InvalidPublicationClockObservation');
  f.mutate(time);
  assert.equal((await f.read(clock)).observedAt, time);
  assert.equal(f.counts().opens, 3);
  const pending = new Error('ClosePending');
  const p = fixture(current, {closeError: pending});
  await assert.rejects(p.read(clock), error => error === pending);
  assert.deepEqual(p.counts(), {closes: 1, opens: 1, readFiles: 0});
});

test('real clock FD enlargement refuses before allocating its output buffer', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-clock-bound-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'clock.json');
  await writeFile(path, wire(time));
  const allocations = [];
  let closes = 0;
  const read = load(current, {
    clockObservationPath: () => path, lstat,
    async open(...args) {
      // The original pathname stat already completed. Exercise an actual
      // enlarged FileHandle, not merely a stand-in bounded-reader callback.
      await writeFile(path, Buffer.concat([wire(time), Buffer.alloc(256, 32)]));
      const handle = await open(...args);
      return {
        stat: (...args) => handle.stat(...args),
        read: (...args) => handle.read(...args),
        async close() { closes++; await handle.close(); },
      };
    },
    readFile() { throw new Error('ClockMustNotUseReadFile'); },
    Buffer: {allocUnsafeSlow(size) { allocations.push(size); return Buffer.allocUnsafeSlow(size); }},
  });
  await assert.rejects(read(clock), invalid);
  assert.deepEqual(allocations, []);
  assert.equal(closes, 1);
});
