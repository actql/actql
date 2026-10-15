import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {createInstalledHttpChatRegistration} from './_internal/installed-http-chat.mjs';
import {installModelProviders} from '../../adapters/host-node/installed-model.mjs';
import {createInferIoNotification} from '../../adapters/host-node/infer-io-notification.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

const cid = x => `sha256:${x.repeat(64)}`;
function configuration() {
  // Explicit original-selection/installation doubles, not adopted numerical
  // values or a grant. Common checks these originals in an actual Run.
  const profile = {};
  const installation = Object.freeze({sdk: undefined,
    endpoint: 'https://fixture.invalid/chat', http_method: 'POST',
    streaming: false, completion_basis: 'generation_finish'});
  const rawCaptureSelection = Object.freeze({profile, installation, probability: undefined,
    retention: {}, metadata: {}, clock: {}, data: {}, selectedAt: 'selected',
    availableUntil: 'available', deleteBy: 'delete', extensionCeilingAt: 'ceiling',
    metadataDeleteBy: 'metadata', selectionAvailable: () => true});
  const nodeInstallation = Object.freeze({installation, probability: undefined,
    runtimeArtifactCid: cid('a'), layoutArtifactCid: cid('b'), layout: Object.freeze({
      response_profile: profile, runtime_artifact_cid: cid('a'), layout_artifact_cid: cid('b'),
      program_definition_cid: cid('c'), parameter_values_cid: cid('d'), barrier_cid: cid('e'),
      prepared_rows: 1n, retained_bytes: 7000n, execution_bytes: 3000n})});
  return {providerId: 'models/http-fixture', modelSelector: 'http-fixture', modelId: 'fixture',
    endpoint: installation.endpoint, headers: [['authorization', 'Bearer fixture-only']],
    taskCid: cid('1'), promptCid: cid('2'), outputSchemaCid: cid('3'),
    promptPayloadWire: '{"instructions":"é\\r\\n"}', rawCaptureSelection,
    originalReadInstallation: Object.freeze({nodeInstallation,
      bootstrap: Object.freeze({bootstrapRetainedBytes: 20n, bootstrapExecutionBytes: 10n,
        maxReservations: 8, maxHoldings: 8, maxDelegations: 8}),
      modelRetainedBytes: 100n, modelExecutionBytes: 10n}),
    bindingOriginals: Object.freeze(Object.fromEntries(Object.entries(
      providerBindingOriginals('models/http-fixture')).map(([name, value]) => [name, Object.freeze(value)]))),
    quantityCapacity: Object.freeze({limits: Object.freeze({tokens: 16n, costUnits: 0n, durationMs: 500n}),
      perAttempt: Object.freeze({tokens: 16n, costUnits: 0n, durationMs: 500n})}),
    projectionLimits: {maxBytes: 4096, maxDepth: 16, maxFrames: 32, maxNodes: 256, maxWork: 4096},
    requestLimits: {maxBytes: 4096, maxHeaderBytes: 128, maxHeaders: 4},
    responseLimits: {maxBytes: 512, maxChunkBytes: 512, maxChunks: 2, maxHeaderBytes: 64,
      observedHeaders: ['content-type']},
    fetch: () => assert.fail('No uninstalled send'), observeAt: () => '2026-10-14T00:00:00Z',
    observeEgress: () => ({}),
  };
}
function runtime(config) {
  const counts = {installs: 0, projections: 0, sends: 0};
  const request = {}, provider = {}, entry = {};
  const body = '{"model":"fixture","n":1,"stream":false,"messages":[{"role":"user","content":"é\\r\\n"}]}';
  const moon = {
    clientProgramModelResponseProfileTransportMatches(profile, ...limits) {
      assert.strictEqual(profile, config.rawCaptureSelection.profile);
      assert.deepEqual(limits, [4096, 512, 512, 2, 64]);
      return true;
    },
    clientProgramInstallAsyncModelProvider(id) { assert.equal(id, config.providerId); counts.installs++; return {}; },
    clientProgramProjectHTTPChatRequest(p, r, model, ...limits) {
      assert.equal(p, provider); assert.equal(r, request); assert.equal(model, 'fixture');
      assert.deepEqual(limits, [4096, 256, 16, 32, 4096]); counts.projections++;
      return {$tag: 1, _0: {_0: body, _1: cid('1'), _2: cid('2'), _3: cid('3'), _4: 'http-fixture'}};
    },
    clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(r, bytes, tokens, cost, duration, profile, installation, start) {
      assert.equal(r, request); assert.equal(bytes, BigInt(Buffer.byteLength(body)));
      assert.deepEqual([tokens, cost, duration], [16n, 0n, 500n]);
      assert.equal(profile, config.rawCaptureSelection.profile);
      assert.equal(installation, config.rawCaptureSelection.installation);
      return {$tag: 1, _0: {start}};
    },
    clientProgramModelPhysicalCallForRequest(e, r, poll, cancel, cleanup) {
      assert.equal(e, entry); assert.equal(r, request); return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedChat: response => ({kind: 'saved', response}),
  };
  config.fetch = (url, init) => {
    counts.sends++; assert.equal(url, 'https://fixture.invalid/chat');
    assert.equal(init.body, body); assert.equal(init.redirect, 'error');
    assert.deepEqual(init.headers, [['authorization', 'Bearer fixture-only']]);
    return new Response('{}', {headers: {'content-type': 'application/json'}});
  };
  return {moon, counts, request, provider, entry};
}
async function until(read, accept) {
  for (let i = 0; i < 40; i++) { const value = read(); if (accept(value)) return value; await turn(); }
  assert.fail('Finite independent installed HTTP observation unavailable');
}

test('SDK-free facade installs the existing exclusive async registration with no construction I/O', () => {
  const config = configuration(), f = runtime(config);
  const register = createInstalledHttpChatRegistration(config);
  const declaration = register(f.moon)[0];
  assert.equal(Object.hasOwn(declaration, 'invoke'), false);
  assert.equal(declaration.entryPersistence, 'async');
  assert.equal(declaration.rawCaptureSelection, config.rawCaptureSelection);
  const installed = installModelProviders(f.moon, register).get(config.providerId);
  assert.equal(installed.rawCaptureSelection.installation.sdk, undefined);
  assert.equal(installed.validatePrompt(cid('1'), 'http-fixture', config.promptPayloadWire), true);
  assert.equal(installed.validatePrompt(cid('1'), 'http-fixture', config.promptPayloadWire + ' '), false);
  assert.deepEqual(f.counts, {installs: 1, projections: 0, sends: 0});
});

test('installed HTTP preflight keeps original endpoint headers selectors and raw binder across mutation', async t => {
  const config = configuration(), f = runtime(config);
  const register = createInstalledHttpChatRegistration(config);
  config.endpoint = 'https://other.invalid/chat'; config.headers[0][1] = 'replacement';
  config.modelId = 'replacement'; config.requestLimits.maxBytes = 1;
  config.projectionLimits.maxWork = 0;
  const installed = installModelProviders(f.moon, register).get('models/http-fixture');
  let bind;
  const preflight = installed.physicalPreflight(f.request, createInferIoNotification(),
    callback => { bind = callback; }, f.provider);
  t.after(() => until(() => preflight.cleanup(), x => x));
  const plan = preflight.advance()._1;
  assert.equal(f.counts.sends, 0);
  let raw;
  const persistence = async (call, originalRaw) => { raw = originalRaw; return {response: {call, raw}}; };
  persistence.cleanup = () => true;
  bind({}, persistence);
  const call = plan.start(f.entry);
  const saved = await until(() => call.poll(), x => x.kind === 'saved');
  assert.equal(saved.response.raw, raw);
  assert.equal(raw.transportComplete, true);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.counts.sends, 1);
  assert.equal(f.counts.projections, 1);
});

test('missing originals foreign profile or an external SDK refuse before provider installation', () => {
  for (const change of [config => { config.originalReadInstallation = undefined; },
    config => { config.rawCaptureSelection = undefined; },
    ...[undefined, null].map(profile => config => {
      config.rawCaptureSelection = Object.freeze({...config.rawCaptureSelection, profile});
      const original = config.originalReadInstallation;
      config.originalReadInstallation = Object.freeze({...original,
        nodeInstallation: Object.freeze({...original.nodeInstallation,
          layout: Object.freeze({...original.nodeInstallation.layout, response_profile: profile})})});
    }),
    config => { config.rawCaptureSelection = Object.freeze({...config.rawCaptureSelection, profile: {}}); },
    config => { config.rawCaptureSelection = Object.freeze({...config.rawCaptureSelection,
      installation: Object.freeze({...config.rawCaptureSelection.installation, sdk: {package_name: 'foreign'}})}); }]) {
    const config = configuration(), f = runtime(config); change(config);
    assert.throws(() => createInstalledHttpChatRegistration(config), /HTTPChatOriginalInstallation/u);
    assert.equal(f.counts.installs, 0); assert.equal(f.counts.projections, 0); assert.equal(f.counts.sends, 0);
  }
});

test('HTTP facade refuses mismatched admitted transport bounds before provider or projection', () => {
  for (const outcome of [false, undefined]) {
    const config = configuration(), f = runtime(config);
    let matches = 0;
    f.moon.clientProgramModelResponseProfileTransportMatches = (profile, ...limits) => {
      matches++;
      assert.strictEqual(profile, config.rawCaptureSelection.profile);
      assert.deepEqual(limits, [4096, 512, 512, 2, 64]);
      return outcome;
    };
    const register = createInstalledHttpChatRegistration(config);
    assert.throws(() => register(f.moon), {message: 'HTTPChatOriginalTransportLimitsMismatch'});
    assert.equal(matches, 1);
    assert.deepEqual(f.counts, {installs: 0, projections: 0, sends: 0});
  }
});

test('missing Common runtime or original physical context refuses without projection or sending', () => {
  const config = configuration(), f = runtime(config);
  const register = createInstalledHttpChatRegistration(config);
  for (const name of ['clientProgramProjectHTTPChatRequest', 'clientProgramModelResponseProfileTransportMatches']) {
    assert.throws(() => register({...f.moon, [name]: undefined}), /HTTPChatOriginalRuntimeUnavailable/u);
  }
  const installed = installModelProviders(f.moon, register).get(config.providerId);
  for (const args of [[f.request, {}, () => {}, f.provider],
    [f.request, createInferIoNotification(), undefined, f.provider],
    [f.request, createInferIoNotification(), () => {}, undefined]]) {
    assert.throws(() => installed.physicalPreflight(...args), /HTTPChatOriginalPhysicalContextUnavailable/u);
  }
  assert.equal(f.counts.projections, 0); assert.equal(f.counts.sends, 0);
});

test('closed DATA configuration snapshots descriptor values without property callbacks', () => {
  const config = configuration(), f = runtime(config);
  let gets = 0;
  const proxy = new Proxy(config, {get() { gets++; return undefined; }});
  const register = createInstalledHttpChatRegistration(proxy);
  assert.equal(register(f.moon)[0].providerId, 'models/http-fixture');
  assert.equal(gets, 0);
  for (const extra of [Symbol('hidden'), 'hidden']) {
    const invalid = configuration();
    Object.defineProperty(invalid, extra, {value: 1});
    assert.throws(() => createInstalledHttpChatRegistration(invalid), /InvalidInstalledHTTPChatConfiguration/u);
  }
});

test('HTTP facade preserves explicit SDK null without treating absence as a completion capability', () => {
  const config = configuration(), f = runtime(config);
  config.rawCaptureSelection = Object.freeze({...config.rawCaptureSelection,
    installation: Object.freeze({...config.rawCaptureSelection.installation, sdk: null})});
  const installed = installModelProviders(f.moon, createInstalledHttpChatRegistration(config)).get(config.providerId);
  assert.equal(installed.rawCaptureSelection.installation.sdk, null);
  assert.equal(f.counts.projections, 0); assert.equal(f.counts.sends, 0);
});

test('header array and pair keep the inspected DATA without Proxy property callbacks', () => {
  const config = configuration(), f = runtime(config);
  let gets = 0;
  const pair = new Proxy(config.headers[0], {get() { gets++; return 'replacement'; }});
  config.headers = new Proxy([pair], {get() { gets++; return undefined; }});
  const register = createInstalledHttpChatRegistration(config);
  assert.equal(register(f.moon)[0].providerId, config.providerId);
  assert.equal(gets, 0);
  assert.equal(f.counts.sends, 0);
  const sparse = configuration(); sparse.headers = Array(1);
  assert.throws(() => createInstalledHttpChatRegistration(sparse), /InvalidInstalledHTTPChatHeaders/u);
  const accessor = configuration();
  Object.defineProperty(accessor.headers[0], '1', {get() { assert.fail('No header getter'); }});
  assert.throws(() => createInstalledHttpChatRegistration(accessor), /InvalidInstalledHTTPChatHeaders/u);
});


test('HTTP facade refuses a combined projection key before registration', () => {
  const config = configuration(), f = runtime(config);
  config.projectionLimits = {'maxBytes,maxDepth': 4096, maxFrames: 32, maxNodes: 256, maxWork: 4096};
  assert.throws(() => createInstalledHttpChatRegistration(config), /InvalidInstalledHTTPChatProjection/u);
  assert.deepEqual(f.counts, {installs: 0, projections: 0, sends: 0});
});

test('HTTP facade refuses a combined request key before registration', () => {
  const config = configuration(), f = runtime(config);
  config.requestLimits = {'maxBytes,maxHeaderBytes': 4096, maxHeaders: 4};
  assert.throws(() => createInstalledHttpChatRegistration(config), /InvalidInstalledHTTPChatRequestLimits/u);
  assert.deepEqual(f.counts, {installs: 0, projections: 0, sends: 0});
});


test('HTTP facade refuses mismatched outer array keys before indexed descriptor reads', () => {
  const config = configuration(), f = runtime(config);
  let indexedReads = 0;
  config.headers = new Proxy(config.headers, {
    ownKeys() { return ['length', 'extra']; },
    getOwnPropertyDescriptor(target, name) {
      if (name !== 'length') indexedReads++;
      return Reflect.getOwnPropertyDescriptor(target, name);
    },
  });
  assert.throws(() => createInstalledHttpChatRegistration(config), /InvalidInstalledHTTPChatHeaders/u);
  assert.equal(indexedReads, 0);
  assert.deepEqual(f.counts, {installs: 0, projections: 0, sends: 0});
});

test('HTTP facade refuses mismatched pair array keys before indexed descriptor reads', () => {
  const config = configuration(), f = runtime(config);
  let indexedReads = 0;
  config.headers = [new Proxy(config.headers[0], {
    ownKeys() { return ['length', '0', 'extra']; },
    getOwnPropertyDescriptor(target, name) {
      if (name !== 'length') indexedReads++;
      return Reflect.getOwnPropertyDescriptor(target, name);
    },
  })];
  assert.throws(() => createInstalledHttpChatRegistration(config), /InvalidInstalledHTTPChatHeaders/u);
  assert.equal(indexedReads, 0);
  assert.deepEqual(f.counts, {installs: 0, projections: 0, sends: 0});
});
