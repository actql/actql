import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {canonical,fileListingDeclaration,item} from './fixtures/file-listing-source.fixture.mjs';

assert(process.env.ACTQL_TEST_FILE_LISTING_RUNTIME,'Select the matching native-metadata Common runtime');
const moon=await import(process.env.ACTQL_TEST_FILE_LISTING_RUNTIME);
const read=path=>readFile(new URL('../../'+path,import.meta.url),'utf8');
const nativeSchema={
  resource:{type:'resource_ref',resource_kind:'file',nullable:false},
  version:{type:'string',nullable:false},name:{type:'string',nullable:false},
  path:{type:'string',nullable:false},media_type:{type:'string',nullable:true},
  size_bytes:{type:'number',nullable:true},modified_at:{type:'timestamp',nullable:true},
  size:{type:'int64',nullable:false},modified_time:{type:'timestamp',nullable:false},
};
const nativeRow={...item('d','a.csv'),size:'9007199254740993',
  size_bytes:null,modified_time:'2026-10-20T00:00:00.000000001Z',
  modified_at:'2026-10-20T00:00:00.000000001Z'};

async function fixture(t,empty=false){
  const base=(await read('spec/local-check-environment.json')).trimEnd();
  const value=fileListingDeclaration(moon,base,{schema:nativeSchema});
  const environment=moon.clientProgramCheckEnvironment(value.environment.wire,
    value.environment.evidenceCid,false,false,true,false,false,false,false);
  assert(environment,'the actual complete nine-field Catalog is admitted');
  const publication=sourceAliasPublication(moon,environment,value.aliases);
  const prepare=installNodeClientProgramPreparation({moon,environment,sourcePublication:publication});
  const text=empty?'SELECT * FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[])':
    'SELECT * FROM LIST_FILES(docs.invoices, paths => [\'a.csv\'])';
  const prepared=await prepare({kind:'aql',input:{text,format:'sql'},parameters:null});
  prepare.assertOwned(prepared);
  const aoa=JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const registry=await read('spec/dependencies/aoa-pipeline-registry.json');
  const values=JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const contracts=checked(moon.clientPrepareInstalledSequenceContracts(registry,values,fragment,ordered));
  const requirement=checked(moon.clientProgramPrepareLocalQueryRequirement(prepared,0,0,
    contracts,values,fragment,ordered));
  const acquisition=checked(moon.clientProgramRowSourcePrepareAcquisition(value.declaration,
    requirement,await read('spec/contracts/actql-query-acquisition.json'),
    await read('spec/contracts/actql-query-process-evidence.json')));
  // Protocol/typed-capture diagnostic, not an operational or funded Host.
  const run=checked(moon.clientProgramRowSourceStart(acquisition,'native-metadata',()=>true));
  t.after(()=>moon.clientProgramRowSourceClose(run));
  checked(moon.clientProgramRowSourceBegin(run,8192,9,3,value.issuer));
  const listing=rowListingCallbacks({moon,run,currentRead:async()=>{}});
  const consume=async rows=>{
    await listing.beginRequest(undefined);
    const body=Buffer.from(JSON.stringify({items:rows,request_token:null,next_token:null}));
    const charge=checked(moon.clientProgramRowSourceChargePage(run,body));
    return listing.consumePage(body,{charge});
  };
  return{...value,base,environment,publication,prepared,requirement,acquisition,run,consume};
}

test('native listing capture binds the same checked task and logical Source input',async t=>{
  const f=await fixture(t);
  assert.equal(await f.consume([nativeRow]),1);
  checked(moon.clientProgramRowSourceFinish(f.run));
  const captured=checked(moon.clientProgramRowSourceCapture(f.run));
  const source=checked(moon.clientProgramRowSourceCaptureSource(captured));
  assert.equal(moon.clientProgramCapturedTaskSourceMatches(f.prepared,source,0),true);
  const identity=checked(moon.clientProgramIdentifyCapturedSourceRelation(source));
  const logical=checked(moon.clientProgramIssueCapturedTaskSourceLogical(
    f.prepared,source,identity,f.requirement,0));
  assert.notEqual(logical,undefined);
});

for(const empty of [false,true])test(`native listing ${empty?'empty schema':'full typed row'} survives original capture and restore`,async t=>{
  const f=await fixture(t,empty);
  if(!empty)assert.equal(await f.consume([nativeRow]),1);
  assert.equal(moon.clientProgramRowSourceListingComplete(f.run),true);
  checked(moon.clientProgramRowSourceFinish(f.run));
  const capture=checked(moon.clientProgramRowSourceCapture(f.run));
  const source=checked(moon.clientProgramRowSourceCaptureSource(capture));
  const binding='original-native-listing/run/task0/input0/attempt1';
  const exported=checked(moon.clientProgramExportSourceCapture(source,f.requirement,binding));
  const rows=moon.clientProgramSourceCaptureExportRows(exported);
  assert.deepEqual(rows.map(JSON.parse),empty?[]:[nativeRow]);
  const descriptor=moon.clientProgramSourceCaptureExportDescriptor(exported);
  const savedRequirement=moon.clientProgramSourceCaptureExportRequirement(exported);
  const capacity=moon.clientProgramInstalledRowCaptureCapacity(f.acquisition);
  const restore=(changes={})=>checked(moon.clientProgramRestoreSourceCapture(f.requirement,
    changes.requirement??savedRequirement,changes.binding??binding,binding,descriptor,
    changes.rows??rows,undefined,capacity,changes.custody??(()=>true),changes.issuer??f.issuer));
  assert.throws(()=>restore({binding:binding+'/foreign'}),{code:'MoonBitHostFailure'});
  assert.throws(()=>restore({requirement:'sha256:'+'f'.repeat(64)}),{code:'MoonBitHostFailure'});
  assert.throws(()=>restore({custody:()=>false}),{code:'MoonBitHostFailure'});
  if(!empty){
    assert.throws(()=>restore({rows:[canonical({...nativeRow,size:'9007199254740992'})]}),
      {code:'MoonBitHostFailure'});
    const denied=moon.clientProgramResourceReferenceIssuer(()=>false,()=>false);
    assert.throws(()=>restore({issuer:denied}),{code:'MoonBitHostFailure'});
  }
  const restored=restore();
  try{
    const again=checked(moon.clientProgramExportSourceCapture(
      moon.clientProgramSourceCaptureSource(restored),f.requirement,binding));
    assert.deepEqual(moon.clientProgramSourceCaptureExportRows(again),rows);
    assert.equal(moon.clientProgramSourceCaptureExportDescriptor(again),descriptor);
  }finally{assert.equal(moon.clientProgramCloseSourceCapture(restored),true);}
  const legacy=fileListingDeclaration(moon,f.base);
  assert.notEqual(legacy.declared.views[0].carrier_schema_cid,
    f.declared.views[0].carrier_schema_cid,'the complete schema has its own identity');
  assert.equal(Object.keys(nativeRow).length,9);
});

test('native listing rejects undeclared missing null wrong-domain and wrong-schema data',async t=>{
  for(const changed of [
    {...nativeRow,size:9007199254740992}, {...nativeRow,size:null},
    Object.fromEntries(Object.entries(nativeRow).filter(([key])=>key!=='size')),
    {...nativeRow,path:null}, {...nativeRow,modified_time:'invalid'},
    {...nativeRow,undeclared:true},
  ]){
    const f=await fixture(t);
    await assert.rejects(f.consume([changed]),{code:'MoonBitHostFailure'});
    assert.throws(()=>checked(moon.clientProgramRowSourceFinish(f.run)),{code:'MoonBitHostFailure'});
  }
  const f=await fixture(t);
  const wrong=f.aliases.map(alias=>({...alias,schemaContractCid:'sha256:'+'f'.repeat(64)}));
  assert.throws(()=>sourceAliasPublication(moon,f.environment,wrong),
    {message:'InvalidPublicSourcePublication'});
});
