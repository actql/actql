// Actual Local assembly functions with independent compiler/Policy stand-ins.
// Counts cover connection wiring, not physical compiler or Provider execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {sourceFreeValuesPlan, sourceFreeTaskPlan, acquiredTaskRunAdmission,
  sourceFreeValuesAdmissionEvidence,sourceFreePlanOriginal} from './local-values-plan.mjs';
import {definition,evidence} from './fixtures/original-plan-journal.mjs';
const cid='sha256:'+'a'.repeat(64);
for (const kind of ['values','source-free-tasks','acquired-tasks']) {
  test(`normal Local ${kind} captures the original opaque compiler plan once`,()=>{
    let compiles=0,captures=0;const prepared={},ticket={};
    const compiled={admission:{},compiledPlan:{identity:cid},
      preparedEvidence:{wire:evidence.prepared},authorization:{wire:evidence.authorization}};
    const control={prepareCheckedClientCompiledRun(actual){assert.equal(actual,prepared);compiles++;return compiled;},
      defineCheckedClientCompiledRun(actual){assert.equal(actual,compiled);return definition;},
      issueCheckedClientCompiledInvocation(){return {observation:{},invocation:{}};},
      seal(){return {identity:cid};},sealRunEvidence(){return {};},compiledRunResultTransformation(){return undefined;},
      captureOriginalClientRunPlan(actual,original,run,limits){captures++;
        assert.equal(actual,compiled);assert.equal(original,prepared);assert.equal(run,definition);
        assert.deepEqual(limits,{maxWireBytes:65536,maxNodes:4096,maxDepth:64});return ticket;}};
    const moon={clientProgramValuesMaxRows:()=>100,clientProgramResultCount:()=>1,clientProgramDefinitionCid:()=>cid};
    const options={moon,control,preparedProgram:prepared,authorityScopeCid:cid,
      namespaceId:'local',storeAuthorityCid:cid,now:()=> '2026-10-12T00:00:00.000Z'};
    const make=kind==='values'?sourceFreeValuesPlan:kind==='source-free-tasks'?sourceFreeTaskPlan:acquiredTaskRunAdmission;
    const plan=make(options);assert.equal(sourceFreePlanOriginal(plan),ticket);
    assert.equal(compiles,1);assert.equal(captures,1);
    if (kind!=='acquired-tasks') assert.deepEqual(sourceFreeValuesAdmissionEvidence(plan),evidence);
    assert.equal(sourceFreePlanOriginal({...plan}),undefined,'copy is not original compiler custody');
  });
}
