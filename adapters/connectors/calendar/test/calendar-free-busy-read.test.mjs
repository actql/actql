import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {CalendarFreeBusyReadFailure} from '../site/calendar-free-busy-read.mjs';
import {freeBusyFixture, freeBusyResponse} from './calendar-free-busy.fixture.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

const expectedRows = [
  {calendar_id:'sales@example.test',start:'2026-10-17T01:00:00.000Z',end:'2026-10-17T01:30:00.000Z'},
  {calendar_id:'private',start:'2026-10-17T02:00:00.000Z',end:'2026-10-17T02:15:00.000Z'},
];

test('Calendar keyless facts omit key evidence and real Common still rejects an empty-key declaration',async t=>{
  await assert.rejects(freeBusyFixture(t,{factsWire:'{"relation_keys":{"candidate_keys":[]}}'}),
    error=>error.code==='ERR_ASSERTION'&&error.message==='check_invalid_configuration');
});

test('Calendar free busy actual TLS POST binds original query signed use Account and accounted RowRun',async t=>{
  const f=await freeBusyFixture(t);const result=await f.read();
  assert.equal(result.pages,1);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,expectedRows);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.equal(f.state.charges,1);
  const request=f.state.requests[0];assert.equal(request.path,'/calendar/v3/freeBusy');
  assert.equal(request.method,'POST');assert.equal(request.authorization,'Bearer calendar-fixture-secret');
  assert.equal(request.contentType,'application/json');
  assert.deepEqual(JSON.parse(request.body),{timeMin:'2026-10-17T00:00:00.000Z',timeMax:'2026-10-18T00:00:00.000Z',
    timeZone:'UTC',calendarExpansionMax:2,items:[{id:'sales@example.test'},{id:'private'}]});
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,BigInt(f.state.responses[0].body.length));
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar free busy original operation and invalid preparation refuse before physical I/O',async t=>{
  const f=await freeBusyFixture(t);
  for(const override of [{names:['foreign']},{names:['start','start']},
    {limits:{...f.options.limits,maxCalendars:51}}]){
    await assert.rejects(f.read(override),error=>error.cause?.code==='InvalidCalendarFreeBusyRead');
  }
  for(const name of ['current','chargeResponse','consumePage']){
    await assert.rejects(f.read({[name]:undefined}),{code:'InstalledSourceReaderMethodUnavailable'});
  }
  await assert.rejects(f.read({authorizationFor:()=>({...f.options.initialAuthorization,
    scope:{...f.scope,operation:'calendar:calendars:list'}})}),
    error=>error.cause?.code==='ForeignInstalledSourceReaderAuthorization');
  await assert.rejects(f.read({limits:{...f.options.limits,maxBodyBytes:1}}),error=>error.cause?.code==='CalendarFreeBusyRequestLimit');
  await assert.rejects(f.read({authorizationFor:()=>({...f.options.initialAuthorization,
    scope:{...f.scope,dispatchRequestCid:`sha256:${'d'.repeat(64)}`}})}));
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar provider cannot replace Credential-owned content type or framing',async t=>{
  const f=await freeBusyFixture(t);
  await assert.rejects(f.read({callResource:options=>{
    const [operation,original]=[...options.operations][0];
    return callHttpsCredentialResource({...options,operations:new Map([[operation,
      {...original,headers:[...(original.headers??[]),['content-type','application/json']]}]])});
  }}),error=>error.cause.code==='ReservedHttpRequestHeader');
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);assert.equal(f.state.charges,0);
  assert.deepEqual(f.journal.recover(),[]);f.row.assertNoCapture();
});

test('Calendar free busy per-calendar refusal never publishes partial availability and retains exact body',async t=>{
  const f=await freeBusyFixture(t);const body=freeBusyResponse();body.calendars.private.errors=[{domain:'calendar',reason:'notFound'}];
  f.state.pages=[JSON.stringify(body)];
  await assert.rejects(f.read(),error=>{
    assert.ok(error instanceof CalendarFreeBusyReadFailure);assert.equal(f.state.responses.length,1);
    assert.equal(f.state.responses[0].body.toString(),f.state.pages[0]);assert(!Object.hasOwn(error,'observations'));return true;
  });
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
});

test('Calendar free busy rejected HTTP retains and charges original without retry',async t=>{
  for(const status of [403,429]){
    const f=await freeBusyFixture(t);f.state.status=status;
    await assert.rejects(f.read(),error=>error.cause.code==='CalendarFreeBusyReadRejected'&&
      f.state.responses.length===1&&f.state.responses[0].statusCode===status);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Calendar free busy response substitution and whole-row bounds refuse before any row escapes',async t=>{
  for(const kind of ['calendar','window','rowlimit','precision']){
    const f=await freeBusyFixture(t);const body=freeBusyResponse();let options={};
    if(kind==='calendar'){body.calendars.other=body.calendars.private;delete body.calendars.private;}
    if(kind==='window')body.timeMax='2026-10-19T00:00:00Z';
    if(kind==='rowlimit')options={limits:{...f.options.limits,maxRows:1}};
    if(kind==='precision')body.calendars.private.busy[0].start='2026-10-17T02:00:00.0001Z';
    f.state.pages=[JSON.stringify(body)];
    await assert.rejects(f.read(options),()=>f.state.responses.length===1);
    assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
  }
});

test('Calendar free busy current Account is checked before I/O and after original secret resolution',async t=>{
  const denied=await freeBusyFixture(t,{account:'deny'});
  await assert.rejects(denied.read(),error=>error.cause.code==='CalendarReadDenied');
  assert.equal(denied.state.requests.length,0);assert.equal(denied.state.resolutions,0);
  const changed=await freeBusyFixture(t);changed.state.resolved=()=>changed.writeAccount('deny');
  await assert.rejects(changed.read(),error=>error.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(changed.state.requests.length,0);assert.equal(changed.state.resolutions,1);changed.row.assertNoCapture();
});

test('Calendar free busy cancellation after received response retains original cause charge and raw custody',async t=>{
  const f=await freeBusyFixture(t);const controller=new AbortController(), reason=new Error('owned stop');
  const charge=f.options.chargeResponse;
  await assert.rejects(f.read({signal:controller.signal,chargeResponse:async body=>{
    const original=await charge(body);controller.abort(reason);return original;
  }}),error=>error.cause===reason&&f.state.responses.length===1);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.deepEqual(f.state.rows,[]);f.row.assertNoCapture();
});

test('Calendar free busy snapshots implementation limits and callbacks once across secret await',async t=>{
  const f=await freeBusyFixture(t);const moon={...f.options.moon},limits={...f.options.limits};
  const options={...f.options,moon,limits,names:['start']};
  let reads=0;const original=moon.calendarProjectFreeBusy;
  Object.defineProperty(moon,'calendarProjectFreeBusy',{get(){reads++;return reads===1?original:()=>{throw new Error('second read');};}});
  f.state.resolved=async()=>{limits.maxRows=1;options.current=()=>{throw new Error('replaced current');};
    options.names[0]='foreign';moon.calendarFreeBusyRowsWire=()=>{throw new Error('replaced implementation');};};
  const result=await f.read(options);assert.equal(reads,1);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,expectedRows);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar free busy uses the shared reader read-once and same physical cleanup observer',async t=>{
  const f=await freeBusyFixture(t);const reader=f.create();
  const result=await reader.read();assert.equal(result.rowCount,2);
  assert.equal(reader.observe().receivedBodyBytes,BigInt(f.state.responses[0].body.length));
  assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(reader.observe().transportClosed,true);
  reader.requestStop(new Error('same original stop'));
  assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(reader.observe().stopRequested,true);
  await assert.rejects(reader.read());
  const copied={...reader};await assert.rejects(copied.read(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copied.observe(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copied.requestStop(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.equal(f.state.requests.length,1);f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar free busy lost POST reply keeps same journal use Unknown with no resend or new resolution',async t=>{
  const f=await freeBusyFixture(t);f.state.beforeResponse=(request)=>request.socket.destroy();
  await assert.rejects(f.read(),error=>error.cause.code==='ECONNRESET');
  const original=f.journal.recover()[0];assert.equal(original.outcome,'unknown');
  await assert.rejects(f.read(),error=>error.cause.code==='RemoteCredentialUseAlreadyClaimed');
  assert.equal(f.journal.recover()[0].useCid,original.useCid);assert.equal(f.journal.recover()[0].outcome,'unknown');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,1);assert.equal(f.state.charges,0);f.row.assertNoCapture();
});
