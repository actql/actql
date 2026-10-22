import assert from 'node:assert/strict';
import test from 'node:test';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

// Explicit existing-registry counters, not an operational startup issuer or
// physical envelope. Another registry cannot authenticate a candidate in the
// installed module's private original registry.
const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('9')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'scope', capabilities: [], limits: {
    maxReadWireBytes: 65536, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
    maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
const options = {mode: 'local', owner: 'local'};
const deferred = () => {
  let resolve;
  const promise = new Promise(done => {resolve = done;});
  return {promise, resolve};
};
function fixture() {
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const calls = [];
  const host = {
    port: {async perform(operation) {
      calls.push(operation);
      if (operation === 'connect') return profile;
      if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
      throw new Error(`Unexpected operation ${operation}`);
    }},
    dispatchOwner: {drain() {calls.push('drain');}},
    retireTerminalEffects() {calls.push('retire');},
    journal: {close() {calls.push('journal');}},
    store: {close() {calls.push('store');}},
  };
  const installation = {};
  registry.registerPreparation(host, installation, host);
  return {registry, host, installation, calls,
    acquire: () => registry.connect('/prepared/root', 'same', async () => host, options, host)};
}

test('registry preparation requires its exact original Host installation and generation', () => {
  const f = fixture();
  f.registry.assertPreparation(f.host, f.installation, f.host);
  for (const [host, installation, generation] of [
    [{...f.host}, f.installation, f.host], [f.host, {...f.installation}, f.host],
    [f.host, f.installation, {}],
  ]) assert.throws(() => f.registry.assertPreparation(host, installation, generation),
  {code: 'InstalledHostPreparationChanged'});
  assert.throws(() => f.registry.registerPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  const foreign = createEmbeddedHostRegistry(() => true);
  assert.throws(() => foreign.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  assert.deepEqual(f.calls, []);
  f.registry.retirePreparation(f.host, f.installation, f.host);
  assert.throws(() => f.registry.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
});

test('Source subject lookup accepts only the same pending request in the original registry', async t => {
  const f = fixture();
  let original;
  f.host.port.perform = async (operation, request) => {
    if (operation === 'connect') return profile;
    assert.equal(operation, 'attach'); original = request;
    assert.equal(f.registry.assertSourceRequest(f.host, f.installation, f.host, request), undefined);
    assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, {...request}),
      {code: 'InstalledHostPreparationChanged'});
    let traps = 0;
    const proxy = new Proxy(request, {get() {traps++;}, ownKeys() {traps++; return [];},
      getOwnPropertyDescriptor() {traps++;}});
    assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, proxy),
      {code: 'InstalledHostPreparationChanged'});
    assert.equal(traps, 0);
    for (const [host, installation, generation] of [
      [{}, f.installation, f.host], [f.host, {}, f.host], [f.host, f.installation, {}],
    ]) assert.throws(() => f.registry.assertSourceRequest(host, installation, generation, request),
      {code: 'InstalledHostPreparationChanged'});
    const foreign = createEmbeddedHostRegistry(() => true);
    assert.throws(() => foreign.assertSourceRequest(f.host, f.installation, f.host, request),
      {code: 'InstalledHostPreparationChanged'});
    return {ref, durability: 'durable', revision: 1};
  };
  const client = await f.acquire(); t.after(() => client.close());
  assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, {}),
    {code: 'InstalledHostPreparationChanged'});
  assert.deepEqual((await client.attach(ref)).ref, ref);
  assert.ok(original);
  assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, original),
    {code: 'InstalledHostPreparationChanged'}, 'Promise retirement cuts only the request association');
});

test('Source subject lookup keeps concurrent original calls separate and close drains both', async t => {
  const f = fixture(), a = deferred(), b = deferred();
  const started = deferred(), originals = [];
  f.host.port.perform = async (operation, request) => {
    if (operation === 'connect') return profile;
    assert.equal(operation, 'attach');
    const index = originals.length; originals.push(request);
    if (originals.length === 2) started.resolve();
    await (index === 0 ? a.promise : b.promise);
    return {ref, durability: 'durable', revision: 1};
  };
  const client = await f.acquire();
  const first = client.attach(ref), second = client.attach(ref);
  void first.catch(() => {}); void second.catch(() => {});
  t.after(async () => {a.resolve(); b.resolve(); await Promise.allSettled([first, second]); await client.close();});
  await started.promise;
  assert.notEqual(originals[0], originals[1]);
  for (const original of originals) f.registry.assertSourceRequest(f.host, f.installation, f.host, original);
  a.resolve(); await first;
  assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, originals[0]),
    {code: 'InstalledHostPreparationChanged'});
  f.registry.assertSourceRequest(f.host, f.installation, f.host, originals[1]);
  let closed = false; const closing = client.close().then(() => {closed = true;});
  await Promise.resolve();
  assert.equal(closed, false); assert.equal(f.calls.includes('store'), false);
  assert.throws(() => f.registry.assertSourceRequest(f.host, f.installation, f.host, originals[1]),
    {code: 'InstalledHostPreparationChanged'});
  b.resolve(); await second; await closing;
  assert.equal(closed, true); assert.equal(f.calls.filter(call => call === 'store').length, 1);
});

test('a preparing record is not an opened root or a reusable Host lease', async () => {
  const f = fixture();
  let opened = 0;
  await assert.rejects(f.registry.connect(f.host, 'same', async () => {
    opened++; return f.host;
  }, options), {code: 'InstalledHostPreparationChanged'});
  assert.equal(opened, 0); assert.deepEqual(f.calls, []);
  f.registry.retirePreparation(f.host, f.installation, f.host);
});

test('adopted preparation stays with the original Host until its final close', async () => {
  const f = fixture(), a = await f.acquire();
  f.registry.assertPreparation(f.host, f.installation, f.host);
  assert.throws(() => f.registry.retirePreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  await assert.rejects(f.acquire(), {code: 'InstalledHostPreparationChanged'});
  await a.close();
  assert.throws(() => f.registry.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
});

test('unused preparation retires before a lease reuses the original Host', async () => {
  const f = fixture(), a = await f.acquire();
  const candidate = {}, installation = {};
  f.registry.registerPreparation(candidate, installation, candidate);
  let unusedOpens = 0, releases = 0;
  const before = f.calls.filter(call => call === 'connect').length;
  const b = await f.registry.connect('/prepared/root', 'same', async () => {
    unusedOpens++; assert.fail('A reused Host must not open the candidate');
  }, options, candidate, async () => {
    releases++;
    assert.equal(f.calls.filter(call => call === 'connect').length, before);
    f.registry.retirePreparation(candidate, installation, candidate);
  });
  assert.equal(releases, 1); assert.equal(unusedOpens, 0);
  await a.close(); assert.equal(f.calls.includes('store'), false);
  assert.deepEqual((await b.attach(ref)).ref, ref);
  await b.close();
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
});

test('a fulfilled callback cannot retire an unused candidate by assertion alone', async () => {
  const f = fixture(), a = await f.acquire();
  const candidate = {}, installation = {};
  f.registry.registerPreparation(candidate, installation, candidate);
  await assert.rejects(f.registry.connect('/prepared/root', 'same', async () => {
    assert.fail('No replacement Host');
  }, options, candidate, async () => ({pending: false})),
  {code: 'InstalledHostPreparationChanged'});
  assert.equal(f.calls.filter(call => call === 'connect').length, 1);
  f.registry.retirePreparation(candidate, installation, candidate);
  await a.close();
});

test('pending unused preparation never acquires a lease or replaces its original Host', async () => {
  const f = fixture(), a = await f.acquire();
  const candidate = {}, installation = {};
  f.registry.registerPreparation(candidate, installation, candidate);
  const original = Object.freeze(Object.assign(new Error('OriginalPreparationCleanupPending'),
    {cleanupPending: true}));
  const before = f.calls.filter(call => call === 'connect').length;
  await assert.rejects(f.registry.connect('/prepared/root', 'same', async () => {
    assert.fail('Do not open another Host');
  }, options, candidate, async () => {throw original;}), error => error === original);
  assert.equal(f.calls.filter(call => call === 'connect').length, before);
  f.registry.assertPreparation(candidate, installation, candidate);
  assert.deepEqual((await a.attach(ref)).ref, ref);
  f.registry.retirePreparation(candidate, installation, candidate);
  await a.close();
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
});

test('Host closing during unused cleanup refuses a new lease after the await', async () => {
  const f = fixture(), a = await f.acquire();
  const candidate = {}, installation = {}, entered = deferred(), release = deferred();
  f.registry.registerPreparation(candidate, installation, candidate);
  const connecting = f.registry.connect('/prepared/root', 'same', async () => {
    assert.fail('A closing original Host must not be replaced');
  }, options, candidate, async () => {
    entered.resolve(); await release.promise;
    f.registry.retirePreparation(candidate, installation, candidate);
  });
  await entered.promise;
  await a.close(); release.resolve();
  await assert.rejects(connecting, {code: 'ClientHostClosing'});
  assert.equal(f.calls.filter(call => call === 'connect').length, 1);
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
});

test('foreign returned Host stays in acquired shutdown custody on pair refusal', async () => {
  const f = fixture();
  let pending = true, closes = 0;
  const foreign = {port: {}, dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {closes++;}},
    sourceProfile: {close() {if (pending) throw new Error('OriginalForeignChildPending');}}};
  const failure = await f.registry.connect('/prepared/root', 'same', async () => foreign,
    options, f.host).catch(error => error);
  assert.equal(failure.code, 'InstalledHostPreparationChanged');
  assert.equal(failure.cleanupPending, true);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(closes, 1);
  assert.throws(() => f.registry.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  await assert.rejects(f.registry.connect('/prepared/root', 'same', async () => {
    assert.fail('Do not replace the retained child');
  }, options), error => error === failure);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(closes, 1, 'confirmed siblings are not closed twice');
});

test('refused opening retains the same root until its original control completes', async () => {
  const f = fixture();
  let pending = true, closes = 0;
  const original = Object.freeze(new Error('OriginalCurrentRefused'));
  const control = {close() {closes++; return {pending};}};
  const failure = await f.registry.connect('/prepared/root', 'same', async () => {throw original;},
    options, f.host, undefined, control).catch(error => error);
  assert.equal(failure.primaryFailure, original);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(f.calls, []);
  await assert.rejects(f.registry.connect('/prepared/root', 'same', async () => {
    assert.fail('Do not replace the original pending control');
  }, options), error => error === failure);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(closes, 2);
  assert.throws(() => f.registry.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
});

test('completed original control preserves the exact opening refusal', async () => {
  const f = fixture();
  const original = Object.freeze(new TypeError('OriginalPreparationRefused'));
  const observation = Object.freeze({pending: false});
  let closes = 0;
  const control = {close() {assert.equal(this, control); closes++; return observation;}};
  await assert.rejects(f.registry.connect('/prepared/root', 'same', async () => {throw original;},
    options, f.host, undefined, control), error => error === original);
  assert.equal(closes, 1);
  assert.deepEqual(f.calls, []);
  assert.throws(() => f.registry.assertPreparation(f.host, f.installation, f.host),
    {code: 'InstalledHostPreparationChanged'});
  const next = await f.registry.connect('/prepared/root', 'same', async () => f.host, options);
  await next.close();
  assert.equal(closes, 1, 'the completed original is never retried by a later Host');
});

test('opening child cannot replace the captured original preparation close callback', async () => {
  const f = fixture(), entered = deferred(), released = deferred();
  let pending = true, originals = 0, replacements = 0;
  const control = {close() {assert.equal(this, control); originals++; return {pending};}};
  const opening = f.registry.connect('/prepared/root', 'same', async () => {
    entered.resolve(); await released.promise; throw new Error('OriginalOpeningRefused');
  }, options, f.host, undefined, control);
  await entered.promise;
  control.close = () => {replacements++; return {pending: false};};
  released.resolve();
  const failure = await opening.catch(error => error);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(originals, 1); assert.equal(replacements, 0);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(originals, 2); assert.equal(replacements, 0);
});
