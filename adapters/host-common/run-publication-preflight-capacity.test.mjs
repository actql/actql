import {createHash} from 'node:crypto';
import {sourceFreeValuesPlan, sourceFreeTaskPlan, sourceFreePlanOriginal} from '../host-node/local-values-plan.mjs';
import test from 'node:test';import assert from 'node:assert/strict';
import {prepareCompletedEffectFreeRunPublication} from './run-publication-preflight.mjs';
import {resultOutputLimitFields} from './result-output-limits.mjs';
function optionsFor(inputs) {
 const c=name=>Object.freeze({name,identity:name,wire:JSON.stringify({name})});
 const context={inputRelationCids:inputs};
 const plan={admission:{},runDefinition:c('run'),invocation:c('invocation'),observation:{},normalizationJournal:{},authoringContext:{},
  results:[{retention:c('retention'),evidenceContext:context}],receiptEvidence:{bindings:[],sourceEvidence:[],modelEvidence:[],barrierAttemptReceiptCids:[]},captureEvidence:{pendingSourceStateAdvances:[],modelEvidence:[]},request:{},attempt:{},outputLimits:Object.fromEntries(resultOutputLimitFields.map(k=>[k,1000])),contractLimits:{maxWireBytes:1000,maxNodes:1000,maxDepth:100},now:()=>''};
 return {store:{publicationCapacitySupports:()=>true},control:{issuePublicationRequest:()=>c('request'),issuePublicationAttempt:()=>c('attempt'),publicationPreflightValid:()=>true,resultPublicationContractByteBounds:ids=>[10,ids.length*74,10,10]},publicationInventory:{occurrences:[{definitionContract:c('definition')}],programDefinitionCid:'program'},plan};
}
test('preflight owns the input-CID inventory used by its narrowed derivation quote',()=>{
 const inputs=['input0'],options=optionsFor(inputs),context=options.plan.results[0].evidenceContext;
 let originalQuoted;
 options.control.resultPublicationContractByteBounds=ids=>{originalQuoted=ids;return [10,ids.length*74,10,10];};
 const prepared=prepareCompletedEffectFreeRunPublication(options);
 const quote=prepared.capacity;inputs.push('input1');context.inputRelationCids=['replacement'];
 assert.deepEqual(prepared.plan.results[0].evidenceContext.inputRelationCids,['input0']);
 assert.equal(prepared.plan.results[0].evidenceContext.inputRelationCids,originalQuoted);
 assert.ok(Object.isFrozen(originalQuoted));assert.equal(prepared.capacity,quote);
 assert.throws(()=>originalQuoted.push('mutation'),TypeError);
});

test('malformed CID containers fail with coded preflight error; empty arrays remain valid',()=>{
 for(const value of [undefined,null,'sha256:not-an-array',{},42]){
  assert.throws(()=>prepareCompletedEffectFreeRunPublication(optionsFor(value)),{code:'InvalidRunPublicationPreflight'});
 }
 const prepared=prepareCompletedEffectFreeRunPublication(optionsFor([]));
 assert.deepEqual(prepared.plan.results[0].evidenceContext.inputRelationCids,[]);
 assert.ok(Object.isFrozen(prepared.plan.results[0].evidenceContext.inputRelationCids));
});


test('nested receipt inputs own binding values while preserving nominal Common originals',()=>{
 const options=optionsFor([]),binding={name:'before',sha256:'0'.repeat(64),ignoredLegacyMetadata:'unchanged'};
 const source={},model={},advance={},authoring={},observation={};
 options.plan.receiptEvidence.bindings.push(binding);
 options.plan.receiptEvidence.sourceEvidence.push(source);options.plan.receiptEvidence.modelEvidence.push(model);
 options.plan.captureEvidence.pendingSourceStateAdvances.push(advance);
 options.plan.authoringContext=authoring;options.plan.observation=observation;
 const prepared=prepareCompletedEffectFreeRunPublication(options);
 binding.name='after';binding.sha256='1'.repeat(64);options.plan.receiptEvidence.bindings.push({name:'extra',sha256:'0'.repeat(64)});
 options.plan.receiptEvidence.sourceEvidence.length=0;options.plan.captureEvidence.pendingSourceStateAdvances.length=0;
 assert.deepEqual(prepared.plan.receiptEvidence.bindings,[{name:'before',sha256:'0'.repeat(64)}]);
 assert.ok(Object.isFrozen(prepared.plan.receiptEvidence.bindings[0]));
 assert.strictEqual(prepared.plan.receiptEvidence.sourceEvidence[0],source);
 assert.strictEqual(prepared.plan.receiptEvidence.modelEvidence[0],model);
 assert.strictEqual(prepared.plan.captureEvidence.pendingSourceStateAdvances[0],advance);
 assert.strictEqual(prepared.plan.authoringContext,authoring);assert.strictEqual(prepared.plan.observation,observation);
});

test('unstable accessor bags are rejected without invoking semantic getters',()=>{
 for(const path of ['binding','context','limit','plan']){
  const options=optionsFor([]);let reads=0;
  const accessor={enumerable:true,get(){reads++;return 'unstable';}};
  if(path==='binding')options.plan.receiptEvidence.bindings.push(Object.defineProperty({sha256:'0'.repeat(64)},'name',accessor));
  if(path==='context')Object.defineProperty(options.plan.results[0].evidenceContext,'inputRelationCids',accessor);
  if(path==='limit')Object.defineProperty(options.plan.outputLimits,'maxRows',accessor);
  if(path==='plan')Object.defineProperty(options.plan,'authoringContext',accessor);
  assert.throws(()=>prepareCompletedEffectFreeRunPublication(options),{code:'InvalidRunPublicationPreflight'});
  assert.equal(reads,0,path);
 }
});

test('caller map and iterator overrides cannot retain mutable binding or Result bags',()=>{
 const options=optionsFor(['input0']);
 const binding={name:'captured',sha256:'0'.repeat(64)};
 const result=options.plan.results[0];let calls=0;
 options.plan.receiptEvidence.bindings=[binding];
 for(const array of [options.plan.receiptEvidence.bindings,options.plan.results,
   result.evidenceContext.inputRelationCids,options.publicationInventory.occurrences]){
  array.map=()=>{calls++;return array;};
  array[Symbol.iterator]=function*(){calls++;yield binding;};
 }
 const prepared=prepareCompletedEffectFreeRunPublication(options);
 binding.name='x'.repeat(500);result.evidenceContext.inputRelationCids.push('late');
 assert.equal(calls,0);
 assert.notStrictEqual(prepared.plan.receiptEvidence.bindings[0],binding);
 assert.equal(prepared.plan.receiptEvidence.bindings[0].name,'captured');
 assert.ok(Object.isFrozen(prepared.plan.receiptEvidence.bindings[0]));
 assert.deepEqual(prepared.plan.results[0].evidenceContext.inputRelationCids,['input0']);
});

test('array index accessors and inherited/sparse indices fail coded without evaluation',()=>{
 for(const kind of ['accessor','inherited','sparse']){
  const options=optionsFor([]);let reads=0;
  const bindings=[];bindings.length=1;
  if(kind==='accessor')Object.defineProperty(bindings,'0',{enumerable:true,get(){reads++;return {name:'x',sha256:'0'.repeat(64)};}});
  if(kind==='inherited')Object.setPrototypeOf(bindings,{0:{name:'x',sha256:'0'.repeat(64)},map(){throw Error('untrusted map');}});
  options.plan.receiptEvidence.bindings=bindings;
  assert.throws(()=>prepareCompletedEffectFreeRunPublication(options),{code:'InvalidRunPublicationPreflight'});
  assert.equal(reads,0);
 }
 const options=optionsFor([]),binding={name:'safe',sha256:'0'.repeat(64)};
 options.plan.receiptEvidence.bindings=[binding];
 Object.setPrototypeOf(options.plan.receiptEvidence.bindings,{map(){throw Error('untrusted prototype');}});
 const prepared=prepareCompletedEffectFreeRunPublication(options);
 binding.name='mutated';assert.equal(prepared.plan.receiptEvidence.bindings[0].name,'safe');
});

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = body => `sha256:${createHash('sha256').update(JSON.stringify(body)).digest('hex')}`;

// Actual planner and preflight consumers, with explicit opaque control/Store
// ports. These cases establish their shared data contract, not physical backing.
for (const kind of ['values', 'tasks']) {
test(`timed ${kind} publication reaches the existing preflight with original contracts`, () => {
  const contract = name => Object.freeze({name, identity: hash({name}), wire: JSON.stringify({name})});
  const prepared = {}, request = {}, time = {}, context = {}, originalPlan = {};
  const definition = contract('run_definition');
  const compiled = Object.freeze({kind, admission: {}, compiledPlan: contract('compiled_plan'),
    preparedEvidence: {wire: 'original-prepared'}, authorization: {wire: 'original-authorization'}});
  const invocationOriginal = Object.freeze({preparedProgram: prepared, requestIdentity: request,
    compiled, runDefinition: definition, createdAt: '2026-10-31T00:00:00.000Z',
    validUntil: '2026-11-01T00:00:00.000Z', queryTimePreparation: time, queryTime: context});
  let captured = 0, issued = 0, supported = 0;
  const control = {
    checkClientCompiledRunOwner(value, owner) {assert.equal(value, compiled); assert.equal(owner, prepared);},
    checkClientCompiledRunDefinition(value, run) {assert.equal(value, compiled); assert.equal(run, definition);},
    prepareCheckedClientCompiledRun() {assert.fail('original compilation must not be repeated');},
    defineCheckedClientCompiledRun() {assert.fail('original Run must not be reissued');},
    prepareClientQueryTime() {assert.fail('original time must not be sampled again');},
    issueCheckedClientCompiledInvocation(value, run) {
      assert.equal(value, compiled); assert.equal(run, definition);
      return {observation: contract('observation'), invocation: contract('invocation')};
    },
    seal: name => contract(name), sealRunEvidence: name => contract(name),
    compiledRunResultTransformation: () => undefined,
    captureOriginalClientRunPlan(value, owner, run) {
      assert.equal(value, compiled); assert.equal(owner, prepared); assert.equal(run, definition);
      captured++; return originalPlan;
    },
    issuePublicationRequest(run) {assert.equal(run, definition); issued++; return contract('request');},
    issuePublicationAttempt(_request, run) {assert.equal(run, definition); return contract('attempt');},
    publicationPreflightValid(admission, run) {
      assert.equal(admission, compiled.admission); assert.equal(run, definition); return true;
    },
    resultPublicationContractByteBounds: () => [10, 10, 10, 10],
  };
  const publicationOriginal = {};
  const moon = {
    clientProgramDefinitionCid: () => cid('b'), clientProgramResultCount: () => 1,
    clientProgramPreparedLocalPublicationLimits(value, owner) {
      assert.equal(value, publicationOriginal); assert.equal(owner, prepared);
      return resultOutputLimitFields.map(() => 1000);
    },
  };
  const plan = (kind === 'values' ? sourceFreeValuesPlan : sourceFreeTaskPlan)({
    moon, control, preparedProgram: prepared, requestIdentity: request, invocationOriginal,
    publicationOriginal: {kind: 'preparation', value: publicationOriginal},
    authorityScopeCid: cid('a'), namespaceId: 'local', storeAuthorityCid: cid('c'),
    now: () => '2026-10-31T00:00:00.000Z',
  });
  assert.equal(sourceFreePlanOriginal(plan), originalPlan);
  assert.equal(sourceFreePlanOriginal({...plan}), undefined);
  const preflight = prepareCompletedEffectFreeRunPublication({
    store: {publicationCapacitySupports() {supported++; return true;}}, control, plan,
    publicationInventory: {programDefinitionCid: cid('b'),
      occurrences: [{definitionContract: contract('result-definition')}]},
  });
  assert.equal(preflight.plan.runDefinition, definition);
  assert.equal(preflight.plan.invocation, plan.invocation);
  assert.equal(preflight.plan.admission, compiled.admission);
  assert.deepEqual({captured, issued, supported}, {captured: 1, issued: 1, supported: 1});
});
}
