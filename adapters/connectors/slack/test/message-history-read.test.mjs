import assert from 'node:assert/strict';
import test from 'node:test';
import {SlackMessageHistoryReadFailure,SLACK_MESSAGE_HISTORY_OPERATION} from '../site/message-history-read.mjs';
import {messageHistoryFixture,messagePage} from './message-history-read.fixture.mjs';
const path='/api/conversations.history?channel=C1&limit=10';

test('Slack history actual Account Credential TLS and RowRun retain exact message counts and instants',async t=>{
  for(const format of ['sql','aql']){
    const f=await messageHistoryFixture(t,{format}),reader=f.create(),result=await reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,2);
    assert.deepEqual(f.state.rows.map(r=>[r.id,r.ts,r.reply_count,r.posted_at]),[
      ['C1:2.000001','2.000001','0','1970-01-01T00:00:02.000001Z'],
      ['C1:1.000002','1.000002','2','1970-01-01T00:00:01.000002Z']]);
    assert.deepEqual(f.state.requests.map(r=>r.path),['/api/auth.test',path,path+'&cursor=opaque%2B%2F%3D%20cursor']);
    assert.equal(f.state.observationCharges,1);assert.equal(f.state.charges,3);
    f.row.finish();assert.equal(f.row.captureCount(),2);
    assert.equal(new Set(f.journal.recover().map(r=>r.grantCid)).size,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'SlackMessageHistoryReaderAlreadyStarted'});
  }
});

test('Slack history exact large count survives retained response token and accounted capture',async t=>{
  const f=await messageHistoryFixture(t);
  f.state.pages=['{"ok":true,"messages":[{"type":"message","ts":"1.000001","reply_count":9007199254740993}],"has_more":false}'];
  assert.equal((await f.create().read()).rowCount,1);
  assert.equal(f.state.rows[0].reply_count,'9007199254740993');
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

test('Slack history time continuation comes from original Common request without rounding',async t=>{
  const f=await messageHistoryFixture(t);
  f.state.pages=[messagePage([{type:'message',ts:'2.000000001',text:'a'}],null,true),
    messagePage([{type:'message',ts:'1.999999999',text:'b'}],null)];
  assert.equal((await f.create().read()).rowCount,2);
  assert.equal(f.state.requests[2].path,path+'&latest=2.000000001&inclusive=false');
  f.row.finish();assert.equal(f.row.captureCount(),2);
});

test('Slack history current and stop after page consumption prevent next Common request and send',async t=>{
  for(const stop of [false,true]){
    const f=await messageHistoryFixture(t);let current=true,next=0,reader;
    const moon={...f.options.moon,slackNextMessageHistoryRequest(...args){
      next++;return f.options.moon.slackNextMessageHistoryRequest(...args);
    }};
    reader=f.create({moon,current:async()=>{await f.current();if(!current)throw new Error('current revoked');},
      consumePage:async(...args)=>{await f.options.consumePage(...args);if(stop)reader.requestStop(new Error('stop'));else current=false;}});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length===2);
    assert.equal(next,0);assert.equal(f.state.requests.length,2);f.row.assertNoCapture();
  }
});

test('Slack identity consumption currentness is checked before preparing any history request',async t=>{
  for(const stop of [false,true]){
    const f=await messageHistoryFixture(t);let current=true,prepared=0,reader;
    const moon={...f.options.moon,slackPrepareMessageHistory(...args){
      prepared++;return f.options.moon.slackPrepareMessageHistory(...args);
    }};
    reader=f.create({moon,current:async()=>{await f.current();if(!current)throw new Error('current revoked');},
      consumeObservation:async(...args)=>{await f.options.consumeObservation(...args);if(stop)reader.requestStop(new Error('stop'));else current=false;}});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length===1);
    assert.equal(prepared,0);assert.equal(f.state.requests.length,1);f.row.assertNoCapture();
  }
});

test('Slack history grant purpose and original invocation cannot be retargeted',async t=>{
  const f=await messageHistoryFixture(t);
  assert.throws(()=>f.create({initialAuthorization:{...f.options.initialAuthorization,
    scope:{...f.scope,operation:'slack:channels:list'}}}),{code:'ForeignSlackMessageHistoryOperation'});
  await assert.rejects(f.create({authorizationFor:({operation,index})=>{
    const original=f.options.authorizationFor({operation,index});
    return operation===SLACK_MESSAGE_HISTORY_OPERATION?{...original,scope:{...f.scope,dispatchRequestCid:'sha256:'+'d'.repeat(64)}}:original;
  }}).read(),e=>e.cause.code==='ForeignSlackMessageHistoryAuthorization');
  assert.equal(f.state.requests.length,1);f.row.assertNoCapture();
});

test('Slack history duplicate cursor message malformed value and retention cap refuse completion',async t=>{
  for(const mode of ['cursor','duplicate','malformed','retained','budget']){
    const f=await messageHistoryFixture(t);
    if(mode==='cursor')f.state.pages=[messagePage([{type:'message',ts:'2.000000'}],'again'),messagePage([{type:'message',ts:'1.000000'}],'again')];
    if(mode==='duplicate')f.state.pages=[messagePage([{type:'message',ts:'2.000000'}],'again'),messagePage([{type:'message',ts:'2.000000'}],null)];
    if(mode==='malformed')f.state.pages=[messagePage([{type:'message',ts:'2.000000',reply_count:'0'}],null)];
    if(mode==='retained')f.state.pages=[{...messagePage([],null),is_limited:true}];
    const options=mode==='budget'?{limits:{...f.options.limits,maxTotalRows:1}}:{};
    const reader=f.create(options);
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length>=2);
    assert.equal(reader.observe().cleanupConfirmed,false);f.row.assertNoCapture();
  }
});

test('Slack history workspace mismatch cannot issue a history request',async t=>{
  const f=await messageHistoryFixture(t);f.state.identity={ok:true,team_id:'T-foreign',user_id:'U'};
  await assert.rejects(f.create().read(),e=>e.cause.code==='ForeignSlackWorkspace'&&e.observations.length===1);
  assert.equal(f.state.requests.length,1);f.row.assertNoCapture();
});
