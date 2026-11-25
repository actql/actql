import assert from 'node:assert/strict';
import {mkdir,writeFile,open,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {loadInstalledProjectConfiguration} from '../../../host-node/installed-project-configuration.mjs';
import {prepareInstalledProjectLocalFiles,installPreparedProjectLocalFiles} from './installed-project-files.mjs';
import {installPreparedProjectLocalFileEffects} from './installed-project-file-effects.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../../../host-common/runtime-result.mjs';
import {installedSourceConfigurationReader} from '../../../host-node/installed-host-services.mjs';
import {createInstalledLoaderParent} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {canonical,cid} from '../../../host-node/fixtures/file-listing-source.fixture.mjs';
import {composeInstalledSourceEnvironment} from '../../../host-node/installed-funded-environment.mjs';

import type {TestContext} from 'node:test';

type Install = Parameters<typeof installPreparedProjectLocalFiles>[0];
type EffectInstall = Parameters<typeof installPreparedProjectLocalFileEffects>[0];
type Construction = NonNullable<Install['construction']>;
type LoadInput<Result> = Readonly<{capacity(): unknown; project(): Result}>;
type OwnedScratch = Awaited<ReturnType<typeof createOwnedScratch>>;
type Failure = Readonly<{primaryFailure?: Error & {code?: string}}>;
type View = Readonly<{resource: string; source_ref: string; capability_contract_cids: readonly string[]}>;
type Contract = Readonly<{kind: string; body: Readonly<{fields: Record<string, unknown>}>}>;
type Declaration = Readonly<{views: readonly View[]; contracts: readonly string[]}>;

assert(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME,'Select the actual qualified Common runtime');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME) as unknown as string);
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const limits=Object.freeze({maxEntries:16,maxDepth:4,maxPathBytes:256,maxFiles:8,
  maxFileBytes:131072,maxReadBytes:524288,maxPages:8,maxPageBytes:65536,maxPageRows:8,
  maxAttempts:8,maxDurationMs:10000,maxListingBytes:524288});
let scratch: OwnedScratch,sequence=0;
test.before(async()=>{scratch=await createOwnedScratch({parent:join(root,'_build'),
  prefix:'local-project-files-',label:'Local Project original files preparation'});});
test.after(()=>scratch?.passed());
async function fixture(wire: string,runtime=moon){
  const directory=join(scratch.path,String(++sequence));await mkdir(join(directory,'configuration'),{recursive:true});
  await writeFile(join(directory,'actql.config.json'),'{"version":"actql-config/0.1","connectors":"configuration/connectors.json"}');
  await writeFile(join(directory,'configuration/connectors.json'),wire);
  return{directory,project:await loadInstalledProjectConfiguration(runtime,{directory})};
}
const document=(entry: string)=>' {"version":"actql-connectors/0.1","connections":{"local":'+entry+'}}\n';

test('actual Common Local preparation preserves original Project bytes and typed files/contents without filesystem discovery',async()=>{
  const entry='{ "connector" : "local", "root" : "../data-é", "version" : "content", "tables" : {} }';
  const runtime=Object.freeze({...moon,clientProjectConnectionsEntryOriginalJson(){
    assert.fail('Local selection must use the admitted Project connections');
  }});
  const f=await fixture(document(entry),runtime);let opens=0;
  const preparation=await prepareInstalledProjectLocalFiles(runtime,f.project,{limits,assertCurrent(){},
    openFile:async(path: string,...args: [flags?: string, mode?: number])=>{assert.equal(path,join(f.directory,'configuration/connectors.json'));opens++;return open(path,...args);}});
  assert.equal(opens,1,'no business directory, child file, credential or Root was acquired');
  const original=preparation!.originalsForRuntime(runtime);assert.equal(original.sources.length,1);
  assert.strictEqual(original.project,f.project!.originalsForRuntime(runtime));
  assert.strictEqual(original.connections.project,original.project);
  assert.equal(original.connections.wire,document(entry));
  const source=original.sources[0];
  assert.equal(source.rootPath,join(f.directory,'data-é'));assert.equal(source.versionMode,'content');
  assert(Object.isFrozen(original)&&Object.isFrozen(original.sources)&&Object.isFrozen(source.limits));
  const declared=JSON.parse(source.wire) as Declaration;assert.deepEqual(declared.views.map(x=>x.resource).sort(),['contents','files']);
  const contracts=declared.contracts.map(text=>JSON.parse(text) as Contract);
  const files=contracts.find(x=>x.kind==='carrier_schema'&&x.body.fields.size);
  assert.deepEqual(files!.body.fields.size,{type:'int64',nullable:false});
  assert.deepEqual(files!.body.fields.modified_time,{type:'timestamp',nullable:false});
  const contents=contracts.find(x=>x.kind==='carrier_schema'&&x.body.fields.content);
  assert.deepEqual(contents!.body.fields.content,{type:'content_ref',nullable:false});
  assert.deepEqual(source.queryAliases,[{name:'local',resource:'files'},
    {name:'local.files',resource:'files'},{name:'local.contents',resource:'contents'}]);
  preparation!.retire(runtime);
  assert.throws(()=>preparation!.originalsForRuntime(runtime),{code:'LocalFilesPreparationRetired'});
});

test('absent and unrelated connections create no Local declaration or default limits',async()=>{
  assert.equal(await prepareInstalledProjectLocalFiles({},undefined),undefined);
  for(const wire of ['{"version":"actql-connectors/0.1","connections":{}}',
    '{"version":"actql-connectors/0.1","connections":{"n":{"connector":"notion","credentials":{"env":"DO_NOT_READ"}}}}']){
    const f=await fixture(wire);
    assert.equal(await prepareInstalledProjectLocalFiles(moon,f.project,{assertCurrent(){}}),undefined);
  }
});

test('actual Common restores distinct declared CSV views with their original schema and key',async()=>{
  const tables={small:{path:'small.csv',columns:{id:'int64',name:'string'},key:['id']},
    other:{path:'other.csv',columns:{id:'int64',name:'string'},key:['id']},
    events:{path:'warehouse/events',format:'iceberg'}};
  const f=await fixture(document(JSON.stringify({connector:'local',root:'../data',tables})));
  let opens=0;
  const preparation=await prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){},
    openFile:async(path: string,...args: [flags: string])=>{assert.equal(path,join(f.directory,'configuration/connectors.json'));
      opens++;return open(path,...args);}});
  assert(preparation);
  const source=preparation.originalsForRuntime(moon).sources[0];
  const declaration=JSON.parse(source.wire) as {
    views: {resource: string; source_ref: string; carrier_schema_cid: string}[];
    contracts: string[];
  };
  const contracts=declaration.contracts.map(wire=>JSON.parse(wire) as {
    cid: string; body: {fields?: unknown; relation_keys?: {candidate_keys: string[][]}};
  });
  assert.equal(opens,1);
  assert.deepEqual(source.queryAliases.map(alias=>alias.name),['local','local.files','local.contents','local.small','local.other']);
  for(const resource of ['small','other']){
    const view=declaration.views.find(view=>view.resource===resource);
    assert(view);
    const schema=contracts.find(contract=>contract.cid===view.carrier_schema_cid);
    assert(schema);
    assert.deepEqual(schema.body.fields,{id:{type:'int64',nullable:false},name:{type:'string',nullable:false}});
    assert.ok(Object.hasOwn(source.csvTransports,view.source_ref));
    assert.ok(contracts.some(contract=>contract.body.relation_keys?.candidate_keys[0][0]==='id'));
  }
  assert.notEqual(declaration.views.find(view=>view.resource==='small')?.source_ref,
    declaration.views.find(view=>view.resource==='other')?.source_ref);
  assert.equal(Object.keys(source.csvTransports).length,2);
  preparation.retire(moon);
});

test('Local preparation refuses malformed roots and unsupported version selection without guessed semantics',async()=>{
  for(const value of [null,false,'','a\0b']){
    const f=await fixture(document(JSON.stringify({connector:'local',root:value,tables:{}})));
    await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){}}),
      {code:'InvalidLocalFilesConnection'});
  }
  const f=await fixture(document('{"connector":"local","root":"../data","version":"guess"}'));
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){}}),
    {code:'LocalFilesVersionUnavailable'});
});

test('Local preparation keeps nominal runtime/receiver and currentness fences with explicit limits',async()=>{
  const f=await fixture(document('{"connector":"local","root":"../data","tables":{}}'));
  let current=true;
  const preparation=await prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){
    if(!current)throw Object.assign(new Error('current changed'),{code:'TestCurrentChanged'});
  }});
  assert.equal(preparation!.originalsForRuntime(moon).sources[0].versionMode,'metadata');
  assert.throws(()=>({...preparation}).originalsForRuntime!(moon),{code:'ForeignLocalFilesPreparation'});
  assert.throws(()=>preparation!.originalsForRuntime({...moon}),{code:'ForeignLocalFilesPreparation'});
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,{...f.project},{limits,assertCurrent(){}}),
    {code:'ForeignInstalledProjectOriginal'});
  await assert.rejects(prepareInstalledProjectLocalFiles({...moon},f.project,{limits,assertCurrent(){}}),
    {code:'ForeignInstalledProjectRuntime'});
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{assertCurrent(){}}),
    {code:'LocalFilesLimitsUnavailable'});
  current=false;assert.throws(()=>preparation!.originalsForRuntime(moon),{code:'TestCurrentChanged'});
  preparation!.retire(moon);
});

// Actual public installer and original Resource/Source construction owner.
// No Run, Account decision, native Root, transport or cleanup ACK is mocked.
async function installedReadProfileFixture(t: TestContext, wrap: (input: Construction) => Construction = value => value) {
  const f=await fixture(document('{"connector":"local","root":"../data","tables":{}}'));
  const preparation=await prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){}});
  const original=preparation!.originalsForRuntime(moon);
  const parent=createInstalledLoaderParent({root:f.directory,moon});parent.open();
  t.after(async()=>{await parent.close();preparation!.retire(moon);});
  let authorizationCalls=0;
  const construction=wrap(installedSourceConfigurationReader(parent.services!) as Construction);
  const base=JSON.parse(await readFile(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8'));
  delete base.evidence_bundle_cid;
  // This component selects its actual finite Source service policy; the
  // Resource parent and its default 512 MiB allowances remain unchanged.
  base.host_policy_profile.lookup_execution={version:'actql-lookup-execution-policy/0.1',
    max_network_attempts_per_request:limits.maxAttempts,max_request_bytes_per_attempt:4096,
    max_total_request_bytes:limits.maxReadBytes,max_total_response_bytes:limits.maxReadBytes,
    max_total_decoded_response_bytes:limits.maxReadBytes,max_total_duration_ms:limits.maxDurationMs};
  const options={moon,preparation,construction,
    sourceManaged:{assertCurrent(){},prepareRead(){assert.fail('No physical read during installation');}},
    baseEnvironmentWire:canonical({...base,evidence_bundle_cid:cid(base)}),
    authorizationFor:async()=>{authorizationCalls++;return {context:{contextCid:'sha256:'+'a'.repeat(64)},
      configurationCid:cid({fixture:'ungranted Local installation'}),
      authorize(){assert.fail('Initialization cannot authorize a Run');},
      assertAccountCurrent(){assert.fail('No Account grant during metadata construction');}};}};
  return{options: options as unknown as Install,original,preparation,parent,authorizationCalls:()=>authorizationCalls};
}

test('public Local installer funds and forwards its same installed row read profile and transport',async t=>{
  const f=await installedReadProfileFixture(t);
  let profile;
  try {profile=f.parent.retain(await installPreparedProjectLocalFiles(f.options));}
  catch(error){
    const primary=(error as Failure).primaryFailure;
    t.diagnostic(JSON.stringify({code:primary?.code,message:primary?.message,
      stack:primary?.stack?.split('\n').slice(1,7)}));throw error;
  }
  assert.strictEqual(f.preparation!.originalsForRuntime(moon),f.original);
  assert.equal(f.authorizationCalls(),1);
  const original=f.original.sources[0],bound=profile.fileReadDeclarations![0];
  assert.notStrictEqual(bound,original.declaration);
  const contents=(JSON.parse(original.wire) as Declaration).views.find(view=>view.resource==='contents');
  assert.equal(moon.clientProgramRowSourceFileReadProfile(original.declaration,contents!.source_ref),undefined);
  const descriptor=moon.clientProgramRowSourceFileReadProfile(bound,contents!.source_ref);
  assert.equal(JSON.parse(moon.strategyPublicationContractJson(descriptor)).response_encoding,'typed_json_row_array');
  const wire=profile.environmentWire!;
  const environment=moon.clientProgramCheckEnvironment(wire,JSON.parse(wire).evidence_bundle_cid,
    false,false,true,false,false,false,false);
  const program={version:'actql/0.1',id:'original-read-profile',stages:[{id:'capture',
    inputs:{files:{connector:'local',resource:'files',request:{paths:null,glob:null}},
      contents:{connector:'local',resource:'contents'}},
    steps:[{join:{left:'files',with:'contents',kind:'inner',
      on:[{left:'resource',right:'resource'},{left:'version',right:'version'}],
      select:{path:'left.path',content:'right.content'}},as:'captured'}],
    results:{out:{from:'captured',fields:['path','content']}}}],
    results:{out:{from:{stage:'capture',result:'out'}}}};
  const preparation=moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),'json',environment,undefined);
  const prepared=moon.clientProgramPreparationReady(preparation);
  assert.ok(prepared,'the original files/contents view remains checked');
  const keyed=checked(moon.clientProgramSelectSingleKeyedAcquisition(prepared));
  const capacity=profile.sources[0].keyedLedgerCapacity!(keyed);
  assert.equal(capacity.executionBytes,2n*BigInt(limits.maxFileBytes)+65536n+24n*BigInt(limits.maxPageBytes));
  assert.equal(capacity.transferBytes,BigInt(limits.maxReadBytes)+BigInt(limits.maxPages)*BigInt(limits.maxPageBytes));
});

test('combined Local Source and STORE initialization retain the same original connection binding',async t=>{
  const f=await installedReadProfileFixture(t);
  const source=f.parent.retain(await installPreparedProjectLocalFiles(f.options));
  let physical=0;
  const nativeFilesystem=Object.freeze({localFileWriteConstructionProfile(){
    return Object.freeze({nativeOriginalBytes:8192,maxRootBytes:4096,maxNameBytes:1024,
      maxDepth:130,writeQuantumBytes:65536});
  },...Object.fromEntries(['openFileRoot','openFileDirectory','openRootFileWriter',
    'fileRootCurrent','fileRootWrite','fileRootPublish','fileRootClose'].map(name=>
    [name,()=>{physical++;assert.fail('Initialization cannot perform a file operation');}]))});
  let effect;
  try{effect=f.parent.retain(await installPreparedProjectLocalFileEffects({
    ...f.options,principalId:'operator',runtimeBundleCid:cid({fixture:'same Local runtime'}),
    ledgerRoot:join(f.original.sources[0].rootPath,'unused-effect-ledger'),nativeFilesystem,
    effectResources:Object.freeze(Object.fromEntries(['bindRunOriginal','assertCurrent','limits'].map(name=>
      [name,()=>assert.fail('Initialization cannot use a Run resource')]))),
    sourceBindings:source.connectorBindings,installationServices:f.parent.services,sourceProfile:source,
  } as unknown as EffectInstall));}catch(error){t.diagnostic(JSON.stringify({primaryFailureCode:(error as Failure).primaryFailure?.code}));throw error;}
  const original=f.original.sources[0];
  const expected=cid({scope:original.scopeCid,declaration:original.wire,
    account_context:'sha256:'+'a'.repeat(64)});
  assert.equal(source.connectorBindings[0].bindingCid,expected);
  assert.equal((effect.queryStoreTargets[0] as {installationBindingCid: string}).installationBindingCid,expected);
  assert.equal(effect.effects.length,1);assert.equal(physical,0);
  const contents=(JSON.parse(original.wire) as Declaration).views.find(view=>view.resource==='contents');
  assert.ok(moon.clientProgramRowSourceFileReadProfile(source.fileReadDeclarations![0],contents!.source_ref),
    'the augmented read-execution declaration remains retained');
  const composed=composeInstalledSourceEnvironment(f.parent.services!,moon,f.options.baseEnvironmentWire,
    source.environmentWire,effect.environmentWire);
  const profileCid=JSON.parse(moon.strategyPublicationContractJson(
    moon.clientProgramRowSourceFileReadProfile(source.fileReadDeclarations![0],contents!.source_ref))).transport_cid;
  assert(JSON.parse(composed.wire).connector_capabilities.some((value: View)=>
    value.source_ref===contents!.source_ref&&value.capability_contract_cids.includes(profileCid)));
  assert.throws(()=>source.originalsForProjectEffects!.call({...source},moon,f.preparation),
    {code:'ForeignLocalFilesPreparation'});
  assert.throws(()=>source.originalsForProjectEffects!(moon,{...f.preparation}),
    {code:'ForeignLocalFilesPreparation'});
  assert.strictEqual(f.preparation!.originalsForRuntime(moon),f.original);
  let closing: Promise<void> | undefined;
  (f.options.sourceManaged as {assertCurrent(): unknown}).assertCurrent=()=>{closing??=source.close();};
  assert.throws(()=>source.originalsForProjectEffects!(moon,f.preparation),
    {code:'LocalFilesInstallationClosing'});
  await closing;
  assert.throws(()=>source.originalsForProjectEffects!(moon,f.preparation),
    {code:'LocalFilesInstallationClosing'});
});

test('public Local profile constructor refuses before projection on the original Source budget',async t=>{
  let projected=0;
  const f=await installedReadProfileFixture(t,real=>({prepareNativeInput<Result extends Extract<SynchronousRuntimeData, object>>(input: LoadInput<Result>){
    return real.prepareNativeInput(Object.freeze({capacity(){
      const policy=moon.clientLocalPreparationResourceLimits(moon.clientLocalResourcePolicyOriginal());
      const excessive=checked(moon.clientProgramInstalledSourceConstructionCapacity(1n,0n,0n,0n,0n,policy[5]));
      return checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(input.capacity(),[excessive]));
    },project(){projected++;return input.project();}}));
  }}));
  await assert.rejects(installPreparedProjectLocalFiles(f.options),(error: unknown)=>(error as Failure).primaryFailure?.code==='MoonBitHostFailure');
  assert.equal(projected,0);assert.equal(f.authorizationCalls(),0);
  assert.strictEqual(f.preparation!.originalsForRuntime(moon),f.original);
});

test('public Local profile construction observes original retirement before authorization or Source publication',async t=>{
  const primary=new Error('OriginalLocalSourceRetired');let retired=false,projected=0;
  const f=await installedReadProfileFixture(t,real=>({prepareNativeInput<Result extends Extract<SynchronousRuntimeData, object>>(input: LoadInput<Result>){
    return real.prepareNativeInput(Object.freeze({capacity:()=>input.capacity(),project(){
      projected++;const value=input.project();retired=true;return value;
    }}));
  }}));
  (f.options.sourceManaged as {assertCurrent(): unknown}).assertCurrent=()=>{if(retired)throw primary;};
  await assert.rejects(installPreparedProjectLocalFiles(f.options),(error: unknown)=>(error as Failure).primaryFailure===primary);
  assert.equal(projected,1);assert.equal(f.authorizationCalls(),0);
  assert.strictEqual(f.preparation!.originalsForRuntime(moon),f.original);
});
