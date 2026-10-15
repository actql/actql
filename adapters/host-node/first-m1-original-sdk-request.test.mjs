import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {readInstalledModelExecution,readInstalledModelDependencies} from './installed-model.mjs';
import {prepareAdmittedOpenAIChatRequest} from '../../packages/provider-ai-sdk/_internal/original-openai-chat.mjs';
import {pollSdkPreparation,sdkPreparedRequest,cleanupSdkPreparation,cancelSdkPreparation}
  from '../../packages/provider-ai-sdk/_internal/intercepted-request.mjs';
import {canonical,identity,configuration,program,task,prompt,output,instructions}
  from '../../scripts/fixtures/first-m1-common-materials.mjs';

const cid=letter=>`sha256:${letter.repeat(64)}`;
const base=JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json',import.meta.url)));
const aoa=JSON.parse(readFileSync(new URL('../../spec/contracts/actql-aoa.json',import.meta.url)));
const registry=canonical(JSON.parse(readFileSync(new URL(`../../${aoa.pipeline_registry_file}`,import.meta.url))));
const values=canonical(aoa.execution_contracts['REL.values']);
const fragment=canonical(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
const ordered=canonical(aoa.execution_contracts['REL.derive.ordered']);
const control=runtimeCore(moon).publicationControl;
const quantities=Object.freeze({limits:Object.freeze({tokens:33n,costUnits:0n,durationMs:500n}),
  perAttempt:Object.freeze({tokens:33n,costUnits:0n,durationMs:500n})});

function openOriginal() {
  const installed=configuration(base);
  const environment=moon.clientProgramCheckEnvironment(installed.environmentWire,
    JSON.parse(installed.environmentWire).evidence_bundle_cid,false,false,true,false,false,false,false);
  assert.ok(environment);
  const prepared=installNodeClientProgramPreparation({moon,environment})({kind:'program',input:program,parameters:null});
  const {execution}=readInstalledModelExecution(moon,prepared,installed);
  const dependencies=readInstalledModelDependencies(moon,execution,installed);
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
    registry,values,provider,consumer,7000n,3000n,100n,5n,fragment,ordered);
  checked(moon.clientProgramRequireInferCallEntry(active));
  checked(moon.clientProgramBindInferQuantityCapacity(active,33n,0n,500n,33n,0n,500n));
  checked(moon.clientProgramBindInferEgress(active,checked(moon.clientProgramAdmitInferEgress(prepared,2,execution,
    ()=>({_0:'public',_1:'fixture-region',_2:false,_3:false})))));
  return {admitted,active,compiled,definition,graph,scope,read};
}

async function stopOriginal(original) {
  assert.equal(moon.clientProgramCancelInferExecution(original.active),true);
  for(let n=0;n<2000;n++){
    const observed=checked(moon.clientProgramAdvanceInferExecution(original.active,1));
    if(moon.clientProgramInferExecutionPollKind(observed)==='stopped')return;
  }
  assert.fail('Same original execution did not stop');
}
async function sdkRetired(handle) {
  for(let n=0;n<30;n++){
    if(cleanupSdkPreparation(handle))return;
    await turn();
  }
  assert.fail('Same SDK preparation did not retire');
}
async function finishOriginal(original) {
  assert.equal(checked(moon.clientProgramCleanupInferExecution(original.active)),true);
  control.settleCheckedClientInferOriginalReadPreparation(original.compiled,original.definition,original.graph,original.read,true);
  assert.equal(control.finishCheckedClientInferOriginalReadScope(original.compiled,original.definition,original.graph,original.scope,true),true);
}

for(const rejectProjection of [false,true]) {
test(`first M1 actual original Core request ${rejectProjection?'bounded refusal':'reaches pinned SDK'} before Entry or transport`,async t=>{
  const ambient=globalThis.fetch;
  let physical=0;
  globalThis.fetch=()=>{physical++;assert.fail('No ambient transport');};
  t.after(()=>{globalThis.fetch=ambient;});
  const original=openOriginal();
  let request,handle,preflights=0,cleanupAllowed=false,cleanupCalls=0;
  checked(moon.clientProgramBindInferPhysicalPreflight(original.active,current=>{
    preflights++;
    request=current;
    if(rejectProjection){
      assert.throws(()=>prepareAdmittedOpenAIChatRequest({moon,request,admittedProvider:original.admitted,
        taskCid:identity(task),promptCid:identity(prompt),outputSchemaCid:identity(output),modelSelector:'fixture-risk-model',
        projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:13},
        modelId:'gpt-4.1-mini-2025-04-14',baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
        maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,notify(){}}),/OpenAIProjection:/u);
    }else{
      handle=prepareAdmittedOpenAIChatRequest({moon,request,admittedProvider:original.admitted,
        taskCid:identity(task),promptCid:identity(prompt),outputSchemaCid:identity(output),modelSelector:'fixture-risk-model',
        projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
        modelId:'gpt-4.1-mini-2025-04-14',baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
        maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,notify(){}});
    }
    // No physical Plan is admitted; retain this same preflight through the
    // SDK's actual Promise settlement and original cancellation/cleanup.
    return moon.clientProgramModelRequestPreflight(()=>({_0:false,_1:undefined}),()=>{
      cleanupCalls++;
      if(!cleanupAllowed)return false;
      return handle===undefined||cleanupSdkPreparation(handle);
    });
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
  if(handle){
    for(let n=0;n<30&&pollSdkPreparation(handle).kind==='pending';n++)await turn();
    assert.equal(pollSdkPreparation(handle).kind,'ready');
    assert.deepEqual(JSON.parse(sdkPreparedRequest(handle).body),{
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
  if(handle){cancelSdkPreparation(handle);await sdkRetired(handle);}
  cleanupAllowed=true;
  await finishOriginal(original);
  assert.equal(control.checkedClientInferOriginalReadScopeLive(original.compiled,original.definition,original.graph,original.scope),false);
  assert.equal(preflights,1);
  assert.equal(physical,0);
});
}
