import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,invokeScopedCredentialOperation}
  from '../host-common/owned-invocation-context.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {prepareNotionUserListPages, NOTION_USER_LIST_OPERATION, NOTION_USER_LIST_API_VERSION}
  from '../connectors/notion/site/user-list-read.mjs';
import {prepareCalendarListPages, CALENDAR_LIST_OPERATION}
  from '../connectors/calendar/site/calendar-list-read.mjs';
import {prepareNotionPageReadPages,NOTION_PAGE_READ_OPERATION}
  from '../connectors/notion/site/page-read.mjs';
import {prepareNotionPropertyReadProjection}
  from '../connectors/notion/site/property-item-read.mjs';

// Real provider namespaces and the shared Host reader, with explicit Credential,
// current, accounting and transport ports. This is not a normal installation,
// Common admission, funded RowRun, physical send or cleanup acknowledgement.
const notion = await import(process.env.ACTQL_TEST_NOTION_URL ??
  new URL('../../_build/js/release/build/connectors/notion/host_node/host_node.js', import.meta.url).href);
const calendar = await import(process.env.ACTQL_TEST_CALENDAR_URL ??
  new URL('../../_build/js/release/build/connectors/calendar/host_node/host_node.js', import.meta.url).href);
const limits = Object.freeze({maxResponseBytes:8192, maxTotalResponseBytes:24576,
  maxNodes:512, maxDepth:16, maxRows:2, maxTotalRows:4, maxPages:3, maxRequests:3,
  pageSize:2, perPage:2, maxCursorBytes:128, maxCursorUnits:128,
  maxIdentityBytes:128, maxTargetBytes:1024, maxValueNodes:100, maxValueTextBytes:4096,
  maxRowsWireBytes:8192, maxRowsWireNodes:200, maxRowsWireDepth:8});

function open(family, pages, {names} = {}) {
  const operation = family === 'notion' ? NOTION_USER_LIST_OPERATION : CALENDAR_LIST_OPERATION;
  const moon = family === 'notion' ? notion : calendar;
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name => [name,name])),
    operation, resourceOrigin:'https://provider.invalid'});
  const credential = {control:{identity:() => 'explicit-grant'}, journal:{
    claim(_cid,useId) {return {use:{},record:{grantCid:'explicit-grant',useId},replayed:false};},
    authorize() {}, finish() {},
  }, resolveSecret:() => 'explicit-secret'};
  const bodies = pages.map(value => Buffer.from(JSON.stringify(value)));
  const requests = [], charged = [], delivered = [];
  const site = {credential, referenceCurrent() {assert.equal(this,site); return true;},
    async callResource(input) {
      assert.equal(this,site);
      requests.push(input.operations.get(operation));
      assert(requests.length <= bodies.length);
      return {accepted:true,statusCode:200,body:bodies[requests.length-1]};
    }};
  const factory = createInstalledCredentialSourceReader({capacity:{},site,operation,
    maxResponses:limits.maxPages,maxResponseBytes:limits.maxResponseBytes,maxSecretBytes:64,
    preparePageReader({columns},applySynchronousProjection) {
      return (family === 'notion' ? prepareNotionUserListPages : prepareCalendarListPages)(
        {moon,names:columns,limits},applySynchronousProjection);
    }});
  const reader = factory.prepare({resource:family === 'notion' ? 'users' : 'calendars',
    columns:names ?? (family === 'notion' ? ['id','name'] : ['summary']),
    async verifyRead() {},
    authorizationFor(index) {return {grant:{},scope,useId:`page-${index}`};},
    chargePage(body) {
      assert.equal(body,bodies[requests.length-1]); charged.push(body);
      return Object.freeze({body});
    },
    consumePage(rows,{charge}) {
      assert.equal(charge.body,charged.at(-1));
      delivered.push(...rows);
    }});
  return {reader,requests,charged,delivered,bodies,close() {
    reader.requestStop();
    assert.equal(reader.observe().cleanupConfirmed,true);
    assert.equal(factory.retire(),true);
  }};
}

const cursor = 'opaque /+e\u0301📅';
const user = (id,name) => ({object:'user',id,type:'bot',name,bot:{}});
const users = (value,next) => ({object:'list',type:'user',user:{},results:[value],
  has_more:next !== null,next_cursor:next});
const entry = (id,summary) => ({id,summary,timeZone:'Asia/Tokyo',accessRole:'reader',deleted:false});
const calendars = (value,next) => ({kind:'calendar#calendarList',items:[value],
  ...(next === null ? {} : {nextPageToken:next})});

test('real Notion Source callbacks retain all declared cells before selected or empty user projection',async()=>{
  for(const names of [['name'],[]]){
    const original={object:'user',id:'original-id',name:'e\u0301\r\n',type:'person',person:{email:'original@example.test'}};
    const f=open('notion',[users(original,null)],{names});
    try{
      assert.deepEqual(await f.reader.read(),{pages:1,rowCount:1});
      assert.deepEqual(f.delivered,[{email:'original@example.test',id:'original-id',name:'e\u0301\r\n',type:'person'}]);
      assert.equal(f.requests.length,1);assert.equal(f.charged.length,1);
      assert.equal(f.charged[0],f.bodies[0]);
      assert.equal(f.reader.observe().cleanupConfirmed,false);
    }finally{f.close();}
  }
});

test('real Notion projections preserve original strings and cursor through the shared reader',async() => {
  const f = open('notion',[users(user('N-e\u0301','一\r\n📚'),cursor),users(user('N-é',''),null)]);
  try {
    assert.deepEqual(await f.reader.read(),{pages:2,rowCount:2});
    assert.deepEqual(f.delivered,[{email:null,id:'N-e\u0301',name:'一\r\n📚',type:'bot'},
      {email:null,id:'N-é',name:'',type:'bot'}]);
    assert.equal(f.charged.length,2);
    for(const [i,request] of f.requests.entries()) {
      assert.equal(request.method,'GET');
      const target = new URL(request.path,'https://provider.invalid');
      assert.equal(target.pathname,'/v1/users');
      assert(request.headers.some(([name,value]) => name === 'notion-version' && value === NOTION_USER_LIST_API_VERSION));
      const query = target.searchParams;
      assert.equal(query.get('page_size'),'2');
      assert.equal(query.get('start_cursor'),i === 0 ? null : cursor);
    }
    assert.equal(f.reader.observe().receivedBodyBytes,BigInt(f.bodies.reduce((n,body) => n+body.length,0)));
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  } finally {f.close();}
  const duplicate = open('notion',[users(user('same','first'),cursor),users(user('same','second'),null)]);
  try {
    await assert.rejects(duplicate.reader.read(),error => error.cause?.code === 'NotionUserListDuplicateUser');
    assert.equal(duplicate.charged.length,2);
    assert.deepEqual(duplicate.delivered,[{email:null,id:'same',name:'first',type:'bot'}]);
  } finally {duplicate.close();}
});

test('real Calendar projections keep remaining rows and validate unselected captured columns',async() => {
  const f = open('calendar',[calendars(entry('C-e\u0301','予定 📅'),cursor),calendars(entry('C-é',''),null)]);
  try {
    assert.deepEqual(await f.reader.read(),{pages:2,rowCount:2});
    assert.deepEqual(f.delivered,[{id:'C-e\u0301',summary:'予定 📅',time_zone:'Asia/Tokyo',access_role:'reader'},
      {id:'C-é',summary:'',time_zone:'Asia/Tokyo',access_role:'reader'}]);
    assert.equal(f.charged.length,2);
    for(const [i,request] of f.requests.entries()) {
      const target = new URL(request.path,'https://provider.invalid');
      assert.equal(target.pathname,'/calendar/v3/users/me/calendarList');
      const query = target.searchParams;
      assert.equal(query.get('maxResults'),i === 0 ? '2' : '1');
      assert.equal(query.get('pageToken'),i === 0 ? null : cursor);
      assert.equal(query.get('showHidden'),'true');
      assert.equal(query.get('showDeleted'),'false');
      assert.equal(query.get('fields'),'kind,items(id,summary,timeZone,accessRole,deleted),nextPageToken');
    }
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  } finally {f.close();}
  const malformed = open('calendar',[calendars({...entry('bad','visible'),timeZone:7},null)]);
  try {
    await assert.rejects(malformed.reader.read());
    assert.equal(malformed.charged.length,1);
    assert.deepEqual(malformed.delivered,[]);
  } finally {malformed.close();}
});

test('real Notion projection keeps remaining-page bounds without reading beyond an incomplete cap',async() => {
  const batch=(values,next)=>({object:'list',type:'user',user:{},results:values,
    has_more:next!==null,next_cursor:next});
  const f=open('notion',[batch([user('one','first')],cursor),
    batch([user('two','second'),user('three','third')],cursor+' next'),
    batch([user('four','fourth')],null)]);
  try{
    assert.deepEqual(await f.reader.read(),{pages:3,rowCount:4});
    assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://provider.invalid').searchParams.get('page_size')),['2','2','1']);
    assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://provider.invalid').searchParams.get('start_cursor')),[null,cursor,cursor+' next']);
    assert.deepEqual(f.delivered,[{email:null,id:'one',name:'first',type:'bot'},
      {email:null,id:'two',name:'second',type:'bot'},
      {email:null,id:'three',name:'third',type:'bot'},
      {email:null,id:'four',name:'fourth',type:'bot'}]);
    assert.equal(f.charged.length,3);assert.equal(f.reader.observe().cleanupConfirmed,false);
  }finally{f.close();}
  const capped=open('notion',[batch([user('one','first'),user('two','second')],cursor),
    batch([user('three','third'),user('four','fourth')],cursor+' next'),
    batch([user('five','not requested')],null)]);
  try{
    await assert.rejects(capped.reader.read(),error=>error.cause?.code==='NotionUserListRowLimit');
    assert.equal(capped.requests.length,2);assert.equal(capped.charged.length,2);
    assert.equal(capped.reader.observe().phase,'failed');
    assert.equal(capped.reader.observe().cleanupConfirmed,false);
  }finally{capped.close();}
});

const pageLimits=Object.freeze({maxRequestBytes:1024,maxResponseBytes:16384,maxTargetBytes:1024,
  maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:16,maxIdentityBytes:128,
  maxNameBytes:128,maxTextBytes:2048,maxWireBytes:4096,maxWireNodes:128,maxWireDepth:8});
const originalPage=()=>({object:'page',id:'page',parent:{type:'data_source_id',data_source_id:'s',database_id:'db'},
  url:'https://notion.example/page',created_by:{object:'user',id:'creator'},last_edited_by:{object:'user',id:'editor'},
  created_time:'2026-10-17T10:00:00+09:00',last_edited_time:'2026-10-17T00:00:00.123000Z',in_trash:false,
  properties:{title:{id:'title',type:'title',title:[]}}});
function openPage(wire,{statusCode=200,limits=pageLimits,afterCharge}={}){
  const operation=NOTION_PAGE_READ_OPERATION,body=Buffer.from(wire),requests=[],charges=[],delivered=[];
  const scope=Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,name])),
    operation,resourceOrigin:'https://provider.invalid'});
  const credential={control:{identity:()=> 'explicit-page-grant'},journal:{
    claim(_cid,useId){return{use:{},record:{grantCid:'explicit-page-grant',useId},replayed:false};},
    authorize(){},finish(){}},resolveSecret:()=> 'explicit-secret'};
  const site={credential,referenceCurrent(){assert.equal(this,site);return true;},async callResource(input){
    assert.equal(this,site);requests.push(input.operations.get(operation));assert.equal(requests.length,1);
    return{accepted:statusCode===200,statusCode,body};}};
  const factory=createInstalledCredentialSourceReader({capacity:{},site,operation,maxResponses:1,
    maxResponseBytes:limits.maxResponseBytes,maxSecretBytes:64,
    preparePageReader(_options,apply){return prepareNotionPageReadPages({moon:notion,pageId:'page',limits},apply);}});
  const reader=factory.prepare({resource:'page',columns:[],async verifyRead(){},
    authorizationFor(index){assert.equal(index,0);return{grant:{},scope,useId:'original-page'};},
    chargePage(value){assert.equal(value,body);const charge=Object.freeze({body:value});charges.push(charge);afterCharge?.(reader);return charge;},
    consumePage(rows,{charge}){assert.equal(charge,charges[0]);delivered.push(...rows);}});
  return{reader,factory,body,requests,charges,delivered,close(){reader.requestStop();
    assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(factory.retire(),true);}};
}

test('real Notion page projection uses the shared owner and preserves exact original page metadata',async()=>{
  const wire=' \r\n'+JSON.stringify(originalPage())+'\n',f=openPage(wire);
  try{
    assert.deepEqual(await f.reader.read(),{pages:1,rowCount:1});
    assert.equal(f.requests[0].method,'GET');assert.equal(f.requests[0].path,'/v1/pages/page');
    assert(f.requests[0].headers.some(([name,value])=>name==='notion-version'&&value===NOTION_USER_LIST_API_VERSION));
    assert.equal(f.delivered.length,1);const{page,metadataWire}=f.delivered[0],metadata=JSON.parse(metadataWire);
    assert.equal(checked(notion.notionPageOriginalJson(page,16384)),wire);
    assert.deepEqual(metadata.parent,{type:'data_source_id',data_source_id:'s',database_id:'db'});
    assert.equal(metadata.resource,'page');assert.equal(metadata.version,'2026-10-17T00:00:00.123000Z');
    assert.equal(metadata.created_time,'2026-10-17T01:00:00.000Z');assert.equal(metadata.last_edited_time,'2026-10-17T00:00:00.123Z');
    assert.equal(f.charges.length,1);assert.equal(f.reader.observe().receivedBodyBytes,BigInt(f.body.length));
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  }finally{f.close();}
});

test('real Notion page projection keeps refusal and post-charge stop under the same shared cleanup',async()=>{
  for(const mode of ['identity','malformed','wire','rejected','stop']){
    const wire=mode==='identity'?JSON.stringify({...originalPage(),id:'foreign'}):mode==='malformed'?'{not-json':JSON.stringify(originalPage());
    const f=openPage(wire,{statusCode:mode==='rejected'?403:200,
      limits:mode==='wire'?{...pageLimits,maxWireBytes:1}:pageLimits,
      afterCharge:mode==='stop'?reader=>reader.requestStop():undefined});
    try{
      await assert.rejects(f.reader.read(),error=>mode==='rejected'?error.code==='NotionPageReadRejected':
        mode==='stop'?error.name==='AbortError':error.code==='MoonBitHostFailure');
      assert.equal(f.requests.length,1);assert.equal(f.charges.length,1);assert.equal(f.delivered.length,0);
      assert.equal(f.charges[0].body,f.body);
    }finally{f.close();}
  }
});

const propertyLimits=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:65536,maxTargetBytes:1024,
  maxPages:8,pageSize:10,maxValueNodes:128,maxValueDepth:16,maxValueTextBytes:4096,
  maxWireBytes:8192,maxWireNodes:256,maxWireDepth:16});
const metadataLimits=[16384,1024,20,8,8,128,128],declarationLimits=[...metadataLimits,256,16,4096,16,100000];
function propertyOriginal(enumeration){
  const database=checked(notion.notionProjectDatabase(Buffer.from('{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}'),...metadataLimits));
  const source=checked(notion.notionProjectDataSource(database,0,Buffer.from('{"object":"data_source","id":"s","parent":{"type":"database_id","database_id":"db"},"properties":{"text":{"id":"t%3Ax","name":"text","type":"rich_text","rich_text":{}}}}'),...metadataLimits));
  const contract={type:'string',nullable:false,...(enumeration===undefined?{}:{enum:enumeration})};
  const declaration=checked(notion.notionReadDatabaseDeclaration(Buffer.from(JSON.stringify({id:'db',read_contracts:{'t%3Ax':[{column:'text',projection:'value',contract}]}})),...declarationLimits));
  const readContracts=checked(notion.notionBindDataSourceReadContracts(declaration,source,...declarationLimits));
  const page=checked(notion.notionProjectQueryPage(source,Buffer.from('{"object":"list","type":"page_or_data_source","page_or_data_source":{},"results":[{"object":"page","id":"page","parent":{"type":"data_source_id","data_source_id":"s"},"properties":{"text":{"id":"t%3Ax","type":"rich_text","rich_text":[],"has_more":true}}}],"has_more":false,"next_cursor":null}'),...metadataLimits,100,128));
  const originalRequest=checked(notion.notionStartColumnPropertyRequest(readContracts,page,0,0,...metadataLimits,8,128,65536,4096,32768,128,1000000));
  return{moon:notion,readContracts,column:0,originalRequest,limits:propertyLimits};
}
function propertyResponse(text,next=null,type='rich_text'){
  return{accepted:true,statusCode:200,body:Buffer.from(JSON.stringify({object:'list',type:'property_item',
    results:text.map(plain=>({object:'property_item',id:'t%3Ax',type,[type]:{type:'text',text:{content:plain},plain_text:plain}})),
    has_more:next!==null,next_cursor:next,property_item:{id:'t%3Ax',type,[type]:{},next_url:next===null?null:'https://foreign.invalid/never-follow'}}))};
}

test('real Notion property projection preserves original cursor target and whole typed completion',()=>{
  const original=propertyOriginal(['é\r\n😀']),projection=prepareNotionPropertyReadProjection(original);
  const first=projection.describeRequest();assert.equal(first.method,'GET');assert.equal(first.path,'/v1/pages/page/properties/t%3Ax');
  assert.deepEqual(first.query,[['page_size','10']]);assert(first.headers.some(([k,v])=>k==='notion-version'&&v==='2026-03-11'));
  const prefix=projection.projectResponse(original.originalRequest,propertyResponse(['é\r\n'],'opaque+/= cursor'));
  assert.equal(prefix.done,false);assert.equal(Object.hasOwn(prefix,'valueWire'),false);
  const next=prefix.nextRequest();assert(notion.notionPropertyRequestMatchesBinding(next,original.readContracts,0));
  const second=projection.describeRequest(next);assert.equal(second.path,first.path);
  assert.deepEqual(second.query,[['page_size','10'],['start_cursor','opaque+/= cursor']]);
  const terminal=projection.projectResponse(next,propertyResponse(['😀']));
  assert.equal(terminal.done,true);assert.equal(terminal.valueWire,'"é\\r\\n😀"');assert.equal(Object.hasOwn(terminal,'nextRequest'),false);
});

test('real Notion property projection refuses copies foreign bindings incomplete values and unsafe bounds',()=>{
  const a=propertyOriginal(),b=propertyOriginal(),p=prepareNotionPropertyReadProjection(a);
  for(const originalRequest of [{...a.originalRequest},b.originalRequest]){
    assert.throws(()=>prepareNotionPropertyReadProjection({...a,originalRequest}),{code:'ForeignNotionPropertyOriginal'});
    assert.throws(()=>p.describeRequest(originalRequest),{code:'ForeignNotionPropertyOriginal'});
    assert.throws(()=>p.projectResponse(originalRequest,propertyResponse(['ignored'])),{code:'ForeignNotionPropertyOriginal'});
  }
  assert.throws(()=>prepareNotionPropertyReadProjection({...a,limits:{...propertyLimits,pageSize:101}}),{code:'InvalidNotionPropertyRead'});
  assert.throws(()=>prepareNotionPropertyReadProjection({...a,limits:{...propertyLimits,maxTargetBytes:1}}).describeRequest(),{code:'NotionPropertyTargetLimit'});
  assert.throws(()=>p.projectResponse(a.originalRequest,{accepted:false,statusCode:403,body:Buffer.from('{}')}),{code:'NotionPropertyReadRejected'});
  const e=propertyOriginal(['ab']),ep=prepareNotionPropertyReadProjection(e),prefix=ep.projectResponse(e.originalRequest,propertyResponse(['a'],'next'));
  assert.equal(prefix.done,false);assert.throws(()=>ep.projectResponse(prefix.nextRequest(),propertyResponse(['c'])),{code:'MoonBitHostFailure'});
});

test('real Notion property projection keeps title originals and captures provider methods and limits',()=>{
  const body={...originalPage(),properties:{'display name':{id:'t%3Ax',type:'title',title:[]}}};
  const pageTitle=checked(notion.notionProjectPage(Buffer.from(JSON.stringify(body)),'page',16384,1024,20,8,16,128,128,2048));
  const originalRequest=checked(notion.notionStartPageTitlePropertyRequest(pageTitle,16384,1024,20,8,16,128,128,8,128,65536,4096,32768,128,1000000));
  const moon={...notion},bounds={...propertyLimits},originalJson=moon.notionPropertyRequestJson;
  moon.notionPropertyRequestJson=function(...args){assert.equal(this,moon);return Reflect.apply(originalJson,notion,args);};
  const p=prepareNotionPropertyReadProjection({moon,originalRequest,pageTitle,limits:bounds});
  moon.notionPropertyRequestJson=moon.notionProjectPropertyItemPage=()=>assert.fail('late provider lookup');bounds.pageSize=99;
  assert.deepEqual(p.describeRequest().query,[['page_size','10']]);
  const terminal=p.projectResponse(originalRequest,propertyResponse(['original title'],null,'title'));
  assert.equal(terminal.done,true);assert.equal(terminal.valueWire,'"original title"');
  assert.throws(()=>prepareNotionPropertyReadProjection({moon:notion,originalRequest,pageTitle:{...pageTitle},limits:propertyLimits}),{code:'ForeignNotionPropertyOriginal'});
});

// Execute every original declaration of the actual data-source reader. Only
// its HTTPS send and dependent-property constructor are explicit ports. The
// scalar-only checked source must not enter the latter. No Host, Account,
// Credential issuer, native binding, RowRun or retirement is supplied here.
async function databaseRequestFixture(maxTotalRows){
  const file=new URL('../connectors/notion/site/data-source-read.mjs',import.meta.url),code=await readFile(file,'utf8');
  const declarations=parse(code,{ecmaVersion:'latest',sourceType:'module'}).body.flatMap(node=>{
    const value=node.declaration??node;
    return ['VariableDeclaration','FunctionDeclaration','ClassDeclaration'].includes(value.type)?[code.slice(value.start,value.end)]:[];
  }).join('\n');
  const operation='notion:data-sources:query',requests=[],grants=[],charges=[],rows=[],observations=[];
  const scope=Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name=>[name,name])),operation});
  const bodies=[['one','two'],['three']].map((ids,index)=>Buffer.from(JSON.stringify({object:'list',type:'page_or_data_source',
    page_or_data_source:{},results:ids.map(id=>({object:'page',id,parent:{type:'data_source_id',data_source_id:'s'},properties:{
      amount:{id:'n',type:'number',number:'EXACT'},enabled:{id:'b',type:'checkbox',checkbox:true}}})),
    has_more:index===0,next_cursor:index===0?'same-query-cursor':null}).replaceAll('"EXACT"','9007199254740993.25')));
  const physical=async input=>{
    await input.currentBeforeSend();const request=input.operations.get(operation);
    assert(request);requests.push(request);assert(requests.length<=bodies.length);
    return{accepted:true,statusCode:200,body:bodies[requests.length-1]};
  };
  const create=new Function('checked','ownInvocationContext','ownInvocationAuthorization','invocationBindingsMatch',
    'invokeScopedCredentialOperation','callHttpsCredentialResource','createNotionPropertyReader',
    'NOTION_PROPERTY_READ_OPERATION','NOTION_PROPERTY_READ_API_VERSION',declarations+'\nreturn createNotionDataSourceReader;')(
      checked,ownInvocationContext,ownInvocationAuthorization,invocationBindingsMatch,invokeScopedCredentialOperation,physical,
      ()=>assert.fail('complete scalar rows require no property child'),'notion:pages:property:read','2026-03-11');
  const database=checked(notion.notionProjectDatabase(Buffer.from('{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}'),...metadataLimits));
  const source=checked(notion.notionProjectDataSource(database,0,Buffer.from('{"object":"data_source","id":"s","parent":{"type":"database_id","database_id":"db"},"properties":{"amount":{"id":"n","name":"amount","type":"number","number":{"format":"number"}},"enabled":{"id":"b","name":"enabled","type":"checkbox","checkbox":{}}}}'),...metadataLimits));
  const declaration=checked(notion.notionReadDatabaseDeclaration(Buffer.from('{"id":"db","read_contracts":{"n":[{"column":"amount","projection":"value","contract":{"type":"decimal","nullable":false,"precision":20,"scale":2}}]}}'),...declarationLimits));
  const readContracts=checked(notion.notionBindDataSourceReadContracts(declaration,source,...declarationLimits));
  const bounds={maxResponseBytes:16384,maxTotalResponseBytes:131072,maxRequestBytes:1024,maxTargetBytes:1024,
    maxPages:4,pageSize:2,maxTotalRows,maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:8,
    maxIdentityBytes:128,maxNameBytes:128,maxCursorBytes:128,maxRowNodes:256,maxRowDepth:16,maxRowTextBytes:4096,
    maxColumns:16,maxRowWork:1000000,maxPageWork:1000000,maxRowsWireBytes:16384,maxRowsWireNodes:2048,maxRowsWireDepth:20,
    maxPropertyPages:4,maxPropertyItems:128,maxPropertyBytes:65536,maxPropertyNodes:4096,maxPropertyTextBytes:32768,maxPropertyWork:1000000};
  const reader=create({moon:notion,declaration,source,readContracts,initialAuthorization:{grant:{},scope,useId:'original'},
    credential:{binding:{}},limits:bounds,async current(value){assert.equal(value,operation);},
    authorizationFor(input){assert.equal(input.operation,operation);grants.push(input);return{grant:{},scope,useId:`query-${input.index}`};},
    chargeResponse(body){assert.equal(body,bodies[requests.length-1]);const ticket=Object.freeze({body});charges.push(ticket);return ticket;},
    consumeObservation(charge){assert(charges.includes(charge));observations.push(charge);},
    consumePage(page,{charge,originalRows,readContracts:actual}){assert.equal(actual,readContracts);assert.equal(originalRows.length,page.length);
      assert.equal(charge,charges.at(-1));rows.push(...page);observations.push(charge);}});
  return{reader,requests,grants,charges,rows,observations,bodies};
}

test('actual extracted Notion database caller requests only remaining rows on its original query cursor',async()=>{
  const f=await databaseRequestFixture(3),result=await f.reader.read();
  assert.equal(result.rowCount,3);assert.equal(result.pages,2);
  assert.deepEqual(f.requests.map(request=>JSON.parse(request.body)),[{page_size:2},{page_size:1,start_cursor:'same-query-cursor'}]);
  assert(f.requests.every(request=>request.method==='POST'&&request.path==='/v1/data_sources/s/query'));
  assert.deepEqual(f.rows,[{amount:'9007199254740993.25',enabled:true},{amount:'9007199254740993.25',enabled:true},{amount:'9007199254740993.25',enabled:true}]);
  assert.equal(f.grants.length,2);assert.deepEqual(result.responseCharges,f.charges);
  assert.equal(f.reader.observe().cleanupConfirmed,false);
});

test('actual extracted Notion database caller refuses a capped continuation before another grant or POST',async()=>{
  const f=await databaseRequestFixture(2);
  await assert.rejects(f.reader.read(),error=>error.code==='NotionDataSourceReadFailed'&&error.cause.code==='NotionDataSourceRowLimit');
  assert.equal(f.requests.length,1);assert.equal(f.grants.length,1);assert.equal(f.charges.length,1);
  assert.equal(f.reader.observe().phase,'failed');assert.equal(f.reader.observe().cleanupConfirmed,false);
  assert.equal(f.rows.length,2,'an earlier prefix is retained, never a successful complete Source');
});
