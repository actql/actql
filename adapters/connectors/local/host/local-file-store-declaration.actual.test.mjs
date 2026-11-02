// Actual Common Catalog/check/lowering consumers. The final capture component
// also supplies the original collection Reference issuer and fresh Content
// Store. Account/resource ports remain explicit; no approval or target send.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fsPromises, {readFile, mkdtemp} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {inspect} from 'node:util';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';
import {createInstalledRowEffect, installedRowEffectOwnerBinding,
  validateInstalledUpdateOwnerSelections, installedRowEffectDescriptors,
  installedRowEffectUnit} from '../../../host-node/installed-row-effect.mjs';
import {installUpdateTargetOriginals} from '../../../host-node/installed-update-originals.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {installNodeContentRun} from '../../../host-node/installed-content-run.mjs';
import {prepareLocalFileStoreTarget} from './local-file-store-target.mjs';
import {createNodeHostEntry} from '../../../host-node/entry.mjs';
import {installStrategyContributions} from '../../../connectors-builtin/strategy.generated.mjs';
import {withLocalExecutionPauseHandler} from '../../../local-node/retained-store.mjs';
import {openLocalPublicationStore} from '../../../store-local/publication-store.mjs';
import {acquiredEffectPublicationAdmission,sourceFreeContentEffectPublicationPlan,localOutputLimits} from '../../../host-node/local-values-plan.mjs';
import {createLocalFileStoreDriver,LOCAL_STORE_LIMITS} from './installed-project-file-effects.mjs';
import {releaseCompletedRunPreparedPayloads, suspendCompletedEffectfulComputation,
  recoverCompletedEffectfulComputation, transferCompletedEffectfulCaptureCustody,
  prepareCompletedEffectfulPublication, publishCompletedEffectfulRun} from '../../../host-common/completed-run-publication.mjs';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import {issueAuthorizedEffectSetReceipt} from '../../../host-node/effect-response-recovery.mjs';
import {refusedEffectPreparation} from '../../../host-common/effect-preparation-result.mjs';

const commonRuntime=process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME
  ?pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME)
  :new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url);
const moon=await import(commonRuntime);
const canonical=value=>canonicalJson(value,{dataKeys:true});
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const base=(await readFile(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8')).trimEnd();
const options={connectorId:'local',rootPath:'/original/data-e\u0301',maxBytes:131072};
function original(){
  const schema={path:{type:'string',nullable:false}};
  const value=checked(moon.clientProgramRowSourceRestoreRelationDeclaration('local','local','local/0.1',
    JSON.stringify({views:[{resource:'files',resource_kind:'file',schema_wire:canonical(schema),
      schema_cid:cid(schema),facts_wire:'{}'}]}),undefined));
  return moon.clientProgramRowSourceDeclarationJson(value);
}
function fixture(){
  const wire=original(),data=localFileStoreDeclaration(wire,options);
  const environment=rowSourceCheckEnvironment(base,JSON.parse(data.declarationWire),[data.mappingWire]);
  const admitted=moon.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,
    false,false,true,false,false,false,false);
  assert(admitted,'the actual Common environment admits the complete Local declaration');
  const publication=JSON.stringify({environmentCid:moon.clientProgramCheckingEnvironmentCid(admitted),
    aliases:[],storeTargets:[{name:'local.files',targetRef:'connector://local/files',
      installationBindingCid:'sha256:'+'b'.repeat(64),installationOwnerCid:'sha256:'+'c'.repeat(64)}]});
  assert.equal(moon.clientProgramSourcePublicationValid(admitted,publication),true);
  return{wire,data,admitted,publication,environment};
}
const source=(set,serializationOptions='',authoredResult=false)=>"SELECT 1 AS id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'one.jsonl'"+
  serializationOptions+") "+
  (authoredResult?'|> RESULT answer ':'')+
  '|> EFFECT STORE local.files SET ('+set+')';
const prepare=(fixture,set)=>moon.clientProgramPrepareSourceComputationWithParameters(source(set,fixture.serializationOptions,fixture.authoredResult),'sql',
  fixture.admitted,fixture.publication,undefined,undefined,true,[]);

test('actual Local STORE declaration retains complete Source originals and requires exact typed Content and approval',()=>{
  const {wire,data}=fixture(),before=JSON.parse(wire),after=JSON.parse(data.declarationWire);
  for(const name of Object.keys(before).filter(name=>!['catalog','catalog_cid','contracts','command_bodies'].includes(name)))
    assert.deepEqual(after[name],before[name],name);
  assert.deepEqual(JSON.parse(after.catalog).source_views,JSON.parse(before.catalog).source_views);
  for(const contract of before.contracts)assert(after.contracts.includes(contract));
  const {contract_cid,...command}=JSON.parse(data.commandWire);
  const inputBody={additional_properties:false,fields:{content:{type:'content_ref',nullable:false},
    overwrite:{type:'boolean',nullable:false},path:{type:'string',nullable:false}},required_fields:['content','path']};
  const input={schema:'actql.contract/0.1',id:'local.local.files.store.command_input',version:'local/0.1',
    kind:'command_input',body:inputBody};
  const output={schema:'actql.contract/0.1',id:'local.local.files.store.command_output',version:'local/0.1',
    kind:'command_output',body:{type:'object',nullable:false,additional_properties:false,fields:{}}};
  const expected={schema:'actql.command_contract/0.1',command_id:'command:local.local.files.store.v1',
    connector_id:'local',version:'local/0.1',target:{resource_kind:'file_collection',cardinality:'single'},
    input_schema:{id:input.id,version:'local/0.1',cid:cid(input)},input_contract:inputBody,
    output_schema:{id:output.id,version:'local/0.1',cid:cid(output)},permissions:['files.write'],
    preview:{strength:'exact'},outcome:'synchronous',
    idempotency:{support:'unsupported'},reversibility:'unknown',atomicity:'single_target'};
  assert.deepEqual(command,expected);assert.equal(contract_cid,cid(expected));
  assert.equal(localFileStoreDeclaration(data.declarationWire,options).declarationWire,data.declarationWire,
    'same exact published Command is retained, not appended again');
  const changed=localFileStoreDeclaration(wire,{...options,rootPath:'/other/root'});
  assert.equal(changed.commandWire,data.commandWire,'scope never changes the Command input contract');
  assert.notEqual(changed.identityWire,data.identityWire);assert.notEqual(changed.mappingWire,data.mappingWire);
});

test('actual SQL Local STORE normalizes once to its checked Command and preserves overwrite omission or TRUE',()=>{
  const f=fixture();
  for(const suffix of ['',', overwrite = TRUE']){
    const outcome=prepare(f,"path = 'copy.jsonl', content = content"+suffix);
    const effect=moon.clientProgramSourceComputationEffect(outcome);
    assert(effect,inspect(outcome,{depth:8}));
    const prepared=moon.clientProgramEffectPreparationReady(effect);
    assert(prepared,inspect(moon.clientProgramEffectPreparationIssue(effect),{depth:10}));
    // Match the real Host boundary: source-free generation requires its
    // original explicit unknown-provenance policy before compilation. This
    // fixture supplies DATA only; it does not install a Host or authorize STORE.
    const policyWire='{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
    assert.equal(typeof moon.clientProgramCompileLocalEffectsWithSourceFreePolicyBody,'function',
      'prepare the changed required Common runtime before executing this new boundary');
    let compilation;
    try{compilation=checked(moon.clientProgramCompileLocalEffectsWithSourceFreePolicyBody(prepared,
      'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',policyWire,1000000,100000,100));}
    catch(cause){assert.fail(inspect(cause.cause,{depth:16}));}
    const plan=JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation));
    const effects=plan.execution_material.program.stages.flatMap(stage=>Object.values(stage.effects??{}));
    assert.equal(effects.length,1);assert(effects[0].command);
    const command=effects[0].command;
    assert.equal(command.contract,'command:local.local.files.store.v1');
    assert.deepEqual(command.target,{published_store:{target_ref:'connector://local/files',
      mapping_ref:'mapping:local.local.files.store.v1'}});
    assert.equal(Object.hasOwn(command.input,'overwrite'),suffix!=='');
    if(suffix){
      // STORE evaluates SET expressions in the original Relation prefix and
      // binds the resulting private field, not a second command literal.
      assert.deepEqual(command.input.overwrite,{field:'overwrite'});
      const stage=plan.execution_material.program.stages.find(value=>
        Object.values(value.effects??{}).some(effect=>effect.command===command));
      const result=Object.entries(stage.results).find(([name])=>
        command.from.result===name||command.from.result===`${stage.id}.${name}`)?.[1];
      assert(result);assert(result.fields.includes('overwrite'));
      const selected=stage.steps.find(step=>step.as===result.from);
      const slot=selected.select.find(value=>typeof value==='object'&&value.overwrite)?.overwrite;
      assert.equal(typeof slot,'string');
      const producer=stage.steps.slice(0,stage.steps.indexOf(selected))
        .find(step=>Object.hasOwn(step.derive??{},slot));
      assert.deepEqual(producer?.derive[slot],{literal:true});
    }
  }
});

test('actual Local STORE refuses missing or wrong typed inputs and conflicting original declaration DATA',()=>{
  const f=fixture();
  for(const set of ["content = content","path = 'copy', content = id",
    "path = 'copy', content = content, overwrite = 'yes'"]){
    const outcome=prepare(f,set),effect=moon.clientProgramSourceComputationEffect(outcome);
    assert(effect===undefined||moon.clientProgramEffectPreparationReady(effect)===undefined,set);
  }
  const parsed=JSON.parse(f.wire),catalog=JSON.parse(parsed.catalog);
  for(const malformed of [
    {...parsed,catalog_cid:'sha256:'+'f'.repeat(64)},
    {...parsed,contracts:[]},
    {...parsed,command_bodies:null},
    {...parsed,connector_registration:'gcs'},
  ])assert.throws(()=>localFileStoreDeclaration(canonical(malformed),options),
    {code:'InvalidLocalFileStoreDeclaration'});
  assert.throws(()=>localFileStoreDeclaration(f.wire,{...options,maxBytes:32}),
    {code:'InvalidLocalFileStoreDeclaration'});
  assert.throws(()=>localFileStoreDeclaration(f.wire,{...options,rootPath:'relative'}),
    {code:'InvalidLocalFileStoreDeclaration'});
  for(const malformed of ['null','[]','true','{"catalog":"null"}'])
    assert.throws(()=>localFileStoreDeclaration(malformed,options),{code:'InvalidLocalFileStoreDeclaration'});
  assert.deepEqual(JSON.parse(f.wire).catalog,canonical(catalog),'no original input mutation');
});

async function storeOwnerFixture({withMapping=true,driverKinds=['command'],continuationBinding,serializationOptions='',authoredResult=false,
  withCollection=false,requestBoundary,inspectRequest,withLocalDriver=false,observeRecovery,
  withContentContracts=false}={}) {
  const f={...fixture(),serializationOptions,authoredResult},mapping=JSON.parse(f.data.mappingWire),command=JSON.parse(f.data.commandWire);
  // The fixture owns one actual installed sequence-contract admission, just
  // as the normal Host retains its original selection before creating Content.
  // Every family/cold context below borrows this SAME original; no provider or
  // runtime method reinterprets a registry wire or creates a replacement cache.
  let contentBodies;
  if(withContentContracts){
    const [registryWire,aoaWire]=await Promise.all([
      readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json',import.meta.url),'utf8'),
      readFile(new URL('../../../../spec/contracts/actql-aoa.json',import.meta.url),'utf8')]);
    const aoa=JSON.parse(aoaWire),values=JSON.stringify(aoa.execution_contracts['REL.values']);
    const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
    const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    const registry=checked(moon.clientPrepareInstalledSequenceContracts(registryWire,values,fragment,ordered));
    assert.equal(typeof registry,'object');
    contentBodies=Object.freeze({registry,values,fragment,ordered});
  }
  const unavailable=()=>assert.fail('Selection validation cannot perform provider work');
  const target=withCollection?prepareLocalFileStoreTarget(moon,{...options,declaredWire:f.wire,
    scopeCid:'sha256:'+'3'.repeat(64),authorityScopeCid:'sha256:'+'a'.repeat(64),
    maxNodes:16384,maxDepth:64,assertCurrent(){}}):undefined;
  const runOriginal=Object.freeze({explicitComponentResourcePort:true});
  const driverLimits={...LOCAL_STORE_LIMITS,maxFileBytes:1000000};
  const resources={bindRunOriginal:()=>runOriginal,
    assertCurrent(value){assert.strictEqual(value,runOriginal);},limits:()=>driverLimits};
  const local=withLocalDriver?createLocalFileStoreDriver({
    entry:{connection:'local',limits:{maxPathBytes:4096,maxFileBytes:1000000}},
    target,command,bindingCid:'sha256:'+'b'.repeat(64),principalId:'component',
    authorization:{},assertCurrent(){},resources,limits:driverLimits,
    nativeFilesystem:()=>assert.fail('A component Preview must not send or mutate a target'),
  }):undefined;
  const owner=await createInstalledRowEffect({moon,environmentWire:f.environment.wire,
    connectorId:'local',connectorRegistration:'local',connectorRevision:'local/0.1',connection:'local',
    runtimeBundleCid:'sha256:'+'d'.repeat(64),bindingCid:'sha256:'+'b'.repeat(64),
    ...(continuationBinding===undefined?{}:{continuationBinding}),
    ...(target===undefined?{}:{issueOriginalCollectionReference:target.issueOriginalCollectionReference}),
    ledgerRoot:await mkdtemp(join(tmpdir(),'actql-store-original-')),
    mappings:withMapping?[{resource:'files',mappingRef:mapping.mapping_ref,
      mappingCid:mapping.mapping_contract_cid,body:f.data.mappingWire}]:[],
    commands:[{resource:'files',commandRef:command.command_id,
      commandCid:command.contract_cid,body:f.data.commandWire}],
    ...(local===undefined?{}:{effectResources:resources}),
    site:local?.site??{issueReadGrant:unavailable,issueEffectGrant:unavailable,close(){}},
    authorization:{authorize:unavailable},
    driver:local===undefined?{kinds:driverKinds,...Object.fromEntries(['prepareRequest','requestFacts','writeOperation',
      'send','project','footprint','recheckRequests','recoveryEntry','recoverRequests','requestCid']
      .map(name=>[name,name==='prepareRequest'&&requestBoundary!==undefined?facts=>{
        inspectRequest?.(facts);throw requestBoundary;
      }:unavailable]))}:observeRecovery===undefined?local.driver:Object.freeze({...local.driver,
        recoverRequests(...args){
          const result=Reflect.apply(local.driver.recoverRequests,local.driver,args);
          observeRecovery(result);return result;
        }})});
  try{
    const publication=JSON.parse(f.publication);
    publication.storeTargets[0].installationOwnerCid=installedRowEffectOwnerBinding(owner).cid;
    const outcome=prepare({...f,publication:JSON.stringify(publication)},"path = 'copy.jsonl', content = content");
    const prepared=moon.clientProgramEffectPreparationReady(moon.clientProgramSourceComputationEffect(outcome));
    assert(prepared);
    const policy='{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
    const compilation=checked(moon.clientProgramCompileLocalEffectsWithSourceFreePolicyBody(prepared,
      'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',policy,1000000,100000,100));
    const originals=installUpdateTargetOriginals({moon,control:runtimeCore(moon).publicationControl,
      installedEffect:{effects:[owner],environmentWire:f.environment.wire},
      limits:{maxWireBytes:1000000,maxNodes:100000,maxDepth:100}});
    const selections=originals.selectionsOf(prepared);
    const descriptor=installedRowEffectDescriptors(moon,prepared,compilation)[0];
    const stageIndex=installedRowEffectUnit(moon,compilation).stageIndex;
    const member={effect_id:descriptor.effectId,effect_kind:'command',target:descriptor.target,
      contract:descriptor.commandRef,resolved_command_contract_cid:descriptor.commandCid};
    const facts={prepared,compilation,selections,stageIndex,preview:{effects:[member]}};
    return {owner,originals,prepared,compilation,selections,member,facts,declaredWire:f.wire,target,
      localDriver:local?.driver,...(contentBodies===undefined?{}:{contentBodies}),
      close:()=>owner.close()};
  }catch(cause){await owner.close();throw cause;}
}

test('actual Local STORE selection reaches its same command Owner without UPDATE substitution',async()=>{
  const f=await storeOwnerFixture();
  const {owner,originals,prepared,compilation,selections,member,facts}=f;
  try{
    assert.equal(selections.length,1);
    assert.equal(validateInstalledUpdateOwnerSelections(owner,selections,prepared),selections);
    originals.validateRecoveredSelectionMembers(facts);
    for(const changed of [{target:'foreign'},{contract:'foreign'},
      {resolved_command_contract_cid:'sha256:'+'f'.repeat(64)},{effect_kind:'update'}]){
      assert.throws(()=>originals.validateRecoveredSelectionMembers({...facts,
        preview:{effects:[{...member,...changed}]}}));
    }
    assert.throws(()=>originals.validateRecoveredSelectionMembers({...facts,selections:[...selections]}));
    assert.throws(()=>originals.validateRecoveredSelectionMembers({...facts,stageIndex:facts.stageIndex+1}));
    const saved=originals.capturePrepared(prepared,compilation);
    assert.equal(typeof saved.preparedWire,'string');
    assert.throws(()=>validateInstalledUpdateOwnerSelections(owner,[...selections],prepared),
      {code:'InstalledRowEffectInstallationChanged'});
  }finally{await f.close();}
});

test('actual Local STORE with authored RESULT reaches its postcompute member fence before publication',async()=>{
  const f=await storeOwnerFixture({authoredResult:true});
  let foreign;
  try{
    assert(moon.clientProgramEffectCompilationResultNames(f.compilation).includes('answer'),
      'keep the authored Named Content Result in the actual checked compilation');
    assert.equal(f.selections.length,1);
    const boundary=new Error('SelectedBeforePublication');
    let liveChecks=0,publicationReads=0;
    const plan={get invocation(){publicationReads++;throw boundary;}};
    // Exercise the actual postcompute consumer with original checked members.
    // The explicit publication port stops before any Result storage/provider
    // work; this fixture does not execute Compute, authorize or write a file.
    const facts={moon,prepared:f.prepared,compilation:f.compilation,
      updateTargetSelections:f.selections,assertUpdateSelectionCurrent(){liveChecks++;},
      execution:{},checkedHost:{},identity:{},definition:{},previewContext:{},
      unit:installedRowEffectUnit(moon,f.compilation),plan};
    await assert.rejects(f.owner.prepareCaptured(facts),error=>error===boundary);
    assert.equal(liveChecks,1);assert.equal(publicationReads,1);
    await assert.rejects(f.owner.prepareCaptured({...facts,updateTargetSelections:[...f.selections]}),
      {code:'InstalledRowEffectInstallationChanged'});
    foreign=await storeOwnerFixture({authoredResult:true});
    await assert.rejects(f.owner.prepareCaptured({...facts,prepared:foreign.prepared,
      compilation:foreign.compilation}),{code:'InstalledRowEffectInstallationChanged'});
    await assert.rejects(f.owner.prepareCaptured({...facts,assertUpdateSelectionCurrent:undefined}),
      {code:'InstalledRowEffectInstallationChanged'});
    const changed=new Error('ActualCurrentRefusal');
    await assert.rejects(f.owner.prepareCaptured({...facts,assertUpdateSelectionCurrent(){throw changed;}}),
      error=>error===changed);
    assert.equal(publicationReads,1,'foreign/copied/missing/current-refused selections never reach publication');
  }finally{await foreign?.close();await f.close();}
});

test('actual Local STORE current selection refuses missing purpose foreign owner and foreign preparation',async()=>{
  const original=await storeOwnerFixture(),others=[];
  try{
    for(const options of [{withMapping:false},{driverKinds:['create']},
      {continuationBinding:'sha256:'+'f'.repeat(64)}]){
      const other=await storeOwnerFixture(options);others.push(other);
      assert.throws(()=>validateInstalledUpdateOwnerSelections(other.owner,
        original.selections,original.prepared),{code:'InstalledRowEffectInstallationChanged'});
    }
    assert.throws(()=>validateInstalledUpdateOwnerSelections({...original.owner},
      original.selections,original.prepared),{code:'InstalledRowEffectInstallationChanged'});
    assert.throws(()=>validateInstalledUpdateOwnerSelections(original.owner,
      original.selections,others[0].prepared),{code:'InstalledRowEffectInstallationChanged'});
  }finally{for(const other of others)await other.close();await original.close();}
});

test('actual Local STORE saved preparation restores its original source-free policy',async t=>{
  const f=await storeOwnerFixture();
  try{
    const saved=f.originals.capturePrepared(f.prepared,f.compilation);
    let restored;
    try { restored=f.originals.restorePrepared(saved); }
    catch(cause) { t.diagnostic(inspect(cause.cause,{depth:8})); throw cause; }
    restored.assertUpdateSelectionCurrent();
  }finally{await f.close();}
});

test('actual Local STORE saved Run retains its policy request and same installed command Owner',async()=>{
  const f=await storeOwnerFixture();
  try{
    const authority='sha256:'+'a'.repeat(64);
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const define=runId=>checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-original-scope',runId,'2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const control=runtimeCore(moon).publicationControl;
    const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:100};
    const admit=definition=>control.admit('run_definition',moon.strategyPublicationContractJson(definition),limits);
    const request=requestId=>moon.clientProgramEffectRequestIdentity(f.prepared,
      authority,requestId,moon.clientProgramSourceFreeInputIntentCid());
    const definition=define('store-original-run'),run=admit(definition),identity=request('store-original-request');
    assert(identity);
    const original=f.originals.captureRun({...f,allowed,definition,identity});
    // Exercise the production saved-material adapter, not a copied selection
    // as an authority. Durable storage and public approval are separate cases.
    const retained=JSON.parse(JSON.stringify(original));
    const restored=f.originals.restoreRun(retained,run,identity);
    restored.assertUpdateSelectionCurrent();
    assert.deepEqual(f.originals.captureRun({...restored,identity}),original);
    assert.equal(moon.clientProgramEffectCompilationPlanWire(restored.compilation),
      moon.clientProgramEffectCompilationPlanWire(f.compilation));
    f.originals.validateRecoveredSelectionMembers({...f.facts,prepared:restored.prepared,
      compilation:restored.compilation,selections:restored.updateTargetSelections});
    assert.throws(()=>f.originals.restoreRun(retained,run,undefined));
    assert.throws(()=>f.originals.restoreRun(retained,run,request('foreign-store-request')));
    assert.throws(()=>f.originals.restoreRun(retained,admit(define('foreign-store-run')),identity));
    for(const name of ['source_free_result_policy_cid','source_free_result_policy_json']){
      const body=JSON.parse(retained.materialsWire);
      delete body[name];
      assert.throws(()=>f.originals.restoreRun({...retained,materialsWire:canonical(body)},run,identity));
    }
    const body=JSON.parse(retained.materialsWire);
    delete body.client_request_identity;
    assert.throws(()=>f.originals.restoreRun({...retained,materialsWire:canonical(body)},run,undefined));
    assert.throws(()=>f.originals.restoreRun({...retained,materialsWire:canonical(body)},run,identity));
    const foreign={...retained,installations:retained.installations.map(value=>({...value,cid:'sha256:'+'f'.repeat(64)}))};
    assert.throws(()=>f.originals.restoreRun(foreign,run,identity));
  }finally{await f.close();}
});

test('actual Local STORE family admits its original source-free Host capacity',async t=>{
  const f=await storeOwnerFixture({withContentContracts:true});
  let family;
  try{
    const core=runtimeCore(moon),control=core.publicationControl;
    const {registry,values,fragment,ordered}=f.contentBodies;
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-capacity-scope','store-capacity-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
    const storeAuthorityCid='sha256:'+'8'.repeat(64);
    // The production family supplies the actual typed provider. Its physical
    // ports are deliberately unaccounted fixtures and must not perform I/O.
    const content=installNodeContentRun({moon,core,registry,values,fragment,ordered,
      namespaceId:'store-capacity-scope',authorityScopeCid:'sha256:'+'a'.repeat(64),
      storeAuthorityCid,ownerPrincipal:'fixture',now:()=> '2026-10-21T00:00:00.000Z',
      authorize:()=>true});
    family=content.effectFamily({prepared:f.prepared,plan:{kind:'effect',compiled,runDefinition,
      serializationGraph:control.compiledSerializationGraph(compiled)},
      store:{storeAuthorityCid,status:()=>({closed:false})},principalId:'fixture'});
    assert(family.provider);
    const capacity=moon.clientProgramEffectContentLedgerLimits(f.prepared,
      registry,values,fragment,ordered,family.provider);
    t.diagnostic(JSON.stringify({sourceFree:true,serializationCount:
      moon.clientProgramEffectSerializationOccurrences(f.prepared).length,
      originalFamilyProvider:true,capacityAvailable:capacity!==undefined}));
    assert(capacity,'the supported source-free STORE family must have an admitted Host envelope');
  }finally{await family?.close();await f.close();}
});

function compiledStoreGeneration(f,runId){
  const control=runtimeCore(moon).publicationControl;
  const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
    'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
  const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
    'store-generation-scope',runId,'2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
  const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
    {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
  const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
  return{control,compiled,graph:control.compiledSerializationGraph(compiled)};
}

for(const [name,serializationOptions,expected] of [
  ['Host defaults','',{maxRows:1000,maxBytes:1000,jsonLeafFields:1}],
  ['authored tighter ceilings',', max_rows = 7, max_bytes = 41',{maxRows:7,maxBytes:41,jsonLeafFields:1}],
])test(`actual Local STORE generation retains original ${name} before encoding`,async()=>{
  const f=await storeOwnerFixture({serializationOptions});let foreign;
  try{
    const {control,compiled,graph}=compiledStoreGeneration(f,'same-generation');
    const limits=control.checkedClientSerializationGenerationLimits(compiled,graph);
    assert.deepEqual(limits,expected);assert(Object.isFrozen(limits));
    assert.throws(()=>control.checkedClientSerializationGenerationLimits({...compiled},graph));
    assert.throws(()=>control.checkedClientSerializationGenerationLimits(compiled,{...graph}));
    if(name==='Host defaults'){
      foreign=await storeOwnerFixture();
      const other=compiledStoreGeneration(foreign,'foreign-generation');
      assert.throws(()=>control.checkedClientSerializationGenerationLimits(compiled,other.graph));
    }
  }finally{await foreign?.close();await f.close();}
});

test('actual Local STORE generation refuses formerly-invalid authored zero guards',()=>{
  const f=fixture();
  for(const serializationOptions of [', max_rows = 0',', max_bytes = 0']){
    const outcome=prepare({...f,serializationOptions},"path = 'copy.jsonl', content = content");
    const effect=moon.clientProgramSourceComputationEffect(outcome);
    assert(effect===undefined||moon.clientProgramEffectPreparationReady(effect)===undefined);
  }
});

test('actual compiled Content preserves zero private generation ceilings without widening authored guards',()=>{
  const f=fixture(),control=runtimeCore(moon).publicationControl;
  const program={version:'actql/0.1',id:'zero-private-generation',stages:[{
    id:'main',inputs:{},steps:[
      {values:{schema:{id:{type:'number',nullable:false}},rows:[]},as:'seed'},
      {serialize:{format:'jsonl',fields:['id'],preserve_order:true,name:'empty.jsonl'},as:'file'},
    ],results:{file:{from:'file',fields:['name','content','media_type','size_bytes','row_count']}},
  }],results:{file:{from:{stage:'main',result:'file'}}}};
  const preparation=moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),'json',f.admitted,undefined);
  const prepared=moon.clientProgramPreparationReady(preparation);assert(prepared);
  const resultDataPolicy={kind:'data_policy',
    cid:'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
    wire:'{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'};
  const graph=control.prepareCheckedClientSerializationGraph(prepared,
    {task:0,step:1,maxRows:0,maxBytes:0,resultDataPolicy});
  const compiled=control.prepareCheckedClientCompiledRun(prepared,'serialization',{
    executionContextCid:'sha256:'+'1'.repeat(64),hostPolicyCid:'sha256:'+'2'.repeat(64),
    expiresAt:'2099-01-01T00:00:00.000Z'},graph);
  assert.deepEqual(control.checkedClientSerializationGenerationLimits(compiled,graph),
    {maxRows:0,maxBytes:0,jsonLeafFields:1});
});

test('actual Local STORE authored Content captures Preview with its original published target',async t=>{
  const f=await storeOwnerFixture({withContentContracts:true,authoredResult:true,withCollection:true,withLocalDriver:true});
  const core=runtimeCore(moon),control=core.publicationControl;
  const directory=await mkdtemp(join(tmpdir(),'actql-store-reference-component-'));
  t.diagnostic(`Fresh component Store retained at ${directory}`);
  const storeAuthorityCid='sha256:'+'8'.repeat(64);
  let store,family,execution,stage;
  try{
    const {registry,values,fragment,ordered}=f.contentBodies;
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-reference-component','store-reference-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
    const owner=checked(moon.clientProgramBindCompiledEffectRun(f.prepared,allowed,definition));
    store=await openLocalPublicationStore({directory,storeAuthorityCid,
      capacityBytes:512*1024*1024,maxObjectBytes:localOutputLimits.maxWireBytes,maxObjects:100,
      maxContractNodes:100000,maxContractDepth:100,privateEvidenceKey:Buffer.alloc(32,7)},control);
    const content=installNodeContentRun({moon,core,registry,values,fragment,ordered,
      namespaceId:'store-reference-component',authorityScopeCid:'sha256:'+'a'.repeat(64),
      storeAuthorityCid,ownerPrincipal:'component',now:()=> '2026-10-21T00:00:00.000Z',authorize:()=>true});
    family=content.effectFamily({prepared:f.prepared,plan:{kind:'effect',compiled,runDefinition,
      serializationGraph:control.compiledSerializationGraph(compiled)},store,principalId:'component'});
    const host=moon.clientProgramOpenSourceFreeFamilyEffectHost(owner,
      registry,values,fragment,ordered,[family.provider]);
    assert(host,'the actual authored Content has its original family Host');
    const entry=createNodeHostEntry(()=>Promise.resolve(moon),installStrategyContributions);
    execution=await entry.runCapturedEffectComputation(host,
      {local:withLocalExecutionPauseHandler(undefined,boundary=>family.handlePause(boundary))});
    assert.equal(execution.status,'host-tasks-completed');
    assert(family.generation());
    assert(moon.clientProgramEffectCompilationResultNames(f.compilation).includes('answer'));
    const identity=moon.clientProgramEffectRequestIdentity(f.prepared,'sha256:'+'a'.repeat(64),
      'store-reference-request',moon.clientProgramSourceFreeInputIntentCid());
    assert(identity);
    const acquired=acquiredEffectPublicationAdmission({moon,control,prepared:f.prepared,
      compilation:f.compilation,allowed,definition,authorityScopeCid:'sha256:'+'a'.repeat(64),
      namespaceId:'store-reference-component',storeAuthorityCid,now:()=> '2026-10-21T00:00:00.000Z',
      resultDataPolicy:control.compiledSerializationPolicy(compiled)});
    const plan=sourceFreeContentEffectPublicationPlan({acquired,compiled,generation:family.generation()});
    try{stage=await f.owner.prepareCaptured({moon,control,store,execution,checkedHost:host,
      prepared:f.prepared,compilation:f.compilation,identity,definition,publicationPlan:plan,
      updateTargetSelections:f.selections,assertUpdateSelectionCurrent(){},contentOwner:family});}
    catch(error){t.diagnostic(`Original postcompute consumer: ${inspect(error,{depth:6})}`);throw error;}
    assert(stage.preview);
    const preview=JSON.parse(control.effectComputationPreviewWire(stage.preview));
    assert.equal(preview.effects.length,1);
    assert.equal(preview.effects[0].effect_kind,'command');
    assert.equal(preview.effects[0].changes.length,1);
    assert.equal(preview.effects[0].changes[0].intended_changes.value.path,'copy.jsonl');
    assert.deepEqual(preview.effects[0].changes[0].target_row_identity,JSON.parse(f.target.resourceWire));
  }finally{
    await stage?.dispose();
    if(stage)await releaseCompletedRunPreparedPayloads(stage.storedResults,control);
    await execution?.close();
    if(execution)assert.equal(execution.cleanupPending(),false);
    await family?.close();
    if(family)assert.equal(family.cleanupPending(),false);
    await store?.close();
    await f.close();
  }
});

test('actual Local STORE cold Content restores its retained generation before send',async t=>{
  const f=await storeOwnerFixture({withContentContracts:true,authoredResult:true,withCollection:true,withLocalDriver:true});
  const core=runtimeCore(moon),control=core.publicationControl;
  const directory=await mkdtemp(join(tmpdir(),'actql-store-cold-component-'));
  t.diagnostic(`Fresh component Store retained at ${directory}`);
  const storeAuthorityCid='sha256:'+'8'.repeat(64);
  let store,family,execution,stage,recoveredStage,recoveredComputation,suspended=false;
  const recoveryOwners=[];
  try{
    const {registry,values,fragment,ordered}=f.contentBodies;
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-reference-component','store-reference-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
    const owner=checked(moon.clientProgramBindCompiledEffectRun(f.prepared,allowed,definition));
    store=await openLocalPublicationStore({directory,storeAuthorityCid,
      capacityBytes:512*1024*1024,maxObjectBytes:localOutputLimits.maxWireBytes,maxObjects:100,
      maxContractNodes:100000,maxContractDepth:100,privateEvidenceKey:Buffer.alloc(32,7)},control);
    const content=installNodeContentRun({moon,core,registry,values,fragment,ordered,
      namespaceId:'store-reference-component',authorityScopeCid:'sha256:'+'a'.repeat(64),
      storeAuthorityCid,ownerPrincipal:'component',now:()=> '2026-10-21T00:00:00.000Z',authorize:()=>true});
    family=content.effectFamily({prepared:f.prepared,plan:{kind:'effect',compiled,runDefinition,
      serializationGraph:control.compiledSerializationGraph(compiled)},store,principalId:'component'});
    const host=moon.clientProgramOpenSourceFreeFamilyEffectHost(owner,
      registry,values,fragment,ordered,[family.provider]);
    assert(host,'the actual authored Content has its original family Host');
    const entry=createNodeHostEntry(()=>Promise.resolve(moon),installStrategyContributions);
    execution=await entry.runCapturedEffectComputation(host,
      {local:withLocalExecutionPauseHandler(undefined,boundary=>family.handlePause(boundary))});
    assert.equal(execution.status,'host-tasks-completed');
    assert(family.generation());
    assert(moon.clientProgramEffectCompilationResultNames(f.compilation).includes('answer'));
    const identity=moon.clientProgramEffectRequestIdentity(f.prepared,'sha256:'+'a'.repeat(64),
      'store-reference-request',moon.clientProgramSourceFreeInputIntentCid());
    assert(identity);
    const acquired=acquiredEffectPublicationAdmission({moon,control,prepared:f.prepared,
      compilation:f.compilation,allowed,definition,authorityScopeCid:'sha256:'+'a'.repeat(64),
      namespaceId:'store-reference-component',storeAuthorityCid,now:()=> '2026-10-21T00:00:00.000Z',
      resultDataPolicy:control.compiledSerializationPolicy(compiled)});
    const plan=sourceFreeContentEffectPublicationPlan({acquired,compiled,generation:family.generation()});
    try{stage=await f.owner.prepareCaptured({moon,control,store,execution,checkedHost:host,
      prepared:f.prepared,compilation:f.compilation,identity,definition,publicationPlan:plan,
      updateTargetSelections:f.selections,assertUpdateSelectionCurrent(){},contentOwner:family});}
    catch(error){t.diagnostic(`Original postcompute consumer: ${inspect(error,{depth:6})}`);throw error;}
    assert(stage.preview);
    const preview=JSON.parse(control.effectComputationPreviewWire(stage.preview));
    assert.equal(preview.effects.length,1);
    assert.equal(preview.effects[0].effect_kind,'command');
    assert.equal(preview.effects[0].changes.length,1);
    assert.equal(preview.effects[0].changes[0].intended_changes.value.path,'copy.jsonl');
    assert.deepEqual(preview.effects[0].changes[0].target_row_identity,JSON.parse(f.target.resourceWire));
    const materials=JSON.parse(JSON.stringify(f.originals.captureRun({
      prepared:f.prepared,compilation:f.compilation,allowed,definition,identity})));
    const continuation=JSON.parse(stage.continuationWire);
    // The actual Host beforeDefer callback prepares these SAME unsent intents
    // before suspending capture. This creates no dispatch or send permission.
    assert.equal(stage.apply.ledger.prepareCapturedSetIntents(
      stage.apply.capturedInputs,stage.apply.members,stage.apply.maxFrontierWork),1);
    await suspendCompletedEffectfulComputation({execution,store,storedResults:stage.storedResults,
      control,computation:stage.computation,preview:stage.preview});
    suspended=true;
    await stage.dispose();
    await execution.close();assert.equal(execution.cleanupPending(),false);execution=undefined;
    await family.close();assert.equal(family.cleanupPending(),false);family=undefined;
    // Re-admit only this NEW component's saved capture. No public/failed Run
    // state, private dispatch/retry or physical target send is a test port.
    recoveredComputation=await recoverCompletedEffectfulComputation({store,control,runDefinition,
      contractLimits:{maxWireBytes:1000000,maxNodes:100000,maxDepth:100}});
    const restored=f.originals.restoreRun(materials,runDefinition,identity);
    const recovered=Object.freeze({...restored,requestIdentity:identity,
      requestScope:moon.clientRequestLogicalScope(identity),runDefinition,computation:recoveredComputation});
    const embedded=await readFile(new URL('../../../host-node/embedded-local.mjs',import.meta.url),'utf8');
    const begin=embedded.indexOf('  function recoveredInstalledEffect(facts) {');
    const end=embedded.indexOf('\n  try {\n    const installationSourcePreparation',begin);
    assert(begin>0&&end>begin);
    const actualSelector=new Function('updateTargetOriginals','installedEffect',
      'validateInstalledUpdateOwnerSelections','installedEffectFor','refusedEffectPreparation',
      'clientOperationError',`return (${embedded.slice(begin,end).trim()});`)(
      f.originals,f.owner,validateInstalledUpdateOwnerSelections,
      ()=>assert.fail('The singular actual installation is the selected component'),
      refusedEffectPreparation,code=>Object.assign(new Error(code),{code}));
    const facts=Object.freeze({moon,control,store,recovered,continuation,contentRun:content,
      principalId:'component',retainRecoveryOwner:owner=>recoveryOwners.push(owner)});
    // Same actual Host selector and callback argument shape. In particular do
    // not supply additional prepared/Plan/definition hints to mask a gap.
    const selected=actualSelector(facts);
    recoveredStage=await selected.prepareRecovered({...facts,
      updateTargetSelections:recovered.updateTargetSelections,
      assertUpdateSelectionCurrent:recovered.assertUpdateSelectionCurrent});
    assert.strictEqual(recoveredStage.preview,recoveredComputation.preview);
    assert.strictEqual(recoveredStage.computation,recoveredComputation.computation);
    assert.strictEqual(recoveredStage.storedResults,recoveredComputation.storedResults);
    assert(recoveryOwners.length>0);
    const copiedSource=Object.freeze({...recoveredComputation.effectSources[0].source});
    const copiedComputation=Object.freeze({...recoveredComputation,effectSources:Object.freeze(
      recoveredComputation.effectSources.map((entry,index)=>index===0
        ? Object.freeze({...entry,source:copiedSource}) : entry))});
    const copied=Object.freeze({...recovered,computation:copiedComputation});
    await assert.rejects(selected.prepareRecovered({...facts,recovered:copied,
      updateTargetSelections:copied.updateTargetSelections,
      assertUpdateSelectionCurrent:copied.assertUpdateSelectionCurrent}),
      /Foreign captured Effect source artifact/);
    const foreignDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(
      checked(moon.clientProgramIssueEffectRunDefinition(allowed,'store-reference-component',
        'foreign-cold-content-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'))),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const foreign=Object.freeze({...recovered,runDefinition:foreignDefinition});
    await assert.rejects(selected.prepareRecovered({...facts,recovered:foreign,
      updateTargetSelections:foreign.updateTargetSelections,
      assertUpdateSelectionCurrent:foreign.assertUpdateSelectionCurrent}));
  }finally{
    // Match installed Effect custody: close the original physical recovery
    // child before disposing the stage whose pending check protects it.
    for(const owner of recoveryOwners)await owner.close();
    await recoveredStage?.dispose();
    await stage?.dispose();
    if(recoveredComputation)await suspendCompletedEffectfulComputation({execution:null,store,
      storedResults:recoveredComputation.storedResults,control,
      computation:recoveredComputation.computation,preview:recoveredComputation.preview});
    if(stage&&!suspended)await releaseCompletedRunPreparedPayloads(stage.storedResults,control);
    await execution?.close();
    if(execution)assert.equal(execution.cleanupPending(),false);
    await family?.close();
    if(family)assert.equal(family.cleanupPending(),false);
    await store?.close();
    await f.close();
  }
});

test('actual Local STORE cold Content settles its original response through final publication',async t=>{
  let recoveredRequests;
  const f=await storeOwnerFixture({withContentContracts:true,authoredResult:true,withCollection:true,withLocalDriver:true,
    observeRecovery:value=>{assert.equal(recoveredRequests,undefined);recoveredRequests=value;}});
  const core=runtimeCore(moon),control=core.publicationControl;
  const directory=await mkdtemp(join(tmpdir(),'actql-store-postwrite-component-'));
  t.diagnostic(`Fresh component Store retained at ${directory}`);
  const storeAuthorityCid='sha256:'+'8'.repeat(64);
  let store,family,execution,stage,recoveredStage,recoveredComputation,suspended=false;
  const recoveryOwners=[],missingContracts=[];
  const originalOpen=fsPromises.open;
  let observing=false,phase='capture',inventory;
  const observedOpen=async function(...args){
    const path=typeof args[0]==='string'?args[0]:undefined;
    const selected=observing&&path?.startsWith(directory+'/contracts/')&&
      /^[0-9a-f]{64}\.json$/.test(path.slice((directory+'/contracts/').length));
    const callStack=selected?new Error('Original component contract read').stack:undefined;
    try{return await Reflect.apply(originalOpen,this,args);}
    catch(error){
      if(selected&&error?.code==='ENOENT'&&missingContracts.length<8)
        missingContracts.push({phase,cid:'sha256:'+path.split('/').at(-1).slice(0,64),stack:callStack});
      throw error; // Same actual error, no missing-contract substitution.
    }
  };
  try{
    const {registry,values,fragment,ordered}=f.contentBodies;
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-reference-component','store-reference-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
    const owner=checked(moon.clientProgramBindCompiledEffectRun(f.prepared,allowed,definition));
    store=await openLocalPublicationStore({directory,storeAuthorityCid,
      capacityBytes:512*1024*1024,maxObjectBytes:localOutputLimits.maxWireBytes,maxObjects:100,
      maxContractNodes:100000,maxContractDepth:100,privateEvidenceKey:Buffer.alloc(32,7)},control);
    const content=installNodeContentRun({moon,core,registry,values,fragment,ordered,
      namespaceId:'store-reference-component',authorityScopeCid:'sha256:'+'a'.repeat(64),
      storeAuthorityCid,ownerPrincipal:'component',now:()=> '2026-10-21T00:00:00.000Z',authorize:()=>true});
    family=content.effectFamily({prepared:f.prepared,plan:{kind:'effect',compiled,runDefinition,
      serializationGraph:control.compiledSerializationGraph(compiled)},store,principalId:'component'});
    const host=moon.clientProgramOpenSourceFreeFamilyEffectHost(owner,
      registry,values,fragment,ordered,[family.provider]);
    assert(host,'the actual authored Content has its original family Host');
    const entry=createNodeHostEntry(()=>Promise.resolve(moon),installStrategyContributions);
    execution=await entry.runCapturedEffectComputation(host,
      {local:withLocalExecutionPauseHandler(undefined,boundary=>family.handlePause(boundary))});
    assert.equal(execution.status,'host-tasks-completed');
    assert(family.generation());
    assert(moon.clientProgramEffectCompilationResultNames(f.compilation).includes('answer'));
    const identity=moon.clientProgramEffectRequestIdentity(f.prepared,'sha256:'+'a'.repeat(64),
      'store-reference-request',moon.clientProgramSourceFreeInputIntentCid());
    assert(identity);
    const acquired=acquiredEffectPublicationAdmission({moon,control,prepared:f.prepared,
      compilation:f.compilation,allowed,definition,authorityScopeCid:'sha256:'+'a'.repeat(64),
      namespaceId:'store-reference-component',storeAuthorityCid,now:()=> '2026-10-21T00:00:00.000Z',
      resultDataPolicy:control.compiledSerializationPolicy(compiled)});
    const plan=sourceFreeContentEffectPublicationPlan({acquired,compiled,generation:family.generation()});
    try{stage=await f.owner.prepareCaptured({moon,control,store,execution,checkedHost:host,
      prepared:f.prepared,compilation:f.compilation,identity,definition,publicationPlan:plan,
      updateTargetSelections:f.selections,assertUpdateSelectionCurrent(){},contentOwner:family});}
    catch(error){t.diagnostic(`Original postcompute consumer: ${inspect(error,{depth:6})}`);throw error;}
    assert(stage.preview);
    const preview=JSON.parse(control.effectComputationPreviewWire(stage.preview));
    assert.equal(preview.effects.length,1);
    assert.equal(preview.effects[0].effect_kind,'command');
    assert.equal(preview.effects[0].changes.length,1);
    assert.equal(preview.effects[0].changes[0].intended_changes.value.path,'copy.jsonl');
    assert.deepEqual(preview.effects[0].changes[0].target_row_identity,JSON.parse(f.target.resourceWire));
    const materials=JSON.parse(JSON.stringify(f.originals.captureRun({
      prepared:f.prepared,compilation:f.compilation,allowed,definition,identity})));
    const continuation=JSON.parse(stage.continuationWire);
    // The actual Host beforeDefer callback prepares these SAME unsent intents
    // before suspending capture. This creates no dispatch or send permission.
    assert.equal(stage.apply.ledger.prepareCapturedSetIntents(
      stage.apply.capturedInputs,stage.apply.members,stage.apply.maxFrontierWork),1);
    await suspendCompletedEffectfulComputation({execution,store,storedResults:stage.storedResults,
      control,computation:stage.computation,preview:stage.preview});
    suspended=true;
    await stage.dispose();
    await execution.close();assert.equal(execution.cleanupPending(),false);execution=undefined;
    await family.close();assert.equal(family.cleanupPending(),false);family=undefined;
    // Re-admit only this NEW component's saved capture. No public/failed Run
    // state, private dispatch/retry or physical target send is a test port.
    recoveredComputation=await recoverCompletedEffectfulComputation({store,control,runDefinition,
      contractLimits:{maxWireBytes:1000000,maxNodes:100000,maxDepth:100}});
    const restored=f.originals.restoreRun(materials,runDefinition,identity);
    const recovered=Object.freeze({...restored,requestIdentity:identity,
      requestScope:moon.clientRequestLogicalScope(identity),runDefinition,computation:recoveredComputation});
    const embedded=await readFile(new URL('../../../host-node/embedded-local.mjs',import.meta.url),'utf8');
    const begin=embedded.indexOf('  function recoveredInstalledEffect(facts) {');
    const end=embedded.indexOf('\n  try {\n    const installationSourcePreparation',begin);
    assert(begin>0&&end>begin);
    const actualSelector=new Function('updateTargetOriginals','installedEffect',
      'validateInstalledUpdateOwnerSelections','installedEffectFor','refusedEffectPreparation',
      'clientOperationError',`return (${embedded.slice(begin,end).trim()});`)(
      f.originals,f.owner,validateInstalledUpdateOwnerSelections,
      ()=>assert.fail('The singular actual installation is the selected component'),
      refusedEffectPreparation,code=>Object.assign(new Error(code),{code}));
    const facts=Object.freeze({moon,control,store,recovered,continuation,contentRun:content,
      principalId:'component',retainRecoveryOwner:owner=>recoveryOwners.push(owner)});
    // Same actual Host selector and callback argument shape. In particular do
    // not supply additional prepared/Plan/definition hints to mask a gap.
    const selected=actualSelector(facts);
    recoveredStage=await selected.prepareRecovered({...facts,
      updateTargetSelections:recovered.updateTargetSelections,
      assertUpdateSelectionCurrent:recovered.assertUpdateSelectionCurrent});
    assert.strictEqual(recoveredStage.preview,recoveredComputation.preview);
    assert.strictEqual(recoveredStage.computation,recoveredComputation.computation);
    assert.strictEqual(recoveredStage.storedResults,recoveredComputation.storedResults);
    assert(recoveryOwners.length>0);
    assert.equal(recoveredRequests.requests.length,1);
    assert.equal(recoveredRequests.requests[0].length,1);
    const request=recoveredRequests.requests[0][0];
    const claim=recoveredStage.receipt.members[0].rowOwners[0].claim;
    assert.equal(f.localDriver.requestCid(request),claim.canonicalRequestCid);
    const {execution:restoredExecution,store:restoredStore,storedResults,control:restoredControl,
      computation:restoredCapture,preview:restoredPreview}=recoveredStage.publication;
    inventory=prepareCompletedEffectfulPublication({execution:restoredExecution,store:restoredStore,
      storedResults,control:restoredControl,computation:restoredCapture,preview:restoredPreview});
    // The original claim, saved response, projector, Ledger, Common issuers
    // and publication are real. Account/current/Resource and this provider
    // observation are explicit component DATA ports; no filesystem send or
    // physical ACK is inferred from the authored observation.
    fsPromises.open=observedOpen;syncBuiltinESMExports();observing=true;
    phase='capture-custody-transfer';
    await transferCompletedEffectfulCaptureCustody(recoveredStage.publication);
    phase='response-capture';
    const value=f.localDriver.requestFacts(request).value;
    const response={request_cid:claim.canonicalRequestCid,path:value.path,bytes:9,action:'stored'};
    const captured=await captureClaimedEffectResponse({ledger:recoveredStage.apply.ledger,
      claim,requestCid:claim.canonicalRequestCid,
      execute:async()=>({observation:{useCid:'sha256:'+'9'.repeat(64),statusCode:200,
        body:Buffer.from(canonical(response))}})});
    assert.equal(captured.claimed,true);
    phase='response-projection';
    const projected=f.localDriver.project({request,observation:captured.physical.observation});
    assert.deepEqual(projected,{kind:'typed-success-response',outcome:{state:'applied',result:{}}});
    phase='row-outcome';
    const row={claim,preview:recoveredStage.receipt.preview,memberIndex:0,previewRowIndex:0};
    recoveredStage.apply.ledger.recordAdmittedRowOutcome({...row,outcomeWire:canonical(projected.outcome)});
    recoveredStage.apply.ledger.commitAdmittedRowOutcome(row);
    phase='effect-set';
    const issuedSet=await issueAuthorizedEffectSetReceipt(recoveredStage.receipt);
    phase='final-publication';
    const published=await publishCompletedEffectfulRun({...recoveredStage.publication,issuedSet,signal:undefined});
    assert(published);
  }catch(error){
    t.diagnostic(JSON.stringify({phase,error:{code:error?.code,message:error?.message,stack:error?.stack},
      missingContracts,inventory:inventory===undefined?undefined:{
        sourceArtifacts:inventory.sourceArtifacts.map(value=>({name:value.name,cid:value.identity})),
        chain:Object.entries(inventory.chain).flatMap(([name,value])=>
          Array.isArray(value)?value.map(item=>({slot:name,name:item?.name,cid:item?.identity})):
            [{slot:name,name:value?.name,cid:value?.identity}])}}));
    throw error;
  }finally{
    observing=false;fsPromises.open=originalOpen;syncBuiltinESMExports();
    assert.strictEqual(fsPromises.open,originalOpen);
    // Match installed Effect custody: close the original physical recovery
    // child before disposing the stage whose pending check protects it.
    for(const owner of recoveryOwners)await owner.close();
    await recoveredStage?.dispose();
    await stage?.dispose();
    if(recoveredComputation)await suspendCompletedEffectfulComputation({execution:null,store,
      storedResults:recoveredComputation.storedResults,control,
      computation:recoveredComputation.computation,preview:recoveredComputation.preview});
    if(stage&&!suspended)await releaseCompletedRunPreparedPayloads(stage.storedResults,control);
    await execution?.close();
    if(execution)assert.equal(execution.cleanupPending(),false);
    await family?.close();
    if(family)assert.equal(family.cleanupPending(),false);
    await store?.close();
    await f.close();
  }
});

test('actual Local STORE cold capture refuses altered original source schema',async t=>{
  const f=await storeOwnerFixture({withContentContracts:true,authoredResult:true,withCollection:true,withLocalDriver:true});
  const core=runtimeCore(moon),control=core.publicationControl;
  const directory=await mkdtemp(join(tmpdir(),'actql-store-schema-controls-'));
  t.diagnostic(`Fresh component Store retained at ${directory}`);
  const storeAuthorityCid='sha256:'+'8'.repeat(64);
  let store,family,execution,stage,recoveredStage,recoveredComputation,suspended=false;
  try{
    const {registry,values,fragment,ordered}=f.contentBodies;
    const allowed=checked(moon.clientProgramIssueAllowedEffectRun(f.compilation,
      'sha256:'+'1'.repeat(64),'sha256:'+'2'.repeat(64),'2099-01-01T00:00:00.000Z'));
    const definition=checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'store-reference-component','store-reference-run','2026-10-21T00:00:00.000Z','2098-01-01T00:00:00.000Z'));
    const runDefinition=control.admit('run_definition',moon.strategyPublicationContractJson(definition),
      {maxWireBytes:1000000,maxNodes:100000,maxDepth:100});
    const compiled=control.adoptCheckedClientEffectSerializationRun(allowed,runDefinition);
    const owner=checked(moon.clientProgramBindCompiledEffectRun(f.prepared,allowed,definition));
    store=await openLocalPublicationStore({directory,storeAuthorityCid,
      capacityBytes:512*1024*1024,maxObjectBytes:localOutputLimits.maxWireBytes,maxObjects:100,
      maxContractNodes:100000,maxContractDepth:100,privateEvidenceKey:Buffer.alloc(32,7)},control);
    const content=installNodeContentRun({moon,core,registry,values,fragment,ordered,
      namespaceId:'store-reference-component',authorityScopeCid:'sha256:'+'a'.repeat(64),
      storeAuthorityCid,ownerPrincipal:'component',now:()=> '2026-10-21T00:00:00.000Z',authorize:()=>true});
    family=content.effectFamily({prepared:f.prepared,plan:{kind:'effect',compiled,runDefinition,
      serializationGraph:control.compiledSerializationGraph(compiled)},store,principalId:'component'});
    const host=moon.clientProgramOpenSourceFreeFamilyEffectHost(owner,
      registry,values,fragment,ordered,[family.provider]);
    assert(host,'the actual authored Content has its original family Host');
    const entry=createNodeHostEntry(()=>Promise.resolve(moon),installStrategyContributions);
    execution=await entry.runCapturedEffectComputation(host,
      {local:withLocalExecutionPauseHandler(undefined,boundary=>family.handlePause(boundary))});
    assert.equal(execution.status,'host-tasks-completed');
    assert(family.generation());
    assert(moon.clientProgramEffectCompilationResultNames(f.compilation).includes('answer'));
    const identity=moon.clientProgramEffectRequestIdentity(f.prepared,'sha256:'+'a'.repeat(64),
      'store-reference-request',moon.clientProgramSourceFreeInputIntentCid());
    assert(identity);
    const acquired=acquiredEffectPublicationAdmission({moon,control,prepared:f.prepared,
      compilation:f.compilation,allowed,definition,authorityScopeCid:'sha256:'+'a'.repeat(64),
      namespaceId:'store-reference-component',storeAuthorityCid,now:()=> '2026-10-21T00:00:00.000Z',
      resultDataPolicy:control.compiledSerializationPolicy(compiled)});
    const plan=sourceFreeContentEffectPublicationPlan({acquired,compiled,generation:family.generation()});
    try{stage=await f.owner.prepareCaptured({moon,control,store,execution,checkedHost:host,
      prepared:f.prepared,compilation:f.compilation,identity,definition,publicationPlan:plan,
      updateTargetSelections:f.selections,assertUpdateSelectionCurrent(){},contentOwner:family});}
    catch(error){t.diagnostic(`Original postcompute consumer: ${inspect(error,{depth:6})}`);throw error;}
    assert(stage.preview);
    const preview=JSON.parse(control.effectComputationPreviewWire(stage.preview));
    assert.equal(preview.effects.length,1);
    assert.equal(preview.effects[0].effect_kind,'command');
    assert.equal(preview.effects[0].changes.length,1);
    assert.equal(preview.effects[0].changes[0].intended_changes.value.path,'copy.jsonl');
    assert.deepEqual(preview.effects[0].changes[0].target_row_identity,JSON.parse(f.target.resourceWire));
    const materials=JSON.parse(JSON.stringify(f.originals.captureRun({
      prepared:f.prepared,compilation:f.compilation,allowed,definition,identity})));
    const continuation=JSON.parse(stage.continuationWire);
    // The actual Host beforeDefer callback prepares these SAME unsent intents
    // before suspending capture. This creates no dispatch or send permission.
    assert.equal(stage.apply.ledger.prepareCapturedSetIntents(
      stage.apply.capturedInputs,stage.apply.members,stage.apply.maxFrontierWork),1);
    await suspendCompletedEffectfulComputation({execution,store,storedResults:stage.storedResults,
      control,computation:stage.computation,preview:stage.preview});
    suspended=true;
    await stage.dispose();
    await execution.close();assert.equal(execution.cleanupPending(),false);execution=undefined;
    await family.close();assert.equal(family.cleanupPending(),false);family=undefined;
    const recordCid=control.effectComputationRecordHoldingCid(runDefinition,store.storeAuthorityCid);
    const raw=await store.readPrivateEvidence('effect_capture',stage.computation.capturedRun.identity,recordCid);
    const original=JSON.parse(raw.toString('utf8'));
    assert.equal(original.effect_source_artifacts.length,1);
    const originalSchema=original.effect_source_artifacts[0].schema;
    assert.equal(originalSchema.cid,JSON.parse(original.effect_source_artifacts[0].artifact).result_schema_cid);
    const changes=[
      {name:'foreign schema identity',code:'InvalidCompletedEffectSourceSchema',
        change:schema=>{schema.cid='sha256:'+'f'.repeat(64);}},
      {name:'changed same-identity schema bytes',code:'PublicationPrivateEvidenceConflict',
        change:schema=>{schema.wire='{}';}},
    ];
    const selected=process.env.ACTQL_SCHEMA_NEGATIVE_SELECTION===undefined?changes:
      changes.filter(value=>value.name===process.env.ACTQL_SCHEMA_NEGATIVE_SELECTION);
    assert(selected.length>0,'a nonempty exact negative selection is required');
    for(const {name,code,change} of selected){
      const changed=JSON.parse(raw.toString('utf8'));
      change(changed.effect_source_artifacts[0].schema);
      // Only this fresh component's authenticated private-record DATA port is
      // deliberately changed. Every actual Common/Store check remains active;
      // neither a schema identity nor its holder is fabricated as authority.
      const changedStore=Object.freeze({...store,readPrivateEvidence:async(...args)=>
        args[0]==='effect_capture'?Buffer.from(JSON.stringify(changed)):
          Reflect.apply(store.readPrivateEvidence,store,args)});
      await assert.rejects(recoverCompletedEffectfulComputation({store:changedStore,control,runDefinition,
        contractLimits:{maxWireBytes:1000000,maxNodes:100000,maxDepth:100}}),
        error=>error?.code===code,name);
    }
    assert.deepEqual(JSON.parse((await store.readPrivateEvidence('effect_capture',
      stage.computation.capturedRun.identity,recordCid)).toString('utf8')),original,
      'refusal never changes the original saved capture');
  }finally{
    await stage?.dispose();
    if(stage&&!suspended)await releaseCompletedRunPreparedPayloads(stage.storedResults,control);
    await execution?.close();
    if(execution)assert.equal(execution.cleanupPending(),false);
    await family?.close();
    if(family)assert.equal(family.cleanupPending(),false);
    await store?.close();
    await f.close();
  }
});
