// Actual Common Catalog/check/lowering consumers. No physical file write,
// Reference issuer, Account decision, Run or approval is supplied here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {inspect} from 'node:util';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';

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
  return{wire,data,admitted,publication};
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
