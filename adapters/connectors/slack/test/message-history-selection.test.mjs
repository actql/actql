import assert from 'node:assert/strict';
import test from 'node:test';
import {messageHistoryFixture} from './message-history-read.fixture.mjs';

// Actual Common projection, Account/Credential, original journal and TLS.
// The charge/consumer callbacks are explicit sequencing fixtures, not a RowRun
// capture, ReaderLoan supplier or proof of normal installed funding.
function selectedReader(f,names){
  const selected=[];
  const reader=f.create({names,
    chargeResponse:body=>Object.freeze({body}),
    consumeObservation:()=>{},
    consumePage:rows=>{selected.push(...rows);}});
  return{reader,selected};
}

test('Slack history captures original columns without invoking a native array own slice',async t=>{
  const f=await messageHistoryFixture(t,{accounted:false});
  const names=['id'];let sliceCalls=0;
  names.slice=()=>{sliceCalls++;return['reply_count'];};
  const{reader,selected}=selectedReader(f,names);
  await reader.read();
  assert.equal(sliceCalls,0);
  assert.deepEqual(selected,[{id:'C1:2.000001'},{id:'C1:1.000002'}]);
});

test('Slack history reads each original column index getter exactly once before awaits',async t=>{
  const f=await messageHistoryFixture(t,{accounted:false});let reads=0;
  const names=['id'];
  Object.defineProperty(names,'0',{enumerable:true,configurable:true,
    get(){reads++;return reads===1?'id':'reply_count';}});
  const{reader,selected}=selectedReader(f,names);
  assert.equal(reads,1);
  await reader.read();assert.equal(reads,1);
  assert.deepEqual(selected,[{id:'C1:2.000001'},{id:'C1:1.000002'}]);
});

test('Slack history rejects the captured invalid column despite native own validation methods',async t=>{
  const f=await messageHistoryFixture(t,{accounted:false});
  const names=['not-a-declared-column'];names.some=()=>false;names.slice=()=>['id'];
  assert.throws(()=>selectedReader(f,names),{code:'InvalidSlackMessageHistoryRead'});
  assert.equal(f.state.requests.length,0);assert.equal(f.state.resolutions,0);
});

test('Slack history ignores native array custom iterator some and slice while retaining its indexed values',async t=>{
  const f=await messageHistoryFixture(t,{accounted:false});const names=['id'];
  const forbidden=()=>{throw new Error('CallerArrayMethodMustNotRun');};
  names[Symbol.iterator]=forbidden;names.some=forbidden;names.slice=forbidden;
  const{reader,selected}=selectedReader(f,names);await reader.read();
  assert.deepEqual(selected,[{id:'C1:2.000001'},{id:'C1:1.000002'}]);
});
