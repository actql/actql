import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createNotionDatabaseDiscovery,NOTION_DATABASE_RETRIEVE_OPERATION as databaseOperation,
  NOTION_DATA_SOURCE_RETRIEVE_OPERATION as sourceOperation} from '../site/database-discovery.mjs';
import {createNotionDataSourceReader,NOTION_DATA_SOURCE_READ_OPERATION as queryOperation} from '../site/data-source-read.mjs';
import {NOTION_PROPERTY_READ_OPERATION as propertyOperation} from '../site/property-item-read.mjs';
import {propertyReadFixture,propertyItemPage} from './property-item-read.fixture.mjs';

const metadata=[16384,1024,20,8,8,128,128];
const declarationBounds=[...metadata,256,16,4096,16,100000];
const limits={maxResponseBytes:16384,maxTotalResponseBytes:32768,maxTargetBytes:1024,
  maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:8,maxIdentityBytes:128,maxNameBytes:128,
  maxContractNodes:256,maxContractDepth:16,maxContractTextBytes:4096,maxColumns:16,maxWork:100000,
  maxWireBytes:8192,maxWireNodes:256,maxWireDepth:16};
const definition={id:'t%3Ax',name:'text',type:'rich_text',rich_text:{}};
const database=ids=>({object:'database',id:'db',data_sources:ids.map(id=>({id,name:'same name'}))});
const schema=()=>({object:'data_source',id:'s',parent:{type:'database_id',database_id:'db'},properties:{text:definition}});

async function fixture(t,{decl={id:'db',read_contracts:{'t%3Ax':[{column:'text',projection:'value',
  contract:{type:'string',nullable:false,enum:['ab']}}]}},ids=['s']}={}){
  const f=await propertyReadFixture(t,{additionalOperations:[databaseOperation,sourceOperation,queryOperation]});
  f.state.respond=request=>request.url==='/v1/databases/db'?database(ids):schema();
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify(decl)),...declarationBounds));
  const options={moon:provider,declaration,initialAuthorization:f.authorize(databaseOperation,'initial-database'),
    sourceAuthorization:f.authorize(sourceOperation,'initial-source'),credential:f.options.credential,
    authorizationFor:({operation,index})=>f.authorize(operation,`discovery-${index}`),current:f.current,
    chargeResponse:f.options.chargeResponse,consumeObservation:f.options.consumeObservation,limits};
  return{...f,declaration,discoveryOptions:options,discover:changes=>createNotionDatabaseDiscovery({...options,...changes})};
}

test('actual Notion discovery passes the same original declaration and schema into typed query and property reads',async t=>{
  const f=await fixture(t),handle=f.discover(),original=await handle.read();
  assert.equal(original.declaration,f.declaration);
  assert.equal(provider.notionDataSourceReadMatches(original.readContracts,f.declaration,original.source),true);
  assert.equal(provider.notionDataSourceMatchesDatabase(original.source,original.database),true);
  assert.deepEqual(f.state.requests.map(x=>[x.method,x.path]),[['GET','/v1/databases/db'],['GET','/v1/data_sources/s']]);
  assert.deepEqual(original.responseCharges,f.state.charges);assert.equal(f.state.observations.length,2);
  assert.match(original.schemaWire,/"enum":\["ab"\]/u);
  let properties=0;f.state.respond=request=>request.method==='POST'?{object:'list',type:'page_or_data_source',page_or_data_source:{},
    results:[{object:'page',id:'page',parent:{type:'data_source_id',data_source_id:'s'},
      properties:{text:{...definition,rich_text:[],has_more:true}}}],has_more:false,next_cursor:null}:
    propertyItemPage(properties++===0?['a']:['b'],properties===1?'next':null);
  const rows=[],l={...limits,maxPages:8,pageSize:10,maxTotalRows:100,maxRequestBytes:1024,
    maxCursorBytes:128,maxRowNodes:128,maxRowDepth:16,maxRowTextBytes:4096,maxRowWork:100000,maxPageWork:100000,
    maxRowsWireBytes:8192,maxRowsWireNodes:256,maxRowsWireDepth:16,maxPropertyPages:8,maxPropertyItems:128,
    maxPropertyBytes:65536,maxPropertyNodes:4096,maxPropertyTextBytes:32768,maxPropertyWork:1000000};
  const read=createNotionDataSourceReader({moon:provider,...original,
    initialAuthorization:f.authorize(queryOperation,'initial-query'),propertyAuthorization:f.authorize(propertyOperation,'initial-property'),
    credential:f.options.credential,authorizationFor:({operation,ordinal})=>f.authorize(operation,`typed-${ordinal}`),
    current:f.current,chargeResponse:f.options.chargeResponse,consumeObservation:f.options.consumeObservation,
    consumePage:(page,{charge})=>{f.options.consumeObservation(charge);rows.push(...page);},limits:l});
  assert.equal((await read.read()).rowCount,1);assert.deepEqual(rows,[{text:'ab'}]);
  assert.equal(f.state.requests.length,5);assert.equal(f.journal.recover().filter(x=>x.outcome==='succeeded').length,5);
  assert.equal(handle.observe().cleanupConfirmed,false);assert.equal(read.observe().cleanupConfirmed,false);
});

test('actual Notion discovery rejects empty or ambiguous inventories and selects only the original explicit id',async t=>{
  for(const ids of [[],['other','s']]){
    const f=await fixture(t,{ids});await assert.rejects(f.discover().read(),{code:'NotionDatabaseDiscoveryFailed'});
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges.length,1);
  }
  const f=await fixture(t,{ids:['other','s'],decl:{id:'db',data_source_id:'s'}});
  await f.discover().read();assert.equal(f.state.requests[1].path,'/v1/data_sources/s');
});

test('actual Notion discovery retains both response charges when schema or declared type refuses',async t=>{
  for(const kind of ['foreign','missing-contract']){
    const f=await fixture(t,kind==='missing-contract'?{decl:'db'}:{}),respond=f.state.respond;
    f.state.respond=request=>request.url==='/v1/databases/db'?respond(request):kind==='foreign'?{...schema(),id:'foreign'}:
      {...schema(),properties:{amount:{id:'n',name:'amount',type:'number',number:{format:'number'}}}};
    const reader=f.discover();let failure;
    await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDatabaseDiscoveryFailed';});
    assert.equal(f.state.requests.length,2);assert.equal(failure.observations.length,2);
    assert.deepEqual(failure.responseCharges,f.state.charges);assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});assert.equal(f.state.requests.length,2);
  }
});

test('actual Notion discovery requires separate original operation grants before dependent I/O',async t=>{
  const f=await fixture(t);
  assert.throws(()=>f.discover({sourceAuthorization:f.discoveryOptions.initialAuthorization}),{code:'ForeignNotionDiscoveryAuthorization'});
  assert.equal(f.state.requests.length,0);
  const reader=f.discover({authorizationFor:({index})=>f.authorize(databaseOperation,`retarget-${index}`)});
  await assert.rejects(reader.read(),error=>error.cause.code==='ForeignNotionDiscoveryAuthorization');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
});

test('actual Notion discovery current refusal and reply loss retain original custody without resend',async t=>{
  const stale=await fixture(t);stale.state.resolved=()=>stale.writeAccount('deny');
  await assert.rejects(stale.discover().read(),{code:'NotionDatabaseDiscoveryFailed'});assert.equal(stale.state.requests.length,0);
  const lost=await fixture(t);lost.state.beforeResponse=request=>{if(request.url==='/v1/data_sources/s')request.socket.destroy();};
  const reader=lost.discover();let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDatabaseDiscoveryFailed';});
  assert.equal(lost.state.requests.length,2);assert.equal(failure.observations.length,1);assert.equal(failure.responseCharges.length,1);
  assert.equal(lost.journal.recover().filter(x=>x.outcome==='unknown').length,1);
  await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});assert.equal(lost.state.requests.length,2);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion discovery aggregate exhaustion retains the offending original body and charge',async t=>{
  const f=await fixture(t);const size=Buffer.byteLength(JSON.stringify(database(['s'])))+Buffer.byteLength(JSON.stringify(schema()));
  const reader=f.discover({limits:{...limits,maxTotalResponseBytes:size-1}});let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDatabaseDiscoveryFailed';});
  assert.equal(failure.responseCharges.length,2);assert.equal(failure.observations.length,2);
  assert.equal(reader.observe().receivedBodyBytes,BigInt(size));assert.equal(reader.observe().cleanupConfirmed,false);
});

test('copied Notion discovery handles and unsafe original path coordinates cannot dispatch',async t=>{
  const f=await fixture(t),reader=f.discover(),copy={...reader};
  await assert.rejects(copy.read(),{code:'ForeignNotionDiscoveryReader'});assert.throws(()=>copy.observe(),{code:'ForeignNotionDiscoveryReader'});
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from('".."'),...declarationBounds));
  assert.throws(()=>f.discover({declaration}),{code:'InvalidNotionDiscoveryCoordinate'});assert.equal(f.state.requests.length,0);
});
