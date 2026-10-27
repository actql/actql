import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {CalendarListReadFailure, createCalendarListReader} from '../site/calendar-list-read.mjs';
import {calendarFixture, calendarRecord} from './calendar-list.fixture.mjs';

const originalRows = [{id:'one',summary:'one',time_zone:'UTC',access_role:'reader'},
  {id:'two',summary:'two',time_zone:'UTC',access_role:'reader'}];

test('actual Calendar TLS pages use original signed grants Account and one accounted RowRun', async t => {
  const f=await calendarFixture(t);const result=await f.read();
  assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);assert.equal(f.state.resolutions,2);
  assert.equal(result.observations.length,2);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,result.observations.reduce((sum,r)=>sum+BigInt(r.body.length),0n));
  for(const request of f.state.requests){const url=new URL('https://fixture'+request.path);
    assert.equal(request.method,'GET');assert.equal(url.pathname,'/calendar/v3/users/me/calendarList');
    assert.equal(url.searchParams.get('maxResults'),'2');assert.equal(url.searchParams.get('showHidden'),'true');
    assert.equal(url.searchParams.get('showDeleted'),'false');assert.equal(request.authorization,'Bearer calendar-fixture-secret');}
  assert.equal(new URL('https://fixture'+f.state.requests[1].path).searchParams.get('pageToken'),'opaque /+é');
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar original operation binding and invalid selections refuse before token resolution or I/O', async t=>{
  const f=await calendarFixture(t);
  for(const override of [{names:['missing']},{names:['id','id']},{current:undefined},{chargeResponse:undefined},
    {consumePage:undefined},{credential:{...f.options.credential,binding:undefined}},
    {limits:{...f.options.limits,perPage:251}}])await assert.rejects(f.read(override),{code:'InvalidCalendarListRead'});
  await assert.rejects(f.read({initialAuthorization:{...f.options.initialAuthorization,scope:{...f.scope,operation:'foreign'}}}),
    {code:'ForeignCalendarListOperation'});
  await assert.rejects(f.read({authorizationFor:({index})=>({...f.options.initialAuthorization,useId:`wrong-${index}`,
    scope:{...f.scope,resourceOrigin:'https://foreign.invalid'}})}),e=>e.cause.code==='ForeignCalendarListAuthorization');
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar duplicate IDs cannot hide behind query projection or a later page',async t=>{
  const f=await calendarFixture(t);f.state.pages[1]=JSON.stringify({kind:'calendar#calendarList',items:[calendarRecord('one')]});
  await assert.rejects(f.read({names:['summary']}),e=>{
    assert.ok(e instanceof CalendarListReadFailure);assert.equal(e.cause.code,'CalendarListDuplicateRecord');
    assert.equal(e.observations.length,2);return true;});
  assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);assert.equal(f.state.rows.length,1);f.row.assertNoCapture();
});

test('Calendar malformed unselected cells and rejected HTTP keep originals charged without partial completion',async t=>{
  for(const status of [200,403,429]){
    const f=await calendarFixture(t);f.state.status=status;
    f.state.pages=[JSON.stringify({kind:'calendar#calendarList',items:[{...calendarRecord('one'),summary:null}]})];
    await assert.rejects(f.read({names:['id']}),e=>{
      assert.ok(e instanceof CalendarListReadFailure);assert.equal(e.observations.length,1);
      assert.equal(e.observations[0].body.toString(),f.state.pages[0]);return true;});
    assert.equal(f.state.charges,1);assert.equal(f.state.requests.length,1);assert.equal(f.state.rows.length,0);f.row.assertNoCapture();
  }
});

test('Calendar cursor cycle and page or total row bound refuse instead of finishing a partial Source',async t=>{
  for(const kind of ['cycle','pages','rows']){
    const f=await calendarFixture(t);
    const options=kind==='pages'?{limits:{...f.options.limits,maxPages:1,maxRequests:1}}
      :kind==='rows'?{limits:{...f.options.limits,maxRows:1}}:{};
    if(kind==='cycle')f.state.pages[1]=JSON.stringify({kind:'calendar#calendarList',items:[calendarRecord('two')],nextPageToken:'opaque /+é'});
    await assert.rejects(f.read(options),e=>{assert.equal(e.cause.code,kind==='cycle'?'CalendarListCursorCycle':
      kind==='pages'?'CalendarListPageLimit':'CalendarListRowLimit');return true;});
    assert.equal(f.state.requests.length,kind==='cycle'?2:1);assert.equal(f.state.charges,f.state.requests.length);f.row.assertNoCapture();
  }
});

test('Calendar Account denial is checked before I/O and again between admitted pages',async t=>{
  const first=await calendarFixture(t,{account:'deny'});
  await assert.rejects(first.read(),e=>e.cause.code==='CalendarReadDenied');
  assert.equal(first.state.requests.length,0);assert.equal(first.state.resolutions,0);
  const f=await calendarFixture(t);const consume=f.options.consumePage;
  await assert.rejects(f.read({consumePage:async(rows,charge)=>{await consume(rows,charge);await f.writeAccount('deny');}}),
    e=>e.cause.code==='AuthorizationCurrentAccountChanged');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);assert.equal(f.state.rows.length,1);f.row.assertNoCapture();
});

test('Calendar cancellation after a delivered page retains the same cause and never sends the next page',async t=>{
  const f=await calendarFixture(t);const controller=new AbortController();const reason=new Error('owned cancellation');
  const consume=f.options.consumePage;
  await assert.rejects(f.read({signal:controller.signal,consumePage:async(rows,charge)=>{
    await consume(rows,charge);controller.abort(reason);}}),e=>e.cause===reason&&e.observations.length===1);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.rows.length,1);assert.equal(f.state.charges,1);f.row.assertNoCapture();
});

test('Calendar physical sequencer snapshots provider callbacks names and limits across secret resolution await',async t=>{
  const f=await calendarFixture(t);const moon={...f.options.moon};const names=['summary','time_zone','access_role'];
  const limits={...f.options.limits};const options={...f.options,moon,names,limits};
  f.state.resolved=async()=>{moon.calendarListRowsWire=()=>{throw new Error('later provider');};
    names[0]='missing';limits.perPage=250;options.current=()=>{throw new Error('later current');};};
  const result=await f.read(options);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  assert.ok(f.state.requests.every(request=>new URL('https://fixture'+request.path).searchParams.get('maxResults')==='2'));
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar changed original credential is refused before the next page send and is not replaced',async t=>{
  const f=await calendarFixture(t);const consume=f.options.consumePage;
  await assert.rejects(f.read({consumePage:async(rows,charge)=>{
    await consume(rows,charge);f.state.secret='replacement-private-fixture-secret';}}),
    e=>e.cause.code==='RemoteCredentialBindingChanged'&&e.observations.length===1);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,2);
  assert.equal(f.state.charges,1);assert.equal(f.state.rows.length,1);f.row.assertNoCapture();
});

test('Calendar original reader handle snapshots once and never acknowledges retained success observations',async t=>{
  const f=await calendarFixture(t);const moon={...f.options.moon};
  const options={...f.options,moon,limits:{...f.options.limits}};
  const reader=createCalendarListReader(options);const read=reader.read, observe=reader.observe;
  assert.deepEqual(observe.call(reader),{phase:'ready',stopRequested:false,receivedResponses:0,
    receivedBodyBytes:0n,observationCustody:'not-observed',cleanupConfirmed:false});
  options.current=()=>{throw new Error('replaced current');};options.limits.perPage=251;
  moon.calendarListRowsWire=()=>{throw new Error('replaced provider');};
  const result=await read.call(reader);const originalBodies=result.observations.map(r=>Buffer.from(r.body));
  assert.deepEqual(f.state.rows,originalRows);assert.equal(result.rowCount,2);
  assert.deepEqual(observe.call(reader),{phase:'succeeded',stopRequested:false,receivedResponses:2,
    receivedBodyBytes:result.observations.reduce((n,r)=>n+BigInt(r.body.byteLength),0n),
    observationCustody:'retained',cleanupConfirmed:false});
  reader.requestStop(new Error('post-read stop'));
  assert.equal(observe.call(reader).cleanupConfirmed,false);
  result.observations.forEach((r,i)=>assert.deepEqual(r.body,originalBodies[i]));
  await assert.rejects(read.call(reader),{code:'CalendarListReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,2);f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar copied reader receivers cannot read stop or observe the original acquisition',async t=>{
  const f=await calendarFixture(t);const reader=createCalendarListReader(f.options);
  const copied={...reader};await assert.rejects(copied.read(),{code:'ForeignCalendarListReader'});
  assert.throws(()=>copied.requestStop(),{code:'ForeignCalendarListReader'});
  assert.throws(()=>copied.observe(),{code:'ForeignCalendarListReader'});
  assert.throws(()=>reader.observe.call(Object.create(reader)),{code:'ForeignCalendarListReader'});
  assert.equal(reader.observe().phase,'ready');assert.equal(f.state.requests.length,0);
  assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar original reader stop before I/O preserves the same reason and never confirms retirement',async t=>{
  const f=await calendarFixture(t);const reader=createCalendarListReader(f.options);
  const reason=new Error('original reader stop');reader.requestStop(reason);
  await assert.rejects(reader.read(),e=>e instanceof CalendarListReadFailure&&e.cause===reason);
  assert.deepEqual(reader.observe(),{phase:'failed',stopRequested:true,receivedResponses:0,
    receivedBodyBytes:0n,observationCustody:'not-observed',cleanupConfirmed:false});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar original reader observes in-flight custody and preserves failed raw aliases after stop',async t=>{
  const f=await calendarFixture(t);const consume=f.options.consumePage;let reader;
  const reason=new Error('stop after first original response');
  reader=createCalendarListReader({...f.options,consumePage:async(rows,charge)=>{
    assert.equal(reader.observe().phase,'reading');assert.equal(reader.observe().receivedResponses,1);
    assert.equal(reader.observe().cleanupConfirmed,false);await consume(rows,charge);reader.requestStop(reason);
  }});
  let original;
  await assert.rejects(reader.read(),e=>{original=e;return e instanceof CalendarListReadFailure&&e.cause===reason;});
  const body=original.observations[0].body;
  assert.equal(body.toString(),f.state.pages[0]);assert.equal(reader.observe().phase,'failed');
  assert.equal(reader.observe().receivedResponses,1);assert.equal(reader.observe().observationCustody,'retained');
  assert.equal(reader.observe().cleanupConfirmed,false);reader.requestStop();
  assert.equal(original.observations[0].body,body);assert.equal(body.toString(),f.state.pages[0]);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);f.row.assertNoCapture();
});

test('Calendar reader factory refusal leaves pre-acquired RowRun and credential cleanup with the caller',async t=>{
  const f=await calendarFixture(t);const before=f.row.usage();
  assert.throws(()=>createCalendarListReader({...f.options,current:undefined}),{code:'InvalidCalendarListRead'});
  assert.deepEqual(f.row.usage(),before);assert.equal(f.state.requests.length,0);
  assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar reader factory snapshots each original provider and limit getter once before I/O',async t=>{
  const f=await calendarFixture(t);const reads=new Map();const moon={}, limits={};
  for(const name of ['calendarProjectCalendarList','calendarListRowsWire','calendarListMetadataJson','calendarListColumnNames']){
    Object.defineProperty(moon,name,{enumerable:true,get(){reads.set(name,(reads.get(name)??0)+1);return f.options.moon[name];}});
  }
  for(const [name,value] of Object.entries(f.options.limits)){
    Object.defineProperty(limits,name,{enumerable:true,get(){reads.set(name,(reads.get(name)??0)+1);return value;}});
  }
  const reader=createCalendarListReader({...f.options,moon,limits});
  for(const [name,count] of reads)assert.equal(count,1,`original snapshot getter ${name}`);
  assert.equal(f.state.requests.length,0);assert.equal(reader.observe().cleanupConfirmed,false);
  const result=await reader.read();assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  for(const [name,count] of reads)assert.equal(count,1,`retained original getter ${name}`);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});
