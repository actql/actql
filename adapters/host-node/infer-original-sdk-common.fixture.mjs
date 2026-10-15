// Actual Common/SDK/Store/journal composition with explicitly synthetic
// physical declarations. This fixture never establishes a normal numerical
// profile, runtime provenance, public startup or permission for a live service.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash,generateKeyPairSync} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {createInferIoNotification} from './infer-io-notification.mjs';
import {installModelProviders,readInstalledModelDependencies,admitInstalledModelProvider,
  admitInstalledModelProviderBinding} from './installed-model.mjs';
import {createAdmittedOpenAIChatPreflight} from '../../packages/provider-ai-sdk/_internal/original-openai-chat.mjs';
import {createAdmittedTypeSafeDecisionPreflight} from '../../packages/provider-ai-sdk/_internal/native-decision-preflight.mjs';

const source=readFileSync(new URL('../../src/client_infer_host/fixture.generated_wbtest.mbt',import.meta.url),'utf8');
const input=name=>source.match(new RegExp(`let ${name} : String =\\n\\s+#\\|([^\\n]+)`,'u'))[1];
const nativeSource=readFileSync(new URL('../../src/client_infer_host/native_original_call_fixture.generated_wbtest.mbt',import.meta.url),'utf8');
const nativeInput=name=>nativeSource.match(new RegExp(`let ${name} : String =\\n\\s+#\\|([^\\n]+)`,'u'))[1];
const hash=wire=>`sha256:${createHash('sha256').update(wire).digest('hex')}`;
const cid=c=>`sha256:${c.repeat(64)}`;
const seal=body=>{const wire=canonicalJson(body,{dataKeys:true}),identity=hash(wire);
  return {body:{...body,self_cid:identity},wire:canonicalJson({...body,self_cid:identity},{dataKeys:true}),cid:identity};};
const now=()=> '2026-10-12T00:00:00.000Z';
const bounds={maxWireBytes:10000,maxNodes:1000,maxDepth:30,maxMembers:1000,maxWork:100000};

export async function originalSdkCommonFixture(t,moon,{responseWire,signal=new AbortController().signal,
  storeOriginals=true,beforeOriginalRead,modelId='gpt-4.1-nano',nativeDecision=false}={}) {
  const root=await mkdtemp(join(tmpdir(),'actql-original-sdk-common-'));
  t.diagnostic(`Original joined fixture custody retained at ${root}`);
  const control=runtimeCore(moon).publicationControl;
  const nativePrompt=nativeDecision?JSON.parse(nativeInput('native_call_prompt')):undefined;
  const prompt=nativeDecision ? {body:nativePrompt,wire:canonicalText(nativePrompt),cid:nativePrompt.self_cid} :
    seal({version:'actql-model-prompt/0.1',payload:{
      format:'actql.openai_chat_prompt/0.1',instructions:'Original é\r\n'}});
  const retry=seal({version:'actql-model-retry-policy/0.1',retryable_failures:[]});
  const backoff=seal({version:'actql-model-backoff/0.1',delays_ms:[]});
  const environmentBody=JSON.parse(nativeDecision ? nativeInput('native_call_environment') : input('infer_fixture_environment'));
  const originalTask=environmentBody.model_task_contracts[0];
  const {contract_cid:ignored,...taskBody}=originalTask;
  taskBody.prompt_template_cid=prompt.cid;
  const task={...taskBody,contract_cid:hash(canonicalText(taskBody))};
  environmentBody.model_task_contracts=[task];
  delete environmentBody.evidence_bundle_cid;
  const environmentCid=hash(canonicalText(environmentBody));
  const environmentWire=canonicalText({...environmentBody,evidence_bundle_cid:environmentCid});
  const env=moon.clientProgramCheckEnvironment(environmentWire,environmentCid,false,false,true,false,false,false,false);
  let programWire=input('infer_fixture_program');
  if(nativeDecision) {
    // A separately selected one-row private native case. Preserve the original
    // Task's checked all-row bound4, schema and key/input expression contract.
    const program=JSON.parse(nativeInput('native_call_program'));
    program.stages[0].steps[0].values.rows=[{id:'b'}];
    programWire=JSON.stringify(program);
  }
  const prepared=moon.clientProgramPreparationReady(moon.clientProgramPrepareEffectFreeWithParameters(
    programWire,'json',env,undefined));
  assert.notEqual(prepared,undefined,'independent original Program must check');
  const step=moon.clientProgramSelectedInferStep(prepared);
  const executionBody={version:'actql-model-execution-contract/0.1',model_task_contract_cid:task.contract_cid,
    retry_classification_contract_cid:retry.cid,backoff_contract_cid:backoff.cid,
    max_attempts_per_slot:1,max_total_attempts:1,max_total_cost_units:0,
    max_total_duration_ms:1000,max_total_wire_bytes:133072,max_total_token_reservation:128,
    media_input_contracts:{},default_publication:'outcomes'};
  const executionCid=hash(canonicalText(executionBody));
  const executionWire=canonicalText({...executionBody,self_cid:executionCid});
  const execution=checked(moon.clientProgramReadInferModelExecution(prepared,step,executionWire,executionCid));
  const graph=checked(moon.clientProgramInferPlanGraph(prepared,step,execution,cid('b'),cid('c')));
  const dataBody={version:'actql-effective-data-policy/0.1',classification:'unknown',
    source_data_policy_cids:[],source_response_policy_cids:[],unknown_provenance:true};
  const dataWire=canonicalText(dataBody),dataCid=hash(dataWire);
  const compiled=control.prepareCheckedClientCompiledRun(prepared,'infer',{
    executionContextCid:cid('d'),hostPolicyCid:cid('d'),expiresAt:'2099-01-01T00:00:00.000Z',
    resultDataPolicy:{kind:'data_policy',cid:dataCid,wire:dataWire}},graph);
  const runDefinition=control.defineCheckedClientCompiledRun(compiled,{namespaceId:'scope',runId:'original-sdk-common',
    createdAt:'2026-10-02T00:00:00.000Z',validUntil:'2099-01-01T00:00:00.000Z'});
  const profileText=nativeDecision ? nativeInput('native_call_profile_wire') :
    readFileSync(new URL('../../src/run_publication_host/client_model_preparation_layout_wbtest.mbt',import.meta.url),'utf8')
      .match(/#\|(\{[^\n]+\})/u)[1];
  const profileBody=JSON.parse(profileText);delete profileBody.self_cid;
  profileBody.task.contract_cid=task.contract_cid;
  // The original independently declared Host request ceiling is1000. The
  // former fixture1024 support declaration correctly failed preflight; tighten
  // the physical selection rather than widening the Host/language budget.
  profileBody.limits.request_bytes=1000;
  // The exact SDK lock is a DATA reference; this explicitly synthetic fixture
  // does not authenticate these otherwise fixture builder/runtime declarations.
  profileBody.adapter.sdk={package:nativeDecision?'@ai-sdk/typesafe-ai':'@ai-sdk/openai',
    version:nativeDecision?'3.0.13':'4.0.91',interface:'v4',
    lock_artifact_cid:hash(readFileSync(new URL('../../packages/provider-ai-sdk/package-lock.json',import.meta.url)))};
  const profileOriginal=seal(profileBody);
  const profile=control.readInstalledModelResponseProfile(profileOriginal.wire,profileOriginal.cid,bounds);
  const installation={...profileBody.adapter,endpoint:profileBody.operation.endpoint,
    sdk:{package_name:profileBody.adapter.sdk.package,version:profileBody.adapter.sdk.version,interface:'v4',
      lock_artifact_cid:profileBody.adapter.sdk.lock_artifact_cid},
    http_method:profileBody.operation.method,streaming:false,
    validator_id:profileBody.completion.validator_id,validator_revision:profileBody.completion.validator_revision,
    validator_artifact_cid:profileBody.completion.validator_artifact_cid,completion_basis:profileBody.completion.basis};
  delete installation.port_abi;
  const physicalOriginals=[];
  const policyOriginals=['retention_contract','metadata_retention_policy','clock_contract'].map(kind=>{
    const wire=canonicalText({version:'actql-installed-local-policy/0.1',name:`joined-${kind}`});
    physicalOriginals.push({kind,cid:hash(wire),wire});
    return checked(moon.clientProgramAdmitEffectDependencyBody(kind,hash(wire),wire,10000,1000,30));
  });
  const data=checked(moon.clientProgramAdmitEffectDependencyBody('data_policy',dataCid,dataWire,10000,1000,30));
  physicalOriginals.push({kind:'data_policy',cid:dataCid,wire:dataWire});
  const probability=nativeDecision?control.selectInstalledInitialJevDecisionProfile():undefined;
  const rawCaptureSelection={profile,installation,probability,
    retention:policyOriginals[0],metadata:policyOriginals[1],clock:policyOriginals[2],data,
    selectedAt:now(),availableUntil:'2026-10-13T00:00:00.000Z',deleteBy:'2026-10-14T00:00:00.000Z',
    extensionCeilingAt:'2026-10-14T00:00:00.000Z',metadataDeleteBy:'2026-10-15T00:00:00.000Z',selectionAvailable:()=>true};
  const template=JSON.parse(compiled.template.wire);
  const nodeInstallation={layout:{response_profile:profile,runtime_artifact_cid:cid('d'),layout_artifact_cid:cid('e'),
    program_definition_cid:template.program_definition_cid,parameter_values_cid:template.parameter_values_cid,
    barrier_cid:moon.clientProgramInferPlanBoundary(graph)._3,prepared_rows:BigInt(task.max_items),retained_bytes:7000n,execution_bytes:3000n},
    installation,runtimeArtifactCid:cid('d'),layoutArtifactCid:cid('e'),probability};
  const quantities={limits:{tokens:128n,costUnits:0n,durationMs:1000n},
    perAttempt:{tokens:128n,costUnits:0n,durationMs:1000n}};
  const originals=providerBindingOriginals('models/fixture',{selector:task.authored_model_selector,
    endpoint:profileBody.operation.endpoint});
  let sends=0;
  const requests=[];
  const ports=[];
  const registered=installModelProviders(moon,()=>[{providerId:'models/fixture',entryPersistence:'async',
    validatePrompt:(taskCid,selector,payload)=>taskCid===task.contract_cid&&selector===task.authored_model_selector&&
      payload===canonicalJson(prompt.body.payload,{dataKeys:true}),bindingOriginals:originals,
    quantityCapacity:quantities,rawCaptureSelection,
    originalReadInstallation:{nodeInstallation,modelRetainedBytes:100000n,modelExecutionBytes:3000n,
      bootstrap:{bootstrapRetainedBytes:100000n,bootstrapExecutionBytes:100000n,
        maxReservations:8,maxHoldings:8,maxDelegations:8},
      currentStateCodec:{quantum:1,comparisonWork:5,decode:{maxWork:20000,
        parse:{max_input_bytes:10000,max_nodes:1000,max_depth:20},
        tree:{max_nodes:1000,max_depth:20,max_string_bytes:10000,max_total_string_bytes:10000}}},
      storeBootstrap:{maxWireBytes:4096,maxDirectoryEntries:22},
      metadataAcquisition:{metadata:{maxWireBytes:4096,maxLedgerEntries:4},directory:{maxWireBytes:1024,maxDirectoryEntries:8},
        retainedBytes:7000n,workspaceBytes:3000n}},
    physicalPreflight(request,notification,retainRawBinder,admittedProvider){
      const port=(nativeDecision?createAdmittedTypeSafeDecisionPreflight:createAdmittedOpenAIChatPreflight)({moon,request,admittedProvider,
        probability,
        taskCid:task.contract_cid,promptCid:prompt.cid,outputSchemaCid:task.output_schema_cid,
        modelSelector:task.authored_model_selector,projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
        modelId,baseURL:nativeDecision?'https://fixture.invalid':'https://fixture.invalid/v1',apiKey:'fixture-only',signal,
        maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,checked,
        notify:notification.notify,rawCaptureBinder:retainRawBinder,profile,installation,
        quantities:quantities.perAttempt,responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
          maxHeaderBytes:128,observedHeaders:['content-type']},observeAt:now,
        fetch(url,init){sends++;requests.push({url,body:init.body});
          return new Response(responseWire,{headers:{'content-type':'application/json'}});}});
      ports.push(port);
      return port.preflight;
    }}]).get('models/fixture');
  const dependencies=readInstalledModelDependencies(moon,execution,{environmentWire,executionContracts:[],
    dependencyBodies:[prompt,retry,backoff].map(value=>({cid:value.cid,bodyWire:value.wire}))});
  const admittedProvider=admitInstalledModelProvider(moon,execution,dependencies,new Map([['models/fixture',registered]]));
  const accountWire=canonicalText({version:'actql-execution-account-config/0.1',account_id:'local',entries:[{
    entry_id:'model',outcome:'allow',principal:{any_of:['owner']},connection:{any_of:['models/fixture']},
    resource:{all:true},operation:{any_of:['infer','model_raw_capture']},exclusions:[]}]});
  const account=moon.executionAuthorizationAdmit(accountWire);
  const storeAuthorityCid=cid('e');
  const store=await openLocalPublicationStore({directory:join(root,'objects'),storeAuthorityCid,
    capacityBytes:1048576,maxObjectBytes:4096,maxObjects:40,maxContractNodes:1000,maxContractDepth:30,
    privateEvidenceKey:Buffer.alloc(32,7)},control);
  // Explicit fixture installation of independently authored originals. This
  // does not synthesize policy selection, current authority or normal funding.
  if(storeOriginals) for(const original of physicalOriginals) {
    await store.putSemantic(original.wire,original.cid);
  }
  let originalReads=0;
  const selectedStore=Object.freeze({...store,async confirmModelRawCaptureOriginals(originals,authority){
    originalReads++;
    assert.deepEqual(originals,physicalOriginals);
    await beforeOriginalRead?.({originals,store,authority,read:originalReads});
    return store.confirmModelRawCaptureOriginals(originals,authority);
  }});
  let cp;
  const controller=await installNodeModelContinuation({moon,control,store:selectedStore,storeAuthorityCid,
    namespaceId:'scope',authorityScopeCid:cid('3'),now,getCheckpoints:()=>cp});
  const keys=generateKeyPairSync('ed25519');
  cp=await installRemoteCheckpoints({root,namespaceId:'scope',authorityScopeCid:cid('3'),ownerPrincipal:'owner',
    siteKey:'local',realizationKey:'source-free-values',environmentCid:environmentCid,contractControl:control,
    modelResumeVerifier:controller.verifier,now:()=>Date.parse(now()),
    authorization:{resumeAfterAnswer:false,accountConfiguration:accountWire,
      reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId:'reviewer',publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})}}});
  t.after(async()=>{await cp.close();assert.equal(await store.close(),true);});
  const original=registered.originalReadInstallation;
  const scope=control.beginCheckedClientInferOriginalReadScope(compiled,runDefinition,graph,
    {...original.bootstrap,quantityCapacity:quantities});
  const read=control.prepareCheckedClientInferNodeReadLayout(compiled,runDefinition,graph,scope,original.nodeInstallation);
  const originalPreparation={scope,read,control,compiled,runDefinition,nodeInstallation:original.nodeInstallation,
    metadataInstallation:original,readRetainedBytes:7000n,readExecutionBytes:3000n,
    modelRetainedBytes:100000n,modelExecutionBytes:3000n};
  const ioNotification=createInferIoNotification();
  const operation=openNodeInferOperation({moon,preparedProgram:prepared,step,graph,
    registry:input('infer_fixture_registry'),values:input('infer_fixture_values'),
    provider:moon.clientProgramAdmittedModelProvider(admittedProvider,execution),
    originalPreparation,durableCalls:true,quantityCapacity:quantities,signal,ioNotification,
    physicalPreflight:(request,notification,binder)=>registered.physicalPreflight(request,notification,binder,admittedProvider)});
  const plan={compiled,runDefinition,inferGraph:graph};
  operation.bindRun(control,plan);
  let boundary;
  try {boundary=await operation.run();}
  catch(error){
    const tag=value=>Number.isInteger(value?.$tag)?value.$tag:null;
    t.diagnostic(`Original pre-Waiting typed tags ${JSON.stringify([tag(error.cause),tag(error.cause?._0)])}`);
    throw error;
  }
  assert.equal(boundary.status,'waiting');
  const providerBinding=admitInstalledModelProviderBinding(moon,'models/fixture',registered);
  const opened=await controller.open({operation,preparedCallSet:boundary.preparedCallSet,plan,
    selected:{step,graph,providerBinding,observeAccount:()=>account,currentProvider:()=>true,
      egressAdmission:checked(moon.clientProgramAdmitInferEgress(prepared,step,execution,
        ()=>({_0:'public',_1:nativeDecision?'fixture':'fixture-region',_2:false,_3:false}))),
      entryPersistence:'async',rawCaptureSelection:registered.rawCaptureSelection},principalId:'owner',
    declaredResults:['answer'],submission:{fixture:'original-sdk-common'},signal,originalPreparation});
  return {root,operation,opened,controller,cp,store,control,plan,prepared,registered,
    sends:()=>sends,requests,ports,originalReads:()=>originalReads,profileWire:profileOriginal.wire};
}
