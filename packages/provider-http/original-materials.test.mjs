import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createInstalledHttpChatRegistration} from './index.mjs';
import {httpMaterialsConfiguration as configuration} from './original-materials.fixture.mjs';
import {installModelProviders} from '../../adapters/host-node/installed-model.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
function runtime(config) {
  const calls = [];
  const profile = Object.freeze({runtimeOwnedDouble:{}});
  const moon = Object.fromEntries(['clientProgramProjectHTTPChatRequest',
    'clientProgramModelRequestPreflight','clientProgramModelAsyncPhysicalRequestPlan',
    'clientProgramModelPhysicalCallForRequest','clientProgramModelPhysicalPending',
    'clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat']
    .map(name => [name, () => assert.fail('No Model, physical selector or Entry')]));
  moon.clientProgramInstallAsyncModelProvider = () => ({});
  moon.clientProgramReadModelResponseProfile = (...args) => {
    calls.push(['profile', ...args]); return {$tag:1,_0:profile};
  };
  moon.clientProgramAdmitEffectDependencyBody = (...args) => {
    calls.push(['policy', ...args]); return {$tag:1,_0:Object.freeze({kind:args[0],wire:args[2]})};
  };
  moon.clientProgramModelResponseProfileTransportMatches = (original, ...bounds) => {
    assert.strictEqual(original, profile);
    assert.deepEqual(bounds, [config.requestLimits.maxBytes, config.responseLimits.maxBytes,
      config.responseLimits.maxChunkBytes, config.responseLimits.maxChunks, config.responseLimits.maxHeaderBytes]);
    return true;
  };
  return {moon, calls, profile};
}

test('HTTP materials snapshot original DATA once and use only the Host callback runtime', () => {
  const config = configuration(), f = runtime(config);
  const wire = config.originalMaterials.responseProfile.wire;
  let gets = 0;
  const supplied = config.originalMaterials;
  config.originalMaterials = new Proxy(supplied, {get() {gets++; assert.fail('No getter reread');}});
  const register = createInstalledHttpChatRegistration(config);
  assert.equal(f.calls.length, 0);
  supplied.responseProfile.wire = '{}';
  config.headers[0][1] = 'replacement';
  config.projectionLimits.maxWork = 0;
  const installed = installModelProviders(f.moon, register).get(config.providerId);
  assert.equal(gets, 0);
  assert.equal(f.calls.length, 5);
  assert.equal(f.calls[0][1], wire);
  assert.strictEqual(installed.rawCaptureSelection.profile, f.profile);
  assert.strictEqual(installed.originalReadInstallation.nodeInstallation.layout.response_profile, f.profile);
  assert.equal(installed.rawCaptureSelection.installation.sdk, null);
  assert.throws(() => register(f.moon), /HTTPOriginalInstallationReused/u);
  assert.throws(() => register({...f.moon}), /HTTPOriginalInstallationReused/u);
});

test('HTTP missing runtime does not spend the callback or start partial admission', () => {
  const config = configuration(), f = runtime(config);
  const register = createInstalledHttpChatRegistration(config);
  for (const missing of [null, undefined, {}]) {
    assert.throws(() => register(missing), /HTTPChatOriginalRuntimeUnavailable/u);
  }
  assert.equal(f.calls.length, 0);
  assert.ok(register(f.moon)[0]);
});

test('HTTP closed materials reject missing policies opaque mixtures accessors and fake SDKs', () => {
  for (const change of [c => delete c.originalMaterials.policyOriginals.clock,
    c => {c.rawCaptureSelection = {};}, c => {c.originalReadInstallation = {};},
    c => {c.originalMaterials.rawCaptureSelection.profile = {};},
    c => {c.originalMaterials.installation.sdk = {};},
    c => {c.originalMaterials.installation.sdk = undefined;},
    c => {Object.defineProperty(c.originalMaterials.responseProfile, 'wire',
      {get() {assert.fail('Do not invoke body accessors');}, enumerable:true});},
    c => {c.originalMaterials[Symbol('extra')] = 1;}]) {
    const config = configuration(); change(config);
    assert.throws(() => createInstalledHttpChatRegistration(config), TypeError);
  }
});

test('HTTP material refusal spends only the original callback and never falls back', () => {
  for (const refusal of ['profile', 'policy', 'missing']) {
    const config = configuration(), f = runtime(config);
    if (refusal === 'profile') f.moon.clientProgramReadModelResponseProfile = () => ({$tag:0,_0:{}});
    if (refusal === 'policy') f.moon.clientProgramAdmitEffectDependencyBody = () => ({$tag:0,_0:{}});
    if (refusal === 'missing') f.moon.clientProgramReadModelResponseProfile = () => ({$tag:1});
    const register = createInstalledHttpChatRegistration(config);
    assert.throws(() => register(f.moon), {code:'HTTPOriginalMaterialsRefused'});
    const before = f.calls.length;
    assert.throws(() => register(f.moon), /HTTPOriginalInstallationReused/u);
    assert.equal(f.calls.length, before);
  }
});

test('HTTP material quantities and parser bounds preserve their finite domains', () => {
  for (const value of [-1n, 9223372036854775808n, 1, '1']) {
    const config = configuration();
    config.originalMaterials.originalReadInstallation.nodeInstallation.layout.prepared_rows = value;
    assert.throws(() => createInstalledHttpChatRegistration(config), {code:'InvalidHTTPOriginalMaterials'});
  }
  const config = configuration(); config.originalMaterials.readerLimits.maxNodes = 2147483648;
  assert.throws(() => createInstalledHttpChatRegistration(config), {code:'InvalidHTTPOriginalMaterials'});
});

test('actual HTTP Common readers bind original wire CID policies and finite acquisition limits', async () => {
  const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const installed = installModelProviders(moon, createInstalledHttpChatRegistration(configuration()))
    .get('models/http-materials');
  assert.strictEqual(installed.rawCaptureSelection.profile,
    installed.originalReadInstallation.nodeInstallation.layout.response_profile);
  assert.equal(moon.clientProgramModelRawSelectionOriginals(...['retention','metadata','clock','data']
    .map(name => installed.rawCaptureSelection[name])).length, 4);
  for (const change of [c => {c.originalMaterials.responseProfile.cid = cid('0');},
    c => {c.originalMaterials.responseProfile.wire = '{}';},
    c => {c.originalMaterials.policyOriginals.clock.cid = cid('0');},
    c => {c.originalMaterials.readerLimits.maxBytes = 1;},
    c => {c.originalMaterials.readerLimits.maxWork = 1;}]) {
    const config = configuration(); change(config);
    assert.throws(() => createInstalledHttpChatRegistration(config)(moon), {code:'HTTPOriginalMaterialsRefused'});
  }
  for (const [section, key] of [['requestLimits','maxBytes'], ['responseLimits','maxBytes'],
    ['responseLimits','maxChunkBytes'], ['responseLimits','maxChunks'], ['responseLimits','maxHeaderBytes']]) {
    const config = configuration(); config[section][key]++;
    assert.throws(() => createInstalledHttpChatRegistration(config)(moon), /HTTPChatOriginalTransportLimitsMismatch/u);
  }
});

test('actual installed HTTP Host supplies the runtime and rejects reuse without Provider I/O', t => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('./materials-host.fixture.mjs', import.meta.url))],
    {env:{PATH:process.env.PATH},encoding:'utf8',timeout:10000,maxBuffer:1024*1024});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {callbacks:2,hostClosed:true,providerCalls:0,
    coreScopes:0,normalNumericProfile:null,publicE2E:0});
  t.diagnostic('Actual Host registration/SQLite close only; no Run, Scope funding, SDK or Provider send');
});
