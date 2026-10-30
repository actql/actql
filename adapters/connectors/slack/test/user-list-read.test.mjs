import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {SlackUserListReadFailure,SLACK_USER_LIST_OPERATION,
  SLACK_WORKSPACE_IDENTITY_OPERATION} from '../site/user-list-read.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {userListFixture,userPage} from './user-list-read.fixture.mjs';

const one={id:'U1',name:'one',real_name:null,display_name:null,email:null,tz:null,is_bot:null,deleted:null};
const two={...one,id:'U2',name:'two'};
const originalPaths=['/api/auth.test','/api/users.list?limit=10',
  '/api/users.list?limit=10&cursor=opaque%2B%2F%3D%20cursor'];

test('Slack actual SQL and AQL use distinct identity and page grants on one token then capture exact rows',async t=>{
  for(const format of ['sql','aql']){
    const f=await userListFixture(t,{format}),reader=f.create(),result=await reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,[one,two]);
    assert.deepEqual(f.state.requests.map(x=>x.path),originalPaths);
    assert.deepEqual(f.state.requests.map(x=>x.method),['POST','GET','GET']);
    assert.equal(f.state.requests[0].body.toString(),'{}');
    assert.equal(f.state.requests[0].contentType,'application/json');
    assert.equal(f.state.requests[1].body.length,0);assert.equal(f.state.requests[1].contentType,undefined);
    assert(f.state.requests.every(x=>x.authorization==='Bearer slack-fixture-token'));
    assert.equal(f.state.resolutions,3);assert.equal(f.state.charges,3);assert.equal(f.state.observationCharges,1);
    assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,BigInt(result.observations.reduce((sum,x)=>sum+x.body.length,0)));
    f.row.finish();assert.equal(f.row.captureCount(),2);
    // Credential Journal success is named succeeded by its original owner;
    // this is not a public Effect accepted/applied transition.
    assert.deepEqual(f.journal.recover().map(x=>x.outcome),['succeeded','succeeded','succeeded']);
    assert.equal(new Set(f.journal.recover().map(x=>x.grantCid)).size,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('Slack empty short page with opaque continuation never ends the sequence',async t=>{
  const f=await userListFixture(t);f.state.pages=[userPage([],'next'),userPage([{id:'U2',name:'two'}],null)];
  const result=await f.create().read();assert.equal(result.pages,2);assert.equal(result.rowCount,1);
  assert.deepEqual(f.state.rows,[two]);assert.equal(f.state.requests.length,3);
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

test('Slack original workspace identity rejects mismatch errors and malformed observations before data I/O',async t=>{
  for(const identity of [{ok:true,team_id:'T-other',user_id:'U-bot'},
    {ok:false,error:'invalid_auth'}, {ok:true,team:'T-original',user_id:'U-bot'},
    '{"ok":true,"team_id":"T-original","team_id":"T-other","user_id":"U-bot"}']){
    const f=await userListFixture(t);f.state.identity=identity;
    await assert.rejects(f.create().read(),error=>error instanceof SlackUserListReadFailure&&
      error.observations.length===1);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);
    assert.equal(f.state.observationCharges,0);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Slack complete reader options reject missing observation custody target and invalid bounds before I/O',async t=>{
  const f=await userListFixture(t);
  for(const override of [{workspaceId:undefined},{workspaceId:''},{workspaceId:'x\ud800'},
    {names:['foreign']},{names:['id','id']},{names:Array(1000).fill('id')},
    {workspaceId:'x'.repeat(f.options.limits.maxIdentityBytes+1)},
    {current:undefined},{chargeResponse:undefined},
    {consumeObservation:undefined},{consumePage:undefined},{credential:{...f.options.credential,binding:undefined}},
    {limits:{...f.options.limits,pageSize:1000}},{limits:{...f.options.limits,maxPages:0}}]){
    assert.throws(()=>f.create(override),{code:'InvalidSlackUserListRead'});
  }
  assert.throws(()=>f.create({initialAuthorization:{...f.options.initialAuthorization,
    scope:{...f.scope,operation:'slack:users:foreign'}}}),{code:'ForeignSlackUserListOperation'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('Slack original nominal auth grant cannot be replaced with users grant or a foreign page invocation',async t=>{
  const auth=await userListFixture(t);
  await assert.rejects(auth.create({authorizationFor:()=>({grant:auth.grant,scope:auth.authScope,useId:'identity-0'})}).read(),
    error=>error instanceof SlackUserListReadFailure);
  assert.equal(auth.state.requests.length,0);assert.equal(auth.state.resolutions,0);
  const page=await userListFixture(t),original=page.options.authorizationFor;
  await assert.rejects(page.create({authorizationFor:input=>input.operation===SLACK_USER_LIST_OPERATION
    ?{...original(input),scope:{...page.scope,dispatchRequestCid:`sha256:${'d'.repeat(64)}`}}:original(input)}).read(),
  error=>error.cause.code==='ForeignSlackUserListAuthorization');
  assert.equal(page.state.requests.length,1);assert.deepEqual(page.state.rows,[]);page.row.assertNoCapture();
});

test('Slack all-page IDs remain checked even when the requested projection omits the key',async t=>{
  const f=await userListFixture(t),projected=[];
  f.state.pages=[userPage([{id:'U1',name:'one'}],'next'),userPage([{id:'U1',name:'changed'}],null)];
  // This projection-only control consumes its exact physical tickets as
  // observations and never finishes/captures rows with the full Source schema.
  await assert.rejects(f.create({names:['name'],consumePage:(rows,{charge})=>{
    f.row.observe(charge);projected.push(...rows);
  }}).read(),
    error=>error.cause.code==='SlackUserListDuplicateUser'&&error.observations.length===3);
  assert.deepEqual(projected,[{name:'one'}]);assert.equal(f.state.requests.length,3);f.row.assertNoCapture();
});

test('Slack repeated cursors and incomplete page or total row bounds refuse without partial capture',async t=>{
  for(const mode of ['cursor','pages','rows']){
    const f=await userListFixture(t);let limits={...f.options.limits};
    if(mode==='cursor')f.state.pages=[userPage([{id:'U1'}],'same'),userPage([{id:'U2'}],'same')];
    if(mode==='pages')limits.maxPages=1;
    if(mode==='rows')limits.maxTotalRows=1;
    const code={cursor:'SlackUserListRepeatedCursor',pages:'SlackUserListPageLimit',rows:'SlackUserListRowLimit'}[mode];
    await assert.rejects(f.create({limits}).read(),error=>error.cause.code===code);
    assert.equal(f.state.requests.length,mode==='cursor'?3:2);f.row.assertNoCapture();
  }
});

test('Slack aggregate raw bound charges and retains the exact offending observation instead of truncating',async t=>{
  const f=await userListFixture(t);
  const expected=Buffer.byteLength(JSON.stringify(f.state.identity))+Buffer.byteLength(JSON.stringify(f.state.pages[0]));
  await assert.rejects(f.create({limits:{...f.options.limits,maxTotalResponseBytes:expected-1}}).read(),
    error=>error.cause.code==='SlackUserListResponseLimit'&&error.observations.length===2&&
      error.observations[1].body.toString()===JSON.stringify(f.state.pages[0]));
  assert.equal(f.state.charges,2);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
});

test('Slack rejected and malformed data responses retain original bodies without retry or data rows',async t=>{
  for(const mode of ['status','error','wrong-members','cell']){
    const f=await userListFixture(t);
    if(mode==='status')f.state.beforeResponse=request=>{f.state.status=request.url==='/api/auth.test'?200:429;};
    if(mode==='error')f.state.pages=[{ok:false,error:'ratelimited'}];
    if(mode==='wrong-members')f.state.pages=[{ok:true,users:[]}];
    if(mode==='cell')f.state.pages=[userPage([{id:'U1',is_bot:'false'}],null)];
    await assert.rejects(f.create().read(),error=>error instanceof SlackUserListReadFailure&&error.observations.length===2);
    assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Slack current Account denies before I/O and after resolving the original credential',async t=>{
  const denied=await userListFixture(t,{account:'deny'});
  await assert.rejects(denied.create().read(),error=>error.cause.code==='SlackReadDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await userListFixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.create().read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);
});

test('Slack original binding refuses token replacement after identity instead of mixing workspaces',async t=>{
  const f=await userListFixture(t);f.state.resolved=()=>{if(f.state.resolutions===2)f.state.secret='replacement-token';};
  await assert.rejects(f.create().read(),error=>error.cause.code==='RemoteCredentialBindingChanged'&&error.observations.length===1);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,2);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
});

test('Slack lost page response keeps the original use Unknown and cannot resend or resolve another token',async t=>{
  const f=await userListFixture(t);f.state.beforeResponse=request=>{if(request.url.startsWith('/api/users.list'))request.socket.destroy();};
  const reader=f.create();await assert.rejects(reader.read(),error=>error.cause.code==='ECONNRESET');
  const original=f.journal.recover().find(x=>x.outcome==='unknown');assert(original);
  await assert.rejects(invokeScopedCredentialOperation({authorization:{grant:f.grant,scope:f.scope,useId:'users-0'},
    credential:f.options.credential,callResource:callHttpsCredentialResource,operation:SLACK_USER_LIST_OPERATION,
    method:'GET',path:'/api/users.list',query:[['limit','10']],maxResponseBytes:f.options.limits.maxResponseBytes}),
  {code:'RemoteCredentialUseAlreadyClaimed'});
  await assert.rejects(reader.read(),{code:'SlackUserListReaderAlreadyStarted'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');
  assert.equal(f.state.requests.length,2);assert.equal(f.state.resolutions,2);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('Slack original reader cancellation copied handles and escaped raw never manufacture cleanup confirmation',async t=>{
  const f=await userListFixture(t),stop=new AbortController(),cause=new Error('OriginalSlackStop');let raw;
  const reader=f.create({signal:stop.signal,chargeResponse:body=>{raw=body;stop.abort(cause);return f.options.chargeResponse(body);}});
  await assert.rejects(reader.read(),error=>error.cause===cause&&error.observations[0].body===raw);
  assert.equal(reader.observe().phase,'failed');assert.equal(reader.observe().stopRequested,true);
  assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,1);
  const copy={...reader};await assert.rejects(copy.read(),{code:'ForeignSlackUserListReader'});
  assert.throws(()=>copy.observe(),{code:'ForeignSlackUserListReader'});
  assert.throws(()=>copy.requestStop(),{code:'ForeignSlackUserListReader'});
});

test('Slack original reader snapshots functions selection and bounds before the original secret await',async t=>{
  const f=await userListFixture(t),moon={...f.options.moon},limits={...f.options.limits};
  const options={...f.options,moon,limits,names:[...f.options.names]};let reads=0;
  const project=moon.slackProjectUserList;
  Object.defineProperty(moon,'slackProjectUserList',{get(){reads++;return reads===1?project:()=>{throw new Error('second read');};}});
  f.state.resolved=()=>{limits.maxPages=1;options.workspaceId='T-other';options.names[0]='foreign';
    options.current=()=>{throw new Error('replaced current');};moon.slackWorkspaceIdentityMatches=()=>false;};
  const result=await f.create(options).read();assert.equal(reads,1);assert.equal(result.rowCount,2);
  assert.deepEqual(f.state.requests.map(x=>x.path),originalPaths);assert.deepEqual(f.state.rows,[one,two]);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});
