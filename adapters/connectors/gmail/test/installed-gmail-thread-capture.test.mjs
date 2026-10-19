import assert from 'node:assert/strict';
import test from 'node:test';
import {installedGmailFixture} from './installed-gmail.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

for(const format of ['sql','aql'])test(`installed Gmail threads ${format} binds list and dependent gets to the original installed capture`,async t=>{
  const f=await installedGmailFixture(t,{resource:'threads'});
  // A missing first-page extent with a continuation is not a completed scan.
  f.state.pages=[{nextPageToken:'next/+'},{threads:[{id:'one'},{id:'two'}]},
    {id:'one',messages:[{id:'m',threadId:'one',internalDate:'-1',payload:{}}]},
    {id:'two',messages:[]}].map(JSON.stringify);
  const source=await f.load(),preparation=await f.prepare(source,{format});
  const opened=await source.openCapture(preparation);await f.retain(opened,preparation.ledger);
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'installed-gmail-thread-test'));
  assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse),[
    {id:'one',labels:[],last_message_date:'1969-12-31T23:59:59.999Z',message_count:'1',subject:null},
    {id:'two',labels:[],last_message_date:null,message_count:'0',subject:null}]);
  assert.equal(f.state.requests.length,4);
  const targets=f.state.requests.map(request=>new URL(request.path,'https://fixture.test'));
  assert(targets[0].pathname.endsWith('/threads'));assert.equal(targets[1].searchParams.get('pageToken'),'next/+');
  assert(targets[2].pathname.endsWith('/threads/one'));assert(targets[3].pathname.endsWith('/threads/two'));
  assert.equal(targets[2].searchParams.get('format'),'metadata');
  assert.deepEqual(targets[2].searchParams.getAll('metadataHeaders'),['Subject','Date']);
  assert.equal(source.sourceReadAccesses[0].resource,'threads');
  const usage=f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger);
  await assert.rejects(async()=>opened.close(),{code:'MoonBitHostFailure'});
  assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(preparation.ledger),usage);
  assert.equal(f.state.requests.length,4);
});

test('installed Gmail threads cannot borrow the labels Account decision',async t=>{
  const f=await installedGmailFixture(t,{resource:'threads',accountResource:'labels'}),source=await f.load();
  await assert.rejects(f.prepare(source),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Gmail threads stops after the list before any dependent get',async t=>{
  const f=await installedGmailFixture(t,{resource:'threads'});
  f.state.pages=[JSON.stringify({threads:[{id:'one'}]})];
  const stop=new AbortController();
  f.state.beforeResponse=()=>{stop.abort(new Error('original thread request stopped'));};
  const source=await f.load(),preparation=await f.prepare(source);let original;
  await assert.rejects(source.openCapture({...preparation,signal:stop.signal}),error=>{original=error;return !!error;});
  assert.equal(f.state.requests.length,1);await f.retain(original,preparation.ledger);
});

test('installed Gmail threads lost get response retains Unknown without another send',async t=>{
  const f=await installedGmailFixture(t,{resource:'threads'});
  f.state.pages=[JSON.stringify({threads:[{id:'one'}]})];
  f.state.beforeResponse=request=>{if(f.state.requests.length===2)request.socket.destroy();};
  const source=await f.load(),preparation=await f.prepare(source);let original;
  await assert.rejects(source.openCapture(preparation),error=>{
    original=error;return error.outcome==='unknown'&&error.recovery?.cleanupPending()===true;
  });
  await f.retain(original.recovery,preparation.ledger);
  await original.recovery.close();assert.equal(await original.recovery.cleanup(),false);
  assert.equal(original.recovery.cleanupPending(),true);assert.equal(f.state.requests.length,2);
});
