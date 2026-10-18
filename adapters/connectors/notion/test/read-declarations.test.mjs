import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';

const metadata=[16384,2048,24,8,8,128,128];
const limits=[...metadata,256,16,4096,16,100000];
const hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');
const read=(wire,{work=100000,count=8}={})=>checked(provider.notionReadDatabaseDeclarations(
  Buffer.isBuffer(wire)?wire:Buffer.from(wire),...limits.slice(0,-1),work,count));
const entry=(inventory,index)=>checked(provider.notionDatabaseReadDeclarationsAt(inventory,index));

test('actual typed public map retains original value bytes and exact Unicode without caller-buffer aliases',()=>{
  const vectors=JSON.parse(readFileSync(new URL('../../../../spec/contracts/fixtures/notion-read-declarations-vectors.json',import.meta.url),'utf8')).vectors;
  for(const vector of vectors){
    const mutable=Buffer.from(vector.source),inventory=read(mutable);
    mutable.fill(0);
    assert.equal(checked(provider.notionDatabaseReadDeclarationsCount(inventory)),vector.entries.length);
    assert.equal(checked(provider.notionDatabaseReadDeclarationsSourceCid(inventory)),vector.sourceCid);
    for(const[index,expected]of vector.entries.entries()){
      const declaration=entry(inventory,index);
      assert.equal(checked(provider.notionDatabaseReadDeclarationsAliasAt(inventory,index)),expected.alias);
      assert.equal(checked(provider.notionDatabaseReadDeclarationOriginalJson(declaration,16384)),expected.source);
      assert.equal(provider.notionReadDatabaseDeclarationSourceCid(declaration),expected.sourceCid);
      assert.equal(provider.notionDatabaseReadDeclarationsMatches(inventory,index,declaration),true);
      assert.equal(provider.notionDatabaseReadDeclarationsMatches(read(vector.source),index,declaration),false);
    }
    assert.throws(()=>entry(inventory,vector.entries.length),{code:'MoonBitHostFailure'});
  }
  // An untyped bare JS object is outside this private typed FFI contract.
  // Nominal copies of the actual Moon type are independently rejected by the owner WB.
  assert.throws(()=>checked(provider.notionDatabaseReadDeclarationsCount(Object.freeze({}))),TypeError);
});

function snapshot(declaration,databaseId,sourceId,properties){
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:databaseId,
    data_sources:[{id:sourceId,name:'same display name'}]})),...metadata));
  const selection=checked(provider.notionSelectReadSource(declaration,database,100000));
  const source=checked(provider.notionProjectSelectedReadSource(selection,Buffer.from(JSON.stringify({object:'data_source',id:sourceId,
    parent:{type:'database_id',database_id:databaseId},properties})),...metadata));
  const original=checked(provider.notionBindSelectedReadContracts(selection,source,...limits));
  const complete=checked(provider.notionSourceSystemReadContracts(original,...limits));
  return checked(provider.notionCaptureDatabaseReadSnapshot(selection,source,complete,65536,8192,32));
}

test('public task/account aliases feed original snapshots and actual Common Source preparation',()=>{
  // Explicit Catalog response DATA, not an installed Site/metadata issuer or full workspace coverage.
  const declaration='{\r\n "id":"db", "data_source_id":"s", "unique":"external_id", "marker":"actql_request",'+
    '"read_contracts":{"n":[{"column":"amount","projection":"value","contract":{"type":"decimal","nullable":false,"precision":20,"scale":2}}]}}';
  const wire='{"tasks":'+declaration+',"accounts":"db2"}',inventory=read(wire,{count:2});
  const aliases=[0,1].map(index=>checked(provider.notionDatabaseReadDeclarationsAliasAt(inventory,index)));
  const snapshots=[snapshot(entry(inventory,0),'db','s',{
    title:{id:'t',name:'title',type:'rich_text',rich_text:{}},amount:{id:'n',name:'amount',type:'number',number:{format:'number'}}}),
  snapshot(entry(inventory,1),'db2','s2',{title:{id:'t2',name:'title',type:'rich_text',rich_text:{}}})];
  assert.equal(checked(provider.notionDatabaseReadDeclarationOriginalJson(entry(inventory,0),16384)),declaration);
  assert.equal(checked(provider.notionDatabaseReadDeclarationsSourceCid(inventory)),hash(wire));
  const specification=checked(provider.notionDatabaseReadSnapshotsRelationSpecification(aliases,snapshots,131072,16384,32,2,1000));
  const original=checked(common.clientProgramRowSourceRestoreRelationDeclaration('original-public-map','notion','notion/0.1',specification,undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(original));
  const environment=rowSourceCheckEnvironment(readFileSync(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8'),declared);
  const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);assert.ok(check);
  const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:declared.views.map(view=>({
    name:'notion.'+view.resource,sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}))});
  for(const[format,text]of[['sql','SELECT id, title, amount FROM notion.tasks'],['aql','FROM notion.accounts |> SELECT id, title']]){
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    assert.ok(common.clientProgramPreparationReady(outcome),common.clientProgramPreparationIssueCode(outcome));
  }
  const saved=JSON.parse(checked(provider.notionDatabaseReadSnapshotWire(snapshots[0])));
  assert.equal(saved.declaration_source,declaration);
  assert.match(saved.schema_wire,/"precision":20/);
  assert.match(saved.schema_wire,/"scale":2/);
});

test('typed map rejects unused invalid declarations and preserves exact aggregate refusal',()=>{
  for(const wire of ['{"tasks":"db","unused":{"id":"db2","marker":null}}',
    '{"tasks":"db","tasks":"db2"}','{"tasks":"db","\\u0074asks":"db2"}',
    '{"":"db"}','{"tasks":"db","unused":{"id":"db2","read_contracts":null}}']){
    assert.throws(()=>read(wire),{code:'MoonBitHostFailure'});
  }
  const wire='{"a":"db","b":"db2"}',work=Buffer.byteLength(wire)+2+2+4+5;
  assert.equal(checked(provider.notionDatabaseReadDeclarationsCount(read(wire,{work,count:2}))),2);
  assert.throws(()=>read(wire,{work:work-1,count:2}),{code:'MoonBitHostFailure'});
  assert.throws(()=>read(wire,{work,count:1}),{code:'MoonBitHostFailure'});
});
