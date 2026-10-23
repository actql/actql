// Compilation dispatch with explicit Common ports. The real policy/body
// admission and source-free compilation are separately executed in Common WB.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientEffectRun} from './client-effect-run.mjs';

const original=Object.freeze({kind:'data_policy',cid:'sha256:'+'a'.repeat(64),wire:'original policy'});
function fixture(options={}){
  const {acquisitions=0,serializations=1,infer}=options;
  const policy=Object.hasOwn(options,'policy')?options.policy:original;
  const prepared=Object.freeze({}),compiled=Object.freeze({}),calls=[];
  const moon={clientProgramEffectCompilationIssueCode:()=>undefined,
    clientProgramEffectAcquisitionCount:value=>{assert.strictEqual(value,prepared);return acquisitions;},
    clientProgramEffectSerializationOccurrences:value=>{assert.strictEqual(value,prepared);return Array(serializations).fill({});},
    clientProgramCompileLocalEffects(value){assert.strictEqual(value,prepared);calls.push('legacy');return{$tag:1,_0:compiled};},
    clientProgramCompileLocalEffectsWithInfer(value,plan){assert.strictEqual(value,prepared);assert.strictEqual(plan,infer);
      calls.push('infer');return{$tag:1,_0:compiled};},
    clientProgramCompileLocalEffectsWithSourceFreePolicyBody(value,cid,wire,bytes,nodes,depth){
      assert.strictEqual(value,prepared);assert.equal(cid,original.cid);assert.equal(wire,original.wire);
      assert.deepEqual([bytes,nodes,depth],[1000000,100000,100]);calls.push('content');return{$tag:1,_0:compiled};},
    clientProgramEffectRunStartCurrent:()=>true,
    clientRunStartAction(){assert.fail('No Run starts during compilation');},
    clientRequestAuthorityScopeCid(){assert.fail('No request is admitted');},
    clientRequestCallerId(){assert.fail('No request is admitted');}};
  const run=installNodeClientEffectRun({moon,publicationControl:{admit(){assert.fail('No publication');}},journal:{
    lookupDefinition(){assert.fail('No Journal lookup');},reserveDispatch(){assert.fail('No dispatch');},
    reservePhysicalStart(){assert.fail('No physical work');},originalSubmittedIntent(){}},authorizeRequest(){},authorizeRunStart(){},
    execute(){},inferPlanFor:()=>infer,resultPolicyOriginalFor(){calls.push('policy');return policy;}});
  return{run,moon,prepared,calls};
}

test('source-free Content compiler receives the explicit original Host policy once',()=>{
  const f=fixture();f.run.checkSupported(f.prepared);f.run.checkSupported(f.prepared);
  assert.deepEqual(f.calls,['policy','content']);
});

test('acquired, non-Content and Model compilation keep their original selection',()=>{
  for(const [options,expected] of [[{acquisitions:1},['legacy']],
    [{serializations:0},['legacy']],[{infer:{}},['infer']],
    [{policy:undefined},['policy','legacy']]]){
    const f=fixture(options);f.run.checkSupported(f.prepared);assert.deepEqual(f.calls,expected);
  }
  const missing=fixture({policy:null});
  assert.throws(()=>missing.run.checkSupported(missing.prepared),{message:'InvalidHostResultDataPolicy'});
  assert.deepEqual(missing.calls,['policy']);
});
