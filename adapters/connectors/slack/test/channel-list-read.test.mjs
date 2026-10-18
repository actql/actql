import assert from 'node:assert/strict';
import test from 'node:test';
import {SlackChannelListReadFailure,SLACK_CHANNEL_LIST_OPERATION} from '../site/channel-list-read.mjs';
import {channelListFixture,channelPage} from './channel-list-read.fixture.mjs';
const one={id:'C1',name:'one',topic:null,purpose:null,member_count:'2',is_private:false,is_archived:false,created:'1970-01-01T00:00:00.000Z'};
const two={...one,id:'C2',name:'two',member_count:'3',is_private:true,is_archived:true,created:'1970-01-01T00:00:01.000Z'};
const path='/api/conversations.list?types=public_channel%2Cprivate_channel&exclude_archived=false&limit=10';

test('Slack channels actual SQL/AQL capture both channel kinds archived rows and typed count on original grants',async t=>{
  for(const format of ['sql','aql']){
    const f=await channelListFixture(t,{format}),reader=f.create(),result=await reader.read();
    assert.equal(result.pages,2);assert.equal(result.rowCount,2);assert.deepEqual(f.state.rows,[one,two]);
    assert.deepEqual(f.state.requests.map(r=>r.path),['/api/auth.test',path,path+'&cursor=opaque%2B%2F%3D%20cursor']);
    assert.deepEqual(f.state.requests.map(r=>r.method),['POST','GET','GET']);
    assert.equal(f.state.resolutions,3);assert.equal(f.state.charges,3);assert.equal(f.state.observationCharges,1);
    assert(f.state.requests.every(r=>r.authorization==='Bearer slack-fixture-token'));
    f.row.finish();assert.equal(f.row.captureCount(),2);
    assert.equal(new Set(f.journal.recover().map(r=>r.grantCid)).size,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('Slack channel empty nonterminal pages retain their opaque continuation',async t=>{
  const f=await channelListFixture(t);f.state.pages=[channelPage([],'next'),channelPage([{id:'C2',name:'two'}],null)];
  assert.equal((await f.create().read()).rowCount,1);assert.equal(f.state.requests.length,3);
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

test('Slack channel count preserves the original large integer token through actual Common wire',async t=>{
  const f=await channelListFixture(t);f.state.pages=['{"ok":true,"channels":[{"id":"C","num_members":9007199254740993}],"response_metadata":{"next_cursor":null}}'];
  assert.equal((await f.create().read()).rowCount,1);assert.equal(f.state.rows[0].member_count,'9007199254740993');
  f.row.finish();assert.equal(f.row.captureCount(),1);
});

test('Slack channel duplicate keys and cursor history refuse whole completion with original raw custody',async t=>{
  for(const duplicate of [true,false]){
    const f=await channelListFixture(t);
    f.state.pages=[channelPage([{id:'C1'}],'again'),channelPage([{id:duplicate?'C1':'C2'}],duplicate?null:'again')];
    await assert.rejects(f.create().read(),e=>e instanceof SlackChannelListReadFailure&&e.observations.length===3&&
      e.cause.code===(duplicate?'SlackChannelListDuplicateChannel':'SlackChannelListRepeatedCursor'));
    assert.equal(f.state.requests.length,3);f.row.assertNoCapture();
  }
});

test('Slack channel workspace mismatch stops before listing under the same original token',async t=>{
  const f=await channelListFixture(t);f.state.identity={ok:true,team_id:'T-foreign',user_id:'U'};
  await assert.rejects(f.create().read(),e=>e.cause.code==='ForeignSlackWorkspace'&&e.observations.length===1);
  assert.equal(f.state.requests.length,1);assert.equal(f.state.observationCharges,0);f.row.assertNoCapture();
});

test('Slack channel current or stop after awaited page consumption prevents the next send',async t=>{
  for(const stop of [false,true]){
    const f=await channelListFixture(t);let active=true,reader;
    reader=f.create({current:async()=>{await f.current();if(!active)throw Object.assign(new Error('revoked'),{code:'FixtureCurrentRevoked'});},
      consumePage:async(...args)=>{await f.options.consumePage(...args);if(stop)reader.requestStop(new Error('stop'));else active=false;}});
    await assert.rejects(reader.read(),e=>e instanceof SlackChannelListReadFailure&&e.observations.length===2);
    assert.equal(f.state.requests.length,2);assert.equal(reader.observe().cleanupConfirmed,false);f.row.assertNoCapture();
  }
});

test('Slack channel per-operation authorization cannot reuse a users grant or foreign invocation',async t=>{
  const f=await channelListFixture(t);
  assert.throws(()=>f.create({initialAuthorization:{...f.options.initialAuthorization,
    scope:{...f.scope,operation:'slack:users:list'}}}),{code:'ForeignSlackChannelListOperation'});
  await assert.rejects(f.create({authorizationFor:({operation,index})=>{
    const original=f.options.authorizationFor({operation,index});
    return operation===SLACK_CHANNEL_LIST_OPERATION?{...original,scope:{...f.scope,dispatchRequestCid:'sha256:'+'d'.repeat(64)}}:original;
  }}).read(),e=>e.cause.code==='ForeignSlackChannelListAuthorization');
  assert.equal(f.state.requests.length,1);f.row.assertNoCapture();
});

test('Slack channel unselected malformed cells and finite limits never become a partial Source',async t=>{
  for(const limits of [false,true]){
    const f=await channelListFixture(t);
    if(limits)f.state.pages=[channelPage([{id:'C1'},{id:'C2'}],null)];
    else f.state.pages=[channelPage([{id:'C1',topic:{value:false}}],null)];
    const reader=f.create({names:['id'],...(limits?{limits:{...f.options.limits,maxRows:1}}:{})});
    await assert.rejects(reader.read(),e=>e instanceof SlackChannelListReadFailure&&e.observations.length===2);
    assert.equal(f.state.requests.length,2);f.row.assertNoCapture();
  }
});
