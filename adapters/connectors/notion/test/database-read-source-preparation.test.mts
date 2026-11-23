import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';

import type {CommonCatalogBindings,NotionCatalogBindings,NotionMetadataBounds,NotionDeclarationBounds,CatalogDeclaredSource} from './catalog-bindings.fixture.mjs';

type Carrier = Readonly<{cid:string;body:Readonly<{fields:Readonly<{label:Readonly<{enum:readonly string[]}>}>}>}>;

const common:CommonCatalogBindings=await import(new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href);
const provider:NotionCatalogBindings=await import(new URL('../../../../_build/js/release/build/connectors/notion/host_node/host_node.js',import.meta.url).href);

const metadata:NotionMetadataBounds=[16384,1024,20,8,8,128,128],readLimits:NotionDeclarationBounds=[...metadata,256,16,4096,16,100000],limits:[number,number,number]=[65536,8192,32];
function declaredSource(enumeration:readonly string[]){
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{
    t:[{column:'label',projection:'value',contract:{type:'string',nullable:false,enum:enumeration,max_codepoints:16,max_utf8_bytes:64}}],
    n:[{column:'amount',projection:'value',contract:{type:'decimal',nullable:true,precision:20,scale:2}}]}})),...readLimits));
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]})),...metadata));
  const selection=checked(provider.notionSelectReadSource(declaration,database,100000));
  const source=checked(provider.notionProjectSelectedReadSource(selection,Buffer.from(JSON.stringify({object:'data_source',id:'s',
    parent:{type:'database_id',database_id:'db'},properties:{title:{id:'t',name:'title',type:'rich_text',rich_text:{}},
      number:{id:'n',name:'number',type:'number',number:{format:'number'}}}})),...metadata));
  const properties=checked(provider.notionBindSelectedReadContracts(selection,source,...readLimits));
  const contracts=checked(provider.notionSourceSystemReadContracts(properties,...readLimits));
  const snapshot=checked(provider.notionCaptureDatabaseReadSnapshot(selection,source,contracts,...limits));
  const specification=checked(provider.notionDatabaseReadSnapshotRelationSpecification(snapshot,'tasks',...limits)) as string;
  const relation=checked(common.clientProgramRowSourceRestoreRelationDeclaration('original-notion','notion','notion/0.1',specification,undefined));
  return JSON.parse(common.clientProgramRowSourceDeclarationJson(relation)) as CatalogDeclaredSource;
}

// These are actual portable Source/check preparations using original saved
// contracts and the existing fixture Host policy. They issue no acquisition,
// grant, Ledger, physical I/O, installation/currentness or numerical profile.
for(const [name,enumeration] of [['ASCII',['plain','plain','other']],['exact Unicode',['é😀\r\n','é😀\r\n','other']]] as const){
  test('actual database Source '+name+' enum survives installed Check Environment and SQL/AQL preparation',()=>{
    const declared=declaredSource(enumeration);
    const base=readFileSync(new URL('../../../../spec/local-check-environment.json',import.meta.url),'utf8');
    const environment=rowSourceCheckEnvironment(base,declared);
    const check=common.clientProgramCheckEnvironment(environment.wire,environment.evidenceCid,false,false,true,false,false,false,false);
    assert.ok(check,'Common must admit the original complete database environment');
    const actual=JSON.parse(environment.wire) as {contract_registry:readonly Carrier[]},view=declared.views[0];
    const originalCarrier=declared.contracts.map(JSON.parse as (wire:string)=>Carrier).find(value=>value.cid===view.carrier_schema_cid);
    const restoredCarrier=actual.contract_registry.find(value=>value.cid===view.carrier_schema_cid);
    assert.deepEqual(restoredCarrier,originalCarrier);
    assert.deepEqual(restoredCarrier!.body.fields.label.enum,enumeration);
    const publication=JSON.stringify({environmentCid:environment.evidenceCid,aliases:[{name:'notion.tasks',
      sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:view.carrier_schema_cid}]});
    for(const [format,text] of [['sql','SELECT id, label, amount FROM notion.tasks'],['aql','FROM notion.tasks |> SELECT id, label, amount']]){
      const preparation=common.clientProgramPrepareSourceWithParameters(text,format,check,publication,undefined,undefined);
      assert.ok(common.clientProgramPreparationReady(preparation),format+': '+common.clientProgramPreparationIssueCode(preparation));
    }
  });
}
