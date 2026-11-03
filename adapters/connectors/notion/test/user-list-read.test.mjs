import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {NotionUserListReadFailure, NOTION_USER_LIST_OPERATION,
  NOTION_USER_LIST_API_VERSION} from '../site/user-list-read.mjs';
import {userListFixture, userPage} from './user-list-read.fixture.mjs';

const one={id:'U1',name:'one',type:'person',email:'one@example.test'};
const two={id:'U2',name:'two',type:'bot',email:null};
const user=(id,name)=>({object:'user',id,name});
const originalPaths=['/v1/users?page_size=10',
  '/v1/users?page_size=10&start_cursor=opaque%2B%2F%3D%20cursor'];

test('Notion actual SQL and AQL original paged Credential reads capture person and bot rows',async t=>{
  for(const format of ['sql','aql']){
    const f=await userListFixture(t,{format}),reader=f.create(),result=await reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,[one,two]);
    assert.deepEqual(f.state.requests.map(x=>x.path),originalPaths);
    assert(f.state.requests.every(x=>x.method==='GET'&&x.body.length===0&&x.contentType===undefined));
    assert(f.state.requests.every(x=>x.notionVersion===NOTION_USER_LIST_API_VERSION&&
      x.authorization==='Bearer notion-fixture-token'));
    assert.equal(NOTION_USER_LIST_API_VERSION,'2026-03-11');
    assert.equal(f.state.resolutions,2);assert.equal(f.state.charges,2);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,reader.observe().receivedBodyBytes);
    assert.equal(reader.observe().transportClosed,false);reader.requestStop();
    f.row.finish();assert.equal(f.row.captureCount(),2);
    assert.deepEqual(f.journal.recover().map(x=>x.outcome),['succeeded','succeeded']);
    assert.equal(new Set(f.journal.recover().map(x=>x.grantCid)).size,1);
    assert.equal(reader.observe().cleanupConfirmed,true);
  }
});

test('Notion empty continued page keeps the opaque cursor while an empty terminal page finishes',async t=>{
  const f=await userListFixture(t);
  f.state.pages=[userPage([],'opaque+/= cursor'),userPage([],null)];
  const reader=f.create(),result=await reader.read();reader.requestStop();
  assert.equal(result.pages,2);assert.equal(result.rowCount,0);
  assert.deepEqual(f.state.requests.map(x=>x.path),originalPaths);
  f.row.finish();assert.equal(f.row.captureCount(),0);
});

test('Notion page meaning and Host callbacks refuse invalid selections before I/O',async t=>{
  const f=await userListFixture(t);
  for(const override of [{names:['foreign']},{names:['id','id']},{names:Array(1000).fill('id')},
    {limits:{...f.options.limits,pageSize:101}}]) {
    await assert.rejects(async()=>f.create(override).read(),e=>e.code==='InvalidNotionUserListRead');
  }
  for(const override of [{current:undefined},{chargeResponse:undefined},{consumePage:undefined}])
    assert.throws(()=>f.create(override),{code:'InstalledSourceReaderMethodUnavailable'});
  assert.throws(()=>f.create({limits:{...f.options.limits,maxPages:0}}),{code:'InvalidInstalledCredentialSourceReader'});
  await assert.rejects(f.create({authorizationFor:({index})=>({grant:f.grant,
    scope:{...f.scope,operation:'notion:pages:foreign'},useId:`foreign-${index}`})}).read(),
    e=>e.cause?.code==='ForeignInstalledSourceReaderAuthorization');
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('Notion original operation and invocation cannot be replaced by a foreign scope or nominal grant',async t=>{
  for(const mode of ['parent','origin','grant']){
    const f=await userListFixture(t),original=f.options.authorizationFor;
    const foreign=f.control.prepare({...f.scope,principal:'foreign'});
    f.journal.acceptGrant(f.sign(foreign),f.control);
    const authorizationFor=input=>mode==='parent'
      ?{...original(input),scope:{...f.scope,dispatchRequestCid:`sha256:${'d'.repeat(64)}`}}
      :mode==='origin'?{...original(input),scope:{...f.scope,resourceOrigin:'https://foreign.example.test'}}
      :{...original(input),grant:foreign};
    await assert.rejects(f.create({authorizationFor}).read(),error=>error instanceof NotionUserListReadFailure);
    assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
  }
});

test('Notion cross-page IDs stay checked when selected output omits identity',async t=>{
  const f=await userListFixture(t),projected=[];
  f.state.pages=[userPage([user('U1','one')],'next'),userPage([user('U1','changed')],null)];
  await assert.rejects(f.create({names:['name'],consumePage:(rows,{charge})=>{
    f.row.observe(charge);
    // User projection follows complete Source capture; it cannot prune the
    // Source callback's identity or other declared cells first.
    assert.deepEqual(rows,[{email:null,id:'U1',name:'one',type:null}]);
    projected.push(...rows.map(({name})=>({name})));
  }}).read(),error=>error.cause.code==='NotionUserListDuplicateUser');
  assert.deepEqual(projected,[{name:'one'}]);assert.equal(f.state.requests.length,2);f.row.assertNoCapture();
});

test('Notion repeated cursor page and total row bounds refuse incomplete capture',async t=>{
  for(const mode of ['cursor','pages','rows']){
    const f=await userListFixture(t);const limits={...f.options.limits};
    if(mode==='cursor')f.state.pages=[userPage([user('U1','one')],'same'),userPage([user('U2','two')],'same')];
    if(mode==='pages')limits.maxPages=1;
    if(mode==='rows')limits.maxTotalRows=1;
    const code={cursor:'NotionUserListRepeatedCursor',pages:'NotionUserListPageLimit',rows:'NotionUserListRowLimit'}[mode];
    await assert.rejects(f.create({limits}).read(),error=>error.cause.code===code);
    // Both exhausted page and row inventories refuse before another send.
    // A repeated cursor is learned only from the second original response.
    const requests=mode==='cursor'?2:1;
    assert.equal(f.state.requests.length,requests);
    assert.equal(f.state.resolutions,requests);assert.equal(f.state.charges,requests);f.row.assertNoCapture();
  }
});

test('Notion aggregate raw bound charges and retains the exact offending body',async t=>{
  const f=await userListFixture(t);
  const total=f.state.pages.reduce((sum,page)=>sum+Buffer.byteLength(JSON.stringify(page)),0);
  await assert.rejects(f.create({limits:{...f.options.limits,maxTotalResponseBytes:total-1}}).read(),
    error=>error.cause.code==='NotionUserListResponseLimit');
  assert.equal(f.state.charges,2);assert.deepEqual(f.state.rows,[one]);f.row.assertNoCapture();
});

test('Notion malformed pages inconsistent cursors and restricted responses never become empty success',async t=>{
  for(const mode of ['status','error','cursor','cell','bytes']){
    const f=await userListFixture(t);
    if(mode==='status')f.state.status=403;
    if(mode==='bytes')f.state.beforeResponse=(_request,response)=>{response.writeHead(200);response.end(Buffer.from([0xff,0x80]));};
    if(mode==='error')f.state.pages=[{object:'error',status:403,code:'restricted_resource'}];
    if(mode==='cursor')f.state.pages=[{...userPage([],null),has_more:true}];
    if(mode==='cell')f.state.pages=[userPage([{object:'user',id:'U1',type:'person',person:{email:false}}],null)];
    await assert.rejects(f.create().read(),error=>error instanceof NotionUserListReadFailure&&!Object.hasOwn(error,'observations'));
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Notion current Account denies before I/O and after original credential resolution',async t=>{
  const denied=await userListFixture(t,{account:'deny'});
  await assert.rejects(denied.create().read(),error=>error.cause.code==='NotionReadDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await userListFixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.create().read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);
});

test('Notion original token binding refuses replacement between workspace pages',async t=>{
  const f=await userListFixture(t);f.state.resolved=()=>{if(f.state.resolutions===2)f.state.secret='replacement-token';};
  await assert.rejects(f.create().read(),error=>error.cause.code==='RemoteCredentialBindingChanged');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,2);assert.deepEqual(f.state.rows,[one]);f.row.assertNoCapture();
});

test('Notion lost original page reply remains Unknown and cannot resend or resolve another token',async t=>{
  const f=await userListFixture(t);f.state.beforeResponse=request=>request.socket.destroy();
  const reader=f.create();await assert.rejects(reader.read(),error=>error.cause.code==='ECONNRESET');
  const original=f.journal.recover().find(x=>x.outcome==='unknown');assert(original);
  await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('Notion cancellation and escaped raw or copied handles cannot manufacture retirement',async t=>{
  const f=await userListFixture(t),stop=new AbortController(),cause=new Error('OriginalNotionStop');let raw;
  const reader=f.create({signal:stop.signal,chargeResponse:body=>{raw=body;stop.abort(cause);return f.options.chargeResponse(body);}});
  await assert.rejects(reader.read(),error=>error.cause===cause&&!Object.hasOwn(error,'observations'));
  assert.equal(reader.observe().phase,'failed');assert.equal(reader.observe().readPending,false);
  assert.equal(reader.observe().receivedBodyBytes,BigInt(raw.byteLength));
  assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,1);
  const copy={...reader};await assert.rejects(copy.read(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copy.observe(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copy.requestStop(),{code:'ForeignInstalledCredentialSourceReader'});
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

test('Notion original reader snapshots functions selection and limits before the secret await',async t=>{
  const f=await userListFixture(t),moon={...f.options.moon},limits={...f.options.limits};
  const options={...f.options,moon,limits,names:[...f.options.names]};let reads=0;
  const project=moon.notionProjectUserList;
  Object.defineProperty(moon,'notionProjectUserList',{get(){reads++;return reads===1?project:()=>{throw new Error('second read');};}});
  f.state.resolved=()=>{limits.maxPages=1;options.names[0]='foreign';options.current=()=>{throw new Error('replaced current');};};
  const reader=f.create(options),result=await reader.read();reader.requestStop();assert.equal(reads,1);assert.equal(result.rowCount,2);
  assert.deepEqual(f.state.requests.map(x=>x.path),originalPaths);assert.deepEqual(f.state.rows,[one,two]);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});
