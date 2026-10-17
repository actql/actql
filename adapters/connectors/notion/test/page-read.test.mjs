import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {propertyReadFixture} from './property-item-read.fixture.mjs';
import {createNotionPageReader,NOTION_PAGE_READ_OPERATION as operation} from '../site/page-read.mjs';

const limits=Object.freeze({maxRequestBytes:1024,maxResponseBytes:16384,maxTargetBytes:1024,
  maxNodes:1024,maxDepth:20,maxDataSources:8,maxProperties:16,maxIdentityBytes:128,
  maxNameBytes:128,maxTextBytes:2048,maxWireBytes:4096,maxWireNodes:128,maxWireDepth:8});
function originalPage(){return{object:'page',id:'page',parent:{type:'data_source_id',data_source_id:'s',database_id:'db'},
  url:'https://notion.example/page',created_by:{object:'user',id:'creator'},last_edited_by:{object:'user',id:'editor'},
  created_time:'2026-10-17T10:00:00+09:00',last_edited_time:'2026-10-17T00:00:00.123000Z',in_trash:false,
  properties:{title:{id:'title',type:'title',title:[]}}};}
async function fixture(t,options){
  const f=await propertyReadFixture(t,{...options,additionalOperations:[operation]});
  f.state.respond=()=>originalPage();
  const original={moon:f.options.moon,pageId:'page',initialAuthorization:f.authorize(operation,'original-page'),
    credential:f.options.credential,current:f.current,chargeResponse:f.options.chargeResponse,
    consumeObservation:f.options.consumeObservation,limits};
  return{...f,original,page:overrides=>createNotionPageReader({...original,...overrides})};
}

test('actual Notion exact-page GET retains the original response parent version and checked UTC metadata',async t=>{
  const f=await fixture(t),wire=' \r\n'+JSON.stringify(originalPage())+'\n';f.state.respond=()=>wire;
  const reader=f.page(),result=await reader.read(),data=JSON.parse(result.metadataWire);
  assert.deepEqual(f.state.requests.map(x=>[x.method,x.path,x.body,x.version]),[['GET','/v1/pages/page','','2026-03-11']]);
  assert.deepEqual(data.parent,{type:'data_source_id',data_source_id:'s',database_id:'db'});
  assert.equal(data.version,'2026-10-17T00:00:00.123000Z');assert.equal(data.last_edited_time,'2026-10-17T00:00:00.123Z');
  assert.equal(data.created_time,'2026-10-17T01:00:00.000Z');assert.equal(data.resource,'page');
  assert.equal(checked(f.options.moon.notionPageOriginalJson(result.page,16384)),wire);
  assert.equal(result.responseCharge,f.state.charges[0]);assert.equal(result.observation.body.toString(),wire);
  assert.deepEqual(f.state.observations,[result.responseCharge]);assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'NotionPageAlreadyStarted'});assert.equal(f.state.requests.length,1);
});

test('actual Notion exact-page reader refuses unsafe targets foreign operations and copied JS handles before I/O',async t=>{
  const f=await fixture(t);
  for(const pageId of ['', '.', '..', '\ud800'])assert.throws(()=>f.page({pageId}),{code:'InvalidNotionPageCoordinate'});
  assert.throws(()=>f.page({pageId:'x'.repeat(1025)}),{code:'NotionPageTargetLimit'});
  assert.throws(()=>f.page({initialAuthorization:{grant:f.grant,scope:f.scope,useId:'wrong'}}),{code:'ForeignNotionPageOperation'});
  const reader=f.page();await assert.rejects(Reflect.apply(reader.read,Object.freeze({}),[]),{code:'ForeignNotionPageReader'});
  reader.requestStop();await assert.rejects(reader.read(),{code:'NotionPageReadFailed'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual Notion rejected page identity malformed response and output exhaustion retain the original body and charge',async t=>{
  for(const kind of ['identity','malformed','wire']){
    const f=await fixture(t),wire=kind==='identity'?JSON.stringify({...originalPage(),id:'foreign'}):
      kind==='malformed'?'{not-json':JSON.stringify(originalPage());f.state.respond=()=>wire;
    const reader=f.page(kind==='wire'?{limits:{...limits,maxWireBytes:1}}:{});let failure;
    await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionPageReadFailed'&&error.cause.code==='MoonBitHostFailure';});
    assert.equal(failure.observation.body.toString(),wire);assert.equal(failure.responseCharge,f.state.charges[0]);
    assert.equal(f.state.observations.length,0);assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'NotionPageAlreadyStarted'});assert.equal(f.state.requests.length,1);
  }
});

test('actual Notion page authorization stays current before I/O and after original secret resolution',async t=>{
  const denied=await fixture(t,{account:'deny'});await assert.rejects(denied.page().read(),error=>error.cause.code==='NotionPropertyDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await fixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.page().read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);
});

test('actual Notion page current or stop refusal after response retains raw custody without publication',async t=>{
  for(const kind of ['account','stop']){
    const f=await fixture(t),stop=new AbortController();
    const reader=f.page({signal:stop.signal,chargeResponse:async body=>{
      const charge=f.options.chargeResponse(body);if(kind==='account')await f.writeAccount('deny');else stop.abort();return charge;
    }});let failure;await assert.rejects(reader.read(),error=>{failure=error;return error.code==='NotionPageReadFailed';});
    assert.equal(failure.observation.body.toString(),JSON.stringify(originalPage()));assert.equal(failure.responseCharge,f.state.charges[0]);
    assert.equal(f.state.observations.length,0);assert.equal(f.state.requests.length,1);assert.equal(reader.observe().cleanupConfirmed,false);
    if(kind==='account')assert.equal(failure.cause.code,'AuthorizationCurrentAccountChanged');else assert.equal(failure.cause.name,'AbortError');
  }
});

test('actual Notion lost page reply keeps the original use Unknown across another reader without resend',async t=>{
  const f=await fixture(t);f.state.beforeResponse=request=>request.socket.destroy();
  const reader=f.page();await assert.rejects(reader.read(),{code:'NotionPageReadFailed'});
  const original=f.journal.recover().find(x=>x.outcome==='unknown');assert(original);
  const resolutions=f.state.resolutions;await assert.rejects(f.page().read(),error=>error.cause.code==='RemoteCredentialUseAlreadyClaimed');
  await assert.rejects(reader.read(),{code:'NotionPageAlreadyStarted'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');assert.equal(f.state.requests.length,1);
  assert.equal(f.state.resolutions,resolutions);assert.equal(reader.observe().cleanupConfirmed,false);
});
