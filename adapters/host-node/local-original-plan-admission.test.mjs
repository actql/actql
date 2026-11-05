// Actual Local assembly functions with independent compiler/Policy stand-ins.
// Counts cover connection wiring, not physical compiler or Provider execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {sourceFreeValuesPlan, sourceFreeTaskPlan, acquiredTaskRunAdmission,
  sourceFreeValuesAdmissionEvidence,sourceFreePlanOriginal} from './local-values-plan.mjs';
import {restoreInferTaskRunAdmission, selectRestoredInferOccurrence} from './local-values-plan.mjs';
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
    const moon={clientProgramPreparedLocalPublicationLimits:()=>Array(22).fill(1),clientProgramValuesMaxRows:()=>100,clientProgramResultCount:()=>1,clientProgramDefinitionCid:()=>cid};
    const options={moon,control,preparedProgram:prepared,publicationOriginal:{kind:'preparation',value:{}},authorityScopeCid:cid,
      namespaceId:'local',storeAuthorityCid:cid,now:()=> '2026-10-12T00:00:00.000Z'};
    const make=kind==='values'?sourceFreeValuesPlan:kind==='source-free-tasks'?sourceFreeTaskPlan:acquiredTaskRunAdmission;
    const plan=make(options);assert.equal(sourceFreePlanOriginal(plan),ticket);
    assert.equal(compiles,1);assert.equal(captures,1);
    if (kind!=='acquired-tasks') assert.deepEqual(sourceFreeValuesAdmissionEvidence(plan),evidence);
    assert.equal(sourceFreePlanOriginal({...plan}),undefined,'copy is not original compiler custody');
  });
}

for(const kind of ['values','source-free-tasks','acquired-tasks']){
  test(`normal Local ${kind} binds one original invocation sample and restores its saved definition`,()=>{
    const prepared={},request={},context={},preparation={},ticket={};
    let samples=0,restores=0,binds=0,createdAt;
    const compiled={admission:{},compiledPlan:{identity:cid},
      preparedEvidence:{wire:evidence.prepared},authorization:{wire:evidence.authorization}};
    const control={
      clientRequiresQueryTime(actual){assert.strictEqual(actual,prepared);return true;},
      prepareClientQueryTime(actual,original,sample){assert.strictEqual(actual,prepared);
        assert.strictEqual(original,request);assert.equal(samples++,0);createdAt=sample;return preparation;},
      bindClientQueryTime(original,actual,compiledOriginal,run,originalRequest){
        assert.strictEqual(original,preparation);assert.strictEqual(actual,prepared);
        assert.strictEqual(compiledOriginal,compiled);assert.strictEqual(originalRequest,request);
        assert.equal(JSON.parse(run.wire).created_at,createdAt);binds++;return context;},
      restoreClientQueryTime(actual,compiledOriginal,run,originalRequest){
        assert.strictEqual(actual,prepared);assert.strictEqual(compiledOriginal,compiled);
        assert.strictEqual(originalRequest,request);assert.equal(JSON.parse(run.wire).created_at,createdAt);
        restores++;return {queryTimePreparation:preparation,queryTime:context};},
      prepareCheckedClientCompiledRun(actual){assert.strictEqual(actual,prepared);return compiled;},
      defineCheckedClientCompiledRun(actual,options){assert.strictEqual(actual,compiled);
        assert.equal(options.createdAt,createdAt);
        return {...definition,wire:options.retainedDefinitionWire??JSON.stringify({
          ...JSON.parse(definition.wire),created_at:options.createdAt,valid_until:options.validUntil})};},
      issueCheckedClientCompiledInvocation(){return {observation:{},invocation:{}};},
      seal(){return {identity:cid};},sealRunEvidence(){return {};},compiledRunResultTransformation(){return undefined;},
      captureOriginalClientRunPlan(){return ticket;},
    };
    const moon={clientProgramPreparedLocalPublicationLimits:()=>Array(22).fill(1),clientProgramValuesMaxRows:()=>100,clientProgramResultCount:()=>1,clientProgramDefinitionCid:()=>cid};
    const options={moon,control,preparedProgram:prepared,publicationOriginal:{kind:'preparation',value:{}},requestIdentity:request,
      authorityScopeCid:cid,namespaceId:'local',storeAuthorityCid:cid,
      now:()=>new Date().toISOString()};
    const make=kind==='values'?sourceFreeValuesPlan:kind==='source-free-tasks'?sourceFreeTaskPlan:acquiredTaskRunAdmission;
    const first=make(options);assert.equal(samples,1);assert.equal(binds,1);
    if(kind==='acquired-tasks'){
      assert.strictEqual(first.queryTime,context);assert.strictEqual(first.queryTimePreparation,preparation);
    }else{
      // Publication plans keep lifetime links in their private original-plan
      // association. The binding ports above still check every original.
      assert.equal(Object.hasOwn(first,'queryTime'),false);
      assert.equal(Object.hasOwn(first,'queryTimePreparation'),false);
    }
    assert.strictEqual(sourceFreePlanOriginal(first),ticket);
    if(kind!=='acquired-tasks')assert.deepEqual(sourceFreeValuesAdmissionEvidence(first),evidence);
    const restored=make({...options,retainedDefinitionWire:JSON.stringify({
      ...JSON.parse(definition.wire),created_at:createdAt,valid_until:'2099-01-01T00:00:00.000Z'})});
    assert.equal(samples,1);assert.equal(restores,1);
    if(kind==='acquired-tasks')assert.strictEqual(restored.queryTime,context);
    else assert.strictEqual(sourceFreePlanOriginal(restored),ticket);
    assert.throws(()=>make({...options,requestIdentity:undefined}),{message:'OriginalClientQueryRequestRequired'});
    assert.equal(samples,1);
  });
}

test('saved Infer admission restores query time from its original definition without a clock sample',()=>{
  const prepared={},request={},graph={},context={},queryPreparation={};
  const compiled={kind:'infer'},restored={compiled,graph,runDefinition:definition};let restores=0;
  const control={
    checkRestoredClientInferRunOwner(value,owner){assert.strictEqual(value,restored);assert.strictEqual(owner,prepared);},
    checkedClientCompiledInferOriginal(value,owner,run){assert.strictEqual(value,compiled);
      assert.strictEqual(owner,prepared);assert.strictEqual(run,definition);return {graph};},
    clientRequiresQueryTime:()=>true,
    prepareClientQueryTime(){assert.fail('Cold restoration must not prepare a fresh sample');},
    restoreClientQueryTime(owner,value,run,original){assert.strictEqual(owner,prepared);
      assert.strictEqual(value,compiled);assert.strictEqual(run,definition);assert.strictEqual(original,request);
      restores++;return {queryTimePreparation:queryPreparation,queryTime:context};},
  };
  const actual=restoreInferTaskRunAdmission({control,preparedProgram:prepared,restored,requestIdentity:request});
  assert.equal(restores,1);assert.strictEqual(actual.queryTime,context);
  assert.strictEqual(actual.runDefinition,definition);assert.strictEqual(actual.inferGraph,graph);
  assert.throws(()=>restoreInferTaskRunAdmission({control,preparedProgram:prepared,restored}),
    {message:'OriginalClientQueryRequestRequired'});
});

test('plural saved Infer keeps compiler order and selects the same occurrence without a new compile or clock', () => {
  const prepared = {}, request = {}, compiled = {kind: 'infer'}, context = {};
  const graph = Object.freeze([{}, {}]), executions = [{}, {}], occurrences = [{}, {}];
  const restored = {compiled, graph, runDefinition: definition};
  const originals = graph.map((value, index) => ({graph: value, execution: executions[index]}));
  let reads = 0;
  const control = {
    checkRestoredClientInferRunOwner(value, owner) {
      assert.strictEqual(value, restored); assert.strictEqual(owner, prepared);
    },
    checkedClientCompiledInferOriginals(value, owner, run) {
      assert.strictEqual(value, compiled); assert.strictEqual(owner, prepared);
      assert.strictEqual(run, definition); return originals;
    },
    clientRequiresQueryTime: () => true,
    prepareClientQueryTime() {assert.fail('No new query-time sample');},
    prepareCheckedClientCompiledRun() {assert.fail('No new compilation');},
    restoreClientQueryTime(owner, value, run, original) {
      assert.strictEqual(owner, prepared); assert.strictEqual(value, compiled);
      assert.strictEqual(run, definition); assert.strictEqual(original, request);
      reads++; return {queryTime: context};
    },
  };
  const moon = {
    clientProgramInferOccurrenceCoordinates: occurrence => ({_0: 2, _1: occurrences.indexOf(occurrence), _2: 1}),
    clientProgramInferPlanBoundary: value => ({_0: 2, _1: graph.indexOf(value), _2: 0, _3: 'original-barrier'}),
  };
  const plan = restoreInferTaskRunAdmission({control, preparedProgram: prepared, restored, requestIdentity: request});
  assert.strictEqual(plan.inferGraph, graph);
  assert.strictEqual(plan.queryTime, context);
  assert.equal(reads, 1);
  for (let index = 0; index < 2; index++) {
    const original = selectRestoredInferOccurrence({moon, control, preparedProgram: prepared,
      restored, occurrence: occurrences[index]});
    assert.strictEqual(original, originals[index]);
  }
  assert.throws(() => selectRestoredInferOccurrence({moon, control, preparedProgram: prepared,
    restored, occurrence: {}}), /ForeignInstalledInferOriginalOccurrence/u);
  assert.throws(() => selectRestoredInferOccurrence({moon: {...moon,
    clientProgramInferPlanBoundary: () => ({_0: 2, _1: 0, _2: 0, _3: 'original-barrier'})}, control,
    preparedProgram: prepared, restored, occurrence: occurrences[0]}), /ForeignInstalledInferOriginalOccurrence/u);
  originals.reverse();
  assert.throws(() => restoreInferTaskRunAdmission({control, preparedProgram: prepared,
    restored, requestIdentity: request}), /ForeignInstalledInferOriginalGraph/u);
});
