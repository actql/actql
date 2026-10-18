import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/slack/host_node/host_node.js';
import {messageProjectionFixture,messageProjectionLimits} from './message-projection-read.fixture.mjs';
import {coalesceSlackMessageReaders,SlackMessageProjectionFailure,
  SLACK_MESSAGE_HISTORY_OPERATION} from '../site/message-history-read.mjs';

// These cases execute the actual Catalog and actual Common/Account/Credential/
// SQLite/TLS. Explicit tickets/issuer/material remain component fixtures.
test('Slack projection uses original completed history replies and retains first checked output',async t=>{
  const f=await messageProjectionFixture(t,{after:{user:'U1'}}),before=f.state.requests.length;
  const result=await f.project();
  assert.equal(result.rowCount,2);assert.equal(result.cleanupConfirmed,false);
  assert.deepEqual(result.rows.map(row=>[row.id,row.user,row.thread_ts]),[
    ['C1:1.000001',null,null],['C1:2.000001',null,'1.000001']]);
  assert.deepEqual(result.rows[0],f.historyRows[0]);
  assert.deepEqual(result.rows[1],f.replyRows[1]);
  assert.equal(f.state.requests.length,before);assert.equal(before,3);
  assert.equal(f.history.observe().cleanupConfirmed,false);
  assert.equal(f.replies.observe().cleanupConfirmed,false);f.assertNoPending();
});

test('Slack projection actual prefix refuses null and changed established fields without another send',async t=>{
  for(const [before,after] of [[{user:null},{user:'U1'}],[{user:'U1'},{user:null}],[{user:'U1'},{user:'U2'}]]) {
    const f=await messageProjectionFixture(t,{before,after}),sent=f.state.requests.length;
    await assert.rejects(f.project(),SlackMessageProjectionFailure);
    assert.equal(f.state.requests.length,sent);f.assertNoPending();
  }
});

test('Slack projection retains original nested reaction absence and refuses explicit null contradiction',async t=>{
  const f=await messageProjectionFixture(t,{before:{reactions:[{name:'eyes',count:1}]},
    after:{reactions:[{name:'eyes',count:1,users:['U1']}]}});
  assert.deepEqual((await f.project()).rows[0].reactions,[{count:'1',name:'eyes',users:null}]);
  const bad=await messageProjectionFixture(t,{before:{reactions:[{name:'eyes',count:1,users:null}]},
    after:{reactions:[{name:'eyes',count:1,users:['U1']}]}});
  await assert.rejects(bad.project(),SlackMessageProjectionFailure);
});

test('Slack projection refuses actual child incorporation beside derived history zero',async t=>{
  const parent={type:'message',ts:'1.000001',text:'parent'};
  const f=await messageProjectionFixture(t,{historyRecords:[parent],replyRecords:[parent,
    {type:'message',ts:'2.000001',thread_ts:'1.000001',text:'child'}]});
  assert.equal(f.historyRows[0].reply_count,'0');assert.equal(f.replyRows[0].reply_count,null);
  await assert.rejects(f.project(),SlackMessageProjectionFailure);
  assert.equal(f.state.requests.length,3);f.assertNoPending();
});

test('Slack projection rejects foreign copied pending and failed reader originals before Common work',async t=>{
  let work=0;
  const moon={...provider,slackCoalesceMessageOriginals(...args){work++;return provider.slackCoalesceMessageOriginals(...args);}};
  const f=await messageProjectionFixture(t,{moon}),foreign=await messageProjectionFixture(t);
  for(const override of [{historyReader:{...f.history}},{replyReaders:[{...f.replies}]},
    {replyReaders:[foreign.replies]}])await assert.rejects(f.project(override));
  const pending=await messageProjectionFixture(t,{moon,readReplies:false});
  await assert.rejects(pending.project(),{code:'ForeignSlackMessageProjectionSelection'});
  pending.state.replyPages=[{ok:false}];
  await assert.rejects(pending.replies.read());
  await assert.rejects(pending.project(),{code:'ForeignSlackMessageProjectionSelection'});
  assert.equal(work,0);
  assert.equal(f.state.requests.length,3);assert.equal(foreign.state.requests.length,3);
});

test('Slack projection current refusal and stop after await prevent any new Common projection',async t=>{
  let work=0;
  const moon={...provider,slackCoalesceMessageOriginals(...args){work++;return provider.slackCoalesceMessageOriginals(...args);}};
  const f=await messageProjectionFixture(t,{moon});
  f.mode.current=async()=>{throw Object.assign(new Error('revoked'),{code:'ProjectionRevoked'});};
  await assert.rejects(f.project(),error=>error instanceof SlackMessageProjectionFailure&&error.cause.code==='ProjectionRevoked');
  f.mode.current=async operation=>{if(operation===SLACK_MESSAGE_HISTORY_OPERATION)f.replies.requestStop(new Error('stop original reply'));};
  await assert.rejects(f.project(),SlackMessageProjectionFailure);
  assert.equal(work,0);assert.equal(f.state.requests.length,3);f.assertNoPending();
});

test('Slack projection captures provider receivers and selection bounds before awaited current',async t=>{
  const calls=[];let moon;
  moon={...provider};
  for(const name of ['slackCoalesceMessageOriginals','slackMessageProjectionRowCount','slackMessageProjectionRowsWire']){
    moon[name]=function(...args){assert.equal(this,moon);calls.push(name);return Reflect.apply(provider[name],provider,args);};
  }
  const f=await messageProjectionFixture(t,{moon});
  for(const name of ['slackCoalesceMessageOriginals','slackMessageProjectionRowCount','slackMessageProjectionRowsWire']){
    moon[name]=()=>assert.fail('reloaded replacement callback');
  }
  const names=['id','user'],limits={...messageProjectionLimits},selected=[f.replies];
  f.mode.current=async()=>{names[0]='foreign';limits.maxRows=1;selected[0]={...f.replies};};
  const result=await f.project({names,limits,replyReaders:selected});
  assert.equal(result.rowCount,2);assert.deepEqual(Object.keys(result.rows[0]),['id','user']);
  assert.equal(result.rows[0].user,null);
  assert.deepEqual(calls,['slackCoalesceMessageOriginals','slackMessageProjectionRowCount','slackMessageProjectionRowsWire']);
});

test('Slack projection bounded work output and own-data configuration remain fail closed',async t=>{
  const f=await messageProjectionFixture(t),sent=f.state.requests.length;
  for(const limits of [{...messageProjectionLimits,maxWork:1},
    {...messageProjectionLimits,maxRows:1},{...messageProjectionLimits,maxOccurrences:1},
    {...messageProjectionLimits,maxRowsWireBytes:1}]){
    await assert.rejects(f.project({limits}),SlackMessageProjectionFailure);
  }
  await assert.rejects(f.project({limits:{...messageProjectionLimits,maxRows:0}}),{code:'InvalidSlackMessageProjection'});
  const accessor={...messageProjectionLimits};Object.defineProperty(accessor,'maxRows',{enumerable:true,get(){assert.fail('invoked bounds getter');}});
  await assert.rejects(f.project({limits:accessor}),{code:'InvalidSlackMessageProjection'});
  await assert.rejects(f.project({names:['id','id']}),{code:'InvalidSlackMessageProjection'});
  await assert.rejects(f.project({names:['unknown']}),{code:'InvalidSlackMessageProjection'});
  const stopped=new AbortController();stopped.abort(new Error('caller stop'));
  await assert.rejects(f.project({signal:stopped.signal}),SlackMessageProjectionFailure);
  assert.equal(f.state.requests.length,sent);f.assertNoPending();
});

test('Slack projection missing partial private bridge group refuses before dependent IO',async t=>{
  const f=await messageProjectionFixture(t);
  const moon={...provider};delete moon.slackMessageProjectionRowCount;
  assert.throws(()=>f.create({moon}),{code:'SlackMessageOriginalRuntimeUnavailable'});
  assert.equal(f.state.requests.length,3);
  const inherited=Object.create({historyReader:f.history});
  Object.assign(inherited,{replyReaders:[f.replies],names:['id'],limits:messageProjectionLimits});
  await assert.rejects(coalesceSlackMessageReaders(inherited),{code:'InvalidSlackMessageProjection'});
});
