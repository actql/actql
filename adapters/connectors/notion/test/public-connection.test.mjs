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
const read=(wire,{work=100000,count=8,reference=512}={})=>checked(provider.notionReadPublicConnection(
  Buffer.isBuffer(wire)?wire:Buffer.from(wire),...limits.slice(0,-1),work,count,reference));
const map=value=>checked(provider.notionPublicConnectionDatabases(value));
const entry=(value,index)=>checked(provider.notionDatabaseReadDeclarationsAt(value,index));
const hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');

test('actual public connection keeps original reference and nested span identities after caller-buffer mutation',()=>{
  const vectors=JSON.parse(readFileSync(new URL('../../../../spec/contracts/fixtures/notion-public-connection-vectors.json',import.meta.url),'utf8')).vectors;
  for(const vector of vectors){
    const buffer=Buffer.from(vector.source),original=read(buffer);buffer.fill(0);
    assert.equal(checked(provider.notionPublicConnectionOriginalJson(original,16384)),vector.source);
    assert.equal(checked(provider.notionPublicConnectionSourceCid(original)),vector.sourceCid);
    assert.equal(checked(provider.notionPublicConnectionCredentialKind(original)),vector.credentialKind);
    assert.equal(checked(provider.notionPublicConnectionCredentialReference(original)),vector.credentialReference);
    assert.equal(checked(provider.notionPublicConnectionHasDatabases(original)),vector.databases!==null);
    if(vector.databases===null){assert.throws(()=>map(original),{code:'MoonBitHostFailure'});continue;}
    const databases=map(original);
    assert.equal(checked(provider.notionDatabaseReadDeclarationsSourceCid(databases)),vector.databases.sourceCid);
    assert.equal(checked(provider.notionDatabaseReadDeclarationsCount(databases)),vector.databases.entries.length);
    for(const[index,expected]of vector.databases.entries.entries()){
      const declaration=entry(databases,index);
      assert.equal(checked(provider.notionDatabaseReadDeclarationOriginalJson(declaration,16384)),expected.source);
      assert.equal(provider.notionReadDatabaseDeclarationSourceCid(declaration),expected.sourceCid);
      assert.equal(provider.notionDatabaseReadDeclarationsMatches(databases,index,declaration),true);
      assert.equal(provider.notionDatabaseReadDeclarationsMatches(map(read(vector.source)),index,declaration),false);
    }
    assert.throws(()=>checked(provider.notionPublicConnectionOriginalJson(original,Buffer.byteLength(vector.source)-1)),{code:'MoonBitHostFailure'});
  }
});

function snapshot(declaration,databaseId,sourceId){
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:databaseId,
    data_sources:[{id:sourceId,name:'same name'}]})),...metadata));
  const selected=checked(provider.notionSelectReadSource(declaration,database,100000));
  const source=checked(provider.notionProjectSelectedReadSource(selected,Buffer.from(JSON.stringify({
    object:'data_source',id:sourceId,parent:{type:'database_id',database_id:databaseId},
    properties:{title:{id:'t',name:'title',type:'rich_text',rich_text:{}}}})),...metadata));
  const contracts=checked(provider.notionBindSelectedReadContracts(selected,source,...limits));
  const complete=checked(provider.notionSourceSystemReadContracts(contracts,...limits));
  return checked(provider.notionCaptureDatabaseReadSnapshot(selected,source,complete,65536,8192,32));
}

test('the documented public connection retains task/account declarations through actual Common Source preparation',()=>{
  // Explicit metadata DATA, not an installed issuer, metadata read or page inventory.
  const originalDeclaration='{\r\n "id":"db", "unique":"external_id", "marker":"actql_request"\r\n}';
  const databases='{"tasks":'+originalDeclaration+',"accounts":"db2"}';
  const wire='{"connector":"notion","databases":'+databases+',"credentials":{"integration_token":{"env":"NOTION_TOKEN"}}}';
  const original=read(wire),declarations=map(original);
  const aliases=[0,1].map(index=>checked(provider.notionDatabaseReadDeclarationsAliasAt(declarations,index)));
  const snapshots=[snapshot(entry(declarations,0),'db','s'),snapshot(entry(declarations,1),'db2','s2')];
  assert.equal(checked(provider.notionPublicConnectionCredentialReference(original)),'NOTION_TOKEN');
  assert.equal(checked(provider.notionPublicConnectionSourceCid(original)),hash(wire));
  assert.equal(checked(provider.notionDatabaseReadDeclarationsSourceCid(declarations)),hash(databases));
  assert.equal(checked(provider.notionDatabaseReadDeclarationOriginalJson(entry(declarations,0),16384)),originalDeclaration);
  const specification=checked(provider.notionDatabaseReadSnapshotsRelationSpecification(aliases,snapshots,131072,16384,32,2,1000));
  const declaration=checked(common.clientProgramRowSourceRestoreRelationDeclaration('public-notion-connection','notion','notion/0.1',specification,undefined));
  const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(readFileSync(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8'),declared);
  const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);assert.ok(check);
  const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:declared.views.map(view=>({
    name:'notion.'+view.resource,sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}))});
  for(const[format,text]of[['sql','SELECT id, title FROM notion.tasks'],['aql','FROM notion.accounts |> SELECT id, title']]){
    const outcome=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
    assert.ok(common.clientProgramPreparationReady(outcome),common.clientProgramPreparationIssueCode(outcome));
  }
});

test('public connection refuses malformed references unused declarations and exact work exhaustion',()=>{
  for(const wire of ['{"connector":"notion","credentials":{"integration_token":"inline-secret"}}',
    '{"connector":"notion","credentials":{"integration_token":{"env":"N","path":"file"}}}',
    '{"connector":"notion","credentials":{"integration_token":{"env":"N\\u0000X"}}}',
    '{"connector":"notion","databases":{"tasks":"db","unused":{"id":"db2","marker":null}},"credentials":{"integration_token":{"env":"N"}}}']){
    assert.throws(()=>read(wire),{code:'MoonBitHostFailure'});
  }
  const databases='{"a":"db"}',wire='{"connector":"notion","databases":'+databases+',"credentials":{"integration_token":{"env":"N"}}}';
  const work=Buffer.byteLength(wire)+2+Buffer.byteLength(databases)+2+4;
  assert.equal(checked(provider.notionDatabaseReadDeclarationsCount(map(read(wire,{work,count:1,reference:1})))),1);
  assert.throws(()=>read(wire,{work:work-1,count:1,reference:1}),{code:'MoonBitHostFailure'});
  assert.throws(()=>read(wire,{work,count:0,reference:1}),{code:'MoonBitHostFailure'});
});
