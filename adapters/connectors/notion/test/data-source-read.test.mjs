import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createNotionDataSourceReader,NOTION_DATA_SOURCE_READ_OPERATION} from '../site/data-source-read.mjs';
import {NOTION_PROPERTY_READ_OPERATION} from '../site/property-item-read.mjs';
import {propertyReadFixture} from './property-item-read.fixture.mjs';

const metadata=[16384,1024,20,8,8,128,128],declarationBounds=[...metadata,256,16,4096,16,100000];
const properties={
  title:{id:'t%3Ax',name:'title',type:'rich_text',rich_text:{}},
  amount:{id:'n',name:'amount',type:'number',number:{format:'number'}},
  enabled:{id:'b',name:'enabled',type:'checkbox',checkbox:{}},
};
function originals(scalarOnly=false){
  const database=checked(provider.notionProjectDatabase(Buffer.from(JSON.stringify({object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]})),...metadata));
  const source=checked(provider.notionProjectDataSource(database,0,Buffer.from(JSON.stringify({object:'data_source',id:'s',parent:{type:'database_id',database_id:'db'},properties:scalarOnly?{amount:properties.amount,enabled:properties.enabled}:properties})),...metadata));
  const declaration=checked(provider.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{
    n:[{column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}}],
    ...(scalarOnly?{}:{'t%3Ax':[{column:'title',projection:'value',contract:{type:'string',nullable:false,enum:['ab','cd']}}]}),
  }})),...declarationBounds));
  const readContracts=checked(provider.notionBindDataSourceReadContracts(declaration,source,...declarationBounds));
  return{source,declaration,readContracts};
}
function queryPage(ids,cursor=null){
  return JSON.stringify({object:'list',type:'page_or_data_source',page_or_data_source:{},results:ids.map(id=>({
    object:'page',id,parent:{type:'data_source_id',data_source_id:'s'},properties:{
      title:{id:'t%3Ax',type:'rich_text',rich_text:[],has_more:true},
      amount:{id:'n',type:'number',number:'EXACT'},enabled:{id:'b',type:'checkbox',checkbox:true},
    },
  })),has_more:cursor!==null,next_cursor:cursor}).replaceAll('"EXACT"','9007199254740993.25');
}
function propertyPage(text,cursor=null){return{object:'list',type:'property_item',results:[{
  object:'property_item',id:'t%3Ax',type:'rich_text',rich_text:{type:'text',text:{content:text},plain_text:text},
}],has_more:cursor!==null,next_cursor:cursor,property_item:{id:'t%3Ax',type:'rich_text',rich_text:{},
  next_url:cursor===null?null:'https://foreign.test/never-follow'}};}
const limits={maxResponseBytes:16384,maxTotalResponseBytes:131072,maxRequestBytes:1024,maxTargetBytes:1024,
  maxPages:4,pageSize:10,maxTotalRows:8,maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:8,
  maxIdentityBytes:128,maxNameBytes:128,maxCursorBytes:128,maxRowNodes:256,maxRowDepth:16,maxRowTextBytes:4096,
  maxColumns:16,maxRowWork:1000000,maxPageWork:1000000,maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20,
  maxPropertyPages:4,maxPropertyItems:128,maxPropertyBytes:65536,maxPropertyNodes:4096,maxPropertyTextBytes:32768,maxPropertyWork:1000000};
async function fixture(t){
  const f=await propertyReadFixture(t,{additionalOperations:[NOTION_DATA_SOURCE_READ_OPERATION]}),original=originals(),rows=[],tickets=[];
  let query=0,property=0;
  f.state.respond=(request,body)=>{
    if(request.method==='POST'){
      assert.equal(request.url,'/v1/data_sources/s/query');assert.equal(JSON.parse(body).page_size,query===0?8:7);
      const expected=query++===0?{ids:['page1'],cursor:'query cursor'}:{ids:['page2'],cursor:null};
      return queryPage(expected.ids,expected.cursor);
    }
    assert.equal(request.method,'GET');assert.match(request.url,/^\/v1\/pages\/page[12]\/properties\/t%3Ax\?page_size=10/u);
    const page=Math.floor(property/2),part=property++%2;
    return propertyPage(page===0?(part===0?'a':'b'):(part===0?'c':'d'),part===0?'property cursor':null);
  };
  const options={moon:provider,...original,initialAuthorization:f.authorize(NOTION_DATA_SOURCE_READ_OPERATION,'initial-query'),
    propertyAuthorization:f.authorize(NOTION_PROPERTY_READ_OPERATION,'initial-property'),credential:f.options.credential,
    authorizationFor:input=>f.authorize(input.operation,`query-child-${input.ordinal}`),current:f.current,limits,
    chargeResponse:f.options.chargeResponse,consumeObservation:f.options.consumeObservation,
    consumePage:(page,{charge,originalRows,readContracts})=>{
      assert.equal(readContracts,original.readContracts);assert.equal(originalRows.length,page.length);
      f.options.consumeObservation(charge);tickets.push(charge);rows.push(...page);
    }};
  return{...f,original,rows,tickets,options,create:overrides=>createNotionDataSourceReader({...options,...overrides})};
}

test('actual Notion query and property operations retain typed rows and original response charges across both cursors',async t=>{
  const f=await fixture(t),reader=f.create(),result=await reader.read();
  assert.deepEqual(f.rows,[{amount:'9007199254740993.25',enabled:true,title:'ab'},
    {amount:'9007199254740993.25',enabled:true,title:'cd'}]);
  assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.equal(result.observations.length,6);
  assert.deepEqual(result.responseCharges,f.state.charges);
  assert.equal(f.state.requests.length,6);assert.equal(f.state.charges.length,6);
  assert(f.tickets.every(ticket=>ticket.originalBody.toString().includes('plain_text')));
  assert.equal(f.state.observations.length,6,'each raw ticket consumed exactly once, no output-byte ticket');
  assert.match(result.schemaWire,/"precision":20/u);assert.match(result.schemaWire,/"enum":\["ab","cd"\]/u);
  assert.equal(reader.observe().receivedResponses,6);assert.equal(reader.observe().cleanupConfirmed,false);
  assert.deepEqual(f.journal.recover().filter(x=>x.outcome==='succeeded').length,6);
  assert.deepEqual(JSON.parse(f.state.requests[3].body),{page_size:7,start_cursor:'query cursor'});
  assert.match(f.state.requests[2].path,/start_cursor=property%20cursor$/u);
});

test('actual Notion complete row never delivers an enum-invalid partial property or a rounded Decimal',async t=>{
  const invalid=await fixture(t),respond=invalid.state.respond;
  invalid.state.respond=(request,body)=>request.method==='GET'?propertyPage('wrong'):respond(request,body);
  await assert.rejects(invalid.create().read(),{code:'NotionDataSourceReadFailed'});assert.deepEqual(invalid.rows,[]);
  assert.equal(invalid.state.requests.length,2);
  const decimal=await fixture(t),original=decimal.state.respond;
  decimal.state.respond=(request,body)=>request.method==='POST'?queryPage(['page1']).replace('9007199254740993.25','9007199254740993.251'):original(request,body);
  await assert.rejects(decimal.create().read(),{code:'NotionDataSourceReadFailed'});assert.deepEqual(decimal.rows,[]);
  assert.equal(decimal.state.requests.length,1,'invalid scalar refuses before dependent property I/O');
});

test('actual Notion missing or retargeted property grant cannot reuse the query authorization',async t=>{
  const missing=await fixture(t);
  await assert.rejects(missing.create({propertyAuthorization:undefined}).read(),error=>error.cause.code==='NotionPropertyAuthorizationUnavailable');
  assert.equal(missing.state.requests.length,1);assert.deepEqual(missing.rows,[]);
  const retarget=await fixture(t);
  assert.throws(()=>retarget.create({propertyAuthorization:retarget.options.initialAuthorization}),{code:'ForeignNotionPropertyAuthorization'});
  assert.equal(retarget.state.requests.length,0);
});

test('actual Notion duplicate page and cursor continuation refuse without a second original row delivery',async t=>{
  const duplicate=await fixture(t),respond=duplicate.state.respond;let count=0;
  duplicate.state.respond=(request,body)=>request.method==='POST'?queryPage(['page1'],count++===0?'next':null):respond(request,body);
  await assert.rejects(duplicate.create().read(),error=>error.cause.code==='NotionDataSourceDuplicatePage');
  assert.equal(duplicate.rows.length,1);assert.equal(duplicate.state.requests.length,4);
  const repeated=await fixture(t);repeated.state.respond=()=>queryPage([],'same');
  await assert.rejects(repeated.create().read(),error=>error.cause.code==='NotionDataSourceRepeatedCursor');
  assert.equal(repeated.state.requests.length,2);assert.deepEqual(repeated.rows,[]);
});

test('actual Notion Account/current and original schema selection refuse before or between dependent reads',async t=>{
  const foreign=await fixture(t);
  assert.throws(()=>foreign.create({declaration:originals().declaration}),{code:'ForeignNotionReadContracts'});
  assert.equal(foreign.state.requests.length,0);
  const changed=await fixture(t);changed.state.resolved=()=>{if(changed.state.resolutions===2)return changed.writeAccount('deny');};
  const reader=changed.create();await assert.rejects(reader.read(),{code:'NotionDataSourceReadFailed'});
  assert.equal(changed.state.requests.length,1);assert.deepEqual(changed.rows,[]);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion dependent reply loss remains the original credential Unknown and retained child, without resend',async t=>{
  const f=await fixture(t);f.state.beforeResponse=request=>{if(request.method==='GET')request.socket.destroy();};
  const reader=f.create();let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDataSourceReadFailed';});
  assert.equal(f.state.requests.length,2);assert.deepEqual(f.rows,[]);
  assert.equal(failure.children.length,1);assert.equal(f.journal.recover().filter(x=>x.outcome==='unknown').length,1);
  await assert.rejects(reader.read(),{code:'NotionDataSourceReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,2);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion aggregate response/output exhaustion and stop retain raw without a complete row',async t=>{
  const raw=await fixture(t);raw.state.respond=()=>queryPage(['page1']);
  await assert.rejects(raw.create({limits:{...limits,maxTotalResponseBytes:1}}).read(),error=>error.observations.length===1);
  assert.deepEqual(raw.rows,[]);assert.equal(raw.state.charges.length,1);
  const output=await fixture(t);
  output.state.respond=request=>request.method==='POST'?queryPage(['p1','p2','p3','p4','p5']):propertyPage('ab');
  const reader=output.create({limits:{...limits,maxRowsWireBytes:300}});
  await assert.rejects(reader.read(),error=>error.cause.code==='MoonBitHostFailure');assert.deepEqual(output.rows,[]);
  const stopped=await fixture(t),controller=new AbortController(),reason=new Error('OriginalQueryStop');
  const handle=stopped.create({signal:controller.signal,chargeResponse:body=>{controller.abort(reason);return stopped.options.chargeResponse(body);}});
  await assert.rejects(handle.read(),error=>error.cause===reason);assert.equal(stopped.state.requests.length,1);
  assert.deepEqual(stopped.rows,[]);assert.equal(handle.observe().cleanupConfirmed,false);
});

test('actual Notion aggregate page node cap applies to all complete rows together',async t=>{
  const f=await fixture(t);
  f.state.respond=request=>request.method==='POST'?queryPage(['p1','p2','p3','p4','p5']):propertyPage('ab');
  // The original checked schema fits 20 writer nodes and each row fits four.
  // The complete five-row page needs 1 + 5 * 4 = 21 nodes, including its array.
  const reader=f.create({limits:{...limits,maxRowsWireNodes:20}});
  await assert.rejects(reader.read(),error=>error.code==='NotionDataSourceReadFailed'&&
    error.responseCharges.length===6&&error.responseCharges.every((charge,index)=>charge===f.state.charges[index]));
  assert.deepEqual(f.rows,[]);
  assert.equal(f.state.requests.length,6);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

const queryStatus=(wire,status)=>wire.slice(0,-1)+',"request_status":'+JSON.stringify(status)+'}';

test('actual Notion incomplete first page refuses before dependent I/O or row delivery and retains original charges',async t=>{
  for(const cursor of [null,'next']){
    const f=await fixture(t);let requests=0;
    f.state.respond=request=>request.method==='POST'?
      (requests++===0?queryStatus(queryPage(['page1'],cursor),{type:'incomplete',incomplete_reason:'query_result_limit_reached'}):queryPage([])):
      propertyPage('ab');
    const reader=f.create();let failure;
    await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDataSourceReadFailed';});
    assert.equal(f.state.requests.length,1);assert.equal(failure.children.length,0);assert.deepEqual(f.rows,[]);
    assert.equal(failure.observations.length,1);assert.equal(failure.responseCharges.length,1);
    assert.equal(failure.responseCharges[0],f.state.charges[0]);
    assert.match(failure.observations[0].body.toString(),/"type":"incomplete"/u);
    assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'NotionDataSourceReaderAlreadyStarted'});assert.equal(f.state.requests.length,1);
  }
});

test('actual Notion incomplete final page cannot complete after an earlier valid original page',async t=>{
  const f=await fixture(t),respond=f.state.respond;let queries=0;
  f.state.respond=(request,body)=>{
    const wire=respond(request,body);
    return request.method==='POST'&&queries++===1?queryStatus(wire,{type:'incomplete',incomplete_reason:'query_result_limit_reached'}):wire;
  };
  const reader=f.create();let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionDataSourceReadFailed';});
  assert.equal(f.state.requests.length,4);assert.equal(f.rows.length,1,'the earlier page is retained, never a successful whole query');
  assert.equal(failure.children.length,1);assert.equal(failure.responseCharges.length,4);
  assert(failure.responseCharges.every((ticket,index)=>ticket===f.state.charges[index]));
  assert(failure.observations.some(response=>response.body.toString().includes('"type":"incomplete"')));
  assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'NotionDataSourceReaderAlreadyStarted'});assert.equal(f.state.requests.length,4);
});

test('actual Notion explicit complete statuses preserve exact Decimal and original page custody',async t=>{
  const f=await fixture(t),respond=f.state.respond;
  f.state.respond=(request,body)=>{
    const wire=respond(request,body);
    return request.method==='POST'?queryStatus(wire,{type:'complete',incomplete_reason:'query_result_limit_reached'}):wire;
  };
  const reader=f.create(),result=await reader.read();
  assert.equal(result.rowCount,2);assert.equal(result.pages,2);assert.equal(f.state.requests.length,6);
  assert(f.rows.every(row=>row.amount==='9007199254740993.25'));
  assert(result.observations.filter(x=>x.body.toString().includes('"type":"complete"')).length===2);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('compiled Notion query admission refuses malformed status instead of treating null cursor as completeness',()=>{
  const {source}=originals();
  for(const status of [null,true,[],{},'complete',{type:'future'},{type:null},{type:'complete',incomplete_reason:null},
    {type:'complete',incomplete_reason:'future'},{type:'complete',extra:true}]){
    const body=Buffer.from(queryStatus(queryPage(['page1']),status));
    assert.throws(()=>checked(provider.notionProjectQueryPage(source,body,...metadata,10,128)),{code:'MoonBitHostFailure'});
  }
});

test('actual Notion lazy property grant follows the original pending request without early authorization',async t=>{
  const f=await fixture(t),selected=[];
  const reader=f.create({propertyAuthorization:undefined,propertyAuthorizationFor:async original=>{
    assert(Object.isFrozen(original));assert.equal(original.readContracts,f.original.readContracts);
    assert.equal(original.declaration,f.original.declaration);assert.equal(original.source,f.original.source);
    assert.equal(original.operation,NOTION_PROPERTY_READ_OPERATION);
    assert.equal(provider.notionPropertyRequestMatchesBinding(original.originalRequest,
      f.original.readContracts,original.column),true);
    assert.equal(f.state.requests.length,selected.length===0?1:4,'select after this actual query response');
    selected.push(original);
    return f.authorize(NOTION_PROPERTY_READ_OPERATION,`lazy-property-${selected.length}`);
  }});
  const result=await reader.read();
  assert.equal(selected.length,2);assert.equal(result.pages,2);assert.equal(result.rowCount,2);
  assert.deepEqual(f.rows,[{amount:'9007199254740993.25',enabled:true,title:'ab'},
    {amount:'9007199254740993.25',enabled:true,title:'cd'}]);
  assert.notEqual(selected[0].originalRequest,selected[1].originalRequest);
  assert.equal(f.state.requests.length,6);assert.deepEqual(result.responseCharges,f.state.charges);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion dependent property selection is exclusive and absent pending work issues no property use',async t=>{
  const f=await fixture(t);
  assert.throws(()=>f.create({propertyAuthorizationFor:()=>{}}),{code:'InvalidNotionDataSourceRead'});
  for(const propertyAuthorizationFor of [null,false,{}])assert.throws(()=>f.create({
    propertyAuthorization:undefined,propertyAuthorizationFor}),{code:'InvalidNotionDataSourceRead'});
  assert.equal(f.state.requests.length,0);
  // An original scalar-only schema has no property-item completion. Keep
  // Common's conservative full-text completion policy and exact Decimal body.
  const selected=originals(true);
  const title='"title":'+JSON.stringify({id:'t%3Ax',type:'rich_text',rich_text:[],has_more:true})+',';
  f.state.respond=()=>queryPage(['page1']).replace(title,'');
  let calls=0;
  const reader=f.create({...selected,propertyAuthorization:undefined,propertyAuthorizationFor:()=>{
    calls++;throw new Error('NoPendingProperty');
  },consumePage:(page,{charge,readContracts})=>{
    assert.equal(readContracts,selected.readContracts);f.options.consumeObservation(charge);f.rows.push(...page);
  }});
  const result=await reader.read();assert.equal(calls,0);assert.equal(result.rowCount,1);
  assert.equal(f.state.requests.length,1);assert.equal(result.observations.length,1);
  assert.deepEqual(f.rows,[{amount:'9007199254740993.25',enabled:true}]);
});

test('actual Notion lazy property selection refuses query and foreign original grants without fallback',async t=>{
  for(const foreign of [false,true]){
    const f=await fixture(t),other=foreign?await fixture(t):undefined;
    const reader=f.create({propertyAuthorization:undefined,propertyAuthorizationFor:()=>foreign?
      other.authorize(NOTION_PROPERTY_READ_OPERATION,'foreign-property'):f.options.initialAuthorization});
    let failure;
    await assert.rejects(reader.read(),error=>{
      failure=error;return error.cause.code==='ForeignNotionPropertyAuthorization';
    });
    assert.equal(f.state.requests.length,1);assert.equal(other?.state.requests.length??0,0);
    assert.equal(failure.children.length,0);assert.equal(failure.observations.length,1);
    assert.equal(failure.responseCharges[0],f.state.charges[0]);assert.deepEqual(f.rows,[]);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('actual Notion current denial or stop after the awaited property selection sends no dependent request',async t=>{
  for(const stop of [false,true]){
    const f=await fixture(t),controller=new AbortController(),reason=new Error('OriginalPropertySelectionStopped');
    const reader=f.create({propertyAuthorization:undefined,signal:controller.signal,
      propertyAuthorizationFor:async()=>{
        await Promise.resolve();
        if(stop)controller.abort(reason);else await f.writeAccount('deny');
        return f.authorize(NOTION_PROPERTY_READ_OPERATION,'late-property');
      }});
    let failure;
    await assert.rejects(reader.read(),error=>{
      // The original Account Owner rejects replacement configuration before
      // returning another decision; the fixture must not demand a later code.
      failure=error;return stop?error.cause===reason:error.cause.code==='AuthorizationCurrentAccountChanged';
    });
    assert.equal(f.state.requests.length,1);assert.equal(failure.children.length,0);
    assert.equal(failure.responseCharges[0],f.state.charges[0]);assert.deepEqual(f.rows,[]);
    assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'NotionDataSourceReaderAlreadyStarted'});
    assert.equal(f.state.requests.length,1);
  }
});

test('actual Notion failed property selection retains its original cause and query observation without another preparation',async t=>{
  const f=await fixture(t),cause=new Error('OriginalPropertySupplierUnavailable');let calls=0;
  const reader=f.create({propertyAuthorization:undefined,propertyAuthorizationFor:async()=>{
    calls++;throw cause;
  }});let failure;
  await assert.rejects(reader.read(),error=>{failure=error;return error.cause===cause;});
  assert.equal(calls,1);assert.equal(f.state.requests.length,1);assert.equal(failure.children.length,0);
  assert.equal(failure.responseCharges[0],f.state.charges[0]);
  assert.equal(failure.observations[0].body,f.state.charges[0].originalBody);
  assert.equal(reader.observe().cleanupConfirmed,false);assert.deepEqual(f.rows,[]);
  await assert.rejects(reader.read(),{code:'NotionDataSourceReaderAlreadyStarted'});assert.equal(calls,1);
});

test('actual Notion dependent supplier is captured once and cannot be replaced after reader preparation',async t=>{
  const f=await fixture(t);let reads=0,calls=0;
  const options={...f.options,propertyAuthorization:undefined};
  const supplier=original=>{calls++;return f.authorize(original.operation,`captured-property-${calls}`);};
  Object.defineProperty(options,'propertyAuthorizationFor',{configurable:true,get(){reads++;return supplier;}});
  const reader=createNotionDataSourceReader(options);assert.equal(reads,1);
  Object.defineProperty(options,'propertyAuthorizationFor',{value:()=>{throw new Error('ReplacedSupplier');}});
  assert.equal((await reader.read()).rowCount,2);assert.equal(calls,2);assert.equal(reads,1);
  assert.equal(f.state.requests.length,6);assert.equal(reader.observe().cleanupConfirmed,false);
});
