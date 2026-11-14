// The numeric port below is a protocol double, not compiled Core ABI proof.
// Core's same-Ledger reservation/retirement is covered by its focused tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createAccountConstruction, readAccountOriginal, readAccountCurrent} from './account-construction.mjs';
import {readAccountConfiguration, observeInstalledAccount, sourceReadAccountConfiguration} from './local-account-config.mjs';

const ok = _0 => ({$tag: 1, _0});
const err = _0 => ({$tag: 0, _0});
function fixture(limit = 100000000000n) {
  const live = new Map(), events = [];
  let admits = 0, current = true, issued = 0;
  const moon = {
    clientProgramAccountReadControlBytes: () => 64n,
    clientProgramPrepareAccountReadConstruction(read, retained, execution) {
      events.push(['prepare', read, retained, execution]);
      if (!live.has(read) || !current) return err('Retired');
      let total = retained;
      for (const [other, amount] of live) if (other !== read) total += amount;
      if (total > limit || execution > limit) return err('RetentionLimit');
      live.set(read, retained); return ok(undefined);
    },
    clientProgramCloseAccountRead(read, ack) {
      events.push(['close', read, ack]);
      if (ack) live.delete(read);
      return ok(ack);
    },
    executionAuthorizationAdmitPrepared(wire, prepare) {
      if (!prepare(512n, 1024n)) return undefined;
      admits++; return Object.freeze({wire});
    },
    executionAuthorizationMissing: () => Object.freeze({missing: true}),
  };
  const facet = createAccountConstruction({moon, current() {
    if (!current) throw new Error('Retired');
  }, prepareRead() {
    if (!current) return err('Retired');
    const read = {issued: ++issued}; live.set(read, 64n); return ok(read);
  }});
  return {facet, moon, live, events, admits: () => admits, retire() {current = false;}};
}
async function files(fn) {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-read-'));
  try {await fn(join(root, 'account.json'));} finally {await rm(root, {recursive: true});}
}

test('funded original and synchronous current read support exact Account beyond old million-byte ceiling', async () => files(async path => {
  const wire = sourceReadAccountConfiguration({connection: 'source', resource: 'records', entryId: 'x'.repeat(1000001)});
  await writeFile(path, wire);
  const f = fixture(), frame = f.facet.begin();
  const configuration = await readAccountConfiguration(path, frame);
  assert.equal(configuration.text, wire);
  frame.finish(false);
  assert.equal(f.facet.observe(read => readAccountCurrent(path, read)), wire);
  assert.equal(f.live.size, 0);
  assert.equal(await f.facet.close(), true);
}));

test('original refusal occurs before Buffer backing or UTF8 decode and failed prefix stays held until cleanup', async () => files(async path => {
  await writeFile(path, 'x'.repeat(256));
  const f = fixture(100n), frame = f.facet.begin();
  const allocate = Buffer.alloc;
  let allocations = 0;
  Buffer.alloc = (...args) => {allocations++; return allocate(...args);};
  try {await assert.rejects(readAccountOriginal(path, frame), {code: 'MoonBitHostFailure'});}
  finally {Buffer.alloc = allocate; frame.finish(false);}
  assert.equal(allocations, 0);
  assert.equal(f.live.size, 1);
  assert.equal(await f.facet.close(), true);
  assert.equal(f.live.size, 0);
}));

test('unchanged exact wire reuses immutable Account DATA, changed wire admits fresh on same original', async () => files(async path => {
  const f = fixture(), authorization = Object.freeze({accountConfig: path, accountConstruction: f.facet});
  await writeFile(path, '{"account_id":"a"}');
  const a = observeInstalledAccount(f.moon, authorization);
  assert.equal(observeInstalledAccount(f.moon, authorization), a);
  assert.equal(f.admits(), 1);
  await writeFile(path, '{"account_id":"b"}');
  const b = observeInstalledAccount(f.moon, authorization);
  assert.notEqual(b, a);
  assert.equal(f.admits(), 2);
  assert.equal(f.live.size, 2); // both retained children coexist until retirement
  assert.throws(() => f.facet.observe(frame => frame.admit({}, 'x')), /ForeignAccountConstructionRuntime/);
  f.retire();
  assert.throws(() => f.facet.begin(), /Retired/);
  assert.equal(await f.facet.close(), true);
  assert.equal(f.live.size, 0);
}));

test('unknown sync FD close is attempted once and never acknowledges parent retirement', async () => files(async path => {
  await writeFile(path, '{}');
  const f = fixture(), close = fs.closeSync;
  let attempts = 0;
  fs.closeSync = fd => {attempts++; close(fd); throw new Error('UnknownClose');};
  syncBuiltinESMExports();
  try {assert.throws(() => f.facet.observe(frame => readAccountCurrent(path, frame)), /UnknownClose/);}
  finally {fs.closeSync = close; syncBuiltinESMExports();}
  assert.equal(attempts, 1);
  assert.equal(await f.facet.close(), false);
  assert.equal(await f.facet.close(), false);
  assert.equal(attempts, 1);
  assert.equal(f.live.size, 1);
}));
