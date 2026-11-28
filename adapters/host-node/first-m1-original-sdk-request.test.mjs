import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openFundedClientPreparation, fundedModelMaterialFixture} from './funded-client-preparation.fixture.mjs';
import {readInstalledModelExecution,readInstalledModelDependencies} from './installed-model.mjs';
import {createOpenAI} from '@ai-sdk/openai';
import {sdkProvider, verifyRequest} from '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';
import {createAdmittedRegisteredSdkPreflight} from '../../packages/provider-ai-sdk/_internal/model-port.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {canonical,identity,configuration,program,task,prompt,output,instructions}
  from '../../scripts/fixtures/first-m1-common-materials.mjs';

const cid=letter=>`sha256:${letter.repeat(64)}`;
const base=JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json',import.meta.url)));
const aoa=JSON.parse(readFileSync(new URL('../../spec/contracts/actql-aoa.json',import.meta.url)));
const values=canonical(aoa.execution_contracts['REL.values']);
const fragment=canonical(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
const ordered=canonical(aoa.execution_contracts['REL.derive.ordered']);
const control=runtimeCore(moon).publicationControl;
const modelId='gpt-4.1-mini-2025-04-14', selector='fixture-risk-model', apiMode='chat_completions';
const quantities=Object.freeze({limits:Object.freeze({tokens:33n,costUnits:0n,durationMs:500n}),
  perAttempt:Object.freeze({tokens:33n,costUnits:0n,durationMs:500n})});

async function openOriginal(t) {
  const installed=configuration(base);
  const environment=moon.clientProgramCheckEnvironment(installed.environmentWire,
    JSON.parse(installed.environmentWire).evidence_bundle_cid,false,false,true,false,false,false,false);
  assert.ok(environment);
  const funded=await openFundedClientPreparation({moon,environment,sequenceContracts:{values,fragment,ordered}});
  t.after(funded.close);
  const prepared=await funded.prepare({kind:'program',input:program,parameters:null});
  const fund=fundedModelMaterialFixture(moon,prepared);
  const {execution}=readInstalledModelExecution(moon,prepared,installed,undefined,fund);
  const dependencies=readInstalledModelDependencies(moon,execution,installed,fund,prepared);
  const provider=moon.clientProgramInstallAsyncModelProvider('models/fixture');
  assert.ok(provider);
  const admitted=checked(moon.clientProgramAdmitModelProvider(provider,execution,dependencies,
    (taskCid,selector,payload)=>taskCid===identity(task)&&selector==='fixture-risk-model'&&payload===canonical(prompt.payload)));
  const graph=checked(moon.clientProgramInstalledInferPlanGraph(prepared,2,execution));
  const resultPolicyWire='{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  const compiled=control.prepareCheckedClientCompiledRun(prepared,'infer',{
    executionContextCid:cid('a'),hostPolicyCid:cid('b'),expiresAt:'2099-01-01T00:00:00.000Z',
    resultDataPolicy:{kind:'data_policy',wire:resultPolicyWire,cid:identity(JSON.parse(resultPolicyWire))}},graph);
  const definition=control.defineCheckedClientCompiledRun(compiled,{namespaceId:'original-sdk',
    runId:'fixture',createdAt:'2026-10-15T00:00:00.000Z',validUntil:'2099-01-01T00:00:00.000Z'});
  const requestIdentity=moon.clientProgramRequestIdentity(prepared,cid('c'),'original-sdk',
    moon.clientProgramSourceFreeInputIntentCid());
  assert.ok(requestIdentity);
  // Independently authored profile/layout DATA for this private custody test.
  // These positive values are not physical adequacy, a normal profile or fees.
  const vector=JSON.parse(readFileSync(new URL('../../portability/corpus/model-response-profiles.json',import.meta.url))).cases[0];
  const profileBody=JSON.parse(vector.wire);delete profileBody.self_cid;
  profileBody.adapter.codec_id='fixture/sdk-v4-saved-text';
  profileBody.completion.validator_id=profileBody.adapter.codec_id;
  profileBody.limits.request_bytes=1000;
  profileBody.task={contract_cid:identity(task),input_schema_cid:task.input_schema_cid,
    output_schema_cid:task.output_schema_cid,kind:'structured_generate'};
  profileBody.adapter.sdk={package:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid('d')};
  const profile=control.readInstalledModelResponseProfile(canonical({...profileBody,self_cid:identity(profileBody)}),
    identity(profileBody),{maxWireBytes:16384,maxNodes:1000,maxDepth:30,maxMembers:1000,maxWork:100000});
  const installation={builder_id:profileBody.adapter.builder_id,builder_revision:profileBody.adapter.builder_revision,
    codec_id:profileBody.adapter.codec_id,codec_revision:profileBody.adapter.codec_revision,
    build_artifact_cid:profileBody.adapter.build_artifact_cid,sdk:{package_name:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid('d')},
    endpoint:profileBody.operation.endpoint,http_method:'POST',streaming:false,
    validator_id:profileBody.completion.validator_id,validator_revision:profileBody.completion.validator_revision,
    validator_artifact_cid:profileBody.completion.validator_artifact_cid,completion_basis:'generation_finish'};
  const {endpoint}=installation;
  const bindingOriginals=providerBindingOriginals('models/fixture',{endpoint,selector});
  const configurationWire=canonical({...JSON.parse(bindingOriginals.configuration.wire),adapter_kind:'ai-sdk',
    structured_routes:{[selector]:{model_id:modelId,api_mode:apiMode,endpoint,
      structured_capability:{operation:'structured_generate',adapter:'supported',model:'supported'}}}});
  const binding=checked(moon.clientProgramModelProviderBinding('models/fixture',
    bindingOriginals.installationRevision.wire,bindingOriginals.configurationContract.wire,configurationWire));
  const capability=checked(moon.clientProgramPrepareInstalledStructuredSdkCapability(
    provider,binding,configurationWire,selector,modelId,apiMode,endpoint,profile));
  const admission=checked(moon.clientProgramAdmitInstalledStructuredSdkCapability(capability,admitted,installation));
  const selection={layout:{response_profile:profile,runtime_artifact_cid:cid('e'),layout_artifact_cid:cid('f'),
    program_definition_cid:moon.clientRequestProgramCid(requestIdentity),
    parameter_values_cid:moon.clientRequestParametersCid(requestIdentity),barrier_cid:moon.clientProgramInferPlanBoundary(graph)._3,
    prepared_rows:2n,retained_bytes:7000n,execution_bytes:3000n},installation,
    runtimeArtifactCid:cid('e'),layoutArtifactCid:cid('f'),probability:undefined};
  const scope=control.beginCheckedClientInferOriginalReadScope(compiled,definition,graph,{quantityCapacity:quantities,
    bootstrapRetainedBytes:3n,bootstrapExecutionBytes:2n,maxReservations:4,maxHoldings:2,maxDelegations:0});
  const read=control.prepareCheckedClientInferNodeReadLayout(compiled,definition,graph,scope,selection);
  const consumer=control.claimCheckedClientInferNodePreparationLayout(compiled,definition,graph,read,selection);
  const active=control.startCheckedClientInferOriginalPreparation(compiled,definition,prepared,2,graph,
    funded.installedContracts,values,provider,consumer,7000n,3000n,100n,5n,fragment,ordered);
  checked(moon.clientProgramRequireInferCallEntry(active));
  checked(moon.clientProgramBindInferQuantityCapacity(active,33n,0n,500n,33n,0n,500n));
  checked(moon.clientProgramBindInferEgress(active,checked(moon.clientProgramAdmitInferEgress(prepared,2,execution,
    ()=>({_0:'public',_1:'fixture-region',_2:false,_3:false})))));
  return {admission,profile,installation,active,compiled,definition,graph,scope,read};
}

async function stopOriginal(original) {
  assert.equal(moon.clientProgramCancelInferExecution(original.active),true);
  for(let n=0;n<2000;n++){
    const observed=checked(moon.clientProgramAdvanceInferExecution(original.active,1));
    if(moon.clientProgramInferExecutionPollKind(observed)==='stopped')return;
  }
  assert.fail('Same original execution did not stop');
}
async function finishOriginal(original) {
  let released=false;
  for(let n=0;n<30&&!released;n++){
    released=checked(moon.clientProgramCleanupInferExecution(original.active));
    if(!released)await turn();
  }
  assert.equal(released,true);
  control.settleCheckedClientInferOriginalReadPreparation(original.compiled,original.definition,original.graph,original.read,true);
  assert.equal(control.finishCheckedClientInferOriginalReadScope(original.compiled,original.definition,original.graph,original.scope,true),true);
}

for(const rejectProjection of [false,true]) {
test(`first M1 actual original Core request ${rejectProjection?'bounded refusal':'reaches pinned SDK'} before Entry or transport`,async t=>{
  const ambient=globalThis.fetch;
  let physical=0;
  globalThis.fetch=()=>{physical++;assert.fail('No ambient transport');};
  t.after(()=>{globalThis.fetch=ambient;});
  const original=await openOriginal(t);
  let request,advance,wire,issue,preflights=0,cleanupAllowed=false,cleanupCalls=0;
  const route={selector,modelId,apiMode,endpoint:original.installation.endpoint};
  const sdk=original.installation.sdk;
  const providerOptions=Object.freeze({openai:Object.freeze({})});
  const runtime=Object.create(moon,{
    clientProgramModelRequestPreflight:{value(next,cleanup){
      advance=next;
      // This diagnostic drives the selected preflight itself while the actual
      // execution retains its CallSet and cannot consume an Entry.
      return moon.clientProgramModelRequestPreflight(()=>({_0:false,_1:undefined}),()=>{
        cleanupCalls++;
        return cleanupAllowed&&cleanup();
      });
    }},
  });
  checked(moon.clientProgramBindInferPhysicalPreflight(original.active,current=>{
    preflights++;
    request=current;
    return createAdmittedRegisteredSdkPreflight({moon:runtime,request,admission:original.admission,
      profile:original.profile,installation:original.installation,
      registeredSdk:{route,sdkProvider,providerOptions,sdkPackage:sdk.package_name,sdkVersion:sdk.version,
        lockArtifactCid:sdk.lock_artifact_cid,adapterArtifactCid:original.installation.build_artifact_cid,
        createLanguageModel:fetch=>createOpenAI({baseURL:route.endpoint.slice(0,-'/chat/completions'.length),
          apiKey:'fixture-only',fetch}).chat(modelId),
        verifyRequest(body,options){wire=body;return verifyRequest(body,options,route,providerOptions);}},
      taskCid:identity(task),promptCid:identity(prompt),outputSchemaCid:identity(output),
      projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:rejectProjection?13:10000},
      maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,notify(){},
      quantities:quantities.perAttempt,
      fetch(){physical++;assert.fail('Request preparation cannot send');},
      responseLimits:{maxBytes:4096,maxChunkBytes:1024,maxChunks:8,maxHeaderBytes:4096},
      persistRaw(){assert.fail('No Raw without Entry');},cleanupRaw:()=>true,
      observeAt:()=> '2026-10-15T00:00:00.000Z',
      checked(result){if(result?.$tag===0)issue=moon.clientProgramOpenAIChatProjectionIssueKind(result._0);
        return checked(result);},
    }).preflight;
  }));
  for(let n=0;n<2000&&!request;n++){
    const observed=checked(moon.clientProgramAdvanceInferExecution(original.active,1));
    assert.equal(moon.clientProgramInferExecutionPollKind(observed),'continue');
  }
  assert.ok(request,'Only the actual Common Model owner supplies this request');
  assert.equal(preflights,1);
  const generation=moon.clientProgramModelRequestGeneration(request);
  assert.equal(generation._0,'fixture-risk-model');
  assert.equal(BigInt.asIntN(64,generation._4),-7n);
  let terminal;
  for(let n=0;n<2000;n++){
    const progress=advance();
    if(progress._0){terminal=progress;break;}
    await turn();
  }
  assert.ok(terminal,'The same selected Core preflight must reach its terminal observation');
  if(rejectProjection){
    assert.equal(issue,'limit');
    assert.equal(wire,undefined);
    assert.equal(terminal._1,undefined);
  }else{
    assert.ok(terminal._1,'The registered SDK reaches the actual checked physical Plan');
    assert.equal(issue,undefined);
    assert.deepEqual(JSON.parse(wire),{
      model:'gpt-4.1-mini-2025-04-14',temperature:0,top_p:1,max_tokens:32,seed:-7,
      messages:[{role:'system',content:instructions},{role:'user',content:'{"text":"hello"}'}],
      response_format:{type:'json_schema',json_schema:{name:'actql_output',strict:true,schema:{type:'object',
        properties:{reason:{anyOf:[{type:'string'},{type:'null'}]},risk:{type:'string'}},
        required:['reason','risk'],additionalProperties:false}}}});
  }
  assert.equal(moon.clientProgramInferPreparedCallSet(original.active),undefined);
  await stopOriginal(original);
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)),false);
  assert.equal(control.checkedClientInferOriginalReadScopeLive(original.compiled,original.definition,original.graph,original.scope),true);
  assert.ok(cleanupCalls>0);
  cleanupAllowed=true;
  await finishOriginal(original);
  assert.equal(control.checkedClientInferOriginalReadScopeLive(original.compiled,original.definition,original.graph,original.scope),false);
  assert.equal(preflights,1);
  assert.equal(physical,0);
});
}
