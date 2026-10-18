import assert from 'node:assert/strict';
import test from 'node:test';
import {NotionPropertyReadFailure,NOTION_PROPERTY_READ_OPERATION,NOTION_PROPERTY_READ_API_VERSION} from '../site/property-item-read.mjs';
import {propertyReadFixture,propertyItemPage,propertyOriginals} from './property-item-read.fixture.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const paths=['/v1/pages/page/properties/t%3Ax?page_size=10',
  '/v1/pages/page/properties/t%3Ax?page_size=10&start_cursor=opaque%2B%2F%3D%20cursor'];

test('actual original Notion property Credential pages complete typed text without following next_url',async t=>{
  const f=await propertyReadFixture(t),reader=f.create(),result=await reader.read();
  assert.equal(result.pages,2);assert.equal(result.valueWire,'"é\\r\\n😀"');
  assert.deepEqual(f.state.values,[result.valueWire]);
  assert.deepEqual(f.state.requests.map(x=>x.path),paths);
  assert(f.state.requests.every(x=>x.method==='GET'&&x.version===NOTION_PROPERTY_READ_API_VERSION&&x.authorization==='Bearer notion-fixture-token'));
  assert.equal(NOTION_PROPERTY_READ_API_VERSION,'2026-03-11');
  assert.equal(f.state.resolutions,2);assert.equal(f.state.charges.length,2);
  assert.equal(f.state.observations.length,1,'prefix observation differs from terminal value ticket');
  assert.equal(f.journal.recover().filter(x=>x.outcome==='succeeded').length,2);
  assert.equal(reader.observe().cleanupConfirmed,false,'protocol completion never retires raw custody');
  assert.equal(reader.observe().receivedBodyBytes,BigInt(result.observations.reduce((n,x)=>n+x.body.length,0)));
});

test('actual complete text is checked once against its whole original enum, including empty terminal pages',async t=>{
  const f=await propertyReadFixture(t,{enumeration:['ab']});
  f.state.pages=[propertyItemPage(['a'],'opaque+/= cursor'),propertyItemPage(['b'])];
  assert.equal((await f.create().read()).valueWire,'"ab"');
  const empty=await propertyReadFixture(t);empty.state.pages=[propertyItemPage([],'opaque+/= cursor'),propertyItemPage([])];
  assert.equal((await empty.create().read()).valueWire,'""');
  const wrong=await propertyReadFixture(t,{enumeration:['ab']});
  await assert.rejects(wrong.create().read(),error=>error instanceof NotionPropertyReadFailure&&error.observations.length===2);
  assert.deepEqual(wrong.state.values,[]);
});

test('original property opaque page snapshots survive external byte mutation without changing requests or source',()=>{
  const original=propertyOriginals(),wire=JSON.stringify(propertyItemPage(['first'],'opaque+/= cursor')),bytes=Buffer.from(wire);
  const first=checked(provider.notionProjectPropertyItemPage(original.request,bytes));
  bytes.fill(0);
  assert.equal(checked(provider.notionPropertyItemOriginalJson(first,8192)),wire);
  assert.equal(provider.notionPropertyItemPageComplete(first),false);
  const next=checked(provider.notionNextPropertyRequest(first));
  assert.deepEqual(JSON.parse(checked(provider.notionPropertyRequestJson(next,1024,16,4))),{pageId:'page',propertyId:'t%3Ax',cursor:'opaque+/= cursor'});
  const terminal=checked(provider.notionProjectPropertyItemPage(next,Buffer.from(JSON.stringify(propertyItemPage(['second'])))));
  assert.equal(checked(provider.notionCompletedPropertyJson(original.binding,terminal,0,128,16,4096,8192,256,16)),'"firstsecond"');
  assert.throws(()=>checked(provider.notionCompletedPropertyJson(propertyOriginals().binding,terminal,0,128,16,4096,8192,256,16)),{code:'MoonBitHostFailure'});
});

test('foreign original binding and copied reader cannot select another property or dispatch',async t=>{
  const f=await propertyReadFixture(t);
  assert.throws(()=>f.create({readContracts:propertyOriginals().binding}),{code:'ForeignNotionPropertyOriginal'});
  assert.throws(()=>f.create({column:1}),{code:'ForeignNotionPropertyOriginal'});
  const reader=f.create(),copy={...reader};
  await assert.rejects(copy.read(),{code:'ForeignNotionPropertyReader'});
  assert.throws(()=>copy.observe(),{code:'ForeignNotionPropertyReader'});
  assert.throws(()=>copy.requestStop(),{code:'ForeignNotionPropertyReader'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('compiled original property controls refuse copied requests and pages across the private Node port',()=>{
  const original=propertyOriginals(),copiedRequest={...original.request};
  assert.equal(provider.notionPropertyRequestMatchesBinding(copiedRequest,original.binding,0),false);
  assert.throws(()=>checked(provider.notionPropertyRequestJson(copiedRequest,1024,16,4)),{code:'MoonBitHostFailure'});
  const bytes=Buffer.from(JSON.stringify(propertyItemPage(['first'],'opaque+/= cursor')));
  assert.throws(()=>checked(provider.notionProjectPropertyItemPage(copiedRequest,bytes)),{code:'MoonBitHostFailure'});
  const first=checked(provider.notionProjectPropertyItemPage(original.request,bytes)),copiedFirst={...first};
  assert.equal(provider.notionPropertyItemPageComplete(copiedFirst),false);
  assert.throws(()=>checked(provider.notionNextPropertyRequest(copiedFirst)),{code:'MoonBitHostFailure'});
  assert.throws(()=>checked(provider.notionPropertyItemOriginalJson(copiedFirst,8192)),{code:'MoonBitHostFailure'});
  const next=checked(provider.notionNextPropertyRequest(first));
  const terminal=checked(provider.notionProjectPropertyItemPage(next,Buffer.from(JSON.stringify(propertyItemPage(['second'])))));
  assert.equal(provider.notionPropertyItemPageComplete(terminal),true);
  assert.equal(provider.notionPropertyItemPageComplete({...terminal}),false);
  assert.throws(()=>checked(provider.notionCompletedPropertyJson(original.binding,{...terminal},0,128,16,4096,8192,256,16)),{code:'MoonBitHostFailure'});
  assert.equal(checked(provider.notionCompletedPropertyJson(original.binding,terminal,0,128,16,4096,8192,256,16)),'"firstsecond"');
});

test('actual property cursor cycles, response/item mismatch and nonterminal limits refuse before value delivery',async t=>{
  for(const mode of ['cycle','foreign','pair','limit','item','status']){
    const f=await propertyReadFixture(t);
    if(mode==='cycle')f.state.pages[1]=propertyItemPage(['second'],'opaque+/= cursor');
    if(mode==='foreign')f.state.pages[0].property_item.id='foreign';
    if(mode==='pair')f.state.pages[0].has_more=false;
    if(mode==='item')f.state.pages[0].results[0].rich_text.plain_text=null;
    if(mode==='status')f.state.status=403;
    await assert.rejects(f.create(mode==='limit'?{limits:{...f.options.limits,maxPages:1}}:{}).read(),error=>error instanceof NotionPropertyReadFailure);
    assert.deepEqual(f.state.values,[],mode);
    assert.equal(f.state.requests.length,mode==='cycle'?2:1);
  }
});

test('actual property aggregate raw budget retains the exact offending response and never returns a partial cell',async t=>{
  const f=await propertyReadFixture(t),total=f.state.pages.reduce((n,p)=>n+Buffer.byteLength(JSON.stringify(p)),0);
  await assert.rejects(f.create({limits:{...f.options.limits,maxTotalResponseBytes:total-1}}).read(),error=>
    error.cause.code==='NotionPropertyResponseLimit'&&error.observations.length===2&&error.observations[1].body.toString()===JSON.stringify(f.state.pages[1]));
  assert.equal(f.state.charges.length,2);assert.deepEqual(f.state.values,[]);
  assert.equal(f.state.observations.length,1);
});

test('actual property Account/current checks remain independent before I/O and after secret resolution',async t=>{
  const denied=await propertyReadFixture(t,{account:'deny'});
  await assert.rejects(denied.create().read(),error=>error.cause.code==='NotionPropertyDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await propertyReadFixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.create().read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);
});

test('actual property token generation and original operation binding cannot change across pages',async t=>{
  const f=await propertyReadFixture(t);f.state.resolved=()=>{if(f.state.resolutions===2)f.state.secret='replacement-token';};
  await assert.rejects(f.create().read(),error=>error.cause.code==='RemoteCredentialBindingChanged'&&error.observations.length===1);
  assert.equal(f.state.requests.length,1);assert.deepEqual(f.state.values,[]);
  const foreign=await propertyReadFixture(t),original=foreign.options.authorizationFor;
  await assert.rejects(foreign.create({authorizationFor:input=>({...original(input),scope:{...foreign.scope,operation:'notion:foreign'}})}).read(),error=>error.cause.code==='ForeignNotionPropertyAuthorization');
  assert.equal(foreign.state.requests.length,0);assert.equal(foreign.state.resolutions,0);
});

test('actual property lost reply remains original journal Unknown with no resend or replacement token resolution',async t=>{
  const f=await propertyReadFixture(t);f.state.beforeResponse=request=>request.socket.destroy();
  const reader=f.create();await assert.rejects(reader.read(),error=>error.cause.code==='ECONNRESET');
  const original=f.journal.recover().find(x=>x.outcome==='unknown');assert(original);
  await assert.rejects(invokeScopedCredentialOperation({authorization:{grant:f.grant,scope:f.scope,useId:'property-0'},
    credential:f.options.credential,callResource:callHttpsCredentialResource,operation:NOTION_PROPERTY_READ_OPERATION,
    method:'GET',path:'/v1/pages/page/properties/t%3Ax',query:[['page_size','10']],
    headers:[['accept','application/json'],['notion-version',NOTION_PROPERTY_READ_API_VERSION]],maxResponseBytes:16384}),{code:'RemoteCredentialUseAlreadyClaimed'});
  await assert.rejects(reader.read(),{code:'NotionPropertyReaderAlreadyStarted'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
  assert.equal(reader.observe().cleanupConfirmed,false);
});

test('actual property original functions and bounds are snapshotted and stop preserves raw custody',async t=>{
  const f=await propertyReadFixture(t),moon={...f.options.moon},limits={...f.options.limits};let getterReads=0;
  const project=moon.notionProjectPropertyItemPage;
  Object.defineProperty(moon,'notionProjectPropertyItemPage',{get(){getterReads++;return getterReads===1?project:()=>{throw new Error('second getter');};}});
  f.state.resolved=()=>{limits.maxPages=1;limits.maxTotalResponseBytes=1;};
  assert.equal((await f.create({moon,limits}).read()).pages,2);assert.equal(getterReads,1);
  const stopped=await propertyReadFixture(t),controller=new AbortController(),cause=new Error('OriginalNotionStop');let raw;
  const reader=stopped.create({signal:controller.signal,chargeResponse:body=>{raw=body;controller.abort(cause);return stopped.options.chargeResponse(body);}});
  await assert.rejects(reader.read(),error=>error.cause===cause&&error.observations[0].body===raw);
  assert.equal(stopped.state.requests.length,1);assert.deepEqual(stopped.state.values,[]);
  assert.equal(reader.observe().stopRequested,true);assert.equal(reader.observe().cleanupConfirmed,false);
});

for(const mode of ['revoke','stop'])test(`actual property ${mode} after partial observation refuses the next Common request`,async t=>{
  const f=await propertyReadFixture(t),moon={...f.options.moon},cause=new Error('OriginalPropertyObservationInvalidated');
  let nextRequests=0,invalid=false,reader;
  moon.notionNextPropertyRequest=function(...args){nextRequests++;return Reflect.apply(f.options.moon.notionNextPropertyRequest,f.options.moon,args);};
  reader=f.create({moon,current:async()=>{if(invalid)throw cause;await f.current();},
    consumeObservation:async charge=>{f.options.consumeObservation(charge);await Promise.resolve();
      if(mode==='revoke')invalid=true;else reader.requestStop(cause);}});
  let failure;await assert.rejects(reader.read(),error=>{failure=error;return error.cause===cause;});
  assert.equal(nextRequests,0);assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);
  assert.deepEqual(f.state.values,[]);assert.equal(failure.observations.length,1);
  assert.equal(failure.observations[0].body,f.state.charges[0].originalBody);
  assert.equal(f.state.observations[0],f.state.charges[0]);
  assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'NotionPropertyReaderAlreadyStarted'});
});
