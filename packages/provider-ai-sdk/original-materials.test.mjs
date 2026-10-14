import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createInstalledOpenAIChatRegistration,createInstalledUndiciOpenAIChatRegistration} from './index.mjs';
import {installModelProviders} from '../../adapters/host-node/installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {canonicalJson} from '../sdk/host-port.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const hash = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const body = value => {const wire=canonicalJson(value,{dataKeys:true});return {wire,cid:hash(wire)};};
function configuration() {
  // Independently selected DATA, not a normal physical profile/loan/grant.
  const vector=JSON.parse(readFileSync(new URL('../../portability/corpus/model-response-profiles.json',import.meta.url))).cases[0];
  const p=JSON.parse(vector.wire);delete p.self_cid;
  p.adapter.sdk={package:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid('a')};
  const original=body(p),wire=canonicalJson({...p,self_cid:original.cid},{dataKeys:true});
  const installation={builder_id:p.adapter.builder_id,builder_revision:p.adapter.builder_revision,
    codec_id:p.adapter.codec_id,codec_revision:p.adapter.codec_revision,build_artifact_cid:p.adapter.build_artifact_cid,
    sdk:{package_name:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid('a')},
    endpoint:p.operation.endpoint,http_method:'POST',streaming:false,
    validator_id:p.completion.validator_id,validator_revision:p.completion.validator_revision,
    validator_artifact_cid:p.completion.validator_artifact_cid,completion_basis:'generation_finish'};
  const policies={};
  for(const name of ['retention','metadata','clock'])policies[name]=body({name:`original-${name}`,version:'actql-installed-local-policy/0.1'});
  policies.data=body({classification:'unknown',source_data_policy_cids:[],source_response_policy_cids:[],
    unknown_provenance:true,version:'actql-effective-data-policy/0.1'});
  const bindings=Object.freeze(Object.fromEntries(Object.entries(providerBindingOriginals('models/fixture'))
    .map(([name,value])=>[name,Object.freeze(value)])));
  return {providerId:'models/fixture',modelSelector:'fixture-chat',modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',taskCid:p.task.contract_cid,promptCid:cid('b'),
    outputSchemaCid:p.task.output_schema_cid,promptPayloadWire:'{}',bindingOriginals:bindings,
    quantityCapacity:Object.freeze({limits:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n}),
      perAttempt:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n})}),
    projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
    requestLimits:{maxBytes:4096,maxHeaderBytes:4096,maxHeaders:16},
    responseLimits:{maxBytes:1024,maxChunkBytes:1024,maxChunks:4,maxHeaderBytes:128,observedHeaders:['content-type']},
    fetch:()=>assert.fail('No physical send'),observeAt:()=> '2026-10-13T00:00:00.000Z',observeEgress:()=>({}),
    originalMaterials:{responseProfile:{wire,cid:original.cid},policyOriginals:policies,
      readerLimits:{maxBytes:16384,maxNodes:1000,maxDepth:30,maxMembers:1000,maxWork:100000},installation,
      originalReadInstallation:{bootstrap:{bootstrapRetainedBytes:20n,bootstrapExecutionBytes:10n,
        maxReservations:8,maxHoldings:8,maxDelegations:8},modelRetainedBytes:100n,modelExecutionBytes:10n,
        nodeInstallation:{runtimeArtifactCid:cid('c'),layoutArtifactCid:cid('d'),layout:{runtime_artifact_cid:cid('c'),
          layout_artifact_cid:cid('d'),program_definition_cid:cid('e'),parameter_values_cid:cid('f'),barrier_cid:cid('0'),
          prepared_rows:1n,retained_bytes:7000n,execution_bytes:3000n}}},
      rawCaptureSelection:{selectedAt:'2026-10-13T00:00:00.000Z',availableUntil:'2026-10-14T00:00:00.000Z',
        deleteBy:'2026-10-15T00:00:00.000Z',extensionCeilingAt:'2026-10-15T00:00:00.000Z',
        metadataDeleteBy:'2026-10-16T00:00:00.000Z',selectionAvailable:()=>true}},
  };
}
const names=['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
  'clientProgramRetireOpenAIChatProjection','clientProgramModelRequestGeneration',
  'clientProgramModelRequestPreflight','clientProgramModelAsyncPhysicalRequestPlan',
  'clientProgramModelPhysicalCallForRequest','clientProgramModelPhysicalPending',
  'clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat'];
function runtime(config) {
  const calls=[];const profile=Object.freeze({originalRuntime:{}});
  const moon=Object.fromEntries(names.map(name=>[name,()=>assert.fail('No Model execution')]));
  moon.clientProgramInstallAsyncModelProvider=()=>({});
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
    const register=createInstalledUndiciOpenAIChatRegistration(selected);
    assert.throws(()=>register(f.moon),{code:'OpenAIOriginalMaterialsRefused'});
    assert.equal(f.calls.length,0);
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
});

test('actual installed Host supplies its original runtime once; second installation refuses and closes',async t=>{
  const {openInstalledRemoteHttpHost}=await import('../../adapters/host-node/embedded-local.mjs');
  const config=configuration(),register=createInstalledOpenAIChatRegistration(config),moon=await realRuntime();
  const root=await mkdtemp(join(tmpdir(),'actql-original-materials-host-'));
  let host,callbacks=0;
  t.after(async()=>{if(host!==undefined)await host.close();await rm(root,{recursive:true,force:true});});
  const options={directory:root,authenticate:()=> 'owner',registerModelProviders:actual=>{
    callbacks++;assert.equal(actual,moon);return register(actual);
  }};
  host=await openInstalledRemoteHttpHost(options);
  await host.close();await host.close();host=undefined;
  assert.equal(callbacks,1);
  await assert.rejects(openInstalledRemoteHttpHost(options),error=>
    error.code==='OpenAIOriginalInstallationReused' || error.cause?.code==='OpenAIOriginalInstallationReused');
  assert.equal(callbacks,2);
  t.diagnostic('Actual Host registration/SQLite close only; no Run, Provider send, grant or public E2E');
});
