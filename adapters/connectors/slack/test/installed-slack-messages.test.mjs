import assert from 'node:assert/strict';
import test from 'node:test';
import {installedSlackChannelsFixture} from './installed-slack-channels.fixture.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

async function fixture(t,{account='allow',resource='messages'}={}){
  const f=await installedSlackChannelsFixture(t,{account,resource});
  // Eight actual exchanges: identity/list, then identity/history/replies for
  // each selected conversation. This explicit component bound is not normal
  // physical funding or proof of escaped raw/callback retirement.
  f.profile.limits={...f.profile.limits,maxPages:8};
  f.state.messages={C1:[{type:'message',ts:'1.000001',text:'parent',reply_count:1}],
    D1:[{type:'message',ts:'3.000000001',text:'direct'}]};
  f.state.replies={C1:[{type:'message',ts:'1.000001',thread_ts:'1.000001',text:'parent',reply_count:1},
    {type:'message',ts:'2.000001',thread_ts:'1.000001',text:'child'}],
  D1:[{type:'message',ts:'3.000000001',text:'direct'}]};
  f.state.beforeResponse=async(request,response)=>{
    const url=new URL(request.url,f.scope.resourceOrigin);let body;
    if(url.pathname==='/api/conversations.list')body={ok:true,channels:[
      {id:'C1',is_im:false,is_mpim:false},{id:'D1',is_im:true,is_mpim:false}],response_metadata:{next_cursor:null}};
    if(url.pathname==='/api/conversations.history')body={ok:true,messages:f.state.messages[url.searchParams.get('channel')],
      has_more:false,response_metadata:{next_cursor:null}};
    if(url.pathname==='/api/conversations.replies')body={ok:true,messages:f.state.replies[url.searchParams.get('channel')],
      has_more:false,response_metadata:{next_cursor:null}};
    if(body!==undefined){response.writeHead(200,{'content-type':'application/json'});response.end(JSON.stringify(body));}
    await f.state.afterResponse?.(request,response);
  };
  return f;
}

test('installed Slack messages uses original messages Account decisions and one charged RowRun for channels history and replies',async t=>{
  for(const format of ['sql','aql']){
    const f=await fixture(t),source=await f.load();
    const p=await f.prepare(source,{format,selection:'id, channel, ts, text, reply_count'});
    const opened=await source.openCapture(p);await f.retain(opened,p.ledger);
    const exported=checked(f.common.clientProgramExportSourceCapture(opened.capture.source(),opened.requirement,'slack-messages'));
    const rows=f.common.clientProgramSourceCaptureExportRows(exported).map(JSON.parse);
    assert.deepEqual(rows.map(r=>[r.id,r.channel,r.ts,r.text,r.reply_count]),[
      ['C1:1.000001','C1','1.000001','parent','1'],
      ['C1:2.000001','C1','2.000001','child',null],
      ['D1:3.000000001','D1','3.000000001','direct','0']]);
    assert.equal(rows[2].posted_at,'1970-01-01T00:00:03.000000001Z');
    assert.deepEqual(JSON.parse(f.profile.accountConfigurationWire).entries[0].resource.any_of,['messages']);
    assert.equal(f.state.requests.length,8);
    assert.deepEqual(f.state.requests.map(r=>new URL(r.path,f.scope.resourceOrigin).pathname),[
      '/api/auth.test','/api/conversations.list','/api/auth.test','/api/conversations.history',
      '/api/conversations.replies','/api/auth.test','/api/conversations.history','/api/conversations.replies']);
    assert.equal(new URL(f.state.requests[1].path,f.scope.resourceOrigin).searchParams.get('types'),
      'public_channel,private_channel,mpim,im');
    assert.equal(f.state.resolutions,8);
    const held=f.common.clientProgramMultiCapturedLedgerUsage(p.ledger);
    await assert.rejects(async()=>opened.close(),{code:'MoonBitHostFailure'});
    assert.deepEqual(f.common.clientProgramMultiCapturedLedgerUsage(p.ledger),held);
  }
});

test('installed Slack channels Account permission cannot substitute for messages permission',async t=>{
  const f=await fixture(t,{resource:'channels'}),source=await f.load();
  await assert.rejects(f.prepare(source,{resource:'messages',selection:'id, text'}),{code:'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('installed Slack broad messages realization refuses invalid excluded rows rather than hiding them behind a residual filter',async t=>{
  const f=await fixture(t);f.state.replies.C1[1].text=[];
  const source=await f.load(),p=await f.prepare(source,{selection:'id',predicate:"channel = 'not-selected'"});
  let recovery;
  await assert.rejects(source.openCapture(p),error=>{recovery=error.recovery;return recovery!==undefined;});
  await f.retain(recovery,p.ledger);
  assert.equal(f.state.requests.length,5);
  assert.equal(recovery.cleanupPending(),true);
  assert.equal(new URL(f.state.requests[3].path,f.scope.resourceOrigin).searchParams.has('oldest'),false);
  assert.equal(new URL(f.state.requests[3].path,f.scope.resourceOrigin).searchParams.has('latest'),false);
});

test('installed Slack messages preserves the original finite exchange ceiling without completing a partial channel prefix',async t=>{
  const f=await fixture(t);f.profile.limits={...f.profile.limits,maxPages:7};
  const source=await f.load(),p=await f.prepare(source,{selection:'id'});let recovery;
  await assert.rejects(source.openCapture(p),error=>{recovery=error.recovery;return recovery!==undefined;});
  await f.retain(recovery,p.ledger);
  assert.equal(f.state.requests.length,7);assert.equal(recovery.cleanupPending(),true);
});
