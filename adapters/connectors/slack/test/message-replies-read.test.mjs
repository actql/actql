import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {messageHistoryFixture,messagePage} from './message-history-read.fixture.mjs';
import {createSlackMessageRepliesReader,SLACK_MESSAGE_REPLIES_OPERATION,
  SlackMessageRepliesReadFailure} from '../site/message-history-read.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';

// Actual Common, Account, Credential, SQLite and TLS. The response-ticket and
// consumer callbacks below are explicit sequencing fixtures, not a normal
// ReaderLoan supplier, complete Source coalescer or installed funding claim.
async function repliesFixture(t,{moon=provider,sourceTs='1.000001'}={}) {
  const f=await messageHistoryFixture(t,{accounted:false});
  f.state.pages=[messagePage([{type:'message',ts:sourceTs,thread_ts:sourceTs,text:'parent',reply_count:2}],null)];
  const originals=[],historyRows=[],replyRows=[];
  let pending;
  const chargeResponse=body=>{
    assert.equal(pending,undefined);
    pending=Object.freeze({body});return pending;
  };
  const consume=(rows,{charge})=>{
    assert.equal(charge,pending);replyRows.push(...rows);pending=undefined;
  };
  const history=f.create({moon,chargeResponse,
    consumeObservation:charge=>{assert.equal(charge,pending);pending=undefined;},
    consumePage:(rows,meta)=>{
      assert.equal(meta.charge,pending);originals.push(meta.originalPage);
      historyRows.push(...rows);pending=undefined;
    }});
  await history.read();
  const scope=Object.freeze({...f.scope,operation:SLACK_MESSAGE_REPLIES_OPERATION});
  const grant=f.control.prepare(scope);f.journal.acceptGrant(f.sign(grant),f.control);
  const options={historyReader:history,originalPage:originals[0],index:0,
    names:provider.slackMessageColumnNames(),initialAuthorization:{grant,scope,useId:'initial-replies'},
    credential:f.options.credential,current:f.current,
    authorizationFor:({operation,index})=>{
      assert.equal(operation,SLACK_MESSAGE_REPLIES_OPERATION);
      return {grant,scope,useId:`replies-${index}`};
    },limits:{...f.options.limits,maxComparisonNodes:200,maxComparisonDepth:16,
      maxComparisonTextBytes:8192,maxWork:100000},chargeResponse,consumePage:consume};
  f.state.replyPages=[messagePage([
    {type:'message',ts:sourceTs,thread_ts:sourceTs,text:'parent',reply_count:2},
    {type:'message',ts:'2.000001',thread_ts:sourceTs,text:'one'}],'reply+/= cursor'),
    messagePage([{type:'message',ts:'2.000001',thread_ts:sourceTs,text:'one'},
      {type:'message',ts:'3.000001',thread_ts:sourceTs,text:'two'}],null)];
  f.state.beforeResponse=()=>assert.equal(pending,undefined);
  return {...f,history,historyRows,replyRows,originals,replyScope:scope,replyGrant:grant,replyOptions:options,
    createReply:overrides=>createSlackMessageRepliesReader({...options,...overrides}),
    consume,assertNoPending:()=>assert.equal(pending,undefined)};
}

test('Slack replies actual original history selection retains prefix and distinct operation uses',async t=>{
  const f=await repliesFixture(t),reader=f.createReply();
  const result=await reader.read();
  assert.equal(result.pages,2);assert.equal(result.rowCount,3);
  assert.deepEqual(f.replyRows.map(r=>[r.id,r.ts,r.reply_count]),[
    ['C1:1.000001','1.000001','2'],['C1:2.000001','2.000001',null],['C1:3.000001','3.000001',null]]);
  assert.deepEqual(f.state.requests.map(r=>r.path),['/api/auth.test',
    '/api/conversations.history?channel=C1&limit=10',
    '/api/conversations.replies?channel=C1&ts=1.000001&limit=10',
    '/api/conversations.replies?channel=C1&ts=1.000001&limit=10&cursor=reply%2B%2F%3D%20cursor']);
  assert.equal(new Set(f.journal.recover().map(r=>r.grantCid)).size,3);
  assert.equal(result.observations.length,2);f.assertNoPending();
  assert.equal(reader.observe().cleanupConfirmed,false);
  await assert.rejects(reader.read(),{code:'SlackMessageRepliesReaderAlreadyStarted'});
  assert.throws(()=>f.createReply(),{code:'ForeignSlackMessageRepliesSelection'});
  await assert.rejects(({...reader}).read(),{code:'ForeignSlackMessageRepliesReader'});
});

test('Slack replies exact original lower time boundary never rounds nanoseconds',async t=>{
  const f=await repliesFixture(t,{sourceTs:'0.999999999'});
  f.state.replyPages=[messagePage([{type:'message',ts:'0.999999999',thread_ts:'0.999999999'},
    {type:'message',ts:'1.000000001',thread_ts:'0.999999999'}],null,true),
    messagePage([{type:'message',ts:'1.000000002',thread_ts:'0.999999999'}],null)];
  assert.equal((await f.createReply().read()).rowCount,3);
  assert.equal(f.state.requests[3].path,
    '/api/conversations.replies?channel=C1&ts=0.999999999&limit=10&oldest=1.000000001&inclusive=false');
  f.assertNoPending();
});

test('Slack replies reject copied foreign selection and credential before any dependent send',async t=>{
  const f=await repliesFixture(t),foreign=await repliesFixture(t);
  for (const overrides of [{originalPage:{...f.originals[0]}},{originalPage:foreign.originals[0]},
    {historyReader:{...f.history}},{index:1},
    {credential:{...f.options.credential,binding:{}}}]) {
    assert.throws(()=>f.createReply(overrides));
  }
  assert.throws(()=>f.createReply({initialAuthorization:f.options.initialAuthorization}),
    {code:'ForeignSlackMessageRepliesAuthorization'});
  assert.throws(()=>f.createReply({initialAuthorization:{grant:f.replyGrant,
    scope:{...f.replyScope,dispatchRequestCid:'sha256:'+'f'.repeat(64)},useId:'foreign'}}),
    {code:'ForeignSlackMessageRepliesAuthorization'});
  assert.equal(f.state.requests.length,2);assert.equal(f.state.replyRequests,0);
});

test('Slack replies current or stop after consumption prevents the next Common request and send',async t=>{
  for (const stop of [false,true]) {
    let next=0;
    const moon={...provider,slackNextMessageRepliesRequest(...args){
      assert.equal(this,moon);next++;return provider.slackNextMessageRepliesRequest(...args);
    }};
    const f=await repliesFixture(t,{moon});let current=true,reader;
    reader=f.createReply({current:async()=>{await f.current();if(!current)throw Error('revoked');},
      consumePage:(...args)=>{f.consume(...args);if(stop)reader.requestStop();else current=false;}});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageRepliesReadFailure&&e.observations.length===1);
    assert.equal(next,0);assert.equal(f.state.replyRequests,1);f.assertNoPending();
    await assert.rejects(reader.read(),{code:'SlackMessageRepliesReaderAlreadyStarted'});
  }
});

test('Slack replies retain malformed or unavailable terminal observations without completion or resend',async t=>{
  for (const mode of ['missing-parent','changed-repeat','limited','malformed']) {
    const f=await repliesFixture(t);
    if(mode==='missing-parent')f.state.replyPages=[messagePage([{type:'message',ts:'2.000001',thread_ts:'1.000001'}],null)];
    if(mode==='changed-repeat')f.state.replyPages[1]=messagePage([{type:'message',ts:'2.000001',thread_ts:'1.000001',text:'changed'}],null);
    if(mode==='limited')f.state.replyPages=[{...messagePage([{type:'message',ts:'1.000001'}],null),is_limited:true}];
    if(mode==='malformed')f.state.replyPages=['{"ok":true,"messages":['];
    const reader=f.createReply();
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageRepliesReadFailure&&e.observations.length>0);
    const sends=f.state.replyRequests;
    await assert.rejects(reader.read(),{code:'SlackMessageRepliesReaderAlreadyStarted'});
    assert.equal(f.state.replyRequests,sends);assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('Slack replies capture original provider receiver and columns before source or dependent awaits',async t=>{
  let calls=0;
  const moon={...provider,slackMessageRepliesRequestJson(...args){
    assert.equal(this,moon);calls++;return provider.slackMessageRepliesRequestJson(...args);
  }};
  const f=await repliesFixture(t,{moon});
  moon.slackMessageRepliesRequestJson=()=>{throw Error('replaced');};
  const names=['ts'];let reads=0;
  Object.defineProperty(names,0,{get(){reads++;return reads===1?'ts':'text';}});
  names.slice=()=>['text'];names.some=()=>false;
  const reader=f.createReply({names});assert.equal(reads,1);
  await reader.read();assert.equal(reads,1);assert.equal(calls,2);
  assert.deepEqual(f.replyRows,[{ts:'1.000001'},{ts:'2.000001'},{ts:'3.000001'}]);
});

test('Slack replies lost response retains the original Unknown use and cannot resend',async t=>{
  const f=await repliesFixture(t);
  f.state.beforeResponse=request=>{if(request.url.startsWith('/api/conversations.replies'))request.socket.destroy();};
  const reader=f.createReply();
  await assert.rejects(reader.read(),e=>e instanceof SlackMessageRepliesReadFailure&&e.cause.code==='ECONNRESET');
  const original=f.journal.recover().find(entry=>entry.outcome==='unknown');assert(original);
  await assert.rejects(invokeScopedCredentialOperation({
    authorization:{grant:f.replyGrant,scope:f.replyScope,useId:'replies-0'},
    credential:f.options.credential,callResource:callHttpsCredentialResource,
    operation:SLACK_MESSAGE_REPLIES_OPERATION,method:'GET',path:'/api/conversations.replies',
    query:[['channel','C1'],['ts','1.000001'],['limit','10']],
    maxResponseBytes:f.options.limits.maxResponseBytes}),{code:'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(f.journal.inspect(original.useCid).outcome,'unknown');
  assert.equal(f.state.requests.length,3);
  await assert.rejects(reader.read(),{code:'SlackMessageRepliesReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,3);
});

test('Slack replies original byte row page comparison and work limits remain fail closed',async t=>{
  for (const override of [{maxTotalResponseBytes:1},{maxTotalRows:1},{maxPages:1},
    {maxWork:1},{maxComparisonTextBytes:1}]) {
    const f=await repliesFixture(t);
    const reader=f.createReply({limits:{...f.replyOptions.limits,...override}});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageRepliesReadFailure&&e.observations.length>0);
    const sends=f.state.requests.length;
    await assert.rejects(reader.read(),{code:'SlackMessageRepliesReaderAlreadyStarted'});
    assert.equal(f.state.requests.length,sends);assert(sends<=4);
  }
});
