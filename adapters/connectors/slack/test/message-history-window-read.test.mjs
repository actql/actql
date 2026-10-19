// Actual Common Credential, SQLite, TLS and vendor Catalog. The observation
// tickets below are explicit sequencing doubles: this does not prove Source
// acquisition coverage, a funded RowRun or a supported installation supplier.
import assert from 'node:assert/strict';
import test from 'node:test';
import {SlackMessageHistoryReadFailure} from '../site/message-history-read.mjs';
import {messageHistoryFixture,messagePage} from './message-history-read.fixture.mjs';

async function windowFixture(t) {
  const f=await messageHistoryFixture(t,{accounted:false});
  let pending;
  const seen=new Set();
  const callbacks={
    chargeResponse(body){
      assert.equal(pending,undefined,'the previous original observation must be consumed');
      f.state.charges++;
      pending=Object.freeze({body});seen.add(pending);return pending;
    },
    consumeObservation(ticket){
      assert.equal(ticket,pending);assert(seen.delete(ticket));pending=undefined;
      f.state.observationCharges++;
    },
    consumePage(rows,{charge}){
      assert.equal(charge,pending);assert(seen.delete(charge));pending=undefined;
      f.state.rows.push(...rows);
    },
  };
  return {...f,callbacks,pending:()=>pending,create:overrides=>f.create({...callbacks,...overrides})};
}
const base='/api/conversations.history?channel=C1&limit=10';

test('Slack original window survives cursor and exact-time pagination at the real HTTP caller',async t=>{
  const f=await windowFixture(t);
  f.state.pages=[messagePage([{type:'message',ts:'2.000000001',text:'first'}],'opaque cursor',true),
    messagePage([{type:'message',ts:'1.500000001',text:'second'}],null,true),
    messagePage([{type:'message',ts:'1.000000001',text:'third'}],null)];
  const requestWindow={oldest:'1.000000000',latest:'3.000000000'};
  const actual=f.options.moon;let receiver,calls=0;
  const moon={...actual,slackPrepareMessageHistoryWindow(...args){
    assert.equal(this,receiver);calls++;return actual.slackPrepareMessageHistoryWindow(...args);
  }};receiver=moon;
  const reader=f.create({moon,requestWindow});
  requestWindow.oldest='2.9';requestWindow.latest='2.99';
  moon.slackPrepareMessageHistoryWindow=()=>{throw new Error('replaced callback');};
  assert.equal((await reader.read()).rowCount,3);assert.equal(calls,1);
  assert.deepEqual(f.state.requests.map(x=>x.path),['/api/auth.test',
    base+'&oldest=1.000000000&latest=3.000000000&inclusive=false',
    base+'&cursor=opaque%20cursor&oldest=1.000000000&latest=3.000000000&inclusive=false',
    base+'&oldest=1.000000000&latest=1.500000001&inclusive=false']);
  assert.deepEqual(f.state.rows.map(x=>x.posted_at),[
    '1970-01-01T00:00:02.000000001Z','1970-01-01T00:00:01.500000001Z','1970-01-01T00:00:01.000000001Z']);
  assert.equal(f.pending(),undefined);assert.equal(reader.observe().cleanupConfirmed,false);
});

test('Slack invalid original window refuses before secret resolution or HTTP',async t=>{
  for(const requestWindow of [
    {oldest:'1.000001',latest:'1.000001000'},
    {oldest:'2',latest:'1'},
    {oldest:'1e0',latest:null},
  ]){
    const f=await windowFixture(t),reader=f.create({requestWindow});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length===0);
    assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
    assert.equal(f.state.charges,0);assert.equal(reader.observe().cleanupConfirmed,false);
  }
});

test('Slack original window descriptors and runtime capability fail closed',async t=>{
  const f=await windowFixture(t);let reads=0;
  const accessor={latest:null};Object.defineProperty(accessor,'oldest',{get(){reads++;return '1';},enumerable:true});
  for(const requestWindow of [null,accessor,{oldest:1,latest:null},{oldest:'1',latest:null,extra:true}]){
    assert.throws(()=>f.create({requestWindow}),{code:'InvalidSlackMessageHistoryWindow'});
  }
  assert.equal(reads,0);
  const moon={...f.options.moon};delete moon.slackPrepareMessageHistoryWindow;
  assert.throws(()=>f.create({moon,requestWindow:{oldest:'1',latest:null}}),{code:'SlackMessageHistoryWindowRuntimeUnavailable'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.charges,0);
});

test('Slack window response failures retain the charged original instead of skipping rows',async t=>{
  for(const row of [
    {type:'message',ts:'0.999999999',text:'outside original request'},
    {type:'message',ts:'1.000000000',text:'excluded endpoint'},
    {type:'message',ts:'2.000000001',reply_count:'0'},
  ]){
    const f=await windowFixture(t);f.state.pages=[messagePage([row],null)];
    const reader=f.create({requestWindow:{oldest:'1.000000000',latest:'3.000000000'}});
    await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length===2);
    assert.equal(f.state.requests.length,2);assert.equal(f.state.charges,2);
    assert(f.pending());assert.equal(f.state.rows.length,0);
    assert.equal(reader.observe().cleanupConfirmed,false);
    await assert.rejects(reader.read(),{code:'SlackMessageHistoryReaderAlreadyStarted'});
  }
});

test('Slack window currentness after consuming a page prevents the next Common request and send',async t=>{
  const f=await windowFixture(t);let current=true,next=0;
  const actual=f.options.moon;
  const moon={...actual,slackNextMessageHistoryRequest(...args){next++;return actual.slackNextMessageHistoryRequest(...args);}};
  const reader=f.create({moon,requestWindow:{oldest:'0.000000000',latest:'3.000000000'},
    current:async()=>{await f.current();if(!current)throw new Error('current revoked');},
    consumePage:async(...args)=>{f.callbacks.consumePage(...args);current=false;}});
  await assert.rejects(reader.read(),e=>e instanceof SlackMessageHistoryReadFailure&&e.observations.length===2);
  assert.equal(next,0);assert.equal(f.state.requests.length,2);assert.equal(f.pending(),undefined);
});


test('Slack history vendor dispatch cap does not lower the Host row ceiling',async t=>{
  const f=await windowFixture(t);f.state.pages=[messagePage([{type:'message',ts:'2.000000001'}],null)];
  const limits={...f.options.limits,pageSize:1000,maxRows:1000};
  const reader=f.create({limits,requestWindow:{oldest:null,latest:'3.000000000'}});
  assert.equal((await reader.read()).rowCount,1);
  assert.equal(f.state.requests[1].path,'/api/conversations.history?channel=C1&limit=999&latest=3.000000000&inclusive=false');
  assert.equal(limits.pageSize,1000);assert.equal(limits.maxRows,1000);
});
