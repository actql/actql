import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import type {BigIntStats} from 'node:fs';
import fs, {lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {createPublicationTrustedClock} from './publication-trusted-clock.mjs';
import {exactKeys} from './publication-store-io.mjs';

type ClockOriginal = Readonly<{source: string; sha256: string; body: string}>;
type ClockValue = Readonly<{clockContractCid: string; observedAt: string}>;
type ClockState = Pick<BigIntStats, 'isFile' | 'dev' | 'ino' | 'size' | 'mtimeNs' | 'ctimeNs'>;
type ClockReadHandle = {
  stat(options: {bigint: true}): Promise<ClockState>;
  read(output: Buffer, offset: number, length: number, position: number): Promise<{bytesRead: number}>;
  close(): Promise<void>;
};
type ClockReadPorts = {
  lstat(path: string, options: {bigint: true}): Promise<ClockState>;
  open(path: string, flags: number): Promise<ClockReadHandle>;
  readFile(path: string): Promise<Buffer>;
};
type ClockFixtureOptions = Readonly<{historical?: boolean; growth?: boolean; closeError?: Error}>;
const original = JSON.parse(await readFile(new URL('./clock-read-original.fixture.json',
  import.meta.url), 'utf8')) as ClockOriginal;
const clock = `sha256:${'c'.repeat(64)}`;
const time = '2026-10-12T00:00:00.000Z';
const wire = (observedAt: string) => Buffer.from(JSON.stringify({clockContractCid: clock, observedAt}));
const code = (error: unknown) => (error as {code?: unknown} | null | undefined)?.code;
const invalid = (error: unknown) => code(error) === 'InvalidPublicationStoreObject';
const contractControl = {trustedClockNotBefore: (_prior: unknown, value: unknown) => value === time};
const configuration = {maxObjectBytes: 512};
const allocUnsafeSlow = Buffer.allocUnsafeSlow;

function selectedReader(directory: string, ports: ClockReadPorts, allocations: number[]) {
  const path = resolve(directory, `${clock.slice(7)}.json`);
  const owner = createPublicationTrustedClock(configuration, directory, contractControl,
    new Set(), () => {}, cid => { assert.equal(cid, clock); return cid.slice(7); },
    () => assert.fail('A read must not acknowledge a write'));
  return async (cid: string) => {
    const fsPorts = fs as unknown as ClockReadPorts;
    const originals = {lstat: fsPorts.lstat, open: fsPorts.open, readFile: fsPorts.readFile};
    function replace<A extends unknown[], R>(
      original: (file: string, ...args: A) => R, selected: (file: string, ...args: A) => R,
    ): (this: ClockReadPorts, file: string, ...args: A) => R {
      return function (file, ...args) {
        return file === path ? selected(file, ...args) : Reflect.apply(original, this, [file, ...args]);
      };
    }
    fsPorts.lstat = replace(originals.lstat, ports.lstat);
    fsPorts.open = replace(originals.open, ports.open);
    fsPorts.readFile = replace(originals.readFile, ports.readFile);
    Buffer.allocUnsafeSlow = size => {
      allocations.push(size);
      return allocUnsafeSlow(size);
    };
    syncBuiltinESMExports();
    try { return await owner.readClockObservation(cid); }
    finally {
      Buffer.allocUnsafeSlow = allocUnsafeSlow;
      Object.assign(fs, originals);
      syncBuiltinESMExports();
    }
  };
}

function historicalReader(ports: ClockReadPorts): (cid: string) => Promise<ClockValue | undefined> {
  // Replay only the fixed pre-migration fixture. Current reads use the actual owner.
  return runInNewContext(`(() => {${original.body}\nreturn readClockObservation;})()`, {
    exactKeys, configuration, contractControl,
    clockObservationPath: () => 'original-clock',
    fail(code: string) { throw Object.assign(new Error(code), {code}); },
    lstat: ports.lstat, readFile: ports.readFile,
  }) as (cid: string) => Promise<ClockValue | undefined>;
}

function fixture({historical = false, growth = false, closeError}: ClockFixtureOptions = {}) {
  let bytes = wire(time), tick = 1n, closes = 0, opens = 0, readFiles = 0;
  const allocations: number[] = [];
  const state = () => ({isFile: () => true, dev: 1n, ino: 2n,
    size: BigInt(bytes.length), mtimeNs: tick, ctimeNs: tick});
  const grow = () => { bytes = Buffer.concat([bytes, Buffer.alloc(256, 32)]); tick++; };
  const ports: ClockReadPorts = {
    async lstat() { return state(); },
    async open() {
      opens++;
      if (growth) grow();
      return {
        async stat() { return state(); },
        async read(output, offset, length, position) {
          const count = Math.min(length, Math.max(0, bytes.length - position));
          bytes.copy(output, offset, position, position + count);
          return {bytesRead: count};
        },
        async close() { closes++; if (closeError) throw closeError; },
      };
    },
    async readFile() {
      readFiles++;
      if (growth) grow();
      allocations.push(bytes.length);
      return Buffer.from(bytes);
    },
  };
  const read = historical ? historicalReader(ports) :
    selectedReader(join(tmpdir(), 'clock-read-fixture'), ports, allocations);
  return {read, allocations, counts: () => ({closes, opens, readFiles}),
    mutate(value: string) { bytes = wire(value); tick++; }};
}
test('clock read uses original exact-size allocation and preserves its cache', async () => {
  // Authored closed clock JSON is independently 134 ASCII bytes.
  assert.equal(wire(time).length, 134);
  const f = fixture();
  const first = await f.read(clock);
  assert.ok(first);
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
  const previous = fixture({historical: true, growth: true});
  await assert.rejects(previous.read(clock), error => code(error) === 'PublicationClockUncertain');
  assert.deepEqual(previous.allocations, [390]);
  const fixed = fixture({growth: true});
  await assert.rejects(fixed.read(clock), invalid);
  assert.deepEqual(fixed.allocations, []);
  assert.deepEqual(fixed.counts(), {closes: 1, opens: 1, readFiles: 0});
});

test('clock cache never hides changed invalid bytes or failed close', async () => {
  const f = fixture();
  await f.read(clock);
  f.mutate('not-a-timestamp');
  await assert.rejects(f.read(clock), error => code(error) === 'InvalidPublicationClockObservation');
  f.mutate(time);
  assert.equal((await f.read(clock))?.observedAt, time);
  assert.equal(f.counts().opens, 3);
  const pending = new Error('ClosePending');
  const p = fixture({closeError: pending});
  await assert.rejects(p.read(clock), error => error === pending);
  assert.deepEqual(p.counts(), {closes: 1, opens: 1, readFiles: 0});
});

test('real clock FD enlargement refuses before allocating its output buffer', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-clock-bound-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, `${clock.slice(7)}.json`);
  await writeFile(path, wire(time));
  const allocations: number[] = [];
  let closes = 0;
  // First acquire the actual pathname stat, then enlarge the selected original before FD stat.
  const actualOpen = open;
  const actualLstat = lstat;
  const read = selectedReader(directory, {
    lstat: (name, options) => actualLstat(name, options),
    async open(name, flags) {
      await writeFile(path, Buffer.concat([wire(time), Buffer.alloc(256, 32)]));
      const handle = await actualOpen(name, flags);
      return {
        stat: options => handle.stat(options),
        read: (output, offset, length, position) => handle.read(output, offset, length, position),
        async close() { closes++; await handle.close(); },
      };
    },
    async readFile() { throw new Error('ClockMustNotUseReadFile'); },
  }, allocations);
  await assert.rejects(read(clock), invalid);
  assert.deepEqual(allocations, []);
  assert.equal(closes, 1);
});
