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
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {checkedLocalOutputLimits, localOutputLimits} from './local-values-plan.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';

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

test('selected Local lifecycle cannot omit its same own preparation receiver before connect', async () => {
  // Explicit shutdown ports observe refusal/cleanup order only. No Source
  // receipt, Root, Account, physical resource or ordinary Run is issued.
  for (const inherited of [false, true]) {
    let connects = 0;
    const closes = [];
    const port = {async perform(operation) {
      assert.equal(operation, 'connect'); connects++; return profile;
    }};
    if (inherited) Object.setPrototypeOf(port, {
      [sourcePreparationPort]: {beforeSourceSnapshot() {assert.fail('InheritedReceiver');}},
    });
    const initialControl = {close() {closes.push('initial'); return {pending: false};}};
    const host = {port, initialControl,
      checkpoints: {stop() {closes.push('stop');}, close() {closes.push('checkpoint');}},
      dispatchOwner: {drain() {closes.push('drain');}},
      retireTerminalEffects() {closes.push('retire');},
      journal: {close() {closes.push('journal');}}, store: {close() {closes.push('store');}}};
    const registry = createEmbeddedHostRegistry(() => true), installation = {};
    registry.registerPreparation(host, installation, host);
    await assert.rejects(registry.connect('/test/selected-local', 'same', async () => host,
      options, host, undefined, initialControl), {code: 'NodeSourceManagedAdmissionUnavailable'});
    assert.equal(connects, 0);
    assert.deepEqual(closes, ['stop', 'drain', 'retire', 'checkpoint', 'journal', 'store', 'initial']);
  }
});

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

// The actual held caller uses the real Host registry with explicit native and
// Journal/Checkpoint ports. No synthetic packet below issues capacity, a Run,
// approval or a physical cleanup acknowledgement.
function heldRequestOriginalFixture({changed = false, failure, failPreparation = false, finishFailure,
  finishFailures = 1, preparePlan, effectful = false} = {}) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let entry;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'heldSubmission') {
      assert.equal(entry, undefined); entry = node;
    }
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  })(tree);
  assert(entry);
  const host = {}, installation = {}, moon = {}, prepared = {}, requested = {};
  const registry = createEmbeddedHostRegistry(() => true);
  registry.registerPreparation(host, installation, host);
  const captured = Object.freeze({version: 'actql-remote-captured-submission/0.1',
    requestId: 'authored-held-request', principalId: 'actor', connection: 'original-connection',
    kind: 'program', input: Object.freeze({version: 'actql/0.1', id: 'same-program'}),
    resultNames: Object.freeze(['answer'])});
  const calls = [], pending = deferred();
  let retainedRequest;
  let finishAttempts = 0;
  const input = Object.freeze({finish(terminal) {
    calls.push('finish:' + terminal);
    if (++finishAttempts <= finishFailures && finishFailure !== undefined) throw finishFailure;
    pending.resolve();
  }});
  const preparation = {
    retainEffectRequestInput(actualMoon, request, intent, actualCapture) {
      assert.equal(actualMoon, moon); assert.equal(intent, undefined);assert.equal(actualCapture, captured);
      retainedRequest = request;
      registry.retainRequest(host, installation, host, request, pending.promise);
      calls.push('retain-original'); return input;
    },
    bindSourceRequest(request, value) {
      assert.equal(request, retainedRequest); assert.equal(value, prepared);
      registry.bindSourceRequest(host, installation, host, request, value);calls.push('bind-original');
    },
  };
  const ports = {moon, preparation, retainInstalledHostRuntimeFailure,
    localPreparationCustody: {adopt: value => value, attach(request, value) {request.preparedProgram = value;}},
    async prepareCapturedSubmission(request) {
      assert.equal(registry.originalSourceRequest(host, installation, host, request), request);
      calls.push('prepare-original');if (failPreparation) throw failure;return prepared;
    },
    requestOf(request) {
      assert.equal(registry.originalSourceRequest(host, installation, host, prepared), request);
      calls.push('request-original');return {requested,resultNames:['answer'],acquired:false,acquisitionCount:0,effectful};
    },
    admitPreparedSubmission(request, held) {
      assert.equal(registry.originalSourceRequest(host, installation, host, prepared), request);
      calls.push('admit-plan');
      return preparePlan?.({request, moon, prepared, requested, preparation, requestOf:ports.requestOf}, held);
    },
    prepareAcquisitions() {assert.fail('No extra Source');}, prepareKeyedSources() {assert.fail('No keyed Source');},
    prepareAcquisition() {assert.fail('No Source');},
    captureSubmission(request) {assert.equal(request, retainedRequest);return changed ? {...captured, requestId:'foreign'} : captured;},
    canonicalValueJson: JSON.stringify};
  const held = new Function(...Object.keys(ports),
    'const ' + source.slice(entry.start, entry.end) + ';return heldSubmission;')(...Object.values(ports));
  return {held: () => held(captured), captured, calls, registry, host, installation, moon, prepared, requested, input,
    original(value) {return registry.originalSourceRequest(host, installation, host, value);}};
}

test('held request reconstruction retains its actual pending original before funded preparation', async () => {
  const f = heldRequestOriginalFixture(), resolved = await f.held();
  assert.deepEqual(f.calls, ['retain-original','prepare-original','bind-original','request-original','admit-plan']);
  assert.equal(resolved.requestInput, f.input);
  assert.equal(f.original(resolved.submission), resolved.submission);
  assert.equal(f.original(f.prepared), resolved.submission);
  assert.throws(() => f.original({...resolved.submission}), {code:'InstalledHostPreparationChanged'});
  resolved.requestInput.finish('returned');await Promise.resolve();await Promise.resolve();
  assert.throws(() => f.original(resolved.submission), {code:'InstalledHostPreparationChanged'});
  assert.throws(() => f.original(f.prepared), {code:'InstalledHostPreparationChanged'});
});

test('held reconstruction failure keeps its original cause and same pending cleanup retry', async () => {
  const primary = Object.freeze(new Error('original prepared failure'));
  const f = heldRequestOriginalFixture({failPreparation:true,failure:primary,
    finishFailure:new Error('first original input cleanup failure')});
  let failure;
  await assert.rejects(f.held(), cause => {
    failure=cause;return cause.cause===primary && cause.cleanupHandle.status().pending===true;
  });
  assert.deepEqual(f.calls,['retain-original','prepare-original','finish:failed']);
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  assert.deepEqual(f.calls,['retain-original','prepare-original','finish:failed','finish:failed']);
});

test('held reconstruction changed capture retires only its own pending original', async () => {
  const f=heldRequestOriginalFixture({changed:true});
  await assert.rejects(f.held(),{message:'HeldAcquisitionChanged'});
  assert.equal(f.calls.at(-1),'finish:failed');await Promise.resolve();await Promise.resolve();
  assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
});

test('held resume retains its original input until the actual physical-start handoff', async () => {
  const f=heldRequestOriginalFixture(),start=deferred(),entered=deferred(),accepted={};
  const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});let entry;
  (function visit(node){if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id.name==='resumeHeld'){assert.equal(entry,undefined);entry=node;}
    for(const child of Object.values(node))if(Array.isArray(child))child.forEach(visit);
    else if(child&&typeof child==='object')visit(child);
  })(tree);assert(entry);
  const ports={heldSubmission:()=>f.held(),retainInstalledHostRuntimeFailure,
    effectRun:{checkSupported(){assert.fail('No Effect');}},
    installedSourceFor(){assert.fail('No Source');},sourceProfile:undefined,
    async admitDefinition(submission){assert.equal(f.original(submission),submission);return accepted;},
    definitionOf:()=>undefined,runIdOf:()=> 'original-component-run',
    settleHeldRun(){},cancelHeldRun(){assert.fail('No cancellation');},
    async startDispatch(submission){assert.equal(f.original(submission),submission);entered.resolve();
      await start.promise;assert.equal(f.original(submission),submission);return 'started';}};
  const resume=new Function(...Object.keys(ports),'const '+source.slice(entry.start,entry.end)+';return resumeHeld;')(...Object.values(ports));
  const pending=resume({captured:f.captured,step:async()=>{},renew(){},preparationCancelled:()=>false,
    beforePhysicalStart(){},started(){}});
  await entered.promise;assert.equal(f.calls.some(value=>value.startsWith('finish:')),false);
  start.resolve();assert.equal(await pending,'started');
  assert.equal(f.calls.at(-1),'finish:returned');await Promise.resolve();await Promise.resolve();
  assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
});

function heldControl(name, ports) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  let entry;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === name) {
      assert.equal(entry, undefined); entry = node;
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(tree);
  assert(entry, name);
  return new Function(...Object.keys(ports), 'const ' + source.slice(entry.start, entry.end) +
    ';return ' + name + ';')(...Object.values(ports));
}

// Extract the actual route/getter rather than reproducing their branch logic.
function heldSourceFunction(name, ports) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  let entry;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === name ||
        node.type === 'Property' && node.method && node.key.name === name) {
      assert.equal(entry, undefined); entry = node.type === 'Property' ? node.value : node;
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(tree);
  assert(entry, name);
  const body = source.slice(entry.start, entry.end);
  return new Function(...Object.keys(ports), 'return (' +
    (entry.type === 'FunctionExpression' ? 'function' : '') + body + ');')(...Object.values(ports));
}

test('held resume adopts the same Request Plan before its original publication consumer', async () => {
  const record = {computeRuns:new WeakMap()}, run = {}, admitted = [];
  const clientOperationError = code => Object.assign(new Error(code), {code});
  const original = heldSourceFunction('managedComputePublicationOriginal', {record, clientOperationError});
  const route = heldSourceFunction('captureInstalledManagedRunRoute', {clientOperationError});
  const f = heldRequestOriginalFixture({preparePlan({request, moon, prepared, requested, preparation, requestOf}) {
    Object.assign(moon, {
      clientProgramSerializationOccurrences(actual) {assert.equal(actual,prepared);return [];},
      clientProgramInstalledManagedPublicationLimits(actual, program, maxBytes) {
        // The checked projection takes the selected Store object ceiling,
        // independently of the smaller output limits returned by this port.
        assert.equal(actual,run);assert.equal(program,prepared);assert.equal(maxBytes,512 * 1024 * 1024);
        return resultOutputLimitFields.map(name => localOutputLimits[name]);
      },
    });
    Object.assign(preparation, {
      admitResultPublicationRun(actual) {assert.equal(actual,prepared);admitted.push(actual);},
      prepareManagedComputeRun(runtime, program, identity, inference, invocation) {
        assert.equal(runtime,moon);assert.equal(program,prepared);assert.equal(identity,requested);
        assert.equal(inference,undefined);assert.equal(invocation,undefined);
        assert.equal(f.original(program),request);
        assert.equal(record.computeRuns.has(program),false,'No second Plan constructor');
        record.computeRuns.set(program,{runtime,prepared:program,value:run,closed:false});
      },
    });
    const admit = heldControl('admitPreparedSubmission', {preparation, requestOf, moon,
      inferSelections:new WeakMap(), admissionFailures:new WeakMap(), holderRefusal:undefined,
      prepareOrdinaryManagedRun:route({preparation,moon}), clientOperationError});
    return admit(request);
  }});
  const restored = await f.held();
  const publication = original(f.moon,f.prepared);
  assert.deepEqual(checkedLocalOutputLimits(f.moon,f.prepared,publication),localOutputLimits);
  assert.equal(publication.kind,'installed_run');assert.equal(publication.value,run);
  assert.deepEqual(admitted,[f.prepared]);assert.equal(f.original(f.prepared),restored.submission);
  assert.deepEqual(f.calls,['retain-original','prepare-original','bind-original','request-original','admit-plan','request-original']);
  restored.requestInput.finish('returned');
});

test('held resume forwards its one admitted ordinary Run through the physical-start handoff', async () => {
  const run = {}, accepted = {}, admitted = [];
  let constructions = 0, starts = 0;
  const clientOperationError = code => Object.assign(new Error(code), {code});
  const route = heldSourceFunction('captureInstalledManagedRunRoute', {clientOperationError});
  const f = heldRequestOriginalFixture({preparePlan({request, moon, prepared, requested, preparation, requestOf}, held) {
    moon.clientProgramSerializationOccurrences = actual => {
      assert.equal(actual, prepared); return [];
    };
    preparation.admitResultPublicationRun = actual => assert.equal(actual, prepared);
    preparation.prepareManagedComputeRun = (runtime, program, identity) => {
      assert.equal(runtime, moon); assert.equal(program, prepared); assert.equal(identity, requested);
      assert.equal(f.original(prepared), request);
      assert.equal(++constructions, 1, 'Resume must not construct or claim a second Run');
      return run;
    };
    const admit = heldControl('admitPreparedSubmission', {preparation, requestOf, moon,
      inferSelections:new WeakMap(), admissionFailures:new WeakMap(), holderRefusal:undefined,
      prepareOrdinaryManagedRun:route({preparation, moon}), clientOperationError});
    assert.equal(admit(request, held), undefined, 'The SDK admission callback remains void');
  }});
  const resume = heldControl('resumeHeld', {heldSubmission:()=>f.held(), retainInstalledHostRuntimeFailure,
    effectRun:{checkSupported(){assert.fail('No Effect');}},
    installedSourceFor(){assert.fail('No Source');}, sourceProfile:undefined,
    async admitDefinition(submission, requested, names, held) {
      assert.equal(f.original(submission), submission); assert.equal(requested, f.requested);
      assert.deepEqual(names, ['answer']); assert.equal(held.managedRun, run);
      admitted.push(held); return accepted;
    },
    definitionOf:()=>undefined, runIdOf:()=> 'original-component-run', settleHeldRun(){},
    cancelHeldRun(){assert.fail('No cancellation');},
    async startDispatch(submission, requested, actualAccepted, held) {
      assert.equal(f.original(submission), submission); assert.equal(requested, f.requested);
      assert.equal(actualAccepted, accepted); assert.equal(held, admitted[0]);
      assert.equal(held.managedRun, run); assert.equal(++starts, 1); return 'started';
    }});
  assert.equal(await resume({captured:f.captured, step:async()=>{}, renew(){},
    preparationCancelled:()=>false, beforePhysicalStart(){}, started(){}}), 'started');
  assert.equal(constructions, 1); assert.equal(starts, 1);
  assert.equal(f.calls.at(-1), 'finish:returned');
});

test('SDK managed admission remains void without a held Run handoff', () => {
  const prepared = {}, requested = {}, run = {}, submission = {preparedProgram:prepared};
  let constructions = 0;
  const admit = heldControl('admitPreparedSubmission', {
    preparation:{admitResultPublicationRun(value){assert.equal(value, prepared);}},
    requestOf(value){assert.equal(value, submission);return {requested, acquisitionCount:0, effectful:false};},
    moon:{clientProgramSerializationOccurrences(value){assert.equal(value, prepared);return [];}},
    inferSelections:new WeakMap(), admissionFailures:new WeakMap(), holderRefusal:undefined,
    prepareOrdinaryManagedRun(facts) {
      assert.equal(facts.preparedProgram, prepared); assert.equal(facts.requestIdentity, requested);
      assert.equal(++constructions, 1); return run;
    },
  });
  assert.equal(admit(submission), undefined);
  assert.equal(constructions, 1);
  assert.equal(Object.hasOwn(submission, 'managedRun'), false);
});

test('held Run forwarding preserves current and cancellation fences before physical start', async () => {
  for (const boundary of ['current', 'request-cancelled', 'run-cancelled']) {
    const marker = new Error('OriginalCurrentRefused'), finishes = [];
    const captured = {}, managedRun = {}, accepted = {}, requested = {};
    const submission = {preparedProgram:{}};
    let cancellations = 0;
    const resume = heldControl('resumeHeld', {retainInstalledHostRuntimeFailure,
      heldSubmission:async()=>({submission, requested, resultNames:['answer'], managedRun,
        requestInput:{finish(value){finishes.push(value);}}}),
      effectRun:{checkSupported(){assert.fail('No Effect');}}, sourceProfile:undefined,
      installedSourceFor(){assert.fail('No Source');},
      async admitDefinition(actual, request, names, held) {
        assert.equal(actual, submission); assert.equal(request, requested);
        assert.deepEqual(names, ['answer']); assert.equal(held.managedRun, managedRun); return accepted;
      },
      definitionOf:()=>({cancellationRequested:boundary==='run-cancelled'}),
      async cancelHeldRun(value){assert.equal(value, captured);cancellations++;},
      startDispatch(){assert.fail('No physical start beyond the original fence');},
    });
    const outcome = await resume({captured, step:async()=>{},
      renew(){if (boundary==='current') throw marker;},
      preparationCancelled:()=>boundary==='request-cancelled'});
    assert.deepEqual(outcome, boundary==='current' ? {refused:marker} : 'not_started');
    assert.equal(cancellations, boundary==='request-cancelled' ? 1 : 0);
    assert.deepEqual(finishes, ['returned']);
  }
});

test('held Effect keeps its existing definition-owned Plan constructor', async () => {
  const f = heldRequestOriginalFixture({effectful:true,preparePlan(){assert.fail('No duplicate Effect admission');}});
  const restored = await f.held();
  assert.equal(restored.effectful,true);assert.equal(f.calls.includes('admit-plan'),false);
  restored.requestInput.finish('returned');
});

test('held Plan admission failure preserves the same original input cleanup', async () => {
  for (const primary of [new Error('original Plan admission failure'),undefined]) {
    const f = heldRequestOriginalFixture({preparePlan(){throw primary;}});
    let rejected = false;
    try {await f.held();} catch (error) {rejected = true;assert.equal(error,primary);}
    assert.equal(rejected,true);assert.equal(f.calls.at(-1),'finish:failed');
    await Promise.resolve();await Promise.resolve();
    assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
  }
});

test('held resume successful start retains the same failed input return retry without restarting', async () => {
  const cleanup = new Error('original input return pending');
  const f = heldRequestOriginalFixture({finishFailure:cleanup, finishFailures:2});
  let starts = 0;
  const resume = heldControl('resumeHeld', {heldSubmission:()=>f.held(), retainInstalledHostRuntimeFailure,
    effectRun:{checkSupported(){assert.fail('No Effect');}},
    installedSourceFor(){assert.fail('No Source');}, sourceProfile:undefined,
    async admitDefinition(submission){assert.equal(f.original(submission),submission);return {};},
    definitionOf:()=>undefined, runIdOf:()=> 'original-component-run', settleHeldRun(){},
    cancelHeldRun(){assert.fail('No cancellation');},
    async startDispatch(submission){assert.equal(f.original(submission),submission);starts++;return 'started';}});
  let failure;
  await assert.rejects(resume({captured:f.captured,step:async()=>{},renew(){},
    preparationCancelled:()=>false,beforePhysicalStart(){},started(){}}), error => {
    failure = error; return error.cause === cleanup && error.cleanupHandle.status().pending === true;
  });
  assert.equal(starts,1);
  assert.equal(f.original(f.prepared).preparedProgram,f.prepared);
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  assert.equal(starts,1,'Retry only returns the SAME input; physical start is never retried');
  await Promise.resolve(); await Promise.resolve();
  assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
});

test('held abandonment keeps the original start failure including undefined and its same input retry', async () => {
  for (const primary of [new Error('original start failure'), undefined]) {
    const f = heldRequestOriginalFixture({finishFailure:new Error('original input return pending'), finishFailures:2});
    let starts = 0, failure;
    const abandon = heldControl('abandonHeld', {heldSubmission:()=>f.held(), retainInstalledHostRuntimeFailure,
      definitionOf:()=>({physicalStartReserved:false,preDispatchFailureConfirmed:false,dispatchReserved:false}),
      namespaceId:'original-namespace',
      async startRun(){starts++;throw primary;},
      journal:{markPreDispatchFailure(){assert.fail('No failure marker after failed admission');}}});
    await assert.rejects(abandon(f.captured), error => {
      failure=error; return Object.hasOwn(error,'primaryFailure') && error.primaryFailure === primary &&
        error.cause === primary && error.cleanupHandle.status().pending === true;
    });
    assert.equal(starts,1);
    await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
    assert.equal(failure.cleanupHandle.status().pending,true);
    assert.equal((await failure.cleanupHandle.retry()).pending,false);
    assert.equal(starts,1,'Retry owns only the original input return');
    await Promise.resolve(); await Promise.resolve();
    assert.throws(()=>f.original(f.prepared),{code:'InstalledHostPreparationChanged'});
  }
});


// Actual cold Model/Effect caller, Host registry and input-retainer wrapper.
// Native allocation, saved tuple admission, dispatch and physical cleanup are
// explicit ports; these controls issue no real Run, permission or stop ACK.
function coldModelEffectRequestFixture({prepareFailure, failPrepare = false,
  executeFailure, finishFailure, missingMaterial = false} = {}) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const nodes = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type) nodes.push(node);
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  const selected = nodes.filter(node => node.type === 'VariableDeclarator' && node.id.name === 'runRestoredModel');
  assert.equal(selected.length, 1);
  const methods = ['retainEffectRequestInput', 'bindSourceRequest'].map(name => {
    const found = nodes.filter(node => node.type === 'Property' && node.method && node.key.name === name);
    assert.equal(found.length, 1, name); return found[0];
  });
  const host = {}, installation = {}, originals = {}, moon = {}, prepared = {}, identity = {}, definition = {};
  const registry = createEmbeddedHostRegistry(() => true);
  registry.registerPreparation(host, installation, host);
  const snapshot = Object.freeze({requestId: 'same-original-request', principalId: 'actor',
    connection: 'same-connection', kind: 'program', input: Object.freeze({id: 'same-program'})});
  const events = [], receipt = {}, result = Object.freeze({status: 'waiting_checkpoint'});
  const execution = deferred(), entered = deferred();
  const intent = {}, material = 'same-original-materials';
  let submitted, finishes = 0;
  const original = value => registry.originalSourceRequest(host, installation, host, value);
  const manager = {retainRequestInput(request, originalIntent, captured, materialWire) {
    assert.strictEqual(this, manager); assert.strictEqual(original(request), request);
    assert.strictEqual(originalIntent, intent); assert.equal(captured, undefined); assert.equal(materialWire, material);
    assert.equal(submitted, undefined); submitted = request; events.push('retain');
    return {receipt, body: snapshot};
  }, finishSourceProducer(value, terminal) {
    assert.strictEqual(this, manager); assert.strictEqual(value, receipt);
    events.push('finish:' + terminal);
    if (++finishes === 1 && finishFailure !== undefined) throw finishFailure;
  }};
  const methodPorts = {moon, sourceManaged: manager, computeManaged: undefined, profiles: registry,
    host, originalInstallation: installation, originals,
    assertSourceManagedInstallationCurrent(actual, selected) {
      assert.strictEqual(actual, manager); assert.strictEqual(selected, originals);
    }, clientOperationError(code) {throw Object.assign(new Error(code), {code});}};
  const preparation = new Function(...Object.keys(methodPorts), 'return ({' + methods.map(node =>
    source.slice(node.start, node.end)).join(',') + '});')(...Object.values(methodPorts));
  const ownRef = {namespaceId: 'namespace', runDefinitionCid: 'same-definition'};
  const current = {requestId: snapshot.requestId, requestIdentity: identity,
    runDefinition: definition, runAdmissionEvidence: missingMaterial ? {} : {updateTargetRunOriginal: {materialsWire: material}}, ref: ownRef};
  const facts = {}, requested = {}, accepted = {ref: ownRef};
  const ports = {moon, control: {}, ref: ownRef, retained: current, token: {snapshot: {submission: snapshot}},
    assertCurrent() {}, canonicalValueJson: JSON.stringify,
    hostConnection: value => value.principalId === snapshot.principalId && value.connection === snapshot.connection,
    preparation, localPreparationCustody: installLocalPreparationRegistry(() => false),
    journal: {lookupOwnedDefinition(value) {
      assert.equal(value.requestId, snapshot.requestId); return current;
    }, originalSubmittedIntent(value) {
      assert.strictEqual(value, identity); events.push('original-intent');
      return {intent, assertCurrent() {events.push('intent-current');}};
    }, resolveDefinition(value) {assert.strictEqual(value, requested); return accepted;}},
    async prepareCapturedSubmission() {assert.fail('No unfunded saved Prepared admission');},
    prepareSubmit: Object.assign(async request => { assert.strictEqual(original(request), request);
      assert.notStrictEqual(request, snapshot); events.push('prepare');
      if (failPrepare) throw prepareFailure; return prepared;
    }, {restoreInferOriginal() {assert.fail('No pure Model replacement for an Effect request');},
      assertSubmittedIntent(value, original) {assert.strictEqual(value, prepared); assert.strictEqual(original, intent); events.push('same-intent');}}),
    requestOf(request) {
      assert.strictEqual(original(prepared), request); assert.strictEqual(request, submitted);
      events.push('request'); return {effectful: true, requested};
    }, namespaceId: ownRef.namespaceId,
    effectRun: {async restoreComputation(value) {assert.strictEqual(value, accepted); events.push('restore'); return facts;}},
    async admitEffectDefinition(request) {assert.strictEqual(request, submitted); events.push('admit'); return accepted;},
    async executeEffectComputation(value, target, sourceTarget, model) {
      assert.strictEqual(value, facts); assert.equal(target, undefined); assert.equal(sourceTarget, undefined);
      assert.strictEqual(model.token, ports.token); assert.strictEqual(original(prepared), submitted);
      events.push('execute'); entered.resolve();
      await execution.promise;
      if (executeFailure !== undefined) throw executeFailure;
      return result;
    }, record: {}, claim: {}, active: {}, runId: 'original-run', parentCheckpoint: undefined,
    retainInstalledHostRuntimeFailure};
  const invoke = new Function(...Object.keys(ports),
    'let restorationDispatchEntered=false,restorationStopConfirmed=false;' +
    'const restorationReclaimed=()=>!restorationDispatchEntered||restorationStopConfirmed;' +
    'return (' + source.slice(selected[0].init.start, selected[0].init.end) + ')();');
  return {invoke: () => invoke(...Object.values(ports)), original, prepared, events, result, entered,
    releaseExecution: () => execution.resolve(), submitted: () => submitted};
}

test('cold Model Effect retains the original pending request and derived Prepared through actual execution return', async () => {
  const f = coldModelEffectRequestFixture(), work = f.invoke(); await f.entered.promise;
  assert.deepEqual(f.events, ['original-intent', 'intent-current', 'retain', 'prepare', 'same-intent', 'request', 'admit', 'restore', 'execute']);
  assert.strictEqual(f.original(f.prepared), f.submitted());
  assert.throws(() => f.original({...f.submitted()}), {code: 'InstalledHostPreparationChanged'});
  f.releaseExecution(); assert.strictEqual(await work, f.result);
  assert.equal(f.events.at(-1), 'finish:returned');
  await Promise.resolve(); await Promise.resolve();
  assert.throws(() => f.original(f.prepared), {code: 'InstalledHostPreparationChanged'});
  assert.equal(f.events.filter(value => value === 'prepare').length, 1);
});

test('cold Model Effect keeps its exact preparation failure and same failed input return retry', async () => {
  const primary = Object.freeze(new Error('same-original-prepare-failure'));
  const f = coldModelEffectRequestFixture({failPrepare: true, prepareFailure: primary,
    finishFailure: new Error('same-original-input-return-pending')});
  let failure;
  await assert.rejects(f.invoke(), error => {
    failure = error; return error.cause === primary && error.cleanupHandle.status().pending === true;
  });
  assert.deepEqual(f.events, ['original-intent', 'intent-current', 'retain', 'prepare', 'finish:failed']);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(f.events, ['original-intent', 'intent-current', 'retain', 'prepare', 'finish:failed', 'finish:failed']);
});

test('cold Model Effect cannot return its request input before the same failed execution cleanup', async () => {
  let physicalPending = true;
  const primary = Object.assign(new Error('same-original-execution-failure'), {cleanupHandle: {
    status: () => ({pending: physicalPending}), async retry() {return {pending: physicalPending};}}});
  const f = coldModelEffectRequestFixture({executeFailure: primary}), work = f.invoke(); await f.entered.promise;
  f.releaseExecution(); let failure;
  await assert.rejects(work, error => {failure = error; return error.cause === primary;});
  assert.strictEqual(f.original(f.prepared), f.submitted());
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(f.events.some(value => value.startsWith('finish:')), false);
  physicalPending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(f.events.at(-1), 'finish:failed');
  await Promise.resolve(); await Promise.resolve();
  assert.throws(() => f.original(f.prepared), {code: 'InstalledHostPreparationChanged'});
});


test('cold Model Effect refuses absent original material before opening its Request input', async () => {
  const f = coldModelEffectRequestFixture({missingMaterial: true});
  await assert.rejects(f.invoke(), {message: 'ModelResumeOriginalMaterialsUnavailable'});
  assert.deepEqual(f.events, ['original-intent']);
});
