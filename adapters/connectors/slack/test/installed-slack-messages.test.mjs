import {ledgerUsageFieldsFor} from '../../../host-node/fixtures/ledger-usage.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createPublicKey} from 'node:crypto';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {installedSlackMessagesFixture as fixture} from './installed-slack-messages.fixture.mjs';
import {assertRetiredSlackCapture} from './installed-slack.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

test('installed Slack messages uses original messages Account decisions and one charged RowRun for channels history and replies',async t=>{
  for(const format of ['sql','aql']){
    const f=await fixture(t),source=await f.load();
    const p=await f.prepare(source,{format,selection:'id, channel, ts, text, reply_count, posted_at'});
    const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-messages'));
    const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
    assert.deepEqual(rows,[
      {id:'C1:1.000001',channel:'C1',ts:'1.000001',text:'parent',reply_count:'1',posted_at:'1970-01-01T00:00:01.000001Z'},
      {id:'C1:2.000001',channel:'C1',ts:'2.000001',text:'child',reply_count:null,posted_at:'1970-01-01T00:00:02.000001Z'},
      {id:'D1:3.000000001',channel:'D1',ts:'3.000000001',text:'direct',reply_count:'0',posted_at:'1970-01-01T00:00:03.000000001Z'}]);
    assert.deepEqual(JSON.parse(f.profile.accountConfigurationWire).entries[0].resource.any_of,['messages']);
    assert.equal(f.state.requests.length,8);
    assert.deepEqual(f.state.requests.map(r=>new URL(r.path,f.scope.resourceOrigin).pathname),[
      '/api/auth.test','/api/conversations.list','/api/auth.test','/api/conversations.history',
      '/api/conversations.replies','/api/auth.test','/api/conversations.history','/api/conversations.replies']);
    assert.equal(new URL(f.state.requests[1].path,f.scope.resourceOrigin).searchParams.get('types'),
      'public_channel,private_channel,mpim,im');
    assert.equal(f.state.resolutions,8);
    await opened.close();
    assert.deepEqual(ledgerUsageFieldsFor(f.common.clientProgramMultiCapturedLedgerUsage(p.ledger),
      ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']),[0n,0n,0n,0n]);
  }
});

test('installed Slack channels Account permission cannot substitute for messages permission',async t=>{
  for(const [options,code] of [[{resource:'channels'},'ACTQL_E_ACCOUNT_NO_MATCH'],
    [{resource:'messages',account:'deny'},'ACTQL_E_ACCOUNT_DENIED']]){
    const f=await fixture(t,options),source=await f.load();
    await assert.rejects(f.prepare(source,{resource:'messages',selection:'id, text'}),{code});
    assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
  }
});

test('installed Slack broad messages realization refuses invalid excluded rows rather than hiding them behind a residual filter',async t=>{
  const f=await fixture(t);f.state.replies.C1[1].text=[];
  const source=await f.load(),p=await f.prepare(source,{selection:'id',predicate:"channel = 'not-selected'"});
  let original;
  await assert.rejects(source.openCapture(p),error=>{original=error;return error.code==='MoonBitHostFailure';});
  await f.retain(original,p.ledger);
  assert.equal(f.state.requests.length,5);
  await assertRetiredSlackCapture(f,p,original);
  assert.equal(new URL(f.state.requests[3].path,f.scope.resourceOrigin).searchParams.has('oldest'),false);
  assert.equal(new URL(f.state.requests[3].path,f.scope.resourceOrigin).searchParams.has('latest'),false);
});

test('installed Slack messages preserves the original finite exchange ceiling without completing a partial channel prefix',async t=>{
  const f=await fixture(t);f.profile.limits={...f.profile.limits,maxPages:7};
  const source=await f.load(),p=await f.prepare(source,{selection:'id'});let original;
  await assert.rejects(source.openCapture(p),error=>{original=error;return error.code==='InstalledSlackMessagesRequestLimit';});
  await f.retain(original,p.ledger);
  assert.equal(f.state.requests.length,7);await assertRetiredSlackCapture(f,p,original);
});

test('installed Slack messages lost original reply keeps recovery and never resends the exchange',async t=>{
  const f=await fixture(t),before=f.state.beforeResponse;
  f.state.beforeResponse=async(request,response)=>{
    if(request.url.startsWith('/api/conversations.replies?')){request.socket.destroy();return;}
    await before(request,response);
  };
  const source=await f.load(),p=await f.prepare(source,{selection:'id'});let original;
  await assert.rejects(source.openCapture(p),error=>{original=error;return error.code==='ECONNRESET';});
  await f.retain(original,p.ledger);
  assert.equal(f.state.requests.length,5);await assertRetiredSlackCapture(f,p,original);
  // openCapture constructs a new RowRun/nonce, not a cleanup retry of this
  // failed reader. Retry only this original Source owner's retirement instead.
  await source.close();await source.close();assert.equal(f.state.requests.length,5);
  const publicKey=createPublicKey(await readFile(join(f.root,'credential-authority.pub')));
  const journal=openSqliteCredentialJournal(f.site.journalRoot,{credentialAuthorities:new Map([
    [f.site.credentialAuthorityId,new Map([[f.site.credentialKeyId,publicKey]])]])});
  try{
    assert.deepEqual(journal.recover().map(use=>use.outcome).sort(),
      ['succeeded','succeeded','succeeded','succeeded','unknown']);
  }finally{journal.close();}
});

test('installed Slack messages stop after the last response cannot publish a partial original prefix',async t=>{
  const f=await fixture(t),stop=new AbortController();
  f.state.afterResponse=request=>{
    const url=new URL(request.url,f.scope.resourceOrigin);
    if(url.pathname==='/api/conversations.replies'&&url.searchParams.get('channel')==='D1')stop.abort(new Error('OriginalMessagesStop'));
  };
  const source=await f.load(),p=await f.prepare(source,{selection:'id'});let original;
  await assert.rejects(source.openCapture({...p,signal:stop.signal}),error=>{original=error;return error.code==='ABORT_ERR';});
  await f.retain(original,p.ledger);
  assert.equal(f.state.requests.length,8);await assertRetiredSlackCapture(f,p,original);
});

test('installed Slack messages empty original conversation extent captures no synthetic message',async t=>{
  const f=await fixture(t);f.state.conversations=[];
  const source=await f.load(),p=await f.prepare(source,{selection:'id'}),opened=await source.openCapture(p);
  await f.retain(opened,p.ledger);
  const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-empty-messages'));
  assert.deepEqual(f.common.clientProgramSourceCaptureExportRows(exported),[]);
  assert.equal(f.state.requests.length,2);assert.equal(f.state.resolutions,2);
});
