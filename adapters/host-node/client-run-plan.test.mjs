import assert from 'node:assert/strict';
import test from 'node:test';
import {installClientRunPlan} from './client-run-plan.mjs';
import {ref, cid} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {planOriginal, request as originalRequest} from './fixtures/original-plan-journal.mjs';
const request = () => ({connection:{mode:'local',owner:'local',consentRefs:[],runners:[]},
  principalId:'original-caller',ref:structuredClone(ref),maxWireBytes:65536,maxNodes:4096,maxDepth:64});
function fixture(changes={}) {
  let allowed=true, reads=0;
  const definition={}, original={runDefinition:definition,
    programDefinitionCid:originalRequest.programDefinitionCid,
    runAdmissionEvidence:{logicalPlanOriginal:planOriginal}};
  const service=installClientRunPlan({authorize:()=> allowed,lookupOriginal:()=> original,
    control:{readStoredRunPlanOriginal(saved,run,program,limits) {
      reads++;assert.equal(saved,planOriginal);assert.equal(run,definition);
      assert.equal(program,originalRequest.programDefinitionCid);assert.equal(limits.maxWireBytes,65536);
      return saved.planViewWire;
    }},...changes});
  return {service,original,setAllowed(value){allowed=value;},reads:()=> reads};
}
test('original plan service reads saved bytes and retains Run identity without control changes',async()=>{
  const f=fixture(),value=await f.service(request());assert.deepEqual(value.run_ref,ref);
  assert.deepEqual(value.plan_view,JSON.parse(planOriginal.planViewWire));assert.equal(f.reads(),1);
  assert.equal(Object.hasOwn(value,'revision'),false);
});
test('current access is rechecked after reading and old missing map remains unavailable',async()=>{
  const f=fixture();f.setAllowed(false);
  await assert.rejects(f.service(request()),{code:'RunObservationAccessDenied'});assert.equal(f.reads(),0);
  f.setAllowed(true);delete f.original.runAdmissionEvidence.logicalPlanOriginal;
  await assert.rejects(f.service(request()),{code:'ClientOperationUnavailable'});assert.equal(f.reads(),0);
  let authorityCalls=0,reads=0;
  const revoked=fixture({authorize:()=> ++authorityCalls===1,control:{readStoredRunPlanOriginal(){reads++;return planOriginal.planViewWire;}}});
  await assert.rejects(revoked.service(request()),{code:'RunObservationAccessDenied'});assert.equal(reads,1);
});
test('current callback cannot substitute original bytes or mutate the captured requested ref',async()=>{
  const given=request();let calls=0;
  const f=fixture({authorize:()=>{calls++;given.ref.runDefinitionCid=cid('0');return true;}});
  assert.deepEqual((await f.service(given)).run_ref,ref);assert.equal(calls,2);
  let snapshots=0;
  const changed=fixture({lookupOriginal:()=> ({runDefinition:{},programDefinitionCid:originalRequest.programDefinitionCid,
    runAdmissionEvidence:{logicalPlanOriginal:++snapshots===1?planOriginal:{...planOriginal,planViewWire:'changed'}}}),
    control:{readStoredRunPlanOriginal:()=> planOriginal.planViewWire}});
  await assert.rejects(changed.service(request()),{code:'InvalidClientHostRunPlanView'});
});
test('aborted reads and invalid limits do not read or dispatch',async()=>{
  const f=fixture();await assert.rejects(f.service({...request(),signal:AbortSignal.abort()}));
  await assert.rejects(f.service({...request(),maxNodes:0}),TypeError);assert.equal(f.reads(),0);
});
