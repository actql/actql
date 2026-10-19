import assert from 'node:assert/strict';
import test from 'node:test';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
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


test('Slack history lost response retains original Unknown use and refuses resend',async t=>{
  const f=await messageHistoryFixture(t);
  f.state.beforeResponse=request=>{if(request.url.startsWith('/api/conversations.history'))request.socket.destroy();};
  const reader=f.create();await assert.rejects(reader.read(),e=>e.cause.code==='ECONNRESET');
  const original=f.journal.recover().find(x=>x.outcome==='unknown');assert(original);
  await assert.rejects(invokeScopedCredentialOperation({authorization:{grant:f.grant,scope:f.scope,useId:'history-0'},
    credential:f.options.credential,callResource:callHttpsCredentialResource,operation:SLACK_MESSAGE_HISTORY_OPERATION,
    method:'GET',path:'/api/conversations.history',query:[['channel','C1'],['limit','10']],
    maxResponseBytes:f.options.limits.maxResponseBytes}),{code:'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');
  assert.equal(f.state.requests.length,2);assert.equal(f.state.resolutions,2);f.row.assertNoCapture();
});

test('Slack history captures provider receivers callbacks selection and bounds before token awaits',async t=>{
  const f=await messageHistoryFixture(t),source={...f.options.moon},moon={},limits={...f.options.limits},names=[...f.options.names];
  for(const [name,method] of Object.entries(source)){
    if(typeof method==='function')moon[name]=function(...args){assert.equal(this,moon);return Reflect.apply(method,source,args);};
  }
  const options={...f.options,moon,limits,names};
  const reader=f.create(options);
  f.state.resolved=()=>{moon.slackNextMessageHistoryRequest=()=>{throw new Error('replaced callback');};
    options.channel='C-foreign';options.current=()=>{throw new Error('replaced current');};names[0]='foreign';limits.maxPages=1;};
  assert.equal((await reader.read()).rowCount,2);f.row.finish();assert.equal(f.row.captureCount(),2);
  const copy={...reader};await assert.rejects(copy.read(),{code:'ForeignSlackMessageHistoryReader'});
  assert.throws(()=>copy.observe(),{code:'ForeignSlackMessageHistoryReader'});
  assert.throws(()=>copy.requestStop(),{code:'ForeignSlackMessageHistoryReader'});
});

test('Slack history accepts an explicit maximum page size without making it a funding grant',async t=>{
  const f=await messageHistoryFixture(t);
  f.state.pages=[messagePage([{type:'message',ts:'1.000000',text:'single'}],null)];
  assert.equal((await f.create({limits:{...f.options.limits,pageSize:1000}}).read()).rowCount,1);
  assert.equal(f.state.requests[1].path,'/api/conversations.history?channel=C1&limit=999');
  f.row.finish();assert.equal(f.row.captureCount(),1);
});


test('Slack history ordinary bots preserve original no-thread zero and explicit or hinted counts',async t=>{
  const f=await messageHistoryFixture(t);
  f.state.pages=[messagePage([
    {type:'message',subtype:'bot_message',ts:'5.000001',text:'ordinary bot'},
    {type:'message',subtype:'bot_message',ts:'4.000001',text:'thread hint',reply_users:[]},
    {type:'message',subtype:'bot_message',ts:'3.000001',text:'positive',reply_count:2},
    {type:'message',subtype:'bot_message',ts:'2.000001',text:'unknown',reply_count:null},
    {type:'message',subtype:'future_subtype',ts:'1.000001',text:'unsupported inference'},
  ],null)];
  assert.equal((await f.create().read()).rowCount,5);
  assert.deepEqual(f.state.rows.map(r=>[r.id,r.reply_count]),[
    ['C1:5.000001','0'],['C1:4.000001',null],['C1:3.000001','2'],
    ['C1:2.000001',null],['C1:1.000001',null]]);
  assert.equal(f.state.charges,2);assert.equal(f.state.observationCharges,1);
  f.row.finish();assert.equal(f.row.captureCount(),5);
});
