import test from 'node:test';
import assert from 'node:assert/strict';
import {createConfiguredUndiciRegisteredSdkRegistration} from './_internal/installed-openai-chat.mjs';
import {createInferIoNotification} from '../../adapters/host-node/infer-io-notification.mjs';

const cid=character=>`sha256:${character.repeat(64)}`;

test('registered physical route consumes the same installed SDK and credential without Chat runtime exports', () => {
  const providerId = 'models/fixture', modelSelector = 'fixture-chat', modelId = 'provider-model';
  const endpoint = 'https://provider.fixture.invalid/v1/messages';
  const profile = {};
  const sdk = Object.freeze({package_name: '@test/provider-sdk', version: '1.0.0',
    interface: 'v4', lock_artifact_cid: cid('a')});
  const installation = Object.freeze({endpoint, sdk, build_artifact_cid: cid('b'),
    http_method:'POST', streaming:false, completion_basis:'generation_finish'});
  const rawCaptureSelection = Object.freeze({profile, installation, probability: undefined});
  const originalReadRecipe = Object.freeze({bootstrap: Object.freeze({}),
    nodeInstallation: Object.freeze({installation, layout: Object.freeze({response_profile: profile})})});
  const requestLimits = {maxBytes:4096,maxHeaderBytes:4096,maxHeaders:16};
  const responseLimits = {maxBytes:1024,maxChunkBytes:1024,maxChunks:4,maxHeaderBytes:128};
  const config = {providerId, taskCid:cid('c'), promptCid:cid('d'), outputSchemaCid:cid('e'),
    promptPayloadWire:'{}', originalReadRecipe, rawCaptureSelection,
    bindingOriginals:Object.freeze({configuration:Object.freeze({}),configurationContract:Object.freeze({}),
      installationRevision:Object.freeze({})}),
    quantityCapacity:Object.freeze({limits:Object.freeze({}),perAttempt:Object.freeze({})}),
    projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
    requestLimits,responseLimits,
    physicalAcquisitionLimits:{maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64},
    observeAt:()=> '2026-10-13T00:00:00.000Z',observeEgress:()=>({})};
  const route = Object.freeze({providerId, selector:modelSelector, modelId, apiMode:'messages', endpoint});
  const transport = Object.freeze({reference:'FIXTURE_API_KEY',header:'x-api-key',endpoint,
    prefix:'',placeholder:'fixture-marker'});
  const registration = Object.freeze({route,sdkPackage:sdk.package_name,sdkVersion:sdk.version,
    adapterArtifactCid:installation.build_artifact_cid,lockArtifactCid:sdk.lock_artifact_cid,
    credential:Object.freeze({transport})});
  const moon = Object.fromEntries(['clientProgramStartAdmittedStructuredSdkProjection',
    'clientProgramAdmittedStructuredSdkRouteMatches', 'clientProgramModelStructuredRequestPlan',
    'clientProgramModelPhysicalSavedStructured', 'clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection', 'clientProgramInstallAsyncModelProvider',
    'clientProgramModelRequestGeneration', 'clientProgramModelRequestPreflight',
    'clientProgramModelPhysicalCallForRequest', 'clientProgramModelPhysicalPending',
    'clientProgramModelPhysicalUnknown'].map(port=>[port,()=>assert.fail('Unexpected physical work')]));
  moon.clientProgramModelResponseProfileTransportMatches = (original,...limits)=>{
    assert.strictEqual(original,profile);
    assert.deepEqual(limits,[4096,1024,1024,4,128]);
    return true;
  };
  const timeouts = {connectMs: 100, headersMs: 200, bodyMs: 300, callMs: 500};
  assert.throws(() => createConfiguredUndiciRegisteredSdkRegistration(config, {...timeouts, bodyMs: 0}, 64, registration),
    {code: 'UndiciOriginalTimeoutsUnavailable'});
  const register = (selected = registration) =>
    createConfiguredUndiciRegisteredSdkRegistration(config, timeouts, 64, selected);
  const [entry] = register()(moon);
  assert.strictEqual(entry.registeredSdk, registration);
  assert.strictEqual(entry.rawCaptureSelection, config.rawCaptureSelection);
  assert.equal(Object.hasOwn(entry, 'sdkStaticOriginals'), false);
  assert.equal(entry.validatePrompt(config.taskCid, modelSelector, config.promptPayloadWire), true);
  assert.equal(entry.validatePrompt(config.taskCid, 'other', config.promptPayloadWire), false);
  assert.throws(() => entry.physicalPreflight({}, createInferIoNotification(), () => {}, {}),
    {code: 'RegisteredSdkPhysicalInstallationUnavailable'});
  for (const changed of [{sdkPackage: '@test/foreign-sdk'}, {adapterArtifactCid: cid('c')},
    {route: Object.freeze({...route, endpoint: 'https://elsewhere.invalid/v1/messages'})},
    {route: Object.freeze({...route, providerId: 'other'})}]) {
    assert.throws(() => register(Object.freeze({...registration, ...changed})),
      {code: 'OpenAIOriginalInstallationMismatch'});
  }
  assert.throws(() => register(Object.freeze({...registration, credential: undefined})),
    {code: 'RegisteredSdkPhysicalInstallationUnavailable'});
  assert.throws(() => register()({...moon,clientProgramModelResponseProfileTransportMatches:()=>false}),
    {code:'OpenAIOriginalTransportLimitsMismatch'});
  let getterReads = 0;
  const inspected = new Proxy(config,{get(){getterReads++;throw Error('Unexpected property read');}});
  const [inspectedEntry] = createConfiguredUndiciRegisteredSdkRegistration(inspected,timeouts,64,registration)(moon);
  assert.strictEqual(inspectedEntry.rawCaptureSelection,rawCaptureSelection);
  assert.equal(getterReads,0);
  for (const additional of [Symbol('extra'),'hidden']) {
    const extra = Object.defineProperty({...config},additional,{value:'not admitted'});
    assert.throws(() => createConfiguredUndiciRegisteredSdkRegistration(extra,timeouts,64,registration),
      {code:'InvalidInstalledOpenAIChatConfiguration'});
  }
});
