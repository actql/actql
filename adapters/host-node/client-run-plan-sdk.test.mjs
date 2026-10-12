// Independent transport fixture, not a compiler-issued or installed E2E claim.
import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {ref, cid} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
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
