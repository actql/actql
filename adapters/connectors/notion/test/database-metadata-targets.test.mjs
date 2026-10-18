import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareNotionDatabaseMetadataTargets} from '../host/database-metadata-targets.mjs';
import {NOTION_DATABASE_RETRIEVE_OPERATION as databaseOperation,NOTION_DATA_SOURCE_RETRIEVE_OPERATION as sourceOperation}
  from '../site/database-discovery.mjs';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

const metadata=[16384,1024,20,8,8,128,128],bounds=[...metadata,256,16,4096,16,100000];
const origin='https://notion.test';
function originals(id='db',sourceId='s'){
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify(id)),...bounds));
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id,data_sources:[{id:sourceId,name:'tasks'}]})),...metadata));
  const selection=checked(provider.notionSelectReadSource(declaration,database,bounds.at(-1)));
  const selected={selection,declaration,database,operation:sourceOperation,origin,method:'GET',
    path:'/v1/data_sources/'+encodeURIComponent(sourceId),bodyBytes:0};
  const options={moon:provider,declaration,origin,resource:'tasks',maxTargetBytes:1024,maxResourceBytes:128};
  return{declaration,database,selection,selected,options};
}

test('metadata targets preserve original declaration then exact selected occurrence and request encoding',()=>{
  const f=originals('d/é😀','s%2Fx? #'),targets=prepareNotionDatabaseMetadataTargets(f.options);
  assert.equal(targets.databaseTarget,f.declaration);
  assert.deepEqual(targets.targetAuthority.project(targets.databaseTarget,f.declaration),{
    resource:'tasks',operation:databaseOperation,origin,method:'GET',path:'/v1/databases/d%2Fe%CC%81%F0%9F%98%80',bodyBytes:0});
  assert.throws(()=>targets.targetAuthority.project(f.selection,f.declaration),{code:'ForeignNotionMetadataTarget'});
  const selected=targets.selectSource(Object.freeze(f.selected));assert.equal(selected,f.selection);
  assert.deepEqual(targets.targetAuthority.project(selected,f.declaration),{
    resource:'tasks',operation:sourceOperation,origin,method:'GET',path:'/v1/data_sources/s%252Fx%3F%20%23',bodyBytes:0});
  assert.throws(()=>targets.selectSource(f.selected),{code:'NotionMetadataSourceAlreadySelected'});
});

test('metadata targets reject foreign originals receiver path purpose and selection substitutions',()=>{
  const f=originals(),foreign=originals(),targets=prepareNotionDatabaseMetadataTargets(f.options);
  assert.throws(()=>targets.targetAuthority.project(foreign.declaration,f.declaration),{code:'ForeignNotionMetadataTarget'});
  assert.throws(()=>targets.targetAuthority.project(f.declaration,foreign.declaration),{code:'ForeignNotionMetadataTarget'});
  assert.throws(()=>targets.targetAuthority.project.call({},f.declaration,f.declaration),{code:'ForeignNotionMetadataTarget'});
  for(const change of [{declaration:foreign.declaration},{database:foreign.database},{operation:databaseOperation},
    {origin:'https://other.test'},{method:'POST'},{bodyBytes:1},{path:'/v1/data_sources/other'},{extra:true}]){
    assert.throws(()=>targets.selectSource({...f.selected,...change}));
  }
  const getter={...f.selected};Object.defineProperty(getter,'selection',{enumerable:true,get(){assert.fail('selection getter must not run');}});
  assert.throws(()=>targets.selectSource(getter),{code:'InvalidNotionMetadataSelection'});
  assert.throws(()=>targets.selectSource.call({},f.selected),{code:'ForeignNotionMetadataTargets'});
  targets.selectSource(f.selected);
  assert.throws(()=>targets.targetAuthority.project(foreign.selection,f.declaration),{code:'ForeignNotionMetadataTarget'});
});

test('metadata target bounds and captured provider receiver cannot be replaced by later getters',()=>{
  const f=originals();let calls=0;
  const moon=Object.fromEntries(['notionReadDatabaseId','notionReadSourceSelectionMatches','notionReadSourceSelectionId'].map(name=>
    [name,function(...args){assert.equal(this,moon);calls++;return Reflect.apply(provider[name],provider,args);} ]));
  const targets=prepareNotionDatabaseMetadataTargets({...f.options,moon});
  for(const name of Object.keys(moon))Object.defineProperty(moon,name,{get(){assert.fail('provider getter reread');}});
  targets.selectSource(f.selected);targets.targetAuthority.project(f.selection,f.declaration);assert(calls>=4);
  for(const change of [{origin:'http://notion.test'},{origin:'https://notion.test/path'},{origin:'https://user@notion.test'},
    {resource:''},{maxTargetBytes:0},{maxResourceBytes:4}])assert.throws(()=>prepareNotionDatabaseMetadataTargets({...f.options,...change}));
  const bounded=originals('bounded-database-id'),exact='/v1/databases/bounded-database-id'.length;
  assert.equal(prepareNotionDatabaseMetadataTargets({...bounded.options,maxTargetBytes:exact}).targetAuthority.project(bounded.declaration,bounded.declaration).path.length,exact);
  assert.throws(()=>prepareNotionDatabaseMetadataTargets({...bounded.options,maxTargetBytes:exact-1}),{code:'NotionMetadataTargetLimit'});
});

test('actual Host metadata discovery selects the same target only after the original database response',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    const targets=prepareNotionDatabaseMetadataTargets({moon:x.provider,declaration:x.declaration,origin:x.origin,
      resource:'database:db',maxTargetBytes:1024,maxResourceBytes:128});
    assert.equal(targets.targetAuthority.project(targets.databaseTarget,x.declaration).operation,databaseOperation);
    let calls=0;
    const reader=x.reader({sourceAuthorizationFor:async selected=>{
      assert.equal(f.state.requests.length,1);calls++;
      const target=targets.selectSource(selected),facts=targets.targetAuthority.project(target,x.declaration);
      assert.equal(facts.path,selected.path);assert.equal(facts.operation,sourceOperation);
      return x.options.sourceAuthorizationFor(selected);
    }});
    const result=await reader.read();assert.equal(calls,1);assert.equal(f.state.requests.length,2);
    assert.equal(result.declaration,x.declaration);assert.equal(reader.observe().cleanupConfirmed,false);
  });
});
