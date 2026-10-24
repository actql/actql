import test from 'node:test';
import assert from 'node:assert/strict';
import {checkedPreparation,cleanupClosedValuesInput} from './closed-values-preparation-adapter.mjs';

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
 const prepared={},holder={},phase={};let returns=0,aborts=0,cuts=0;
 const runtime={
  clientProgramAbortClosedValuesPreparationAfterCleanup(original){assert.equal(original,phase);aborts++;return {$tag:1,_0:undefined};},
  clientProgramClosedValuesInitialRetirementStarted(original,token){assert.equal(original,phase);assert.equal(token,holder);return true;},
  clientProgramPreparationBorrowReturn(token){assert.equal(token,holder);returns++;return {$tag:1,_0:false};},
 };
 const state={prepared,holder,phase,context:{runtime}};
 assert.throws(()=>cleanupClosedValuesInput(state),{code:'NodeLocalPreparationAdmissionUnavailable'});
 assert.equal(returns,0);assert.equal(state.prepared,prepared);assert.equal(state.holder,holder);assert.equal(state.phase,phase);
 cleanupClosedValuesInput(state,original=>{assert.equal(original,prepared);assert.equal(state.holder,holder);cuts++;});
 assert.equal(cuts,1);assert.equal(returns,1);assert.equal(aborts,3);
 assert.equal(state.prepared,undefined);assert.equal(state.holder,undefined);assert.equal(state.phase,undefined);
 cleanupClosedValuesInput(state);assert.equal(returns,1);
});

test('pre-body initial cleanup needs no registry callback or fabricated Prepared',()=>{
 const phase={};let aborts=0;
 const state={phase,context:{runtime:{clientProgramAbortClosedValuesPreparationAfterCleanup(original){assert.equal(original,phase);aborts++;return {$tag:1,_0:undefined};}}}};
 cleanupClosedValuesInput(state);assert.equal(aborts,1);assert.equal(state.phase,undefined);
});
