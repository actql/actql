import test from 'node:test';
import assert from 'node:assert/strict';
import {installNodeClientProgramPreparation,checkedRequestProgramPreparation} from './client-program-preparation.mjs';

function fixture(extra = {}) {
  const environment = {};
  // Explicit original-owner port for JS metadata/retirement tests. This
  // fixture does not claim an actual Core Request, Run or resource admission.
  const moon = {};
  return {environment, prepare: installNodeClientProgramPreparation({moon, environment,
    getFundedPreparation() {return {kind: 'effect_free', prepared: {},
      originalInputs: {environment, parameters: '{"p":"retained"}'}};}, ...extra})};
}
const request = () => ({kind: 'program', input: {}, parameters: {p: 'retained'}});

test('execution preparation requires the original Request owner even when every old raw export exists', () => {
  let calls = 0;
  const old = () => {calls++;};
  const moon = {
    clientProgramPrepareEffectFreeWithParameters: old,
    clientProgramPreparationReady: old,
    clientProgramPreparationIssue: old,
    clientProgramPreparationIssueCode: old,
    clientProgramPrepareEffectComputationWithParameters: old,
  };
  assert.throws(() => installNodeClientProgramPreparation({moon, environment: {}}),
    {message: 'InvalidClientProgramPreparationInstallation'}, '[request-funding-required]');
  assert.equal(calls, 0);
});

test('private Pure preparation retirement clears only exact metadata and is idempotent', async () => {
  const {environment, prepare} = fixture();
  const first = await prepare(request());
  const second = await prepare(request());
  assert.equal(prepare.originalInputs(first).environment, environment);
  assert.equal(prepare.originalInputs(first).parameters, '{"p":"retained"}');
  prepare.retireOriginal(first);
  prepare.retireOriginal(first);
  assert.throws(() => prepare.originalInputs(first), /ClientProgramPreparationFailure/);
  assert.throws(() => prepare.assertOwned(first), /Foreign Client preparation/);
  assert.throws(() => prepare.kindOf(first), /Foreign Client preparation/);
  assert.equal(prepare.kindOf(second), 'effect_free');
  assert.equal(prepare.originalInputs(second).environment, environment);
  assert.equal(prepare.kindOf(await prepare(request())), 'effect_free');
});

test('private Pure preparation retirement rejects foreign and restored Infer owners', async () => {
  const definition = {};
  const restored = {prepared: {}, compiled: {}, graph: {}, runDefinition: definition};
  const {prepare} = fixture({restoreInferOriginal: () => restored});
  const other = await fixture().prepare(request());
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
 assert.equal(Object.hasOwn(prepare, 'sourceCheckFailure'), false, 'No legacy Source marker or audience observation is fabricated');
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


test('typed Request projection preserves result and thrown-failure identity without public rechecking',async()=>{
  let projections=0;
  const moon={clientProgramRequestPreparationIssueCode(result){projections++;assert.equal(result,refusal);return 'check_invalid_input';}};
  const original={},issue={},refusal={$tag:0,_0:issue};
  assert.equal(checkedRequestProgramPreparation(moon,{$tag:1,_0:original}),original);
  assert.equal(projections,0);
  assert.throws(()=>checkedRequestProgramPreparation(moon,{$tag:7}),{code:'InvalidHostRuntimeResult'});
  assert.equal(projections,0);
  let checks=0,preparations=0,first;
  const {prepare}=fixture({getFundedPreparation(){preparations++;return checkedRequestProgramPreparation(moon,refusal);},
    check(){checks++;assert.fail('No second public check for the same preparation');}});
  await assert.rejects(prepare(request()),error=>{
    assert.equal(error.code,'ClientProgramInvalidInput');assert.equal(error.cause,issue);first=error;return true;
  });
  assert.equal(preparations,1);assert.equal(checks,0);assert.equal(projections,1);
  assert.equal(Object.hasOwn(prepare, 'sourceCheckFailure'), false, 'Original typed failure has no legacy Source marker');
});

test('selected Local row limit uses its first funded original without legacy runtime exports', async () => {
  const environment = {}, original = {}, parametersCursor = {};
  let preparations = 0, reads = 0, serialized = 0;
  const moon = {clientProgramValuesMaxRows(prepared) {
    assert.strictEqual(prepared, original); reads++; return 2;
  }};
  const prepare = installNodeClientProgramPreparation({moon, environment, valuesMaxRows: 2,
    getFundedPreparation(request, selected) {
      assert.strictEqual(selected, environment); preparations++;
      return {kind: 'effect_free', prepared: original,
        originalInputs: {environment, parameters: undefined, parametersCursor}};
    }});
  const prepared = await prepare({kind: 'program', parameters: null,
    input: {toJSON() {serialized++; throw Error('No second serializer');}}});
  assert.strictEqual(prepared, original);
  assert.strictEqual(prepare.originalInputs(original).parametersCursor, parametersCursor);
  assert.equal(preparations, 1); assert.equal(reads, 1); assert.equal(serialized, 0);
});

test('selected funded row limit refuses an unmatched original bound without legacy rescue', async () => {
  for (const observed of [undefined, 1, 3]) {
    const environment = {}, original = {}; let preparations = 0, serialized = 0;
    const moon = {clientProgramValuesMaxRows(prepared) {
      assert.strictEqual(prepared, original); return observed;
    }};
    const prepare = installNodeClientProgramPreparation({moon, environment, valuesMaxRows: 2,
      getFundedPreparation() {preparations++; return {kind: 'effect_free', prepared: original,
        originalInputs: {environment}};}});
    await assert.rejects(prepare({kind: 'program', parameters: null,
      input: {toJSON() {serialized++; throw Error('No old path');}}}),
    {code: 'ClientProgramPreparationFailure'});
    assert.equal(preparations, 1); assert.equal(serialized, 0);
    assert.throws(() => prepare.assertOwned(original), /Foreign Client preparation/);
  }
});


test('original frontend implementation limit keeps its cause and leaves unavailable capabilities generic', () => {
  // Explicit issue-code port: this is a JS projection control, not a Core
  // Request, a new check, or evidence that a Source/Run was accepted.
  for (const [category, code] of [
    ['source_implementation_limit', 'ClientProgramImplementationLimit'],
    ['source_unsupported', 'ClientProgramRejected'],
  ]) {
    const issue = {}, original = {$tag: 0, _0: issue};
    let projections = 0;
    const moon = {clientProgramRequestPreparationIssueCode(value) {
      projections++;
      assert.equal(value, original);
      return category;
    }};
    assert.throws(() => checkedRequestProgramPreparation(moon, original), error => {
      assert.equal(error.code, code);
      assert.equal(error.cause, issue);
      return true;
    });
    assert.equal(projections, 1);
  }
});
