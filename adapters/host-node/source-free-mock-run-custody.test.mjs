import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeInferRun} from './installed-infer-run.mjs';

// Actual installed composition with explicit Model/driver ports. These cases
// establish original forwarding and partial custody, not a public runtime pass.
function fixture({pendingRetirement=false,missingOriginal=false}={}) {
  const prepared={},compiled={},graph={},occurrence={},provider={},setup={};
  const definition={wire:'{"run_id":"source-free-original"}'},control={};
  const plan={compiled,inferGraph:graph,runDefinition:definition};
  const selected={localMock:true,graph,occurrence,computePrefix:{},computeSuffix:{},provider:{}};
  const failure=new Error('BeforeOriginalDriverRuns'),calls=[];
  let owner,retirementPending=pendingRetirement;
  const original={control,compiled,runDefinition:definition,scope:{},
    retain(){calls.push('retain-scope');},
    openSourceFreeHost(registry,values,fragment,ordered,providers){
      assert.deepEqual([registry,values,fragment,ordered],['registry','values','fragment','ordered']);
      assert.deepEqual(providers,[provider]);assert(calls.includes('retain-scope'));
      calls.push('open-same-run');return setup;
    },async retire(){calls.push('retire-scope');return !retirementPending;}};
  const moon={clientProgramAcquisitionCount:actual=>{assert.strictEqual(actual,prepared);return 0;},
    clientProgramResultCount:()=>0,clientProgramInferPlanBoundary:()=>[0,0],
    clientProgramComposedInferLocalProvider(actual){assert.strictEqual(actual,occurrence);return provider;},
    clientProgramAdmitComposedInferSources(){assert.fail('No fake captured Sources');},
    clientProgramOpenCapturedComposedInferHost(){assert.fail('No captured Host fallback');},
    clientProgramOpenMultiCapturedComposedInferHost(){assert.fail('No multi-Source fallback');},
    strategyHostStop(actual){assert.strictEqual(actual,setup);calls.push('stop-driver');},
    strategyHostCloseOutputs(actual){assert.strictEqual(actual,setup);calls.push('close-outputs');},
    strategyHostUsage(actual){assert.strictEqual(actual,setup);return [0n,0n,0n,0n,0n,0n];}};
  const run=installNodeInferRun({moon,core:{publicationControl:control},registry:'registry',values:'values',
    fragment:'fragment',ordered:'ordered',selections:new Map([[prepared,selected]]),
    modelController:{discover:()=>[]},computeConfigurations:{},
    prepareOriginalMockRun(actual,actualPlan){
      assert.strictEqual(actual,prepared);assert.strictEqual(actualPlan,plan);calls.push('borrow-original');
      return missingOriginal?undefined:original;
    }});
  return {calls,failure,original,owner:()=>owner,allowRetirement(){retirementPending=false;},
    start:()=>run({preparedProgram:prepared,plan,signal:new AbortController().signal,
      retainExecution(value){assert.equal(owner,undefined);owner=value;calls.push('retain-cleanup');},
      beginPhysicalWork(){assert(owner);throw failure;}})};
}

test('source-free Mock forwards its early original Scope and same-Run driver without captured Sources',async()=>{
  const f=fixture();await assert.rejects(f.start(),error=>error===f.failure);
  assert.deepEqual(f.calls,['borrow-original','retain-cleanup','retain-scope','open-same-run']);
  assert.equal(f.owner().cleanupPending(),true);
  assert.equal(await f.owner().close(),true);
  assert.deepEqual(f.calls.slice(-3),['stop-driver','close-outputs','retire-scope']);
  assert.equal(f.owner().cleanupPending(),false);
  const count=f.calls.length;assert.equal(await f.owner().cleanup(),true);assert.equal(f.calls.length,count);
});

test('source-free Mock keeps the same driver and Scope until their separate retirement completes',async()=>{
  const f=fixture({pendingRetirement:true});await assert.rejects(f.start(),error=>error===f.failure);
  assert.equal(await f.owner().close(),false);assert.equal(f.owner().cleanupPending(),true);
  f.allowRetirement();assert.equal(await f.owner().cleanup(),true);
  assert.equal(f.owner().cleanupPending(),false);
  assert.equal(f.calls.filter(value=>value==='borrow-original').length,1);
  assert.equal(f.calls.filter(value=>value==='open-same-run').length,1);
});

test('source-free Mock cannot manufacture a Scope when its original Host preparation is absent',async()=>{
  const f=fixture({missingOriginal:true});
  await assert.rejects(f.start(),{message:'InvalidInstalledMockModelPreparation'});
  assert.equal(f.owner(),undefined);assert.deepEqual(f.calls,['borrow-original']);
});
