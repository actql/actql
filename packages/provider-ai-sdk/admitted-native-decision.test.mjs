// Actual pinned SDK with synthetic fetch, explicit Common/Plan/Entry/raw
// doubles. No installed native capability, funded startup or Provider traffic.
import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {createAdmittedTypeSafeDecisionPreflight} from './_internal/native-decision-preflight.mjs';
import {createInstalledTypeSafeDecisionRegistration} from './_internal/installed-typesafe-decision.mjs';

function fixture(change = {}) {
  const request = {}, provider = {}, cursor = {}, projected = {}, entry = {}, probability = {};
  let emitterRetired = false, viewRetired = false, releaseRaw = false;
  let releaseView = true, releaseEmitter = true;
  const counts = {children: 0, steps: 0, emitterRetires: 0, viewRetires: 0, plans: 0, sends: 0, saves: 0};
  const body = '{"answers":{"q0000000000":{"type":"noul","noul":0.25}}}';
  const moon = {
    clientProgramStartNativeDecisionProjection(p, r, ...limits) {
      assert.equal(p, provider); assert.equal(r, request);
      assert.deepEqual(limits, [4096, 100, 10, 20, 1000]); counts.children++;
      return {$tag: 1, _0: cursor};
    },
    clientProgramAdvanceNativeDecisionProjection(c) {
      assert.equal(c, cursor); assert.equal(emitterRetired, false); counts.steps++;
      return {$tag: 1, _0: counts.steps === 1 ? undefined : projected};
    },
    clientProgramRetireNativeDecisionProjection(c) {
      assert.equal(c, cursor); if (!releaseEmitter) throw Error('OriginalEmitterRetirementPending');
      emitterRetired = true; counts.emitterRetires++;
    },
    clientProgramRetireNativeDecisionRequest(view) {
      assert.equal(view, projected); if (!releaseView) throw Error('OriginalViewRetirementPending');
      viewRetired = true; counts.viewRetires++;
    },
    clientProgramNativeDecisionRequestMatches: (view, p, r) => !viewRetired &&
      view === projected && p === provider && r === request,
    clientProgramNativeDecisionRequestBinding: () => ({_0: 'task', _1: 'prompt', _2: 'schema', _3: 'native'}),
    clientProgramNativeDecisionRequestWires: () => ({_0: '"é\\r\\n"',
      _1: '{"q0000000000":{"type":"boolean","instructions":""}}'}),
    // Match the real bridge Result/tuple adaptation, rather than treating
    // the typed inner preflight's advance as the raw JS callback tuple.
    clientProgramModelRequestPreflight: (advance, cleanup) => ({
      advance() {
        const value = advance();
        if (value._0 === false && value._1 === undefined) return {$tag: 1, _0: undefined};
        if (value._0 === true && value._1 !== undefined) return {$tag: 1, _0: value._1};
        return {$tag: 0, _0: 'InvalidProvider'};
      }, cleanup,
    }),
    clientProgramModelAsyncNativeDecisionRequestPlan(r, view, p, bytes, tokens, cost, duration, profile, installation, prob, start) {
      assert.equal(r, request); assert.equal(view, projected); assert.equal(p, provider);
      assert.equal(prob, probability); assert.equal(emitterRetired, true); assert.equal(viewRetired, false);
      assert(bytes > 0n); assert.deepEqual([tokens, cost, duration], [128n, 0n, 1000n]);
      counts.plans++;
      return {$tag: 1, _0: {start: e => viewRetired ? undefined : start(e)}};
    },
    clientProgramModelPhysicalCallForRequest(e, r, poll, cancel, cleanup) {
      assert.equal(e, entry); assert.equal(r, request); return {poll, cancel, cleanup};
    },
    clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
    clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
    clientProgramModelPhysicalSavedNativeDecision(response, view, p, prob) {
      assert.equal(viewRetired, false); assert.equal(view, projected); assert.equal(p, provider); assert.equal(prob, probability);
      return {$tag: 1, _0: {kind: 'saved', response}};
    },
    clientProgramModelRequestGeneration: () => assert.fail('Native installer must not read generation defaults'),
  };
  const config = {moon, request, admittedProvider: provider, probability,
    projectionLimits: {maxBytes: 4096, maxNodes: 100, maxDepth: 10, maxFrames: 20, maxWork: 1000},
    taskCid: 'task', promptCid: 'prompt', outputSchemaCid: 'schema', modelSelector: 'native',
    modelId: 'jev-latest', baseURL: 'https://fixture.invalid/v1', apiKey: 'fixture-only',
    maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16,
    profile: {}, installation: {}, quantities: {tokens: 128n, costUnits: 0n, durationMs: 1000n},
    responseLimits: {maxBytes: 512, maxChunkBytes: 512, maxChunks: 4, maxHeaderBytes: 64},
    notify() {}, observeAt: () => '2026-10-14T00:00:00.000Z',
    checked: value => {if (value?.$tag !== 1) throw Error('OriginalPlanRefused'); return value._0;},
    fetch(url, init) {
      counts.sends++; assert.equal(url, 'https://fixture.invalid/v1/systemone');
      assert.deepEqual(JSON.parse(init.body), {model: 'jev-latest', state: 'é\r\n',
        questions: {q0000000000: {type: 'noul', instructions: ''}}});
      return new Response(body, {headers: {'content-type': 'application/json'}});
    },
    persistRaw(call, raw) {
      counts.saves++; assert.deepEqual(Buffer.from(raw.body), Buffer.from(body));
      return Promise.resolve({response: Object.freeze({fixtureSavedRaw: true})});
    }, cleanupRaw: () => releaseRaw,
    ...change,
  };
  return {config, counts, moon, projected, entry,
    releaseRaw: () => {releaseRaw = true;},
    emitterAllowed: value => {releaseEmitter = value;}, viewAllowed: value => {releaseView = value;},
    viewRetired: () => viewRetired};
}
async function until(read, accept) {
  for (let count = 0; count < 100; count++) {const value = read(); if (accept(value)) return value; await turn();}
  assert.fail('Finite private native composition did not settle');
}
async function release(f, port) {f.releaseRaw(); f.emitterAllowed(true); f.viewAllowed(true); await until(() => port.preflight.cleanup(), Boolean);}

test('admitted native projection starts lazily and preserves escaped view until outer cleanup', async t => {
  const f = fixture(), port = createAdmittedTypeSafeDecisionPreflight(f.config);
  t.after(() => release(f, port));
  assert.equal(f.counts.children, 0); assert.equal(f.counts.sends, 0);
  const plan = (await until(() => port.preflight.advance(), value => value.$tag === 1 && value._0 !== undefined))._0;
  assert.deepEqual({...f.counts}, {children: 1, steps: 2, emitterRetires: 1, viewRetires: 0, plans: 1, sends: 0, saves: 0});
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'saved');
  assert.equal(call.cleanup(), false); assert.equal(port.preflight.cleanup(), false);
  assert.equal(f.viewRetired(), false);
  f.releaseRaw(); await until(() => call.cleanup(), Boolean);
  assert.equal(f.viewRetired(), false, 'physical call cleanup is before Common raw-child retirement');
  assert.equal(port.preflight.cleanup(), true);
  assert.equal(port.preflight.cleanup(), true);
  assert.equal(f.counts.viewRetires, 1);
  assert.equal(plan.start(f.entry), undefined);
  assert.equal(f.counts.sends, 1); assert.equal(f.counts.saves, 1);
});

test('native outer cleanup keeps emitter and escaped view responsibilities after retirement failure', async t => {
  const f = fixture(); f.emitterAllowed(false);
  const port = createAdmittedTypeSafeDecisionPreflight(f.config); t.after(() => release(f, port));
  const refused = await until(() => port.preflight.advance(), value => value.$tag === 0);
  assert.equal(refused._0, 'InvalidProvider'); assert.equal(f.counts.sends, 0);
  assert.equal(port.preflight.cleanup(), false); assert.equal(f.counts.viewRetires, 0);
  f.emitterAllowed(true); f.viewAllowed(false);
  assert.equal(port.preflight.cleanup(), false); assert.equal(f.counts.emitterRetires, 1);
  f.viewAllowed(true); assert.equal(port.preflight.cleanup(), true);
  assert.equal(f.counts.viewRetires, 1); assert.equal(f.counts.children, 1);
});

test('native projection refusal cannot fall back to generation or allocate a second child', async t => {
  const f = fixture();
  f.moon.clientProgramAdvanceNativeDecisionProjection = () => ({$tag: 0, _0: 'Unsupported'});
  const port = createAdmittedTypeSafeDecisionPreflight(f.config); t.after(() => release(f, port));
  assert.equal((await until(() => port.preflight.advance(), value => value.$tag === 0))._0, 'InvalidProvider');
  for (let count = 0; count < 3; count++) assert.equal(port.preflight.advance().$tag, 0);
  assert.equal(f.counts.children, 1); assert.equal(f.counts.plans, 0); assert.equal(f.counts.sends, 0);
});

test('native cancellation before projected SDK preparation retains same child cleanup', async t => {
  const signal = new AbortController(), f = fixture({signal: signal.signal});
  const port = createAdmittedTypeSafeDecisionPreflight(f.config); t.after(() => release(f, port));
  assert.equal(port.preflight.advance().$tag, 1); signal.abort();
  assert.equal(port.preflight.advance().$tag, 0);
  assert.equal(f.counts.sends, 0); assert.equal(f.counts.viewRetires, 0);
  assert.equal(port.preflight.cleanup(), true); assert.equal(f.counts.emitterRetires, 1);
});

test('missing native runtime or probability refuses before the child is allocated', () => {
  for (const name of ['clientProgramStartNativeDecisionProjection',
    'clientProgramRetireNativeDecisionRequest', 'clientProgramModelPhysicalSavedNativeDecision']) {
    const f = fixture(); delete f.moon[name];
    assert.throws(() => createAdmittedTypeSafeDecisionPreflight(f.config), /RuntimeUnavailable/);
    assert.equal(f.counts.children, 0); assert.equal(f.counts.sends, 0);
  }
  const f = fixture({probability: undefined});
  assert.throws(() => createAdmittedTypeSafeDecisionPreflight(f.config), /RuntimeUnavailable/);
});

test('native projection clamps are exact read-once DATA, not getter or comma-key substitutes', async t => {
  const f = fixture();
  for (const limits of [Object.assign(Object.create(f.config.projectionLimits), {'maxBytes,maxDepth,maxFrames,maxNodes,maxWork': 1}),
    {...f.config.projectionLimits, maxWork: -1}, {...f.config.projectionLimits, maxBytes: 2147483648},
    {...f.config.projectionLimits, get maxNodes() {assert.fail('Getter not accepted');}}]) {
    assert.throws(() => createAdmittedTypeSafeDecisionPreflight({...f.config, projectionLimits: limits}), /ProjectionLimits/);
  }
  const port = createAdmittedTypeSafeDecisionPreflight(f.config); t.after(() => release(f, port));
  f.config.projectionLimits.maxBytes = 1;
  assert.equal(port.preflight.advance().$tag, 1);
  assert.equal(f.counts.children, 1);
});

function installedConfiguration(f) {
  const cid = value => `sha256:${value.repeat(64)}`, profile = Object.freeze({});
  const probability = Object.freeze(f.config.probability);
  const sdk = Object.freeze({package_name: '@ai-sdk/typesafe-ai', version: '3.0.13',
    interface: 'v4', lock_artifact_cid: cid('a')});
  const installation = Object.freeze({sdk, endpoint: 'https://fixture.invalid/v1/systemone',
    http_method: 'POST', streaming: false, completion_basis: 'native_decision'});
  const nodeInstallation = Object.freeze({probability,
    layout: Object.freeze({response_profile: profile})});
  const config = {providerId: 'models/native-fixture', modelSelector: 'native', modelId: 'jev-latest',
    baseURL: 'https://fixture.invalid/v1', apiKey: 'fixture-only', taskCid: cid('b'), promptCid: cid('c'),
    outputSchemaCid: cid('d'), promptPayloadWire: '{"format":"actql.decision_prompt/0.1"}',
    originalReadInstallation: Object.freeze({bootstrap: Object.freeze({}), nodeInstallation}),
    rawCaptureSelection: Object.freeze({profile, installation, probability}),
    bindingOriginals: Object.freeze({configuration: Object.freeze({}),
      configurationContract: Object.freeze({}), installationRevision: Object.freeze({})}),
    quantityCapacity: Object.freeze({limits: Object.freeze(f.config.quantities),
      perAttempt: Object.freeze(f.config.quantities)}),
    projectionLimits: {...f.config.projectionLimits},
    requestLimits: {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16},
    responseLimits: f.config.responseLimits, fetch: f.config.fetch,
    observeAt: f.config.observeAt, observeEgress() {}};
  f.moon.clientProgramInstallAsyncModelProvider = () => ({});
  f.moon.clientProgramNativeDecisionRequestBinding = () => ({_0: cid('b'), _1: cid('c'), _2: cid('d'), _3: 'native'});
  return config;
}

test('private native Host registration consumes the real caller shape with deferred raw binder', async t => {
  const f = fixture(), config = installedConfiguration(f);
  const register = createInstalledTypeSafeDecisionRegistration(config), raw = register(f.moon)[0];
  assert.equal(raw.entryPersistence, 'async'); assert.equal(Object.hasOwn(raw, 'invoke'), false);
  assert.equal(raw.originalReadInstallation, config.originalReadInstallation);
  assert.equal(raw.validatePrompt(config.taskCid, 'native', config.promptPayloadWire), true);
  assert.equal(raw.validatePrompt(config.taskCid, 'foreign', config.promptPayloadWire), false);
  config.modelId = 'replacement'; config.apiKey = 'replacement'; config.projectionLimits.maxBytes = 1;
  let bind, binds = 0;
  const preflight = raw.physicalPreflight(f.config.request, {notify() {}},
    callback => {assert.equal(bind, undefined); bind = callback; binds++;}, f.config.admittedProvider);
  const port = {preflight}; t.after(() => release(f, port));
  const plan = (await until(() => preflight.advance(), value => value.$tag === 1 && value._0 !== undefined))._0;
  assert.equal(f.counts.sends, 0); assert.equal(binds, 1);
  const persistence = f.config.persistRaw; persistence.cleanup = f.config.cleanupRaw;
  bind(Object.freeze({fixtureRegistration: true}), persistence);
  assert.throws(() => bind(Object.freeze({}), persistence), /BindingUnavailable/);
  const call = plan.start(f.entry);
  await until(() => call.poll(), value => value.kind === 'saved');
  assert.equal(f.counts.sends, 1); assert.equal(f.viewRetired(), false);
  f.releaseRaw(); await until(() => call.cleanup(), Boolean);
  assert.equal(f.viewRetired(), false); assert.equal(preflight.cleanup(), true);
  assert.equal(f.counts.viewRetires, 1);
});

test('native installer refuses unsupported installation and physical context before children', () => {
  const f = fixture(), config = installedConfiguration(f);
  for (const change of [
    {originalReadInstallation: undefined},
    {rawCaptureSelection: Object.freeze({...config.rawCaptureSelection, probability: Object.freeze({})})},
    {rawCaptureSelection: Object.freeze({...config.rawCaptureSelection,
      installation: Object.freeze({...config.rawCaptureSelection.installation, completion_basis: 'generation_finish'})})},
    {rawCaptureSelection: Object.freeze({...config.rawCaptureSelection,
      installation: Object.freeze({...config.rawCaptureSelection.installation,
        sdk: Object.freeze({...config.rawCaptureSelection.installation.sdk, package_name: '@ai-sdk/openai'})})})},
  ]) assert.throws(() => createInstalledTypeSafeDecisionRegistration({...config, ...change}), /Installation/);
  const raw = createInstalledTypeSafeDecisionRegistration(config)(f.moon)[0];
  assert.throws(() => raw.physicalPreflight(f.config.request, undefined, () => {}, f.config.admittedProvider), /ContextUnavailable/);
  assert.throws(() => raw.physicalPreflight(f.config.request, {notify() {}}, undefined, f.config.admittedProvider), /ContextUnavailable/);
  assert.equal(f.counts.children, 0); assert.equal(f.counts.sends, 0);
});

test('native installer validates all runtime hooks before creating the preflight callback', () => {
  const f = fixture(), config = installedConfiguration(f);
  const register = createInstalledTypeSafeDecisionRegistration(config);
  delete f.moon.clientProgramModelPhysicalSavedNativeDecision;
  assert.throws(() => register(f.moon), /RuntimeUnavailable/);
  assert.equal(f.counts.children, 0); assert.equal(f.counts.sends, 0);
});

test('native installer borrows the original opaque probability without JS freeze as authority', () => {
  const f = fixture(), config = installedConfiguration(f), probability = {};
  const raw = Object.freeze({...config.rawCaptureSelection, probability});
  const original = Object.freeze({...config.originalReadInstallation,
    nodeInstallation: Object.freeze({...config.originalReadInstallation.nodeInstallation, probability})});
  assert.equal(Object.isFrozen(probability), false);
  const selected = createInstalledTypeSafeDecisionRegistration({...config,
    originalReadInstallation: original, rawCaptureSelection: raw})(f.moon)[0];
  assert.equal(selected.rawCaptureSelection.probability, probability);
  assert.equal(f.counts.children, 0); assert.equal(f.counts.sends, 0);
});

test('native installer checks exact physical ceilings against its original profile before returning a selector',()=>{
  for(const accepted of [false,undefined,true]){
    const f=fixture(),config=installedConfiguration(f),seen=[];
    f.moon.clientProgramModelResponseProfileTransportMatches=function(profile,...limits){
      assert.equal(this,f.moon);
      seen.push([profile,...limits]);
      return accepted;
    };
    const register=createInstalledTypeSafeDecisionRegistration(config);
    if(accepted===true)assert.equal(register(f.moon).length,1);
    else assert.throws(()=>register(f.moon),{message:'TypeSafeOriginalTransportLimitsMismatch'});
    assert.deepEqual(seen,[[config.rawCaptureSelection.profile,4096,512,512,4,64]]);
    assert.equal(f.counts.children,0);assert.equal(f.counts.plans,0);
    assert.equal(f.counts.sends,0);assert.equal(f.counts.saves,0);
  }
});

test('native admitted preflight refuses missing or nontrue profile support before projection or raw binder',()=>{
  for(const accepted of ['missing',false,undefined]){
    const f=fixture();let binds=0,checks=0;
    if(accepted!=='missing')f.moon.clientProgramModelResponseProfileTransportMatches=(profile,...limits)=>{
      checks++;assert.equal(profile,f.config.profile);
      assert.deepEqual(limits,[4096,512,512,4,64]);return accepted;
    };
    assert.throws(()=>createAdmittedTypeSafeDecisionPreflight({...f.config,
      persistRaw:undefined,cleanupRaw:undefined,rawCaptureBinder(){binds++;}}),
    accepted==='missing'?{message:'TypeSafeOriginalTransportLimitsUnavailable'}:
      {message:'TypeSafeOriginalTransportLimitsMismatch'});
    assert.equal(checks,accepted==='missing'?0:1);
    assert.equal(f.counts.children,0);assert.equal(binds,0);
    assert.equal(f.counts.sends,0);
  }
});
