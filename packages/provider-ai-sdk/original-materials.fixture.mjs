import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {canonicalJson} from '../sdk/host-port.mjs';
import {installModelProviders} from '../../adapters/host-node/installed-model.mjs';
import {openAIChatStaticOriginals} from './_internal/openai-chat.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const hash = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const body = value => {const wire=canonicalJson(value,{dataKeys:true});return {wire,cid:hash(wire)};};
export function originalMaterialsConfiguration() {
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
    originalStringLimits:{maxApiKeyCodeUnits:64,maxBaseURLCodeUnits:256,maxModelIdCodeUnits:64},
    outputSchemaCid:p.task.output_schema_cid,promptPayloadWire:'{}',bindingOriginals:bindings,
    quantityCapacity:Object.freeze({limits:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n}),
      perAttempt:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n})}),
    projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
    requestLimits:{maxBytes:p.limits.request_bytes,maxHeaderBytes:4096,maxHeaders:16},
    responseLimits:{maxBytes:p.limits.response_bytes,maxChunkBytes:p.limits.chunk_bytes,
      maxChunks:p.limits.chunks,maxHeaderBytes:p.limits.header_bytes,observedHeaders:['content-type']},
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

// Explicit installation-observer double for non-Host SDK/reader unit cases.
// The real selected preload/Host boundary is exercised in its own child entry;
// this helper provides no startup, Scope, coverage, funding or send evidence.
export function installFixtureModelProviders(moon, register) {
  return installModelProviders(moon,register,undefined,undefined,actual=>{
    assert.strictEqual(actual,openAIChatStaticOriginals);
  });
}
