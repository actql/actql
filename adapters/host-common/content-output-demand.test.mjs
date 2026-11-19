import assert from 'node:assert/strict';
import test from 'node:test';
import {contentGenerationControl} from './runtime-core.mjs';
import {localOutputLimits, localContractLimits} from '../host-node/local-values-plan.mjs';

// Actual imported Host facade with explicit typed Common ports. The actual
// original Request/Ledger/Graph demand arithmetic is covered by its Core case.
test('Content demand facade retains the same funded capacity and bounded DATA for its original prefix', () => {
  const parent = {}, input = {}, compiled = {}, graph = {}, capacity = {}, definition = {}, request = {};
  const generation = {maxRows:1,maxBytes:10000000,maxValueNodes:100000,maxValueDepth:64,maxFrames:256};
  const reference = {maxBytes:16384,maxNodes:256,maxDepth:32};
  let calls = 0, refusal;
  const publications = {
    prepareRequestSerializationOutputDemand(p, i, c, g, fields, output) {
      assert.deepEqual([p,i,c,g],[parent,input,compiled,graph]);
      assert.deepEqual(fields,[1,10000000,100000,64,256,4000800,16384,256,32,
        localContractLimits.maxWireBytes,localContractLimits.maxNodes,localContractLimits.maxDepth]);
      assert.equal(output,localOutputLimits); calls++;
      if (refusal !== undefined) throw refusal;
      return {_0:capacity,_1:1,_2:64,_3:1,_4:4,_5:3,_6:6,_7:1,_8:152};
    },
    prepareCheckedClientRequestSerializationPlan(p,i,r,c,d,l,w) {
      assert.deepEqual([p,i,r,c,d,w],[parent,input,request,compiled,definition,capacity]);
      return l;
    },
  };
  const moon = {clientProgramPrepareRequestSerializationOutputDemand() {assert.fail('Only the nominal publication owner calls Common');},
    clientProgramSerializationCapacityBytes(actual) {assert.equal(actual,capacity);return {_0:123n,_1:456n};}};
  const control = contentGenerationControl(moon,publications);
  const selected = control.prepareRequestOutputDemand(parent,input,compiled,graph,generation,
    reference,localContractLimits,localOutputLimits,4000800);
  assert.equal(calls,1); assert(Object.isFrozen(selected));
  assert.equal(selected.generationLimits.maxBytes,64); assert.equal(selected.generationLimits.maxRows,1);
  assert.equal(selected.outputLimits.maxValueTextBytes,localOutputLimits.maxValueTextBytes);
  assert.equal(selected.outputLimits.maxWireBytes,localOutputLimits.maxWireBytes);
  assert.equal(selected.outputLimits.maxValueNodes,4); assert.equal(selected.identitySlots,152);
  const prefix = {};
  assert.equal(control.prepareRequestPrefix(parent,input,request,compiled,definition,prefix,selected.workspace),prefix);
  assert.throws(() => control.prepareRequestPrefix(parent,input,request,compiled,definition,prefix,{...selected.workspace}),/Foreign Content workspace/);
  const primary = new Error('Original Request refused'); refusal = primary;
  assert.throws(() => control.prepareRequestOutputDemand(parent,input,compiled,graph,generation,
    reference,localContractLimits,localOutputLimits,4000800),cause => cause === primary);
  assert.equal(calls,2);
});
