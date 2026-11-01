import {ledgerUsageSnapshot} from '../../../host-common/runtime-core.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {CalendarListReadFailure} from '../site/calendar-list-read.mjs';
import {calendarFixture, calendarRecord} from './calendar-list.fixture.mjs';

const originalRows = [{id:'one',summary:'one',time_zone:'UTC',access_role:'reader'},
  {id:'two',summary:'two',time_zone:'UTC',access_role:'reader'}];

test('actual Calendar TLS pages use original signed grants Account and one accounted RowRun', async t => {
  const f=await calendarFixture(t),reader=f.create();const result=await reader.read();
  assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);assert.equal(f.state.resolutions,2);
  assert.equal(reader.observe().responseCount,2);
  assert.equal(ledgerUsageSnapshot(f.row.usage()).transferredBytes,reader.observe().receivedBodyBytes);
  for(const request of f.state.requests){const url=new URL('https://fixture'+request.path);
    assert.equal(request.method,'GET');assert.equal(url.pathname,'/calendar/v3/users/me/calendarList');
    assert.equal(url.searchParams.get('maxResults'),'2');assert.equal(url.searchParams.get('showHidden'),'true');
    assert.equal(url.searchParams.get('showDeleted'),'false');assert.equal(request.authorization,'Bearer calendar-fixture-secret');}
  assert.equal(new URL('https://fixture'+f.state.requests[1].path).searchParams.get('pageToken'),'opaque /+é');
  reader.requestStop();f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar original operation and invalid page selections refuse before token resolution or I/O', async t=>{
  const f=await calendarFixture(t);
  for(const override of [{names:['missing']},{names:['id','id']},
    {limits:{...f.options.limits,perPage:251}}])
    await assert.rejects(f.read(override),{code:'InvalidCalendarListRead'});
  for(const override of [{current:undefined},{chargeResponse:undefined},{consumePage:undefined}])
    await assert.rejects(f.read(override),{code:'InstalledSourceReaderMethodUnavailable'});
  await assert.rejects(f.read({authorizationFor:({index})=>({grant:f.grant,
    scope:{...f.scope,operation:'foreign'},useId:`foreign-${index}`})}),
    e=>e.cause?.code==='ForeignInstalledSourceReaderAuthorization');
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar duplicate IDs cannot hide behind query projection or a later page',async t=>{
  const f=await calendarFixture(t);f.state.pages[1]=JSON.stringify({kind:'calendar#calendarList',items:[calendarRecord('one')]});
  await assert.rejects(f.read({names:['summary']}),e=>{
    assert.ok(e instanceof CalendarListReadFailure);assert.equal(e.cause.code,'CalendarListDuplicateRecord');
    assert(!Object.hasOwn(e,'observations'));return true;});
  assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);assert.equal(f.state.rows.length,1);f.row.assertNoCapture();
});

test('Calendar malformed unselected cells and rejected HTTP keep originals charged without partial completion',async t=>{
  for(const status of [200,403,429]){
    const f=await calendarFixture(t);f.state.status=status;
    f.state.pages=[JSON.stringify({kind:'calendar#calendarList',items:[{...calendarRecord('one'),summary:null}]})];
    await assert.rejects(f.read({names:['id']}),e=>{
      assert.ok(e instanceof CalendarListReadFailure);assert(!Object.hasOwn(e,'observations'));return true;});
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
    await consume(rows,charge);controller.abort(reason);}}),e=>e.cause===reason&&!Object.hasOwn(e,'observations'));
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
    e=>e.cause.code==='RemoteCredentialBindingChanged');
  assert.equal(f.state.requests.length,1);assert.equal(f.state.resolutions,2);
  assert.equal(f.state.charges,1);assert.equal(f.state.rows.length,1);f.row.assertNoCapture();
});

test('Calendar actual shared Host reader retires only after original stop and keeps typed rows',async t=>{
  const f=await calendarFixture(t),reader=f.create();
  assert.equal(reader.observe().phase,'ready');assert.equal(reader.observe().cleanupConfirmed,false);
  const result=await reader.read();assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  assert.equal(reader.observe().responseCount,2);assert.equal(reader.observe().transportClosed,false);
  assert.equal(reader.observe().cleanupConfirmed,false);
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
  reader.retry();await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,2);f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Calendar copied shared reader receivers cannot read stop or observe the original acquisition',async t=>{
  const f=await calendarFixture(t),reader=f.create(),copied={...reader};
  await assert.rejects(copied.read(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copied.requestStop(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>copied.observe(),{code:'ForeignInstalledCredentialSourceReader'});
  assert.throws(()=>reader.observe.call(Object.create(reader)),{code:'ForeignInstalledCredentialSourceReader'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar stop before physical start retires the unacquired shared reader without sending',async t=>{
  const f=await calendarFixture(t),reader=f.create();reader.requestStop(new Error('owned stop'));
  assert.equal(reader.observe().transportClosed,true);assert.equal(reader.observe().cleanupConfirmed,true);
  await assert.rejects(reader.read(),{code:'InstalledSourceReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);f.row.assertNoCapture();
});

test('Calendar stop after the first received page keeps the same cause and prevents the next send',async t=>{
  const f=await calendarFixture(t),consume=f.options.consumePage;let reader;
  const reason=new Error('stop after first original response');
  reader=f.create({consumePage:async(rows,ticket)=>{
    assert.equal(reader.observe().phase,'reading');assert.equal(reader.observe().responseCount,1);
    assert.equal(reader.observe().cleanupConfirmed,false);await consume(rows,ticket);reader.requestStop(reason);
  }});
  await assert.rejects(reader.read(),e=>e instanceof CalendarListReadFailure&&e.cause===reason&&!Object.hasOwn(e,'observations'));
  assert.equal(reader.observe().responseCount,1);assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.charges,1);f.row.assertNoCapture();
});

test('Calendar reader factory snapshots each original provider and limit getter once before I/O',async t=>{
  const f=await calendarFixture(t);const reads=new Map();const moon={}, limits={};
  for(const name of ['calendarProjectCalendarList','calendarListRowsWire','calendarListMetadataJson','calendarListColumnNames']){
    Object.defineProperty(moon,name,{enumerable:true,get(){reads.set(name,(reads.get(name)??0)+1);return f.options.moon[name];}});
  }
  for(const [name,value] of Object.entries(f.options.limits)){
    Object.defineProperty(limits,name,{enumerable:true,get(){reads.set(name,(reads.get(name)??0)+1);return value;}});
  }
  const reader=f.create({moon,limits});
  for(const [name,count] of reads)assert.equal(count,1,`original snapshot getter ${name}`);
  assert.equal(f.state.requests.length,0);assert.equal(reader.observe().cleanupConfirmed,false);
  const result=await reader.read();assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,originalRows);
  for(const [name,count] of reads)assert.equal(count,1,`retained original getter ${name}`);
  f.row.finish();assert.equal(f.row.captureCount(),2);
});
