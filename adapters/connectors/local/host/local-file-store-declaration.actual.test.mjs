// Actual Common Catalog/check/lowering consumers. No physical file write,
// Reference issuer, Account decision, Run or approval is supplied here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, mkdtemp} from 'node:fs/promises';
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

assert(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME,'Select the actual qualified Common runtime');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
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
const source=set=>"SELECT 1 AS id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'one.jsonl') "+
  '|> EFFECT STORE local.files SET ('+set+')';
const prepare=(fixture,set)=>moon.clientProgramPrepareSourceComputationWithParameters(source(set),'sql',
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
    minimum_approval:'required',preview:{strength:'exact'},outcome:'synchronous',
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
    if(suffix)assert.equal(command.input.overwrite,true);
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

async function storeOwnerFixture({withMapping=true,driverKinds=['command'],continuationBinding}={}) {
  const f=fixture(),mapping=JSON.parse(f.data.mappingWire),command=JSON.parse(f.data.commandWire);
  const unavailable=()=>assert.fail('Selection validation cannot perform provider work');
  const owner=await createInstalledRowEffect({moon,environmentWire:f.environment.wire,
    connectorId:'local',connectorRegistration:'local',connectorRevision:'local/0.1',connection:'local',
    runtimeBundleCid:'sha256:'+'d'.repeat(64),bindingCid:'sha256:'+'b'.repeat(64),
    ...(continuationBinding===undefined?{}:{continuationBinding}),
    ledgerRoot:await mkdtemp(join(tmpdir(),'actql-store-original-')),
    mappings:withMapping?[{resource:'files',mappingRef:mapping.mapping_ref,
      mappingCid:mapping.mapping_contract_cid,body:f.data.mappingWire}]:[],
    commands:[{resource:'files',commandRef:command.command_id,
      commandCid:command.contract_cid,body:f.data.commandWire}],
    site:{issueReadGrant:unavailable,issueEffectGrant:unavailable,close(){}},
    authorization:{authorize:unavailable},
    driver:{kinds:driverKinds,...Object.fromEntries(['prepareRequest','requestFacts','writeOperation',
      'send','project','footprint','recheckRequests','recoveryEntry','recoverRequests','requestCid']
      .map(name=>[name,unavailable]))}});
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
    return {owner,originals,prepared,compilation,selections,member,facts,
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
  const f=await storeOwnerFixture();
  let family;
  try{
    const core=runtimeCore(moon),control=core.publicationControl;
    const registry=await readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json',import.meta.url),'utf8');
    const aoa=JSON.parse(await readFile(new URL('../../../../spec/contracts/actql-aoa.json',import.meta.url),'utf8'));
    const values=JSON.stringify(aoa.execution_contracts['REL.values']);
    const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
    const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
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
