import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

const limits=[65536,8192,32];
const hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');
const readLimits=[16384,1024,20,8,8,128,128,256,16,4096,16,100000];

// The metadata fixture has actual Common/Account/Credential/SQLite/local TLS
// with explicit private issuer/material and response-ticket doubles. Restoring
// a declaration here is DATA admission, not a normal installed reader or grant.
test('actual saved database schema enters the existing Common row-source declaration without rediscovery',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader({systemColumns:true}),observed=await reader.read(),p=x.provider;
    const snapshot=checked(p.notionCaptureDatabaseReadSnapshot(observed.selection,observed.source,observed.readContracts,...limits));
    const specification=checked(p.notionDatabaseReadSnapshotRelationSpecification(snapshot,'tasks',...limits));
    const restore=expected=>checked(common.clientProgramRowSourceRestoreRelationDeclaration(
      'original-notion','notion','notion/0.1',specification,expected));
    const declaration=restore(undefined);
    const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
    const repeated=JSON.parse(common.clientProgramRowSourceDeclarationJson(restore(declared.catalog_cid)));
    assert.deepEqual(repeated,declared);
    assert.equal(declared.views.length,1);assert.equal(declared.views[0].resource,'tasks');
    const originalSchema=JSON.parse(observed.schemaWire);
    const view=JSON.parse(specification).views[0];
    assert.deepEqual(JSON.parse(view.schema_wire),originalSchema.fields);
    assert.equal(view.schema_cid,hash(view.schema_wire));
    assert.notEqual(view.schema_cid,hash(observed.schemaWire));
    const carrier=declared.contracts.map(JSON.parse).find(value=>value.cid===declared.views[0].carrier_schema_cid);
    assert.deepEqual(carrier.body.fields,originalSchema.fields);
    assert.equal(Object.hasOwn(view,'facts_wire'),false);
    assert.equal(Object.hasOwn(view,'acquisition_wire'),false);
    assert.throws(()=>restore('sha256:'+'0'.repeat(64)));
    assert.equal(f.state.requests.length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
    assert.equal(checked(p.notionDatabaseReadSnapshotWire(snapshot)).length>0,true);
  });
});

test('restored original enum and Decimal contracts survive Common Relation admission without key facts',()=>{
  const text={type:'string',nullable:false,enum:['é😀','é😀','z'],max_codepoints:8,max_utf8_bytes:32};
  const decimal={type:'decimal',nullable:true,precision:20,scale:2};
  const original=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{
    t:[{column:'label',projection:'value',contract:text}],n:[{column:'amount',projection:'value',contract:decimal}]}})),...readLimits));
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:'db',
    data_sources:[{id:'s',name:'tasks'}]})),...readLimits.slice(0,7)));
  const selection=checked(provider.notionSelectReadSource(original,database,readLimits.at(-1)));
  const source=checked(provider.notionProjectSelectedReadSource(selection,Buffer.from(JSON.stringify({object:'data_source',id:'s',
    parent:{type:'database_id',database_id:'db'},properties:{title:{id:'t',name:'title',type:'rich_text',rich_text:{}},
      number:{id:'n',name:'number',type:'number',number:{format:'number'}}}})),...readLimits.slice(0,7)));
  const properties=checked(provider.notionBindSelectedReadContracts(selection,source,...readLimits));
  const propertySnapshot=checked(provider.notionCaptureDatabaseReadSnapshot(selection,source,properties,...limits));
  assert.throws(()=>checked(provider.notionDatabaseReadSnapshotRelationSpecification(propertySnapshot,'tasks',...limits)));
  const full=checked(provider.notionSourceSystemReadContracts(properties,...readLimits));
  const snapshot=checked(provider.notionCaptureDatabaseReadSnapshot(selection,source,full,...limits));
  const saved=checked(provider.notionDatabaseReadSnapshotWire(snapshot));
  const restored=checked(provider.notionReadDatabaseReadSnapshot(Buffer.from(saved),hash(saved),...readLimits,...limits));
  const spec=checked(provider.notionDatabaseReadSnapshotRelationSpecification(restored,'tasks',...limits));
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('original-notion','notion','notion/0.1',spec,undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const carrier=declared.contracts.map(JSON.parse).find(value=>value.cid===declared.views[0].carrier_schema_cid);
  assert.deepEqual(carrier.body.fields.label,text);
  assert.deepEqual(carrier.body.fields.amount,decimal);
  assert.deepEqual(Object.keys(carrier.body.fields).sort(),['amount','created_by','created_time','id','label','last_edited_by','last_edited_time','resource','url','version']);
  assert.equal(Object.hasOwn(JSON.parse(spec).views[0],'facts_wire'),false);
  assert.equal(checked(provider.notionDatabaseReadSnapshotWire(restored)),saved);
});
