import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createInstalledOpenAIChatRegistration,createInstalledUndiciOpenAIChatRegistration} from './index.mjs';
import {originalMaterialsConfiguration as configuration,
  installFixtureModelProviders as installModelProviders} from './original-materials.fixture.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const names=['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
  'clientProgramRetireOpenAIChatProjection','clientProgramModelRequestGeneration',
  'clientProgramModelRequestPreflight','clientProgramModelAsyncPhysicalRequestPlan',
  'clientProgramModelPhysicalCallForRequest','clientProgramModelPhysicalPending',
  'clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat'];
function runtime(config) {
  const calls=[];const profile=Object.freeze({originalRuntime:{}});
  const transportBounds=[config.requestLimits.maxBytes,config.responseLimits.maxBytes,
    config.responseLimits.maxChunkBytes,config.responseLimits.maxChunks,config.responseLimits.maxHeaderBytes];
  const moon=Object.fromEntries(names.map(name=>[name,()=>assert.fail('No Model execution')]));
  moon.clientProgramInstallAsyncModelProvider=()=>({});
  moon.clientProgramModelResponseProfileTransportMatches=(actual,...limits)=>{
    assert.strictEqual(actual,profile);
    assert.deepEqual(limits,transportBounds);
    return true;
  };
  moon.clientProgramReadModelResponseProfile=(...args)=>{calls.push(['profile',...args]);
    return {$tag:1,_0:profile};};
  moon.clientProgramAdmitEffectDependencyBody=(...args)=>{calls.push(['policy',...args]);
    return {$tag:1,_0:Object.freeze({kind:args[0],wire:args[2]})};};
  return {moon,calls,profile};
}

test('material descriptors snapshot once before the actual Host callback and retain same-runtime opaque originals',()=>{
  const config=configuration(),f=runtime(config);let gets=0;
  const suppliedProfile=config.originalMaterials.responseProfile;
  config.originalMaterials=new Proxy(config.originalMaterials,{get(){gets++;assert.fail('No repeated property reads');}});
  const register=createInstalledOpenAIChatRegistration(config);
  assert.equal(f.calls.length,0);
  suppliedProfile.wire='replacement'; // snapshot kept the original descriptor value
  config.projectionLimits.maxWork=0;config.requestLimits.maxBytes=1;
  const installed=installModelProviders(f.moon,register).get(config.providerId);
  assert.equal(gets,0);assert.equal(f.calls.length,5);
  assert.equal(installed.originalReadInstallation.nodeInstallation.layout.response_profile,f.profile);
  assert.equal(installed.rawCaptureSelection.profile,f.profile);
  assert.equal(installed.rawCaptureSelection.retention.kind,'retention_contract');
  assert.notEqual(f.calls[0][1],'replacement');
  assert.throws(()=>register(f.moon),{code:'OpenAIOriginalInstallationReused'});
  assert.throws(()=>register({...f.moon}),{code:'OpenAIOriginalInstallationReused'});
});

test('material original String ceilings reject before original readers and snapshot before callback',()=>{
  const config=configuration(),f=runtime(config);
  config.originalStringLimits={maxApiKeyCodeUnits:12,maxBaseURLCodeUnits:26,maxModelIdCodeUnits:12};
  const oversized={...config,apiKey:'x'.repeat(13)};
  assert.throws(()=>createInstalledOpenAIChatRegistration(oversized),{code:'OpenAIOriginalStringLimitExceeded'});
  assert.equal(f.calls.length,0);
  const register=createInstalledOpenAIChatRegistration(config);
  config.originalStringLimits.maxApiKeyCodeUnits=1;
  config.apiKey='replacement';config.baseURL='https://foreign.invalid';config.modelId='replacement';
  const [entry]=register(f.moon);
  assert.equal(entry.rawCaptureSelection.profile,f.profile);
  assert.equal(f.calls.length,5);
  assert.throws(()=>register({...f.moon}),{code:'OpenAIOriginalInstallationReused'});
});

test('materials refuse null/absent runtime readers before any physical selector or Model allocation',()=>{
  for(const moon of [null,undefined,{}, {clientProgramReadModelResponseProfile:()=>assert.fail('No partial reader')}]) {
    assert.throws(()=>createInstalledOpenAIChatRegistration(configuration())(moon),
      {code:'OpenAIOriginalRuntimeUnavailable'});
  }
  const config=configuration(),f=runtime(config);
  delete f.moon.clientProgramModelPhysicalSavedChat;
  assert.throws(()=>createInstalledOpenAIChatRegistration(config)(f.moon),{code:'OpenAIOriginalRuntimeUnavailable'});
  assert.equal(f.calls.length,0,'Missing consumer is checked before material admission');
});

test('closed materials refuse missing policy, extra opaque field and ambiguous mixed overload',()=>{
  for(const change of [config=>delete config.originalMaterials.policyOriginals.clock,
    config=>{config.originalMaterials.rawCaptureSelection.profile={};},
    config=>{config.rawCaptureSelection={};},config=>{config.originalReadInstallation={};}]) {
    const config=configuration();change(config);
    assert.throws(()=>createInstalledOpenAIChatRegistration(config),TypeError);
  }
});

test('material read/layout quantities keep the existing Int64 domain before callback or selector',()=>{
  for(const value of [1,-1n,9223372036854775808n,'1']) {
    const config=configuration();config.originalMaterials.originalReadInstallation.nodeInstallation.layout.prepared_rows=value;
    assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'InvalidOpenAIOriginalMaterials'});
  }
  const config=configuration();config.originalMaterials.readerLimits.maxNodes=2147483648;
  assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'InvalidOpenAIOriginalMaterials'});
});

test('material accessors do not read secrets or original bodies',()=>{
  const config=configuration();let reads=0;
  Object.defineProperty(config.originalMaterials.responseProfile,'wire',{enumerable:true,get(){reads++;return 'secret';}});
  assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'InvalidOpenAIOriginalMaterials'});
  assert.equal(reads,0);
});

test('Common refusal or missing opaque result never constructs a physical selection',()=>{
  for(const result of [{$tag:0,_0:{}},{$tag:1,_0:undefined},{$tag:1,_0:null}]) {
    const config=configuration(),f=runtime(config);
    f.moon.clientProgramReadModelResponseProfile=()=>result;
    const {fetch:unused,...selected}=config;void unused;
    const register=createInstalledUndiciOpenAIChatRegistration({...selected,
      physicalAcquisitionLimits:{maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64}});
    assert.throws(()=>register(f.moon),{code:'OpenAIOriginalMaterialsRefused'});
    assert.equal(f.calls.length,0);
    assert.throws(()=>register({...f.moon}),{code:'OpenAIOriginalInstallationReused'});
  }
});

// No builder/opaque object is produced from this JSON in JS. Actual Common
// reader and the real installed Host callback are tested below, without a Run.
const realRuntime=()=>import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
test('actual Common readers preserve original policies and refuse changed wire/CID or finite bounds',async()=>{
  const moon=await realRuntime();
  const installed=installModelProviders(moon,createInstalledOpenAIChatRegistration(configuration())).get('models/fixture');
  const profile=installed.rawCaptureSelection.profile;
  assert.equal(installed.originalReadInstallation.nodeInstallation.layout.response_profile,profile);
  const policies=moon.clientProgramModelRawSelectionOriginals(...['retention','metadata','clock','data']
    .map(name=>installed.rawCaptureSelection[name]));
  assert.equal(policies.length,4);assert.equal(policies[0]._0,'retention_contract');
  for(const change of [config=>{config.originalMaterials.responseProfile.cid=cid('0');},
    config=>{config.originalMaterials.responseProfile.wire='{}';},
    config=>{config.originalMaterials.policyOriginals.clock.cid=cid('0');},
    config=>{config.originalMaterials.readerLimits.maxBytes=1;},
    config=>{config.originalMaterials.readerLimits.maxWork=1;}]) {
    const config=configuration();change(config);
    assert.throws(()=>createInstalledOpenAIChatRegistration(config)(moon),{code:'OpenAIOriginalMaterialsRefused'});
  }
  // The real Common reader, not the runtime double above, binds the five
  // acquisition ceilings to this original admitted profile before selection.
  for(const [section,key] of [['requestLimits','maxBytes'],['responseLimits','maxBytes'],
    ['responseLimits','maxChunkBytes'],['responseLimits','maxChunks'],['responseLimits','maxHeaderBytes']]) {
    const config=configuration();config[section][key]++;
    assert.throws(()=>createInstalledOpenAIChatRegistration(config)(moon),
      {code:'OpenAIOriginalTransportLimitsMismatch'});
  }
  const tighter=configuration();tighter.requestLimits.maxBytes--;
  tighter.responseLimits.maxBytes--;tighter.responseLimits.maxChunkBytes--;
  tighter.responseLimits.maxChunks--;tighter.responseLimits.maxHeaderBytes--;
  const tightened=installModelProviders(moon,createInstalledOpenAIChatRegistration(tighter))
    .get('models/fixture');
  assert.equal(tightened.rawCaptureSelection.profile,
    tightened.originalReadInstallation.nodeInstallation.layout.response_profile);
});

for(const route of ['generic','Undici']) {
test(`actual installed ${route} Host supplies its original runtime once; second installation refuses and closes`,async t=>{
  const preload=fileURLToPath(new URL('../../adapters/host-node/infer-trusted-node-preload.cjs',import.meta.url));
  const entry=fileURLToPath(new URL('./sdk-static-host.fixture.mjs',import.meta.url));
  // A dedicated entry keeps the real --require phase before SDK imports.
  // Passing --test to that child would be a different startup selection.
  const result=spawnSync(process.execPath,['--require',preload,entry,route],{
    env:{PATH:process.env.PATH},encoding:'utf8',timeout:10000,maxBuffer:1024*1024});
  assert.equal(result.error,undefined);assert.equal(result.signal,null);
  assert.equal(result.status,0,result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()),{route,callbacks:2,hostClosed:true,
    providerCalls:0,coreScopes:0,normalNumericProfile:null,publicE2E:0});
  t.diagnostic('Actual selected startup/Host registration/SQLite close; no Run, Scope funding or Provider send');
});
}
