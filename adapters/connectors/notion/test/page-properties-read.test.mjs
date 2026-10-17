import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {propertyReadFixture,propertyItemPage} from './property-item-read.fixture.mjs';
import {NOTION_PAGE_READ_OPERATION as pageOperation} from '../site/page-read.mjs';
import {NOTION_PROPERTY_READ_OPERATION as propertyOperation} from '../site/property-item-read.mjs';
import {createNotionPagePropertiesReader} from '../site/page-properties-read.mjs';

const metadata=[16384,1024,20,8,16,128,128],declarationLimits=[...metadata,256,16,4096,16,100000];
const limits={maxRequestBytes:1024,maxResponseBytes:16384,maxTotalResponseBytes:65536,maxTargetBytes:1024,
  maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:16,maxIdentityBytes:128,maxNameBytes:128,maxTextBytes:4096,
  maxRowNodes:256,maxRowDepth:16,maxRowTextBytes:4096,maxColumns:16,maxRowWork:1000000,
  maxPropertyPages:4,maxPropertyItems:128,maxPropertyBytes:32768,maxPropertyNodes:4096,maxPropertyTextBytes:16384,
  maxCursorBytes:128,maxPropertyWork:1000000,pageSize:10,maxWireBytes:8192,maxWireNodes:256,maxWireDepth:16};

function originals(moon,scalarOnly){
  const database=checked(moon.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]})),...metadata));
  const source=checked(moon.notionProjectDataSource(database,0,Buffer.from(JSON.stringify({object:'data_source',id:'s',parent:{type:'database_id',database_id:'db'},properties:{
    amount:{id:'n',name:'amount',type:'number',number:{format:'number'}},
    ...(scalarOnly?{}:{notes:{id:'t%3Ax',name:'notes',type:'rich_text',rich_text:{}}}),
  }})),...metadata));
  const declaration=checked(moon.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{
    n:[{column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}}],
    ...(scalarOnly?{}:{'t%3Ax':[{column:'notes',projection:'value',contract:{type:'string',nullable:false,enum:['ab']}}]}),
  }})),...declarationLimits));
  const property=checked(moon.notionBindDataSourceReadContracts(declaration,source,...declarationLimits));
  const readContracts=checked(moon.notionSourceSystemReadContracts(property,...declarationLimits));
  return{declaration,source,readContracts};
}

function pageWire(scalarOnly=false){return JSON.stringify({object:'page',id:'page',parent:{type:'data_source_id',data_source_id:'s',database_id:'db'},
  url:'https://notion.test/page',created_time:'2026-10-18T10:20:30+09:00',created_by:{object:'user',id:'maker'},
  last_edited_time:'2026-10-18T10:21:30+09:00',last_edited_by:{object:'user',id:'editor'},in_trash:false,
  properties:{amount:{id:'n',type:'number',number:'EXACT'},
    ...(scalarOnly?{}:{notes:{id:'t%3Ax',type:'rich_text',rich_text:[],has_more:true}})},
}).replace('"EXACT"','9007199254740993.25');}

async function fixture(t,{scalarOnly=false,...options}={}){
  const f=await propertyReadFixture(t,{...options,additionalOperations:[pageOperation]}),moon=f.options.moon;
  const original=originals(moon,scalarOnly),rows=[],selections=[];let properties=0;
  f.state.respond=request=>request.url==='/v1/pages/page'?pageWire(scalarOnly):
    propertyItemPage([properties++===0?'a':'b'],properties===1?'next':null);
  const supplied={moon,...original,pageId:'page',initialAuthorization:f.authorize(pageOperation,'original-page'),
    credential:f.options.credential,limits,current:f.current,chargeResponse:f.options.chargeResponse,
    consumeObservation:f.options.consumeObservation,consumeRow:(wire,record)=>{
      assert.equal(moon.notionReadRowMatchesObservedPage(record.originalRow,original.readContracts,record.originalPage),true);
      f.options.consumeValue(wire,record);rows.push(JSON.parse(wire));
    },propertyAuthorizationFor:input=>{
      assert(Object.isFrozen(input));assert.equal(input.operation,propertyOperation);
      assert.equal(input.readContracts,original.readContracts);assert.equal(rows.length,0);
      assert.equal(moon.notionReadRowMatchesObservedPage(input.originalRow,original.readContracts,input.originalPage),true);
      assert.equal(moon.notionPropertyRequestMatchesBinding(input.originalRequest,original.readContracts,input.column),true);
      selections.push(input);return f.authorize(propertyOperation,`original-property-${input.column}-${input.index}`);
    }};
  return{...f,...original,rows,selections,supplied,reader:overrides=>createNotionPagePropertiesReader({...supplied,...overrides})};
}

test('actual Notion exact GET completes the same checked row and paginated property under separate original uses',async t=>{
  const f=await fixture(t),reader=f.reader(),result=await reader.read();
  assert.deepEqual(f.rows,[{amount:'9007199254740993.25',created_by:'maker',created_time:'2026-10-18T01:20:30.000Z',id:'page',
    last_edited_by:'editor',last_edited_time:'2026-10-18T01:21:30.000Z',notes:'ab',resource:'page',url:'https://notion.test/page',version:'2026-10-18T10:21:30+09:00'}]);
  assert.equal(f.state.requests.length,3);assert.equal(f.state.requests[0].path,'/v1/pages/page');
  assert.equal(f.state.requests[1].path,'/v1/pages/page/properties/t%3Ax?page_size=10');
  assert.equal(new URL('https://notion.test'+f.state.requests[2].path).searchParams.get('start_cursor'),'next');
  assert.equal(f.selections.length,2);assert.equal(f.selections[0].originalPage,result.originalPage);
  assert.equal(f.selections[0].originalRow,result.originalRow);assert.equal(result.readContracts,f.readContracts);
  assert.deepEqual(result.responseCharges,f.state.charges);assert.deepEqual(f.state.observations,f.state.charges.slice(0,2));
  assert.deepEqual(Object.keys(JSON.parse(result.schemaWire).fields),Object.keys(f.rows[0]));
  assert.equal(reader.observe().receivedResponses,3);assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'NotionPagePropertiesAlreadyStarted'});assert.equal(f.state.requests.length,3);
});

test('actual scalar-only Notion GET supplies its original ticket with the complete row without property authorization',async t=>{
  const f=await fixture(t,{scalarOnly:true}),reader=f.reader({propertyAuthorizationFor:undefined});
  const result=await reader.read();assert.equal(f.state.requests.length,1);assert.equal(f.state.charges.length,1);
  assert.equal(f.state.observations.length,0);assert.equal(f.rows.length,1);assert.equal(f.rows[0].amount,'9007199254740993.25');
  assert.equal(result.responseCharges[0],f.state.charges[0]);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion changed parent property kind or missing schema field refuses before dependent I/O',async t=>{
  for(const kind of ['parent','property','missing']){
    const f=await fixture(t);let wire=pageWire();
    if(kind==='parent')wire=wire.replace('"data_source_id":"s"','"data_source_id":"foreign"');
    if(kind==='property')wire=wire.replace('"type":"rich_text"','"type":"title"');
    if(kind==='missing')wire=wire.replace('"amount":{"id":"n","type":"number","number":9007199254740993.25},','');
    f.state.respond=()=>wire;const reader=f.reader();let failure;
    await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionPagePropertiesReadFailed'&&error.cause.code==='MoonBitHostFailure';});
    assert.equal(f.state.requests.length,1);assert.equal(f.selections.length,0);assert.equal(f.rows.length,0);
    assert.equal(f.state.observations.length,0);assert.equal(failure.responseCharges[0],f.state.charges[0]);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('actual pending Notion property has no missing or wrong-operation authorization fallback',async t=>{
  for(const kind of ['missing','page-purpose']){
    const f=await fixture(t),reader=f.reader({propertyAuthorizationFor:kind==='missing'?undefined:()=>f.authorize(pageOperation,'wrong-purpose')});
    await assert.rejects(reader.read(),error=>error.cause.code===(kind==='missing'?'NotionPropertyAuthorizationUnavailable':'ForeignNotionPropertyAuthorization'));
    assert.equal(f.state.requests.length,1);assert.equal(f.state.observations.length,0);assert.equal(f.rows.length,0);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('actual Notion dependent authorization await rechecks current Account and abort before property send',async t=>{
  for(const kind of ['account','abort']){
    const f=await fixture(t),stop=new AbortController(),reader=f.reader({signal:stop.signal,propertyAuthorizationFor:async input=>{
      const result=f.supplied.propertyAuthorizationFor(input);if(kind==='account')await f.writeAccount('deny');else stop.abort();return result;
    }});
    await assert.rejects(reader.read(),error=>kind==='account'?error.cause.code==='AuthorizationCurrentAccountChanged':error.cause.name==='AbortError');
    assert.equal(f.state.requests.length,1);assert.equal(f.state.observations.length,0);assert.equal(f.rows.length,0);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('actual Notion aggregate response exhaustion retains the actual failing child and every returned charge',async t=>{
  const f=await fixture(t),total=Buffer.byteLength(pageWire())+Buffer.byteLength(JSON.stringify(propertyItemPage(['a'],'next')))-1;
  const reader=f.reader({limits:{...limits,maxTotalResponseBytes:total}});let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.cause.cause.code==='NotionPagePropertiesResponseLimit';});
  assert.equal(f.state.requests.length,2);assert.equal(f.state.charges.length,2);assert.equal(f.rows.length,0);
  assert.deepEqual(failure.responseCharges,f.state.charges);assert.equal(failure.children.length,2);
  assert.equal(failure.children[1].observe().receivedResponses,1);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion lost dependent property reply stays Unknown across an explicit new reader without resend',async t=>{
  const f=await fixture(t);f.state.beforeResponse=request=>{if(request.url.includes('/properties/'))request.socket.destroy();};
  const reader=f.reader();await assert.rejects(reader.read(),{code:'NotionPagePropertiesReadFailed'});
  const unknown=f.journal.recover().find(x=>x.outcome==='unknown');assert(unknown);
  await assert.rejects(reader.read(),{code:'NotionPagePropertiesAlreadyStarted'});
  const next=f.reader({initialAuthorization:f.authorize(pageOperation,'explicit-new-page-read')});
  await assert.rejects(next.read(),error=>error.cause.cause.code==='RemoteCredentialUseAlreadyClaimed');
  assert.equal(f.journal.inspect(unknown.useCid).outcome,'unknown');assert.equal(f.rows.length,0);
  assert.equal(f.state.requests.length,3);assert.equal(f.state.requests.filter(x=>x.path.includes('/properties/')).length,1);
  assert.equal(f.state.resolutions,3);assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(next.observe().cleanupConfirmed,false);
});
