import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

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
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
};
function fixture({perform, sourceClose, drain, open, observationClose} = {}) {
  const calls = [];
  let opens = 0;
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const acquire = (identity = 'same') => registry.connect('/test/root', identity,
    async () => {
      opens++;
      if (open) await open();
      return {
        port: {async perform(operation, body, signal) {
          calls.push(operation);
          if (operation === 'connect') return profile;
          if (perform) return perform(operation, body, signal);
          if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
          throw new Error(`Unexpected operation ${operation}`);
        }},
        checkpoints: {stop() { calls.push('stop'); }, close() {calls.push('checkpoint');}},
        dispatchOwner: {async drain() {calls.push('drain'); await drain?.();}},
        retireTerminalEffects() { calls.push('retire'); },
        journal: {close() {calls.push('journal');}},
        sourceProfile: {async close() {calls.push('source'); await sourceClose?.();}},
        installedEffect: {close() {calls.push('effect');}},
        store: {close() {calls.push('store');}},
        diagnostic: {close() {calls.push('diagnostic');}},
        ...(observationClose === undefined ? {} : {observation: {close: observationClose}}),
      };
    }, options);
  return {acquire, calls, opens: () => opens};
}

test('shared clients close independently and the last lease closes the Host once', async () => {
  const f = fixture();
  const [a, b] = await Promise.all([f.acquire(), f.acquire()]);
  assert.equal(f.opens(), 1);
  await assert.rejects(f.acquire('changed'), {message: 'InstalledHostConfigurationMismatch'});
  await a.close();
  assert.equal(f.calls.includes('stop'), false);
  assert.deepEqual((await b.attach(ref)).ref, ref);
  await Promise.all([b.close(), b.close()]);
  assert.deepEqual(f.calls.filter(call => !['connect', 'attach'].includes(call)),
    ['stop', 'drain', 'retire', 'checkpoint', 'journal', 'source', 'effect', 'store', 'diagnostic']);
  await a.close(); await b.close();
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
  const reopened = await f.acquire('new');
  assert.equal(f.opens(), 2);
  await reopened.close();
});

test('final close waits in-flight ingress and dispatch without cancelling a Run', async () => {
  const request = deferred(), requestDone = deferred(), dispatch = deferred(), dispatchDone = deferred();
  const f = fixture({async perform(operation) {
    assert.equal(operation, 'attach'); request.resolve(); await requestDone.promise;
    return {ref, durability: 'durable', revision: 1};
  }, async drain() { dispatch.resolve(); await dispatchDone.promise; }});
  const client = await f.acquire();
  const attached = client.attach(ref);
  await request.promise;
  const close = client.close();
  await assert.rejects(f.acquire(), {code: 'ClientHostClosing'});
  assert.equal(f.calls.includes('stop'), false);
  requestDone.resolve(); await attached; await dispatch.promise;
  assert.equal(f.calls.includes('store'), false);
  dispatchDone.resolve(); await close;
  assert.equal(f.calls.includes('cancel'), false);
  assert.equal(f.calls.includes('store'), true);
});

test('simultaneously closing both Clients finalizes only their original Host generation', async () => {
  const f = fixture();
  const [a, b] = await Promise.all([f.acquire(), f.acquire()]);
  await Promise.all([a.close(), b.close()]);
  for (const name of ['stop', 'drain', 'journal', 'source', 'effect', 'store', 'diagnostic']) {
    assert.equal(f.calls.filter(call => call === name).length, 1, name);
  }
  const c = await f.acquire();
  await Promise.all([a.close(), b.close()]);
  assert.deepEqual((await c.attach(ref)).ref, ref);
  await c.close();
  assert.equal(f.calls.filter(call => call === 'store').length, 2);
});

test('concurrent final leases share the same asynchronous observation close', async () => {
  const entered = deferred(), release = deferred();
  let closes = 0;
  const f = fixture({async observationClose() { closes++; entered.resolve(); await release.promise; }});
  const [a, b] = await Promise.all([f.acquire(), f.acquire()]);
  const closed = Promise.all([a.close(), b.close()]);
  await entered.promise;
  assert.equal(closes, 1);
  assert.equal(f.calls.filter(call => call === 'diagnostic').length, 1);
  release.resolve(); await closed;
  assert.equal(closes, 1);
});

test('failed shutdown retains its generation and retries only the failed owner', async () => {
  let ready = false;
  const f = fixture({sourceClose() { if (!ready) throw new Error('SourcePending'); }});
  const client = await f.acquire();
  await assert.rejects(client.close(), error => {
    assert.equal(error.cleanupPending, true);
    assert.equal(error.code, 'ClientCleanupPending');
    assert.equal(error.cause, undefined);
    assert.equal(error.cleanupHandle, undefined);
    return true;
  });
  await assert.rejects(f.acquire(), {code: 'ClientHostClosing'});
  assert.equal(f.opens(), 1);
  ready = true;
  await client.close();
  assert.equal(f.calls.filter(call => call === 'source').length, 2);
  assert.equal(f.calls.filter(call => call === 'store').length, 1);
  const second = await f.acquire();
  assert.equal(f.opens(), 2);
  await second.close();
});

test('failed initialization keeps the exact cleanup owner before another open', async () => {
  let pending = true, failing = true;
  const failure = Object.assign(new Error('InitializationPending'), {
    cleanupPending: true,
    cleanupHandle: {status: () => ({pending}), async retry() {pending = false;}},
  });
  const f = fixture({open() {if (failing) throw failure;}});
  await assert.rejects(f.acquire(), error => error === failure);
  const retained = failure.cleanupHandle;
  failure.cleanupPending = false;
  failure.cleanupHandle = {status: () => ({pending: false})};
  await assert.rejects(f.acquire(), error => error === failure);
  assert.equal(f.opens(), 1);
  await retained.retry(); failing = false;
  const client = await f.acquire();
  assert.equal(f.opens(), 2);
  await client.close();
});

test('failed negotiation returns its reserved lease and closes the opened Host', async () => {
  const registry = createEmbeddedHostRegistry(() => true);
  const calls = [];
  const host = {port: {async perform() {return {}; }},
    dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {calls.push('store');}},
    diagnostic: {close() {}},
  };
  for (let i = 0; i < 2; i++) await assert.rejects(registry.connect('/test/root', 'same',
    async () => {calls.push('open'); return host;}, options), {code: 'InvalidHostProfile'});
  assert.deepEqual(calls, ['open', 'store', 'open', 'store']);
});

test('failed negotiation keeps a sanitized recovery operation when physical close also fails', async () => {
  const registry = createEmbeddedHostRegistry(() => true);
  let ready = false;
  const host = {port: {async perform() {return {}; }},
    dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {}}, diagnostic: {close() {}},
    sourceProfile: {close() {if (!ready) throw Object.assign(new Error('private-source-secret'),
      {code: 'private-source-secret'});}},
  };
  let failure;
  await assert.rejects(registry.connect('/test/root', 'same', async () => host, options), error => {
    failure = error;
    assert.equal(error.code, 'InstalledLocalConnectionCleanupPending');
    assert.equal(error.cause, undefined);
    assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-source-secret/);
    return true;
  });
  await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
  assert.deepEqual(failure.cleanupHandle.status(), {pending: true});
  assert.doesNotMatch(inspect(failure, {showHidden: true, depth: 8}), /private-source-secret/);
  ready = true;
  assert.deepEqual(await failure.cleanupHandle.retry(), {pending: false});
});
