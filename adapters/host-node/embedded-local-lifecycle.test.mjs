import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {parse} from 'acorn';
import {beginInitialControlInstallation, assertInitialControlInstallationCurrent,
  readInitialControlInstallationInput} from './node-initial-control-installation.mjs';
import {retainInstalledHostInitializationFailure, retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';
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
function fixture({perform, sourceClose, drain, open, observationClose,
  stopModelRuntime, retireModelRuntime, answerCheckpoint} = {}) {
  const calls = [];
  let opens = 0;
  const registry = createEmbeddedHostRegistry((left, right) => left === right);
  const acquire = (identity = 'same') => registry.connect('/test/root', identity,
    async () => {
      opens++;
      if (open) await open();
      return {
        port: {...(answerCheckpoint === undefined ? {} : {answerCheckpoint}), async perform(operation, body, signal) {
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
        ...(stopModelRuntime===undefined?{}:{stopModelRuntime}),
        ...(retireModelRuntime===undefined?{}:{retireModelRuntime}),
        ...(observationClose === undefined ? {} : {observation: {close: observationClose}}),
      };
    }, options);
  return {acquire, calls, opens: () => opens};
}

test('ordinary Client close retires the original runtime once after all actual closes',async()=>{
  let retired=0,stopped=0;
  const f=fixture({stopModelRuntime(){stopped++;},retireModelRuntime(){
    assert.equal(f.calls.at(-1),'diagnostic');retired++;
  }});
  const [a,b]=await Promise.all([f.acquire(),f.acquire()]);
  await a.close();assert.equal(retired,0);
  await Promise.all([b.close(),b.close()]);
  await a.close();await b.close();
  assert.equal(stopped,1);assert.equal(retired,1);
});

test('same Host lease keeps a pending original Checkpoint answer until its settlement', async () => {
  const entered = deferred(), released = deferred();
  const summary = {checkpointId: 'original', checkpointCid: cid('a'),
    kind: 'effect_set', phase: 'commit', subject: {kind: 'run_unit', runId: 'original-run',
      runDefinitionCid: cid('b')}, requiredArtifact: {type: 'effect_set_preview', cid: cid('c')},
    reviewProjectionCid: cid('d'), requirements: ['effect_scope_approved'],
    createdAt: '2026-10-18T00:00:00.000Z', expiresAt: '2027-01-01T00:00:00.000Z', humanSummary: 'Original'};
  let signatures = 0;
  const f = fixture({perform(operation, body) {
    assert.equal(operation, 'checkpoints'); assert.equal(body.checkpointId, 'original');
    return {items: [summary]};
  }, async answerCheckpoint(observed, decision) {
    assert.equal(typeof this.perform, 'function');
    assert.equal(observed.checkpointId, 'original'); assert.equal(decision, 'approved');
    signatures++; entered.resolve(); await released.promise;
    return {}; // Deliberately no signed success or physical ACK in this double.
  }});
  const client = await f.acquire();
  const pending = client.approve('original').catch(error => error);
  await entered.promise;
  let closed = false;
  const closing = client.close().then(() => {closed = true;});
  await Promise.resolve(); await Promise.resolve();
  assert.equal(closed, false); assert.equal(f.calls.includes('store'), false);
  released.resolve();
  assert.equal((await pending).code, 'ClientClosed');
  await closing;
  assert.equal(signatures, 1); assert.equal(f.calls.filter(value => value === 'store').length, 1);
  assert.equal(f.calls.includes('resolve'), false);
});

test('a malformed original answer port closes the acquired Host through its same shutdown', async () => {
  const f = fixture({answerCheckpoint: 42});
  await assert.rejects(f.acquire(), {message: 'InvalidLocalCheckpointAnswerPort'});
  assert.equal(f.calls.filter(value => value === 'store').length, 1);
  assert.equal(f.calls.filter(value => value === 'journal').length, 1);
});

test('throwing original answer acquisition retains the same unfinished Host cleanup', async () => {
  let cleanupReady = false, storeCloses = 0;
  const registry = createEmbeddedHostRegistry(() => true);
  const host = {port: {get answerCheckpoint() {throw new Error('private-key-selection-failure');},
    async perform() {return profile;}},
    dispatchOwner: {drain() {}}, retireTerminalEffects() {},
    journal: {close() {}}, store: {close() {storeCloses++;}}, diagnostic: {close() {}},
    sourceProfile: {close() {if (!cleanupReady) throw new Error('original-cleanup-pending');}}};
  const error = await registry.connect('/test/failing-original', 'same', async () => host, options)
    .catch(error => error);
  assert.equal(error.code, 'InstalledLocalConnectionCleanupPending');
  assert.equal(error.cleanupPending, true); assert.equal(storeCloses, 1);
  assert.doesNotMatch(inspect(error, {showHidden: true, depth: 8}), /private-key-selection-failure/);
  await assert.rejects(error.cleanupHandle.retry(), failure => failure === error);
  cleanupReady = true;
  assert.deepEqual(await error.cleanupHandle.retry(), {pending: false});
  assert.equal(storeCloses, 1);
});

test('failed final cleanup retains the runtime and the same shutdown for retry',async()=>{
  let pending=true,retired=0,closed=0;
  const f=fixture({async observationClose(){
    closed++;if(pending)throw new Error('OriginalObservationCloseUnknown');
  },retireModelRuntime(){assert.equal(pending,false);retired++;}});
  const client=await f.acquire();
  await assert.rejects(client.close(),{code:'ClientCleanupPending'});
  assert.equal(retired,0);
  assert.equal(f.calls.filter(value=>value==='store').length,1);
  pending=false;await client.close();await client.close();
  assert.equal(retired,1);assert.equal(closed,2);
  assert.equal(f.calls.filter(value=>value==='store').length,1);
});

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

test('failed observation close retains the Host and retries only unfinished finalization', async () => {
  let pending = true, closes = 0;
  const f = fixture({async observationClose() {
    closes++;
    if (pending) throw new Error('ObservationPending');
  }});
  const client = await f.acquire();
  await assert.rejects(client.close(), {code: 'ClientCleanupPending'});
  await assert.rejects(f.acquire(), {code: 'ClientHostClosing'});
  assert.equal(f.opens(), 1);
  pending = false;
  await client.close();
  await client.close();
  assert.equal(closes, 2);
  for (const name of ['stop', 'drain', 'journal', 'source', 'effect', 'store', 'diagnostic']) {
    assert.equal(f.calls.filter(call => call === name).length, 1, name);
  }
  const reopened = await f.acquire();
  assert.equal(f.opens(), 2);
  await reopened.close();
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


test('prepared HTTP Request uses the same registry identity and retires only its original handling', async () => {
  const registry = createEmbeddedHostRegistry(() => true);
  const host = {}, installation = {}, request = {}, alias = {};
  registry.registerPreparation(host, installation, host);
  const done = deferred();
  registry.retainRequest(host, installation, host, request, done.promise);
  registry.bindSourceRequest(host, installation, host, request, alias);
  assert.strictEqual(registry.originalSourceRequest(host, installation, host, alias), request);
  assert.throws(() => registry.retainRequest(host, {}, host, {}, Promise.resolve()),
    /InstalledHostPreparationChanged/);
  await Promise.resolve();
  assert.strictEqual(registry.originalSourceRequest(host, installation, host, alias), request);
  done.resolve();
  await done.promise;
  assert.throws(() => registry.originalSourceRequest(host, installation, host, alias),
    /InstalledHostPreparationChanged/);
  registry.retirePreparation(host, installation, host);
  assert.throws(() => registry.assertPreparation(host, installation, host),
    /InstalledHostPreparationChanged/);
});


function remoteOpeningFixture(failure) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = tree.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'openPreparedInstalledHost');
  assert.ok(declaration);
  const body = source.slice(declaration.start, declaration.end);
  assert.equal(body.split('import.meta').length, 2);
  const registry = createEmbeddedHostRegistry(() => true);
  const events = [];
  let selected, sameHost, sameInstallation;
  const prepareRequest = () => {};
  const options = {directory: '/component/remote', authenticate() {},
    beforeDispatch() {}, loopbackHttp: true, valuesMaxRows: 7};
  // Execute the actual complete shared opening. The final Host constructor,
  // runtime namespace and HTTP constructor are explicit ports: no real
  // Resource/Journal/Store/Run or ordinary acceptance is claimed here.
  const context = {profiles: registry, moduleLifetime: {}, resolve,
    beginInitialControlInstallation, assertInitialControlInstallationCurrent,
    readInitialControlInstallationInput, retainInstalledHostInitializationFailure,
    retainInstalledHostRuntimeFailure,
    clientOperationError: code => Object.assign(new Error(code), {code}),
    snapshotInstalledCalendar: x => x, snapshotHostCapacityPolicy: x => x,
    snapshotHostLookupExecutionPolicy: x => x,
    runtimeUrl: new URL('data:text/javascript,export const componentRuntime = true'),
    async openInstalledHost(installation, preparation) {
      events.push('open');
      selected = preparation; sameHost = preparation.host; sameInstallation = installation;
      assert.equal(installation.mode, 'remote');
      assert.equal(installation.root, '/component/remote');
      assert.equal(installation.retainedRelationOutput, false);
      assert.equal(installation.projectRuntime.componentRuntime, true);
      assert.equal(installation.project, undefined);
      assert.equal(installation.projectProfile, undefined);
      assert.strictEqual(installation.initialControl, readControl(preparation));
      registry.assertPreparation(sameHost, installation, sameHost);
      if (failure !== undefined) throw failure;
      return Object.assign(sameHost, {initialControl: preparation.initialControl});
    },
    installedHostShutdown(host) {
      assert.strictEqual(host, sameHost);
      return {close: () => host.initialControl.close()};
    },
    installHttpRequestPreparation(preparation, actualRegistry, originals) {
      assert.strictEqual(preparation, selected); assert.strictEqual(actualRegistry, registry);
      assert.strictEqual(originals.host, sameHost);
      assert.strictEqual(originals.installation, sameInstallation);
      assert.strictEqual(originals.generation, sameHost);
      assert.strictEqual(originals.supplier, opening);
      events.push('request-preparation'); return prepareRequest;
    },
    installedRemoteHttpTransport(host, input, shutdown, prepared) {
      assert.strictEqual(host, sameHost); assert.strictEqual(prepared, prepareRequest);
      assert.strictEqual(input.authenticate, options.authenticate);
      assert.equal(input.loopbackHttp, true);
      events.push('http'); return {close: shutdown.close};
    },
  };
  function readControl(preparation) {
    // The actual constructor receives this same ordinary scope through the
    // original installation; the public cleanup adapter is a distinct duty.
    assert.notStrictEqual(sameInstallation.initialControl, preparation.initialControl);
    return sameInstallation.initialControl;
  }
  const opening = new Function(...Object.keys(context), 'return (' +
    body.replace('import.meta', 'moduleLifetime') + ');')(...Object.values(context));
  return {options, events, open: () => opening(options, 'remote'),
    assertRetired() {assert.throws(() => registry.assertPreparation(sameHost, sameInstallation, sameHost),
      /InstalledHostPreparationChanged/);}};
}

test('Remote opening retains the same prepared Host without Local discovery and releases its original scope', async () => {
  const f = remoteOpeningFixture();
  const host = await f.open();
  assert.deepEqual(f.events, ['open', 'request-preparation', 'http']);
  const observation = await host.close();
  assert.equal(observation.pending, false);
  f.assertRetired();
  assert.strictEqual(await host.close(), observation);
});

test('Remote constructor failure retains the original cause and retires the same preparation', async () => {
  const primary = new Error('OriginalRemoteConstructorFailure');
  const f = remoteOpeningFixture(primary);
  await assert.rejects(f.open(), error => error === primary);
  assert.deepEqual(f.events, ['open']);
  f.assertRetired();
});

// Execute the unchanged registry declaration with counted JS containers.
// These are operation counts, not latency, ordinary Host or capacity proof.
function countedRequestRegistry() {
  const source = readFileSync(new URL('./embedded-local-lifecycle.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'ExportNamedDeclaration' &&
      node.declaration?.id?.name === 'createEmbeddedHostRegistry').declaration;
  const counts = {visits: 0, mapGets: 0, weakGets: 0};
  const originals = new Map();
  class CountedMap extends Map {
    get(key) {counts.mapGets++; return super.get(key);}
    *values() {for (const value of super.values()) {counts.visits++; yield value;}}
    *entries() {for (const value of super.entries()) {counts.visits++; yield value;}}
    *keys() {for (const value of super.keys()) {counts.visits++; yield value;}}
    [Symbol.iterator]() {return this.entries();}
    forEach(use, receiver) {
      return super.forEach((value, key) => {counts.visits++; Reflect.apply(use, receiver, [value, key, this]);});
    }
  }
  class CountedWeakMap extends WeakMap {
    get(key) {counts.weakGets++; return super.get(key);}
    set(key, value) {originals.set(key, value); return super.set(key, value);}
  }
  const factory = new Function('Map', 'WeakMap',
    `return (${source.slice(declaration.start, declaration.end)});`)(CountedMap, CountedWeakMap);
  return {registry: factory(() => true), counts, originals,
    reset() {counts.visits = counts.mapGets = counts.weakGets = 0;}};
}

test('prepared Request identity lookup and binding use linear counted index work at N and 2N', async () => {
  const samples = [];
  for (const count of [64, 128]) {
    const f = countedRequestRegistry(), host = {}, installation = {};
    f.registry.registerPreparation(host, installation, host);
    const requests = Array.from({length: count}, () => ({}));
    const aliases = requests.map(() => ({})), pending = requests.map(() => deferred());
    try {
      for (let index = 0; index < count; index++) {
        f.registry.retainRequest(host, installation, host, requests[index], pending[index].promise);
        f.registry.bindSourceRequest(host, installation, host, requests[index], aliases[index]);
      }
      f.reset();
      for (let index = 0; index < count; index++) {
        assert.strictEqual(f.registry.originalSourceRequest(host, installation, host, requests[index]), requests[index]);
        assert.strictEqual(f.registry.originalSourceRequest(host, installation, host, aliases[index]), requests[index]);
        f.registry.bindSourceRequest(host, installation, host, aliases[index], aliases[index]);
      }
      samples.push({count, ...f.counts});
    } finally {
      for (const original of pending) original.resolve();
      await Promise.all(pending.map(original => original.promise));
      f.registry.retirePreparation(host, installation, host);
    }
  }
  console.log('ACTQL_REQUEST_INDEX_COUNTER ' + JSON.stringify(samples));
  for (const sample of samples) {
    assert.equal(sample.visits, 0, 'Identity lookup must not enumerate the strong drain inventory');
    assert(sample.weakGets > 0 && sample.mapGets > 0, 'Count actual index and pending-membership lookups');
    assert(sample.weakGets + sample.mapGets <= 12 * sample.count);
  }
  assert.equal(samples[1].weakGets, samples[0].weakGets * 2);
  assert.equal(samples[1].mapGets, samples[0].mapGets * 2);
});

test('prepared Request aliases refuse cross-request foreign generation and retired rebinding', async () => {
  const registry = createEmbeddedHostRegistry(() => true);
  const host = {}, installation = {}, otherHost = {}, otherInstallation = {};
  registry.registerPreparation(host, installation, host);
  registry.registerPreparation(otherHost, otherInstallation, otherHost);
  const a = {}, b = {}, alias = {}, nested = {}, first = deferred(), second = deferred();
  registry.retainRequest(host, installation, host, a, first.promise);
  registry.retainRequest(host, installation, host, b, second.promise);
  try {
    registry.bindSourceRequest(host, installation, host, a, alias);
    registry.bindSourceRequest(host, installation, host, alias, nested);
    registry.bindSourceRequest(host, installation, host, a, alias);
    assert.strictEqual(registry.originalSourceRequest(host, installation, host, nested), a);
    for (const derived of [a, alias, nested]) {
      assert.throws(() => registry.bindSourceRequest(host, installation, host, b, derived),
        /InstalledHostPreparationChanged/);
    }
    assert.throws(() => registry.originalSourceRequest(otherHost, otherInstallation, otherHost, alias),
      /InstalledHostPreparationChanged/);
    assert.throws(() => registry.originalSourceRequest(host, installation, otherHost, alias),
      /InstalledHostPreparationChanged/);
    assert.throws(() => registry.retainRequest(host, installation, host, a, Promise.resolve()),
      /InstalledHostPreparationChanged/);
    first.resolve(); await first.promise;
    assert.throws(() => registry.originalSourceRequest(host, installation, host, nested),
      /InstalledHostPreparationChanged/);
    assert.throws(() => registry.bindSourceRequest(host, installation, host, b, nested),
      /InstalledHostPreparationChanged/);
    assert.strictEqual(registry.originalSourceRequest(host, installation, host, b), b);
    registry.retirePreparation(host, installation, host);
    assert.throws(() => registry.originalSourceRequest(host, installation, host, b),
      /InstalledHostPreparationChanged/);
  } finally {
    first.resolve(); second.resolve(); await Promise.all([first.promise, second.promise]);
    registry.retirePreparation(otherHost, otherInstallation, otherHost);
  }
});

test('prepared Request cancellation does not retire pending work and settled index records cut heavy references', async () => {
  const f = countedRequestRegistry(), host = {}, installation = {}, request = {}, alias = {};
  const controller = new AbortController(), done = deferred();
  f.registry.registerPreparation(host, installation, host);
  f.registry.retainRequest(host, installation, host, request, done.promise);
  f.registry.bindSourceRequest(host, installation, host, request, alias);
  const record = f.originals.get(request);
  assert(record !== undefined);
  assert.strictEqual(f.originals.get(alias), record, 'The index points to the same existing pending record');
  controller.abort(new Error('Original component cancellation request'));
  assert.strictEqual(f.registry.originalSourceRequest(host, installation, host, alias), request);
  assert.strictEqual(record.request, request);
  done.resolve(); await done.promise;
  assert.throws(() => f.registry.originalSourceRequest(host, installation, host, alias),
    /InstalledHostPreparationChanged/);
  for (const field of ['request', 'pending', 'generation', 'owner']) assert.equal(record[field], undefined);
  f.registry.retirePreparation(host, installation, host);
});

test('prepared Client pending request index preserves original close drain and retirement order', async () => {
  const registry = createEmbeddedHostRegistry(() => true), calls = [], gate = deferred(), entered = deferred();
  const host = {}, installation = {}, alias = {};
  let actualRequest;
  Object.assign(host, {
    port: {async perform(operation, request) {
      assert.strictEqual(registry.originalSourceRequest(host, installation, host, request), request);
      if (operation === 'connect') return profile;
      assert.equal(operation, 'attach'); actualRequest = request;
      registry.bindSourceRequest(host, installation, host, request, alias);
      calls.push('attach-entered'); entered.resolve(); await gate.promise; calls.push('attach-returned');
      return {ref, durability: 'durable', revision: 1};
    }},
    checkpoints: {stop() {calls.push('stop');}, close() {calls.push('checkpoint');}},
    dispatchOwner: {drain() {calls.push('drain');}},
    retireTerminalEffects() {calls.push('retire');},
    journal: {close() {calls.push('journal');}}, store: {close() {calls.push('store');}},
  });
  registry.registerPreparation(host, installation, host);
  const client = await registry.connect('/test/index-owned', 'same', async () => host,
    {mode: 'local', owner: 'local'}, host);
  const attached = client.attach(ref);
  await Promise.race([entered.promise, attached.then(() => assert.fail('Original attach returned before its barrier'))]);
  assert.strictEqual(registry.originalSourceRequest(host, installation, host, alias), actualRequest);
  let closed = false;
  const closing = client.close().then(() => {closed = true;});
  await Promise.resolve(); assert.equal(closed, false);
  assert.deepEqual(calls, ['attach-entered']);
  gate.resolve(); await attached; await closing;
  assert.deepEqual(calls, ['attach-entered', 'attach-returned', 'stop', 'drain', 'retire', 'checkpoint', 'journal', 'store']);
  assert.throws(() => registry.originalSourceRequest(host, installation, host, alias),
    /InstalledHostPreparationChanged/);
});
