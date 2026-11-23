// Independent transport fixture, not a compiler-issued or installed E2E claim.
import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {ref, cid, acceptedResumeLookup, resumeOperationRef}
  from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {planOriginal} from './fixtures/original-plan-journal.mjs';
const profile = {version:'actql-client-host/0.1',mode:'local',owner:'local',
  durability:'volatile',scopeRef:'run-plan-fixture',capabilities:[],limits:{
  maxReadWireBytes:4096,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,
  maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:10,maxBatchRetainedValueBytes:2048}};
const answer = () => ({version:'actql-run-plan-view/0.1',run_ref:structuredClone(ref),
  plan_view:JSON.parse(planOriginal.planViewWire)});

for (const mutation of ['none','foreignRun','mapCid','compiledCid','extra','wireLimit']) {
  test(`Run.plan original envelope: ${mutation}`, async t => {
    let reads=0, starts=0;
    const port=createNodeInProcessClientHost({authenticate:()=> 'caller',
      authorizeConnection:()=> true,negotiate:()=> profile,maxRowBytes:1024,
      attach:value=> ({ref:value.ref,durability:'volatile',revision:0}),
      runPlan() {reads++;const view=answer();
        if (mutation==='foreignRun') view.run_ref.runDefinitionCid=cid('0');
        if (mutation==='mapCid') view.plan_view.logical_map.self_cid=cid('0');
        if (mutation==='compiledCid') view.plan_view.compiled_plan_cid=cid('0');
        if (mutation==='extra') view.preview={};
        return view;
      },submit(){starts++;throw Error('unexpected execution');}});
    const client=await connectInProcess({mode:'local',owner:'local'},port);
    t.after(()=> client.close());const run=await client.attach(ref);
    if (mutation==='none') {
      assert.deepEqual(await run.plan(),answer());
      assert.equal(Object.isFrozen((await run.plan()).plan_view.logical_map),true);
    } else await assert.rejects(run.plan(mutation==='wireLimit'?{maxWireBytes:1024}:{}),
      mutation==='wireLimit'?undefined:{code:'InvalidClientHostRunPlanView'});
    assert.equal(starts,0);assert(reads>0);
  });
}

// Isolate the SDK guard from the ingress guard: a Host port can return a
// structurally valid view for a different Run, and the SDK must still refuse it.
test('SDK independently refuses a foreign original Run response', async t => {
  const client=await connectInProcess({mode:'local',owner:'local'}, {async perform(operation,body) {
    if(operation==='connect') return profile;
    if(operation==='attach') return {ref:body.ref,durability:'volatile',revision:0};
    assert.equal(operation,'run-plan');
    return {...answer(),run_ref:{...ref,runDefinitionCid:cid('0')}};
  }});
  t.after(()=>client.close());const run=await client.attach(ref);
  await assert.rejects(run.plan(),{code:'InvalidClientHostRunPlanView'});
});

test('SDK lookup consumes the original control receipt through Local Host ingress', async t => {
  let mode = 'accepted', reads = 0;
  const port = createNodeInProcessClientHost({authenticate: () => 'caller', authorizeConnection: () => true,
    negotiate: () => profile, maxRowBytes: 1024, attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    lookupControlOperation(request, consume) {
      reads++;
      assert.equal(request.principalId, 'caller');
      assert.deepEqual(request.operationRef, resumeOperationRef);
      assert(Object.isFrozen(request.operationRef.run_ref));
      const view = mode === 'contradictory' ? acceptedResumeLookup(cid('0')) : acceptedResumeLookup();
      if (mode === 'advanced') view.observation.outcome = 'completed';
      if (mode === 'foreign') view.observation.operation_ref = {...view.observation.operation_ref, operation_id: 'another'};
      if (mode === 'edited') view.receipt.observed_state.run_id = 'changed';
      return consume(view);
    }});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  const run = await client.attach(ref);
  assert.deepEqual(await run.lookupControlOperation(resumeOperationRef), acceptedResumeLookup());
  assert.equal(reads, 1);
  await assert.rejects(run.lookupControlOperation({...resumeOperationRef, run_ref: {...ref, runDefinitionCid: cid('0')}}),
    {code: 'InvalidRunControlOperationRef'});
  assert.equal(reads, 1);
  mode = 'foreign';
  await assert.rejects(run.lookupControlOperation(resumeOperationRef), {code: 'InvalidClientHostControlOperationLookup'});
  mode = 'contradictory';
  await assert.rejects(run.lookupControlOperation(resumeOperationRef), {code: 'InvalidClientHostControlOperationLookup'});
  mode = 'edited';
  await assert.rejects(run.lookupControlOperation(resumeOperationRef), {code: 'InvalidClientHostControlOperationLookup'});
  mode = 'advanced';
  const advanced = await run.lookupControlOperation(resumeOperationRef);
  assert.equal(advanced.receipt.outcome, 'accepted');
  assert.equal(advanced.observation.outcome, 'completed');
  assert.equal(reads, 5);
});
