import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {createNotionPageReader,NOTION_PAGE_READ_OPERATION} from '../site/page-read.mjs';
import {createNotionPageTitleReader,createNotionPropertyReader,NOTION_PROPERTY_READ_OPERATION,
  NOTION_PROPERTY_READ_API_VERSION} from '../site/property-item-read.mjs';
import {propertyReadFixture,propertyReadLimits} from './property-item-read.fixture.mjs';

const metadata=[16384,1024,20,8,16,128,128];
const pageLimits=Object.freeze({maxRequestBytes:1024,maxResponseBytes:16384,maxTargetBytes:1024,
  maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:16,maxIdentityBytes:128,
  maxNameBytes:128,maxTextBytes:2048,maxWireBytes:4096,maxWireNodes:128,maxWireDepth:8});
const requestLimits=[...metadata,8,128,65536,4096,32768,128,1000000];
function pageBody(){return{object:'page',id:'page',parent:{type:'workspace',workspace:true},
  url:'https://notion.example/page',created_by:{object:'user',id:'creator'},last_edited_by:{object:'user',id:'editor'},
  created_time:'2026-10-17T00:00:00Z',last_edited_time:'2026-10-17T00:00:00.123000Z',in_trash:false,
  properties:{'arbitrary display name':{id:'t%3Ax',type:'title',title:[{type:'text',text:{content:'fragment'},plain_text:'fragment'}]}}};}
function titleBody(text,cursor=null){return{object:'list',type:'property_item',results:text.map(plain=>({
  object:'property_item',id:'t%3Ax',type:'title',title:{type:'text',text:{content:plain},plain_text:plain},
})),has_more:cursor!==null,next_cursor:cursor,property_item:{id:'t%3Ax',type:'title',title:{},
  next_url:cursor===null?null:'https://foreign.example/never-follow'}};}
async function fixture(t){
  const f=await propertyReadFixture(t,{additionalOperations:[NOTION_PAGE_READ_OPERATION]});
  const bodies=[titleBody(['é\r\n'],'opaque+/= cursor'),titleBody(['😀'])];
  f.state.respond=request=>request.url==='/v1/pages/page'?pageBody():
    bodies[new URL(request.url,'https://localhost').searchParams.has('start_cursor')?1:0];
  const pageReader=createNotionPageReader({moon:f.options.moon,pageId:'page',
    initialAuthorization:f.authorize(NOTION_PAGE_READ_OPERATION,'page-title-original'),credential:f.options.credential,
    current:f.current,chargeResponse:f.options.chargeResponse,consumeObservation:f.options.consumeObservation,limits:pageLimits});
  const original=await pageReader.read();
  const request=checked(f.options.moon.notionStartPageTitlePropertyRequest(original.page,...requestLimits));
  const {readContracts:unused,column:unusedColumn,...propertyOptions}=f.options;
  const options={...propertyOptions,pageTitle:original.page,originalRequest:request};
  return{...f,bodies,original,pageReader,request,options,title:overrides=>createNotionPageTitleReader({...options,...overrides})};
}

test('actual original Page GET and separately scoped title pages complete without a synthetic data-source row',async t=>{
  const f=await fixture(t),reader=f.title(),result=await reader.read();
  assert.equal(JSON.parse(f.original.metadataWire).parent.type,'workspace');
  assert.equal(result.valueWire,'"é\\r\\n😀"');assert.equal(result.pages,2);
  assert.deepEqual(f.state.requests.map(x=>x.path),['/v1/pages/page',
    '/v1/pages/page/properties/t%3Ax?page_size=10',
    '/v1/pages/page/properties/t%3Ax?page_size=10&start_cursor=opaque%2B%2F%3D%20cursor']);
  assert(f.state.requests.every(x=>x.method==='GET'&&x.version==='2026-03-11'&&x.authorization==='Bearer notion-fixture-token'));
  assert.equal(f.state.resolutions,3);assert.equal(f.journal.recover().filter(x=>x.outcome==='succeeded').length,3);
  assert.deepEqual(f.state.values,[result.valueWire]);assert.equal(f.state.observations.length,2);
  assert.equal(f.pageReader.observe().cleanupConfirmed,false);assert.equal(reader.observe().cleanupConfirmed,false);
  assert.equal(f.options.moon.notionPropertyRequestMatchesPageTitle(f.request,f.original.page),true);
  await assert.rejects(reader.read(),{code:'NotionPropertyReaderAlreadyStarted'});
});

test('actual title receiver rejects foreign copied query originals and page-operation grants before property I/O',async t=>{
  const f=await fixture(t),moon=f.options.moon;
  const equal=checked(moon.notionProjectPage(Buffer.from(JSON.stringify(pageBody())),'page',...metadata,2048));
  for(const pageTitle of [equal,{...f.original.page}])assert.throws(()=>f.title({pageTitle}),{code:'ForeignNotionPropertyOriginal'});
  assert.throws(()=>f.title({originalRequest:{...f.request}}),{code:'ForeignNotionPropertyOriginal'});
  assert.throws(()=>f.title({originalRequest:f.originals.request}),{code:'ForeignNotionPropertyOriginal'});
  assert.throws(()=>f.title({readContracts:f.originals.binding,column:0}),{code:'InvalidNotionPropertyRead'});
  assert.throws(()=>createNotionPropertyReader({...f.options,readContracts:f.originals.binding,column:0}),{code:'InvalidNotionPropertyRead'});
  assert.throws(()=>f.title({initialAuthorization:f.authorize(NOTION_PAGE_READ_OPERATION,'not-property')}),{code:'ForeignNotionPropertyOperation'});
  const reader=f.title(),copy={...reader};await assert.rejects(copy.read(),{code:'ForeignNotionPropertyReader'});
  assert.throws(()=>copy.observe(),{code:'ForeignNotionPropertyReader'});reader.requestStop();
  await assert.rejects(reader.read(),{code:'NotionPropertyReadFailed'});
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.deepEqual(f.state.values,[]);
});

test('actual completed empty title is empty String rather than the inline fragment',async t=>{
  const f=await fixture(t);f.bodies[0]=titleBody([]);
  const result=await f.title().read();assert.equal(result.pages,1);assert.equal(result.valueWire,'""');
  assert.equal(f.state.requests.length,2);assert.deepEqual(f.state.values,['""']);
});

test('actual title cycle mismatch response exhaustion and incomplete chain never publish partial text',async t=>{
  for(const mode of ['cycle','foreign','item','status','limit','bytes']){
    const f=await fixture(t);let overrides={};
    if(mode==='cycle')f.bodies[1]=titleBody(['later'],'opaque+/= cursor');
    if(mode==='foreign')f.bodies[0].property_item.id='other';
    if(mode==='item')f.bodies[0].results[0].title.plain_text=null;
    if(mode==='status')f.state.status=403;
    if(mode==='limit')overrides={limits:{...propertyReadLimits,maxPages:1}};
    if(mode==='bytes')overrides={limits:{...propertyReadLimits,maxTotalResponseBytes:
      f.bodies.reduce((n,p)=>n+Buffer.byteLength(JSON.stringify(p)),0)-1}};
    const reader=f.title(overrides);let failure;
    await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionPropertyReadFailed';});
    assert.deepEqual(f.state.values,[],mode);assert.equal(reader.observe().cleanupConfirmed,false);
    assert(failure.observations.length>0);assert.equal(failure.observations.at(-1).body.toString(),
      JSON.stringify(f.bodies[failure.observations.length-1]));
    assert.equal(f.state.requests.length,mode==='cycle'||mode==='bytes'?3:2);
  }
});

test('actual title current checks after secret and response retain original raw custody without delivery',async t=>{
  const changed=await fixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.title().read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,1);assert.deepEqual(changed.state.values,[]);
  const stopped=await fixture(t),stop=new AbortController(),cause=new Error('OriginalTitleStop');let raw;
  const reader=stopped.title({signal:stop.signal,chargeResponse:body=>{raw=body;const ticket=stopped.options.chargeResponse(body);stop.abort(cause);return ticket;}});
  await assert.rejects(reader.read(),error=>error.cause===cause&&error.observations[0].body===raw);
  assert.equal(stopped.state.requests.length,2);assert.deepEqual(stopped.state.values,[]);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual title lost terminal reply stays original Unknown and cannot resend or refresh secret',async t=>{
  const f=await fixture(t);f.state.beforeResponse=request=>{if(request.url.includes('start_cursor'))request.socket.destroy();};
  const reader=f.title();await assert.rejects(reader.read(),error=>error.cause.code==='ECONNRESET');
  const unknown=f.journal.recover().find(x=>x.outcome==='unknown');assert(unknown);
  const before=f.state.resolutions;
  await assert.rejects(invokeScopedCredentialOperation({authorization:{grant:f.grant,scope:f.scope,useId:'property-1'},
    credential:f.options.credential,callResource:callHttpsCredentialResource,operation:NOTION_PROPERTY_READ_OPERATION,
    method:'GET',path:'/v1/pages/page/properties/t%3Ax',query:[['page_size','10'],['start_cursor','opaque+/= cursor']],
    headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],maxResponseBytes:16384}),{code:'RemoteCredentialUseAlreadyClaimed'});
  await assert.rejects(reader.read(),{code:'NotionPropertyReaderAlreadyStarted'});
  assert.equal(f.journal.inspect(unknown.useCid).outcome,'unknown');assert.equal(f.state.requests.length,3);
  assert.equal(f.state.resolutions,before);assert.deepEqual(f.state.values,[]);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual title compiled callbacks and their original receiver are captured once across awaits',async t=>{
  const f=await fixture(t),moon={},reads=new Map();
  const names=['notionPropertyRequestJson','notionProjectPropertyItemPage','notionPropertyItemPageComplete',
    'notionNextPropertyRequest','notionPropertyRequestMatchesPageTitle','notionCompletedPageTitleJson'];
  for(const name of names){const fn=f.options.moon[name];Object.defineProperty(moon,name,{configurable:true,get(){
    reads.set(name,(reads.get(name)??0)+1);return function(...args){assert.equal(this,moon);return Reflect.apply(fn,f.options.moon,args);};
  }});}
  const reader=f.title({moon});f.state.resolved=()=>{for(const name of names)Object.defineProperty(moon,name,{value:()=>{throw new Error('replacement callback');},configurable:true});};
  assert.equal((await reader.read()).valueWire,'"é\\r\\n😀"');
  for(const name of names)assert.equal(reads.get(name),1);
});
