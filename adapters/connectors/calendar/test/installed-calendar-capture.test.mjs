import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {installedCalendarFixture} from './installed-calendar.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {calendarRecord} from './calendar-list.fixture.mjs';

for(const format of ['sql','aql'])test(`ordinary installed Calendar ${format} captures two original pages and releases its native binding`,async t=>{
  const f=await installedCalendarFixture(t),source=await f.load(),preparation=await f.prepare(source,{format});
  const opened=await source.openCapture(preparation);
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-calendar-test'));
  assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
    {access_role:'reader',id:'one',summary:'one',time_zone:'UTC'},
    {access_role:'reader',id:'two',summary:'two',time_zone:'UTC'}]);
  assert.equal(f.state.requests.length,2);
  const paths=f.state.requests.map(r=>new URL(r.path,'https://calendar.test'));
  assert(paths.every(p=>p.pathname==='/calendar/v3/users/me/calendarList'));
  assert.equal(paths[1].searchParams.get('pageToken'),'opaque /+é');
  assert(paths.every(p=>p.searchParams.get('showHidden')==='true'&&p.searchParams.get('showDeleted')==='false'));
  assert(paths.every(p=>p.searchParams.get('fields').includes('accessRole')));
  assert.equal(source.sourceReadAccesses[0].resource,'calendars');
  opened.close();
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger).slice(4,8),[0n,0n,0n,0n]);
  assert.throws(()=>opened.capture.originalRead(),{code:'InstalledSourceClosed'});
  assert.equal(f.state.requests.length,2);
});

test('ordinary installed Calendar keeps the calendars Account decision separate',async t=>{
  const f=await installedCalendarFixture(t,{accountResource:'free_busy'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_NO_MATCH'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('ordinary installed Calendar refuses a malformed unselected cell before capture',async t=>{
  const f=await installedCalendarFixture(t);
  f.state.pages=[JSON.stringify({kind:'calendar#calendarList',items:[{...calendarRecord('one'),summary:null}]})];
  const source=await f.load(),preparation=await f.prepare(source,{selection:'id'});
  await assert.rejects(source.openCapture(preparation));
  assert.equal(f.state.requests.length,1);
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger).slice(4,8),[0n,0n,0n,0n]);
});

test('ordinary installed Calendar rechecks stop before the next page and does not resend',async t=>{
  const f=await installedCalendarFixture(t),stop=new AbortController();
  f.state.beforeResponse=()=>stop.abort(new Error('same original Calendar stopped'));
  const source=await f.load(),preparation=await f.prepare(source);
  await assert.rejects(source.openCapture({...preparation,signal:stop.signal}));
  assert.equal(f.state.requests.length,1);
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger).slice(4,8),[0n,0n,0n,0n]);
});

test('ordinary installed Calendar preserves the lost-response Credential Unknown after physical close',async t=>{
  const f=await installedCalendarFixture(t);f.state.beforeResponse=request=>request.socket.destroy();
  const source=await f.load(),preparation=await f.prepare(source);let original;
  await assert.rejects(source.openCapture(preparation),cause=>{original=cause;return true;});
  assert.equal(f.state.requests.length,1);
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger).slice(4,8),[0n,0n,0n,0n]);
  // Physical transport cleanup does not replace the durable use's outcome.
  const database=new DatabaseSync(join(f.root,'installed-journal','credential-journal.sqlite3'),{readOnly:true});
  try{assert.deepEqual(database.prepare('SELECT outcome FROM credential_uses ORDER BY use_ordinal').all().map(row=>row.outcome),[3]);}
  finally{database.close();}
  assert(original.cause);assert.equal(f.state.requests.length,1);
});
