import test from 'node:test';
import assert from 'node:assert/strict';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';

function fixture(extra = {}) {
  const environment = {};
  const moon = {
    clientProgramPrepareEffectFreeWithParameters() {return {prepared: {}};},
    clientProgramPreparationReady(outcome) {return outcome.prepared;},
    clientProgramPreparationIssue() {},
    clientProgramPreparationIssueCode() {},
  };
  return {environment, prepare: installNodeClientProgramPreparation({moon, environment, ...extra})};
}
const request = () => ({kind: 'program', input: {}, parameters: {p: 'retained'}});

test('private Pure preparation retirement clears only exact metadata and is idempotent', () => {
  const {environment, prepare} = fixture();
  const first = prepare(request());
  const second = prepare(request());
  assert.equal(prepare.originalInputs(first).environment, environment);
  assert.equal(prepare.originalInputs(first).parameters, '{"p":"retained"}');
  prepare.retireOriginal(first);
  prepare.retireOriginal(first);
  assert.throws(() => prepare.originalInputs(first), /ClientProgramPreparationFailure/);
  assert.throws(() => prepare.assertOwned(first), /Foreign Client preparation/);
  assert.throws(() => prepare.kindOf(first), /Foreign Client preparation/);
  assert.equal(prepare.kindOf(second), 'effect_free');
  assert.equal(prepare.originalInputs(second).environment, environment);
  assert.equal(prepare.kindOf(prepare(request())), 'effect_free');
});

test('private Pure preparation retirement rejects foreign and restored Infer owners', () => {
  const definition = {};
  const restored = {prepared: {}, compiled: {}, graph: {}, runDefinition: definition};
  const {prepare} = fixture({restoreInferOriginal: () => restored});
  const other = fixture().prepare(request());
  assert.throws(() => prepare.retireOriginal(other), /Foreign Pure Client preparation/);
  assert.throws(() => prepare.retireOriginal({}), /Foreign Pure Client preparation/);
  const infer = prepare.restoreInferOriginal({}, definition, {}, {});
  assert.throws(() => prepare.retireOriginal(infer), /Foreign Pure Client preparation/);
  assert.equal(prepare.originalInferRun(infer), restored);
});

test('fixed funded original awaits the same owner and retains its original metadata without serialization',async()=>{
 const original={},input={toJSON(){throw Error('unexpected second serialization');}};
 const parametersCursor={};let seen,release;
 const {environment,prepare}=fixture({getFundedPreparation(request,selected){seen=[request,selected];
   return new Promise(resolve=>{release=()=>resolve(Object.freeze({kind:'effect_free',prepared:original,
     originalInputs:Object.freeze({environment:selected,parameters:undefined,parametersCursor})}));});}});
 const request={kind:'program',input,parameters:null};
 const pending=prepare(request);assert.deepEqual(seen,[request,environment]);
 assert.throws(()=>prepare.assertOwned(original),/Foreign Client preparation/);
 assert.throws(()=>prepare.assertOwned(pending),/Foreign Client preparation/);
 release();assert.equal(await pending,original);
 assert.deepEqual(prepare.originalInputs(original),{environment,parameters:undefined,parametersCursor});
 assert.equal(prepare.originalInputs(original).parametersCursor,parametersCursor);
 prepare.retireOriginal(original);assert.throws(()=>prepare.assertOwned(original));
});
test('selected funded original refuses missing or old results without entering the legacy serializer',async()=>{
 let serialized=0;
 const request={kind:'program',input:{toJSON(){serialized++;return {}; }},parameters:null};
 for(const missing of [undefined,null,{},Promise.resolve(undefined)]){
   const {prepare}=fixture({getFundedPreparation(){return missing;}});
   await assert.rejects(async()=>prepare(request),{code:'ClientProgramPreparationFailure'});
 }
 assert.equal(serialized,0);
 const cause=Error('original funding failed');
 const broken=fixture({getFundedPreparation(){throw cause;}}).prepare;
 await assert.rejects(async()=>broken(request),error=>error===cause);
 assert.equal(serialized,0);
});

test('selected async owner failure does not repeat public checking or preparation',async()=>{
 const cause=Object.assign(new Error('actual owner refusal'),{code:'ClientProgramRejected'});
 let checks=0,preparations=0;
 const {prepare}=fixture({async getFundedPreparation(){preparations++;throw cause;},
   async check(){checks++;throw Error('unexpected repeated public check');}});
 await assert.rejects(prepare({kind:'aql',input:{text:'SELECT 1 AS n',format:'sql'},parameters:null}),
   error=>error===cause);
 assert.equal(preparations,1);assert.equal(checks,0);
 assert.equal(prepare.sourceCheckFailure(cause),false,'No audience-bound observation is fabricated');
});

test('pending funded result is not admitted after installation retirement or original cancellation',async()=>{
 for(const retired of [false,true]){
   let release;
   const controller=new AbortController(),original={};
   const {prepare}=fixture({getFundedPreparation(_request,environment){return new Promise(resolve=>{
     release=()=>resolve({kind:'effect_free',prepared:original,originalInputs:{environment}});
   });}});
   const pending=prepare({...request(),signal:controller.signal});
   const cause=Error('original cancellation');
   if(retired)prepare.retireReferences();else controller.abort(cause);
   release();
   await assert.rejects(pending,error=>retired?error.code==='ClientProgramPreparationFailure':error===cause);
   assert.throws(()=>prepare.assertOwned(original),/Foreign Client preparation/);
 }
});

test('selected result must retain the exact Environment and cannot admit a foreign or fabricated kind',async()=>{
 for(const change of [{environment:{}},{parameters:{}},{kind:'unknown'}]){
   const {prepare}=fixture({getFundedPreparation(_request,environment){return {
     kind:change.kind??'effect_free',prepared:{},originalInputs:{environment,...change}};}});
   await assert.rejects(prepare(request()),{code:'ClientProgramPreparationFailure'});
 }
});

test('selected funded primitive failure keeps its exact cause without a public recheck',async()=>{
 for(const cause of [undefined,null,0,'original-foreign-failure']) {
  let checks=0,entries=0;
  const {prepare}=fixture({check(){checks++;throw new Error('MustNotRecheck');},
   getFundedPreparation(){entries++;throw cause;}});
  await assert.rejects(prepare({kind:'program',input:{},parameters:null}),error=>
   error.code==='ClientProgramPreparationFailure'&&Object.hasOwn(error,'cause')&&error.cause===cause);
  assert.equal(entries,1);assert.equal(checks,0);
 }
});
