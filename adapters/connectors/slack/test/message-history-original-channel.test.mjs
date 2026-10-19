// Actual Common/Credential/Account/SQLite/TLS and vendor Catalog originals.
// Response tickets below are explicit sequencing doubles, not a funded Source
// or proof that a channel listing covers an installed messages Source.
import assert from 'node:assert/strict';
import test from 'node:test';
import {channelListFixture,channelPage} from './channel-list-read.fixture.mjs';
import {selectSlackOriginalChannel,createSlackChannelListReaderForHistory,
  createSlackConversationListReaderForHistory} from '../site/channel-list-read.mjs';
import {createSlackMessageHistoryReaderFromChannel,SLACK_MESSAGE_HISTORY_OPERATION,
  SLACK_WORKSPACE_IDENTITY_OPERATION} from '../site/message-history-read.mjs';

async function fixture(t,{moon,conversations=false}={}) {
  const f=await channelListFixture(t,{accounted:false});
  const provider=moon?.(f.options.moon)??f.options.moon;
  f.state.pages=[channelPage([{id:'C-original',name:'original'}],null)];
  f.state.beforeResponse=async(request,response)=>{
    if(request.url.startsWith('/api/conversations.history?')){
      response.writeHead(200,{'content-type':'application/json'});
      response.end(JSON.stringify({ok:true,messages:[{type:'message',ts:'1.000000001',text:'original'}],
        has_more:false,response_metadata:{next_cursor:null}}));
    }
  };
  let pending;
  const pages=[],rows=[];
  const chargeResponse=body=>{
    assert.equal(pending,undefined);pending=Object.freeze({body});return pending;
  };
  const consumeObservation=charge=>{assert.equal(charge,pending);pending=undefined;};
  let channels;
  const createChannels=conversations ? createSlackConversationListReaderForHistory : createSlackChannelListReaderForHistory;
  channels=createChannels({...f.options,moon:provider,chargeResponse,consumeObservation,consumePage:(value,{charge,originalPage})=>{
    assert.equal(charge,pending);assert(value.length>0);pages.push(originalPage);
    assert.throws(()=>selectSlackOriginalChannel(channels,originalPage,0),{code:'ForeignSlackOriginalChannel'});
    pending=undefined;
  }});
  const scope=Object.freeze({...f.scope,operation:SLACK_MESSAGE_HISTORY_OPERATION});
  const grant=f.control.prepare(scope);f.journal.acceptGrant(f.sign(grant),f.control);
  // This identity observation has a distinct explicit grant/use. The previous
  // channels identity grant is exhausted and is not silently reset or reused.
  const authScope=Object.freeze({...f.authScope,maxUses:2});
  const authGrant=f.control.prepare(authScope);f.journal.acceptGrant(f.sign(authGrant),f.control);
  const options={moon:provider,workspaceId:f.options.workspaceId,names:['id','ts'],
    initialAuthorization:{grant,scope,useId:'history-initial'},credential:f.options.credential,
    limits:f.options.limits,current:f.current,chargeResponse,consumeObservation,
    consumePage:(value,{charge})=>{assert.equal(charge,pending);rows.push(...value);pending=undefined;},
    authorizationFor:({operation,index})=>operation===SLACK_WORKSPACE_IDENTITY_OPERATION
      ?{grant:authGrant,scope:authScope,useId:'history-identity'}:{grant,scope,useId:'history-'+index}};
  return {...f,provider,channels,pages,rows,options,scope,grant,
    select:()=>selectSlackOriginalChannel(channels,pages[0],0),
    create:(channelSelection,overrides)=>createSlackMessageHistoryReaderFromChannel({...options,channelSelection,...overrides}),
    assertNoPending:()=>assert.equal(pending,undefined)};
}

test('Slack history consumes its original completed channel occurrence through the actual HTTPS caller',async t=>{
  let prepared=0,receiver;
  const f=await fixture(t,{moon:original=>{
    receiver={...original,slackPrepareMessageHistoryFromChannel(...args){
      assert.equal(this,receiver);prepared++;return original.slackPrepareMessageHistoryFromChannel(...args);
    }};return receiver;
  }});
  await f.channels.read();
  assert.equal(f.channels.observe().originalExchanges,2);
  assert.equal(f.channels.observe().originalChannelPages,1);
  const selection=f.select();
  receiver.slackPrepareMessageHistoryFromChannel=()=>{throw Error('replacement must not run');};
  const reader=f.create(selection);assert.equal(prepared,1);
  assert.throws(()=>f.create(selection),{code:'ForeignSlackOriginalChannel'});
  const result=await reader.read();
  assert.equal(result.rowCount,1);
  assert.deepEqual(f.rows,[{id:'C-original:1.000000001',ts:'1.000000001'}]);
  assert.deepEqual(f.state.requests.map(r=>r.path),['/api/auth.test',
    '/api/conversations.list?types=public_channel%2Cprivate_channel&exclude_archived=false&limit=10',
    '/api/auth.test','/api/conversations.history?channel=C-original&limit=10']);
  assert.equal(reader.observe().cleanupConfirmed,false);f.assertNoPending();
});

test('Slack channel selection rejects copied foreign out-of-range and reused page occurrences',async t=>{
  const f=await fixture(t);await f.channels.read();
  for(const token of [{},{...f.pages[0]}])assert.throws(()=>selectSlackOriginalChannel(f.channels,token,0),{code:'ForeignSlackOriginalChannel'});
  for(const index of [-1,1,2147483647])assert.throws(()=>selectSlackOriginalChannel(f.channels,f.pages[0],index),{code:'ForeignSlackOriginalChannel'});
  assert.throws(()=>selectSlackOriginalChannel({...f.channels},f.pages[0],0),{code:'ForeignSlackChannelListReader'});
  const selected=f.select();
  assert.throws(()=>f.select(),{code:'ForeignSlackOriginalChannel'});
  assert.throws(()=>f.create({...selected}),{code:'ForeignSlackOriginalChannel'});
  assert.throws(()=>f.create(selected,{moon:{...f.provider}}),{code:'ForeignSlackOriginalChannel'});
  assert.equal(f.state.requests.length,2);f.assertNoPending();
});

test('Slack original channel binding cannot accept a different credential workspace or authored window',async t=>{
  const f=await fixture(t);await f.channels.read();const selected=f.select();
  assert.throws(()=>f.create(selected,{workspaceId:'foreign'}),{code:'ForeignSlackOriginalChannel'});
  assert.throws(()=>f.create(selected,{credential:{...f.options.credential,binding:{}}}),{code:'ForeignSlackOriginalChannel'});
  assert.throws(()=>f.create(selected,{channel:'C-forged'}),{code:'InvalidSlackChannelHistoryRead'});
  assert.throws(()=>f.create(selected,{requestWindow:{oldest:'1.0',latest:'2.0'}}),{code:'InvalidSlackChannelHistoryRead'});
  assert.equal(f.state.requests.length,2);f.assertNoPending();
});

test('Slack original channel stop after a child await prevents identity and history sends',async t=>{
  const f=await fixture(t);await f.channels.read();const selected=f.select();
  const reader=f.create(selected,{current:async()=>{await f.current();f.channels.requestStop('original stopped');}});
  await assert.rejects(reader.read(),e=>e.code==='SlackMessageHistoryReadFailed'&&e.cause.code==='ForeignSlackOriginalChannel');
  assert.equal(f.state.requests.length,2);assert.equal(f.rows.length,0);f.assertNoPending();
});

test('Slack failed typed channel-history preparation is not rebound with a larger bound',async t=>{
  const f=await fixture(t);await f.channels.read();const selected=f.select();
  assert.throws(()=>f.create(selected,{limits:{...f.options.limits,maxValueTextBytes:1}}),{code:'MoonBitHostFailure'});
  assert.throws(()=>f.create(selected),{code:'ForeignSlackOriginalChannel'});
  assert.equal(f.state.requests.length,2);f.assertNoPending();
});

test('Slack ordinary channel readers preserve their metadata shape and do not issue history selections',async t=>{
  const f=await channelListFixture(t);
  f.state.pages=[channelPage([{id:'C-ordinary'}],null)];
  let metadata;
  const reader=f.create({consumePage:(rows,original)=>{
    metadata=original;assert.deepEqual(Object.keys(original),['charge']);f.options.consumePage(rows,original);
  }});
  await reader.read();f.row.finish();assert.equal(f.row.captureCount(),1);
  assert.throws(()=>selectSlackOriginalChannel(reader,metadata.originalPage,0),{code:'ForeignSlackOriginalChannel'});
});


test('Slack lost channel reply retains the original pending exchange and cannot issue a history selection',async t=>{
  const f=await fixture(t);
  f.state.beforeResponse=request=>{if(request.url.startsWith('/api/conversations.list?'))request.socket.destroy();};
  await assert.rejects(f.channels.read(),e=>e.code==='SlackChannelListReadFailed');
  assert.equal(f.channels.observe().originalExchanges,2);
  assert.equal(f.channels.observe().originalChannelPages,0);
  assert.equal(f.channels.observe().cleanupConfirmed,false);
  assert.throws(()=>selectSlackOriginalChannel(f.channels,{},0),{code:'ForeignSlackOriginalChannel'});
  await assert.rejects(f.channels.read(),{code:'SlackChannelListReaderAlreadyStarted'});
  assert.equal(f.state.requests.length,2);assert.equal(f.rows.length,0);f.assertNoPending();
});

test('Slack history discovery selects all conversation kinds and binds original IM and MPIM history',async t=>{
  for(const [id,flags] of [['D-original',{is_im:true,is_mpim:false}],['G-original',{is_im:false,is_mpim:true}]]){
    const f=await fixture(t,{conversations:true});
    f.state.pages=[channelPage([{id,...flags}],null)];
    await f.channels.read();
    const reader=f.create(f.select());await reader.read();
    assert.deepEqual(f.state.requests.map(r=>r.path),['/api/auth.test',
      '/api/conversations.list?types=public_channel%2Cprivate_channel%2Cmpim%2Cim&exclude_archived=false&limit=10',
      '/api/auth.test',`/api/conversations.history?channel=${id}&limit=10`]);
    assert.deepEqual(f.rows,[{id:id+':1.000000001',ts:'1.000000001'}]);
    assert.equal(reader.observe().cleanupConfirmed,false);f.assertNoPending();
  }
});

test('Slack broader discovery checks unselected conversation fields before history selection',async t=>{
  const f=await fixture(t,{conversations:true});
  f.state.pages=[channelPage([{id:'D-original',is_im:true,name:[]}],null)];
  await assert.rejects(f.channels.read(),e=>e.code==='SlackChannelListReadFailed'&&e.cause.code==='MoonBitHostFailure');
  assert.throws(()=>f.select(),{code:'ForeignSlackOriginalChannel'});
  assert.equal(f.state.requests.length,2);assert.equal(f.rows.length,0);
  assert.equal(f.channels.observe().originalExchanges,2);
});

test('Slack broader discovery never falls back to the ordinary channel projector when its port is absent',async t=>{
  const f=await channelListFixture(t,{accounted:false});
  const moon={...f.options.moon};delete moon.slackProjectHistoryConversationList;
  assert.throws(()=>createSlackConversationListReaderForHistory({...f.options,moon}),{code:'InvalidSlackChannelListRead'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});
