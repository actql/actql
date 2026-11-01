import test from 'node:test';
import assert from 'node:assert/strict';
import {checkedPreparation,cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';

test('preparation capacity refusal preserves exact original Common facts as immutable data',()=>{
 const issue=Object.freeze({}), calls=[];
 const moon={clientProgramPreparationCapacityRefusal(original){assert.equal(original,issue);calls.push(original);return {_0:'snapshot_and_intent',_1:'execution',_2:123n,_3:9223372036854775807n,_4:536870912n,_5:536870912n};}};
 let error;try{checkedPreparation(moon,{$tag:0,_0:issue});}catch(value){error=value;}
 assert.equal(error.code,'PreparationCapacityExceeded');assert.equal(error.cause,issue);
 assert.equal(calls.length,1);assert.ok(Object.isFrozen(error.capacity));
 assert.deepEqual(error.capacity,{phase:'snapshot_and_intent',dimension:'execution',requiredRetentionBytes:'123',requiredExecutionBytes:'9223372036854775807',availableRetentionBytes:'536870912',availableExecutionBytes:'536870912'});
 assert.throws(()=>{error.capacity.availableExecutionBytes='9999999999999999999';},TypeError);
 assert.deepEqual(Object.keys(error.capacity).sort(),['phase','dimension','requiredRetentionBytes','requiredExecutionBytes','availableRetentionBytes','availableExecutionBytes'].sort());
});
test('successful and non-capacity preparation results keep ordinary semantics',()=>{
 const body={},issue={};let projections=0;
 const moon={clientProgramPreparationCapacityRefusal(original){assert.equal(original,issue);projections++;return undefined;}};
 assert.equal(checkedPreparation(moon,{$tag:1,_0:body}),body);assert.equal(projections,0);
 assert.throws(()=>checkedPreparation(moon,{$tag:0,_0:issue}),error=>error.code==='MoonBitHostFailure'&&error.cause===issue);
 assert.equal(projections,1);
});
test('malformed diagnostic data never becomes a resource refusal or numeric authority',()=>{
 const moon={clientProgramPreparationCapacityRefusal(){return {_0:'snapshot_and_intent',_1:'execution',_2:1,_3:2,_4:3,_5:4};}};
 assert.throws(()=>checkedPreparation(moon,{$tag:0,_0:{}}),{code:'InvalidHostRuntimeResult'});
});


test('prepared initial cleanup requires its fixed retirement callback and preserves retry ownership',()=>{
 const prepared={},holder={},parent={};let returns=0,aborts=0,cuts=0;
 const runtime={
  clientProgramAbortRequestPreparation(original){assert.equal(original,parent);aborts++;return {$tag:1,_0:undefined};},
  clientProgramPreparationBorrowRetirementStarted(token){assert.equal(token,holder);return true;},
  clientProgramPreparationBorrowReturn(token){assert.equal(token,holder);returns++;return {$tag:1,_0:false};},
 };
 const state={prepared,holder,parent,context:{runtime}};
 assert.throws(()=>cleanupRequestInput(state),{code:'NodeLocalPreparationAdmissionUnavailable'});
 assert.equal(returns,0);assert.equal(state.prepared,prepared);assert.equal(state.holder,holder);assert.equal(state.parent,parent);
 cleanupRequestInput(state,original=>{assert.equal(original,prepared);assert.equal(state.holder,holder);cuts++;});
 assert.equal(cuts,1);assert.equal(returns,1);assert.equal(aborts,3);
 assert.equal(state.prepared,undefined);assert.equal(state.holder,undefined);assert.equal(state.parent,undefined);
 cleanupRequestInput(state);assert.equal(returns,1);
});

test('pre-body initial cleanup needs no registry callback or fabricated Prepared',()=>{
 const parent={};let aborts=0;
 const state={parent,context:{runtime:{clientProgramAbortRequestPreparation(original){assert.equal(original,parent);aborts++;return {$tag:1,_0:undefined};}}}};
 cleanupRequestInput(state);assert.equal(aborts,1);assert.equal(state.parent,undefined);
});

import {checkedRequestProgramPreparation, requestProgramCapacityRefusal}
  from './client-program-preparation.mjs';

test('only an original typed module capacity refusal becomes an operation refusal', () => {
  const issue = {}, result = {$tag:0,_0:issue};
  const moon = {
    clientProgramRequestPreparationIssueCode(original) {
      assert.equal(original,result); return 'source_free_capacity_exceeded';
    },
    clientProgramRequestProgramModuleCapacityRefusal(original) {
      assert.equal(original,result);
      return {_0:'source_free_plan',_1:'execution',_2:203770432n,_3:703186240n,
        _4:536870912n,_5:536870912n};
    },
  };
  let error;
  assert.throws(() => checkedRequestProgramPreparation(moon,result), value => {
    error=value; return value.code==='ClientProgramRejected' && value.cause===issue;
  });
  const facts=requestProgramCapacityRefusal(error);
  assert.ok(Object.isFrozen(facts));
  assert.deepEqual(facts,{phase:'source_free_plan',dimension:'execution',
    requiredRetentionBytes:'203770432',requiredExecutionBytes:'703186240',
    availableRetentionBytes:'536870912',availableExecutionBytes:'536870912'});
  error.capacity={dimension:'retention'};
  assert.equal(requestProgramCapacityRefusal(error),facts);
  assert.equal(requestProgramCapacityRefusal({code:error.code,capacity:facts}),undefined);
  assert.equal(requestProgramCapacityRefusal(new Error('PreparationCapacityExceeded')),undefined);
});

test('unknown foreign current and cleanup module failures do not become capacity refusals', () => {
  for(const issue of [{code:'InsufficientCapacity'}, {code:'ForeignOriginal'},
    {code:'CurrentChanged'}, {code:'CleanupPending',cleanupPending:true}]) {
    const result={$tag:0,_0:issue};
    const moon={clientProgramRequestPreparationIssueCode:()=>undefined,
      clientProgramRequestProgramModuleCapacityRefusal:()=>assert.fail('Do not project an unrelated issue')};
    assert.throws(()=>checkedRequestProgramPreparation(moon,result),error=>
      error.code==='MoonBitHostFailure' && error.cause===issue && requestProgramCapacityRefusal(error)===undefined);
  }
});

test('invalid or missing original module quantities never certify a capacity refusal', () => {
  for(const value of [undefined,{_0:'source_free_plan',_1:'execution',_2:0n,_3:1n,_4:2n,_5:2n},
    {_0:'source_free_plan',_1:'retention',_2:1,_3:3n,_4:0n,_5:2n}]) {
    const moon={clientProgramRequestPreparationIssueCode:()=> 'source_free_capacity_exceeded',
      clientProgramRequestProgramModuleCapacityRefusal:()=>value};
    assert.throws(()=>checkedRequestProgramPreparation(moon,{$tag:0,_0:{}}),error=>
      error.code==='InvalidHostRuntimeResult' && requestProgramCapacityRefusal(error)===undefined);
  }
});

test('retention is the first exact exceeded dimension when both byte requirements fail', () => {
  const result={$tag:0,_0:{}};
  const moon={clientProgramRequestPreparationIssueCode:()=> 'source_free_capacity_exceeded',
    clientProgramRequestProgramModuleCapacityRefusal:()=>({_0:'source_free_plan',_1:'retention',
      _2:537000000n,_3:800000000n,_4:536870912n,_5:536870912n})};
  assert.throws(()=>checkedRequestProgramPreparation(moon,result),error=>{
    assert.deepEqual(requestProgramCapacityRefusal(error),{phase:'source_free_plan',dimension:'retention',
      requiredRetentionBytes:'537000000',requiredExecutionBytes:'800000000',
      availableRetentionBytes:'536870912',availableExecutionBytes:'536870912'});
    return error.code==='ClientProgramRejected';
  });
  moon.clientProgramRequestProgramModuleCapacityRefusal=()=>({_0:'source_free_plan',_1:'execution',
    _2:537000000n,_3:800000000n,_4:536870912n,_5:536870912n});
  assert.throws(()=>checkedRequestProgramPreparation(moon,result),{code:'InvalidHostRuntimeResult'});
});

test('original metadata quote failure refuses admission without inventing numeric capacity', () => {
  const issue = {}, result = {$tag: 0, _0: issue};
  let projections = 0;
  const moon = {
    clientProgramRequestProgramModuleIssueCode(original) {
      assert.equal(original, result);
      projections++;
      return 'source_free_metadata_capacity_unavailable';
    },
    clientProgramRequestProgramModuleCapacityRefusal() {
      assert.fail('A failed quote has no numeric exceeded amount');
    },
  };
  assert.throws(() => checkedRequestProgramPreparation(moon, result,
    moon.clientProgramRequestProgramModuleIssueCode), error => {
    assert.equal(error.code, 'ClientProgramRejected');
    assert.equal(error.cause, issue);
    assert.equal(Object.hasOwn(error, 'capacity'), false);
    assert.equal(requestProgramCapacityRefusal(error), undefined);
    return true;
  });
  assert.equal(projections, 1);
  const body = {};
  assert.equal(checkedRequestProgramPreparation(moon, {$tag: 1, _0: body},
    () => assert.fail('Success must not project a refusal')), body);
});
