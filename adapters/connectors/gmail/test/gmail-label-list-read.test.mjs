import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {GmailLabelListReadFailure, createGmailLabelListReader} from '../site/gmail-label-list-read.mjs';
import {labelListFixture, labelListResponse} from './gmail-label-list.fixture.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

const expectedRows=[{id:'INBOX',name:'Inbox',type:'system'},
  {id:'Label_1',name:'顧客 / é 📩',type:'user'}];
const expectedTarget='/gmail/v1/users/support%2Bbox%40example.test/labels?fields=labels%28id%2Cname%2Ctype%29';

test('Gmail labels actual SQL and AQL prepare then TLS Account Credential and RowRun capture exact full rows',async t=>{
  for(const format of ['sql','aql']){
    const f=await labelListFixture(t,{format});const result=await f.read();
    assert.equal(result.pages,1);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,expectedRows);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.equal(f.state.charges,1);
    const request=f.state.requests[0];assert.equal(request.path,expectedTarget);assert.equal(request.method,'GET');
    assert.equal(request.authorization,'Bearer gmail-fixture-secret');assert.equal(request.contentType,undefined);
    assert.equal(request.body.length,0);assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,BigInt(result.observations[0].body.length));
    f.row.finish();assert.equal(f.row.captureCount(),2);
  }
});

test('Gmail labels Source key and cell checks survive a text query projecting id away',async t=>{
  const f=await labelListFixture(t,{selection:'name'});const result=await f.read();
  assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,expectedRows);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Gmail labels explicit original mailbox operation and complete target bounds refuse before I/O',async t=>{
  const f=await labelListFixture(t);
  for(const override of [{mailbox:undefined},{mailbox:'me'},{mailbox:'x\ny@example.test'},
    {mailbox:'x\ud800@example.test'},{names:['foreign']},{names:['id','id']},{current:undefined},
    {chargeResponse:undefined},{consumePage:undefined},{credential:{...f.options.credential,binding:undefined}},
    {limits:{...f.options.limits,maxRows:0}}]){
    await assert.rejects(f.read(override),{code:'InvalidGmailLabelListRead'});
  }
  await assert.rejects(f.read({initialAuthorization:{...f.options.initialAuthorization,
    scope:{...f.scope,operation:'gmail:messages:list'}}}),{code:'ForeignGmailLabelListOperation'});
  await assert.rejects(f.read({limits:{...f.options.limits,maxTargetBytes:Buffer.byteLength(expectedTarget)-1}}),
    {code:'GmailLabelListTargetLimit'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
  const result=await f.read({limits:{...f.options.limits,maxTargetBytes:Buffer.byteLength(expectedTarget)}});
  assert.equal(result.rowCount,2);assert.equal(f.state.requests[0].path,expectedTarget);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Gmail mailbox component cannot escape the fixed label path and no default me is sent',async t=>{
  const f=await labelListFixture(t);await f.read({mailbox:'support+box/a?b#c@example.test'});
  assert.equal(f.state.requests[0].path,
    '/gmail/v1/users/support%2Bbox%2Fa%3Fb%23c%40example.test/labels?fields=labels%28id%2Cname%2Ctype%29');
  assert.equal(f.state.requests.length,1);
});

test('Gmail original authorization scope and foreign nominal grant are refused by their real owners',async t=>{
  const scoped=await labelListFixture(t);
  await assert.rejects(scoped.read({authorizationFor:()=>({...scoped.options.initialAuthorization,
    scope:{...scoped.scope,dispatchRequestCid:`sha256:${'d'.repeat(64)}`}})}),
    error=>error.cause.code==='ForeignGmailLabelListAuthorization');
  assert.equal(scoped.state.requests.length,0);assert.equal(scoped.state.resolutions,0);
  const nominal=await labelListFixture(t);const foreign=nominal.control.prepare({...nominal.scope,principal:'foreign'});
  nominal.journal.acceptGrant(nominal.sign(foreign),nominal.control);
  await assert.rejects(nominal.read({authorizationFor:()=>({...nominal.options.initialAuthorization,grant:foreign})}),
    error=>error instanceof GmailLabelListReadFailure);
  assert.equal(nominal.state.requests.length,0);assert.equal(nominal.state.resolutions,0);nominal.row.assertNoCapture();
});

test('Gmail provider cannot inject Credential-owned authorization framing or content type',async t=>{
  const f=await labelListFixture(t);
  await assert.rejects(f.read({callResource:options=>{
    const [operation,original]=[...options.operations][0];
    return callHttpsCredentialResource({...options,operations:new Map([[operation,
      {...original,headers:[...(original.headers??[]),['content-type','application/json']]}]])});
  }}),error=>error.cause.code==='ReservedHttpRequestHeader');
  assert.deepEqual(f.journal.recover(),[]);assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('Gmail label whole response refuses duplicate IDs missing cells foreign envelopes and row budget without partial rows',async t=>{
  for(const kind of ['duplicate','missing','foreign','continuation','rowlimit']){
    const f=await labelListFixture(t);let body=labelListResponse(),overrides={};
    if(kind==='duplicate')body.labels[1].id='INBOX';
    if(kind==='missing')delete body.labels[1].type;
    if(kind==='foreign')body={messages:[]};
    if(kind==='continuation')body.nextPageToken='unhandled';
    if(kind==='rowlimit')overrides={limits:{...f.options.limits,maxRows:1}};
    f.state.pages=[JSON.stringify(body)];
    await assert.rejects(f.read(overrides),error=>error instanceof GmailLabelListReadFailure&&
      error.observations.length===1&&error.observations[0].body.toString()===f.state.pages[0]);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Gmail known rejection status retains and charges original body without retry',async t=>{
  for(const status of [403,429]){
    const f=await labelListFixture(t);f.state.status=status;
    await assert.rejects(f.read(),error=>error.cause.code==='GmailLabelListReadRejected'&&
      error.observations.length===1&&error.observations[0].statusCode===status);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Gmail current Account refuses before I/O and after the same original secret resolver await',async t=>{
  const denied=await labelListFixture(t,{account:'deny'});
  await assert.rejects(denied.read(),error=>error.cause.code==='GmailReadDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await labelListFixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);changed.row.assertNoCapture();
});

test('Gmail cancellation and callback refusal preserve original received body and unchanged cause',async t=>{
  for(const kind of ['stop','charge','deliver']){
    const f=await labelListFixture(t);const stop=new AbortController(),cause=new Error('OriginalGmailReadRefusal');
    let raw;const charge=f.options.chargeResponse;const overrides={signal:stop.signal};
    overrides.chargeResponse=async body=>{raw=body;if(kind==='charge')throw cause;const ticket=await charge(body);
      if(kind==='stop')stop.abort(cause);return ticket;};
    if(kind==='deliver')overrides.consumePage=()=>{throw cause;};
    await assert.rejects(f.read(overrides),error=>error.cause===cause&&
      error.observations.length===1&&error.observations[0].body===raw);
    assert.equal(f.state.requests.length,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Gmail reader snapshots compiled functions mailbox limits and callbacks once before secret await',async t=>{
  const f=await labelListFixture(t);const moon={...f.options.moon},limits={...f.options.limits};
  const options={...f.options,moon,limits,names:['name']};let reads=0;const original=moon.gmailProjectLabelList;
  Object.defineProperty(moon,'gmailProjectLabelList',{get(){reads++;return reads===1?original:()=>{throw new Error('second read');};}});
  f.state.resolved=()=>{limits.maxRows=1;options.mailbox='other@example.test';options.current=()=>{throw new Error('replaced current');};
    options.names[0]='foreign';moon.gmailLabelListRowsWire=()=>{throw new Error('replaced implementation');};};
  const result=await f.read(options);assert.equal(reads,1);assert.equal(result.rowCount,2);
  assert.equal(f.state.requests[0].path,expectedTarget);assert.deepEqual(f.state.rows,expectedRows);
});

test('Gmail original reader read-once stop and escaped observation never manufacture cleanup confirmation',async t=>{
  const f=await labelListFixture(t);const reader=createGmailLabelListReader(f.options),result=await reader.read();
  assert.deepEqual(reader.observe(),{phase:'succeeded',stopRequested:false,receivedResponses:1,
    receivedBodyBytes:BigInt(result.observations[0].body.length),observationCustody:'retained',cleanupConfirmed:false});
  reader.requestStop(new Error('same original stop'));assert.equal(reader.observe().stopRequested,true);
  assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'GmailLabelListReaderAlreadyStarted'});
  const copied={...reader};await assert.rejects(copied.read(),{code:'ForeignGmailLabelListReader'});
  assert.throws(()=>copied.observe(),{code:'ForeignGmailLabelListReader'});
  assert.throws(()=>copied.requestStop(),{code:'ForeignGmailLabelListReader'});
  assert.equal(f.state.requests.length,1);
});

test('Gmail lost GET reply stays same journal Unknown and same use cannot resend or resolve another secret',async t=>{
  const f=await labelListFixture(t);f.state.beforeResponse=request=>request.socket.destroy();
  await assert.rejects(f.read(),error=>error.cause.code==='ECONNRESET');
  const original=f.journal.recover()[0];assert.equal(original.outcome,'unknown');
  await assert.rejects(f.read(),error=>error.cause.code==='RemoteCredentialUseAlreadyClaimed');
  assert.equal(f.journal.recover()[0].useCid,original.useCid);assert.equal(f.journal.recover()[0].outcome,'unknown');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.equal(f.state.charges,0);f.row.assertNoCapture();
});
