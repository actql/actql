import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import resources from './ordinary-node-resource-runtime.cjs';
import {openRequestPreparation, cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';

// Actual normal manager/adapter/Resource originals; Core phase/shape results
// are explicit ports. This does not certify a matching Common or body tariff.
const ok = value => ({$tag:1, _0:value});
const input = () => ({version:'actql/0.1',id:'parent',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{
  schema:{n:{type:'number',nullable:false}},rows:[{n:1}],
}}],results:{rows:{from:'v',fields:['n']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
const connection = Object.freeze({mode:'local',owner:'local',consentRefs:Object.freeze([]),runners:Object.freeze([])});
async function fixture({beginFailure, environment, observe, validate = () => {}, validateRetained = validate, control=[1024n,0n], policyLimits=[10000n,10000n,10000n,100000n,100000n,100000n]}={}) {
  const calls=[],shapes=[],policy={},parent={};let admission;
  const stop = () => {
    assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0),0);
    assert.equal(admission.ports.status(2),0);
    return ok(undefined);
  };
  const moon={
    clientLocalResourcePolicyOriginal(){assert.equal(this,moon);return policy;},
    clientProgramRequestPreparationControl(actual){assert.equal(this,moon);assert.equal(actual,policy);calls.push('control');return control;},
    clientLocalPreparationResourceLimits(actual){assert.equal(this,moon);assert.equal(actual,policy);calls.push('policy-limits');return policyLimits;},
    clientProgramPrepareLocalPreparationAdmission(original,receipt){
      assert.equal(this,moon);calls.push('admission');
      admission={original,receipt,ports:resources.prepareOriginalLocalPreparationPorts(original,receipt)};return ok(admission);
    },
    clientProgramBeginRequestPreparation(actual,receipt,selectedPolicy){
      assert.equal(this,moon);assert.equal(actual,admission);assert.equal(receipt,admission.receipt);assert.equal(selectedPolicy,policy);
      if(beginFailure!==undefined) throw beginFailure;
      assert.equal(admission.ports.status(0),0);calls.push('parent');return ok(parent);
    },
    clientProgramReserveRequestSnapshot(actual,receipt,units,values){
      assert.equal(this,moon);assert.equal(actual,parent);assert.equal(receipt,admission.receipt);
      assert.equal(typeof units,'bigint');assert.equal(typeof values,'bigint');
      assert.ok(units>=values && values>0n);shapes.push({units,values});calls.push('snapshot-grow');return ok(undefined);
    },
    clientProgramAbortRequestPreparation(actual){assert.equal(this,moon);assert.equal(actual,parent);calls.push('abort-parent');return stop();},
    clientProgramCleanupLocalPreparationAdmission(actual){assert.equal(this,moon);assert.equal(actual,admission);calls.push('cancel-admission');assert.equal(admission.ports.cancelUnpublished(),0);return ok(undefined);},
    clientProgramPrepareRequestNativeComputation(){assert.fail('No semantic compilation selected');},
    clientProgramPrepareRequestSourceComputation(){assert.fail('No Source semantic check selected');},
    clientProgramFinishRequestComputation(owner,actual,selected,publication){
      assert.equal(this,moon);assert.equal(owner,parent);assert.equal(actual,admission.receipt);
      assert.equal(selected,environment);assert.equal(publication,context.preparedEnvironment);
      calls.push('compiler-finish');return ok('effect_free');
    },
    clientProgramPrepareRequestPolicySubjects(){assert.fail('No policy verifier selected');},
    clientProgramReadRequestPolicySubject(){assert.fail('No policy descriptor selected');},
    clientProgramBindRequestPolicySubject(){assert.fail('No policy binding selected');},
    clientProgramFinishRequestPolicySubjects(){assert.fail('No policy supplement selected');},
    clientProgramPrepareRequestProgramModuleBody(){assert.fail('No module compilation selected');},
    clientProgramRequestProgramModuleIssueCode(){assert.fail('No module failure projection selected');},
    clientProgramBorrowRequestProgramPlanInput(){assert.fail('No constructor input borrow selected');},
    clientProgramComposedInferOccurrences: () => ok([]),
    clientProgramSerializationOccurrences: () => [],
    clientProgramAcquisitionCount(){return 0;},
    clientProgramAdoptRequestProgramPreparation(){assert.fail('No Run adoption selected');},
  };
  const context=Object.freeze({runtime:moon,environment,preparedEnvironment:{},retainedRelationOutput:false});
  const originals=observe===undefined?{}:{installation:{authorization:{observe}}};const view=await prepareOrdinarySourceManagedInstallation(originals,{
    validator(actual){assert.equal(actual,originals);validate();},
    retainedValidator(actual){assert.equal(actual,originals);validateRetained();},
    preparationContext(actual){assert.equal(actual,originals);return context;},
    retireInitialPreparation(actual,prepared){assert.equal(actual,originals);assert.ok(prepared);calls.push('retire-registry-original');},
  },false);
  return {view,calls,shapes,context,originals,get parent(){return parent;},get original(){return admission?.original;}};
}

async function policyRequestFixture(kind = 'program', projectOriginal) {
  const environment = {}, f = await fixture({environment}), moon = f.context.runtime;
  if (projectOriginal !== undefined) moon.clientProgramProjectRequestCheckOutcome = projectOriginal;
  const request = {}, parameters = {path: 'cafe\u0301\r\n日本語😀'};
  const original = kind === 'program' ? input() : {format: 'sql', text: 'SELECT @path AS path'};
  const receipt = f.view.beforeSourceSnapshot(kind, kind === 'program' ? original : original.text,
    {parameters}, connection);
  const body = f.view.captureSourceSnapshot(receipt, {kind, input: original, parameters}, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
  const prepared = {}, holder = {}, cursor = {}, contracts = {}, events = [];
  const policy = 'sha256:' + 'a'.repeat(64);
  const subject = index => ({program_cid: policy, parameters_cid: policy,
    stage: 0, input: index, source_ref: 'fixture:files', source_view_contract_cid: policy,
    request_cid: policy, request: {path: parameters.path}, origins: {path: 'parameter'}});
  const wires = [0, 1].map(index => JSON.stringify(subject(index)));
  let semantic = false, subjectsPrepared = false, next = 0, supplemented = false,
    compiled = false, borrowed = false, returned = false;
  const same = (owner, actual, selected) => {
    assert.strictEqual(owner, f.parent); assert.strictEqual(actual, receipt);
    assert.strictEqual(selected, environment);
  };
  const check = function(owner, actual, captured, supplied, selected, publication) {
    assert.strictEqual(this, moon); same(owner, actual, selected);
    assert.strictEqual(captured, body.input); assert.strictEqual(supplied, body.parameters);
    assert.strictEqual(publication, f.context.preparedEnvironment);
    assert.equal(semantic, false); semantic = true; events.push('check'); return ok(undefined);
  };
  moon.clientProgramPrepareRequestNativeComputation = kind === 'program' ? check
    : () => assert.fail('Source envelope must retain its original frontend');
  moon.clientProgramPrepareRequestSourceComputation = kind === 'aql' ? check
    : () => assert.fail('Native Program must retain its original frontend');
  moon.clientProgramPrepareRequestPolicySubjects = function(owner, actual, selected) {
    assert.strictEqual(this, moon); same(owner, actual, selected); assert.equal(semantic, true);
    assert.equal(subjectsPrepared, false); subjectsPrepared = true;
    events.push('subjects'); return ok(wires.length);
  };
  moon.clientProgramReadRequestPolicySubject = function(owner, actual, selected, index) {
    assert.strictEqual(this, moon); same(owner, actual, selected);
    assert.equal(index, next); events.push('read-' + index); return ok(wires[index]);
  };
  moon.clientProgramBindRequestPolicySubject = function(owner, actual, selected, index, cid) {
    assert.strictEqual(this, moon); same(owner, actual, selected); assert.equal(index, next++);
    assert.equal(cid, index === 0 ? undefined : policy);
    events.push('bind-' + index); return ok(undefined);
  };
  moon.clientProgramFinishRequestPolicySubjects = function(owner, actual, selected) {
    assert.strictEqual(this, moon); same(owner, actual, selected); assert.equal(next, wires.length);
    assert.equal(supplemented, false); supplemented = true; events.push('supplement'); return ok(undefined);
  };
  moon.clientProgramFinishRequestComputation = function(owner, actual, selected, publication) {
    assert.strictEqual(this, moon); same(owner, actual, selected);
    assert.strictEqual(publication, f.context.preparedEnvironment);
    assert.equal(semantic, true); assert.equal(supplemented, subjectsPrepared); assert.equal(compiled, false);
    compiled = true; events.push('compile'); return ok('effect_free');
  };
  moon.clientProgramBorrowRequestProgramPlanInput = function(owner, actual) {
    assert.strictEqual(this, moon); assert.strictEqual(owner, f.parent); assert.strictEqual(actual, receipt);
    assert.equal(compiled, true); borrowed = true; events.push('borrow'); return ok(holder);
  };
  moon.clientProgramPreparationBorrowRead = actual => {assert.strictEqual(actual, holder); return prepared;};
  moon.clientProgramPrepareRequestProgramModuleBody = function(owner, actual, admission, retained) {
    assert.strictEqual(this, moon); assert.strictEqual(owner, f.parent); assert.strictEqual(actual, receipt);
    assert.strictEqual(admission, contracts); assert.equal(retained, false); events.push('module'); return ok(undefined);
  };
  moon.clientProgramRequestParametersOriginal = function(owner, actual) {
    assert.strictEqual(this, moon); assert.strictEqual(owner, f.parent); assert.strictEqual(actual, receipt);
    events.push('parameters'); return ok(cursor);
  };
  moon.clientProgramRequestPreparationIssueCode = () => undefined;
  const abort = moon.clientProgramAbortRequestPreparation;
  moon.clientProgramAbortRequestPreparation = function(owner) {
    return borrowed && !returned ? {$tag: 0, _0: {pendingOriginal: holder}}
      : Reflect.apply(abort, moon, [owner]);
  };
  moon.clientProgramPreparationBorrowRetirementStarted = actual => {assert.strictEqual(actual, holder); return true;};
  moon.clientProgramPreparationBorrowReturn = actual => {
    assert.strictEqual(actual, holder); assert.equal(returned, false); returned = true; return ok(true);
  };
  f.originals.installation = {sequenceContractOriginal: {moon, admission: contracts}};
  return {...f, moon, environment, request, prepared, cursor, events, policy, subject, wires, receipt, body,
    async finish() {
      f.view.finishSourceProducer(receipt, 'failed'); await f.view.close();
      assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
    }};
}

test('same Request policy checks once binds every original subject then compiles once without changing Environment', async () => {
  for (const kind of ['program', 'aql']) {
    const f = await policyRequestFixture(kind), controller = new AbortController();
    let enter, release, verified = 0;
    const entered = new Promise(resolve => {enter = resolve;});
    const held = new Promise(resolve => {release = resolve;});
    const verify = async (subject, options) => {
      const index = verified++;
      assert.deepEqual(subject, f.subject(index));
      assert.ok(Object.isFrozen(subject)); assert.ok(Object.isFrozen(subject.request));
      assert.ok(Object.isFrozen(subject.origins)); assert.strictEqual(options.signal, controller.signal);
      if (index === 0) {enter(); await held; return undefined;}
      return f.policy;
    };
    const shapes = f.shapes.length;
    const pending = f.view.fundedPreparation(f.request, f.environment, verify, controller.signal);
    try {
      await Promise.race([entered, pending.then(() => assert.fail('Preparation returned before verification'))]);
      assert.deepEqual(f.events, ['check', 'subjects', 'read-0']);
      assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
      await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify, controller.signal),
        {code: 'ForeignInstalledSourceProducer'});
      f.moon.clientProgramFinishRequestComputation = () => assert.fail('Captured compiler method was replaced');
      f.moon.clientProgramBindRequestPolicySubject = () => assert.fail('Captured binder method was replaced');
      release();
      const selected = await pending;
      assert.strictEqual(selected.prepared, f.prepared);
      assert.strictEqual(selected.originalInputs.environment, f.environment);
      assert.strictEqual(selected.originalInputs.parametersCursor, f.cursor);
      assert.equal(verified, 2); assert.equal(f.shapes.length, shapes);
      assert.deepEqual(f.events, ['check', 'subjects', 'read-0', 'bind-0', 'read-1', 'bind-1',
        'supplement', 'compile', 'borrow', 'module', 'parameters']);
      assert.strictEqual((await f.view.fundedPreparation(f.request, f.environment, verify, controller.signal)).prepared,
        f.prepared);
      assert.equal(verified, 2);
    } finally {release(); await pending.catch(() => {}); await f.finish();}
  }
});

test('same Request policy keeps a thrown verifier failure without binding compiling or re-preparing', async () => {
  const f = await policyRequestFixture(), cause = new Error('Original verifier failure');
  let verified = 0;
  const verify = async () => {verified++; throw cause;};
  try {
    await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify), error => error === cause);
    await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify), error => error === cause);
    assert.equal(verified, 1);
    assert.deepEqual(f.events, ['check', 'subjects', 'read-0']);
  } finally {await f.finish();}
});

test('same Request policy cancellation after verification refuses before binding or compiler entry', async () => {
  const f = await policyRequestFixture(), controller = new AbortController();
  const cause = new Error('Original policy cancellation');
  let verified = 0;
  const verify = async (_subject, options) => {
    assert.strictEqual(options.signal, controller.signal);
    verified++; controller.abort(cause); return undefined;
  };
  try {
    await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify, controller.signal),
      error => error === cause);
    assert.equal(verified, 1); assert.deepEqual(f.events, ['check', 'subjects', 'read-0']);
  } finally {await f.finish();}
});

test('same Request policy rejects invalid verifier DATA without binding or retrying the original', async () => {
  for (const value of [true, null, {policy: 'public'}, 'invalid']) {
    const f = await policyRequestFixture(); let verified = 0, original;
    const verify = async () => {verified++; return value;};
    try {
      await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify), error => {
        assert.equal(error.code, 'ClientProgramPreparationFailure'); original = error; return true;
      });
      await assert.rejects(f.view.fundedPreparation(f.request, f.environment, verify), error => error === original);
      assert.equal(verified, 1); assert.deepEqual(f.events, ['check', 'subjects', 'read-0']);
    } finally {await f.finish();}
  }
});

test('same Request policy handles no verifier and an empty selected inventory without a callback or second check', async () => {
  for (const selected of [false, true]) {
    const f = await policyRequestFixture(); f.wires.length = 0;
    const verify = selected ? () => assert.fail('An empty original inventory has no verifier call') : undefined;
    try {
      const result = await f.view.fundedPreparation(f.request, f.environment, verify);
      assert.strictEqual(result.prepared, f.prepared);
      assert.deepEqual(f.events, ['check', ...(selected ? ['subjects', 'supplement'] : []),
        'compile', 'borrow', 'module', 'parameters']);
    } finally {await f.finish();}
  }
});

test('same Request policy keeps subject construction failure distinct from an empty successful inventory', async () => {
  const f = await policyRequestFixture(), issue = {}; let verified = 0;
  f.moon.clientProgramPrepareRequestPolicySubjects = function(owner, original, environment) {
    assert.strictEqual(this, f.moon); assert.strictEqual(owner, f.parent);
    assert.strictEqual(original, f.receipt); assert.strictEqual(environment, f.environment);
    f.events.push('subjects-failed'); return {$tag: 0, _0: issue};
  };
  try {
    await assert.rejects(f.view.fundedPreparation(f.request, f.environment, () => {verified++;}), error => {
      assert.equal(error.code, 'MoonBitHostFailure'); assert.strictEqual(error.cause, issue); return true;
    });
    assert.equal(verified, 0); assert.deepEqual(f.events, ['check', 'subjects-failed']);
  } finally {await f.finish();}
});

test('generic snapshot passes the same native intent and original Request to Common once without a wire fallback', async () => {
  const f=await fixture(),moon=f.context.runtime,request={};
  const input={text:'SELECT @text AS text',format:'sql'},parameters={text:'日本語\r\n😀',nested:[{n:2}]};
  const receipt=f.view.beforeSourceSnapshot('aql',input.text,{parameters},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'aql',input,parameters,
    stopBefore:'commit',readOnly:true},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  const intent={},cid=`sha256:${'1'.repeat(64)}`;let prepares=0,finishes=0;
  moon.clientProgramPrepareRequestSubmittedIntent=function(parent,original,value){
    assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
    assert.deepEqual(Object.keys(value).sort(),['input','kind','parameters','readOnly','stopBefore']);
    assert.equal(value.input,body.input);assert.equal(value.parameters,body.parameters);
    assert.equal(value.kind,'aql');assert.equal(value.stopBefore,'commit');assert.equal(value.readOnly,true);
    prepares++;return ok(cid);
  };
  moon.clientProgramFinishRequestSubmittedIntent=function(parent,original){
    assert.equal(parent,f.parent);assert.equal(original,receipt);finishes++;return ok(undefined);
  };
  moon.clientProgramRequestSubmittedIntentOriginal=function(parent,original){
    assert.equal(parent,f.parent);assert.equal(original,receipt);return intent;
  };
  try{
    assert.equal(f.view.intentCid(receipt,body),cid);
    assert.equal(f.view.submittedIntentOriginal(request),intent);
    assert.equal(prepares,1);assert.equal(finishes,1);
    assert.throws(()=>f.view.submittedIntentOriginal({...request}),{code:'ForeignInstalledSourceProducer'});
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
});

test('generic intent keeps its original Common refusal and does not finish or enter wire fallback', async () => {
  const f=await fixture(),moon=f.context.runtime;
  const receipt=f.view.beforeSourceSnapshot('aql','SELECT 1 AS n',{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'aql',input:{format:'sql',text:'SELECT 1 AS n'},parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);
  const issue={};let calls=0;
  moon.clientProgramPrepareRequestSubmittedIntent=function(parent,original,value){
    assert.equal(parent,f.parent);assert.equal(original,receipt);
    assert.deepEqual(Object.keys(value).sort(),['input','kind','parameters']);
    calls++;return {$tag:0,_0:issue};
  };
  moon.clientProgramFinishRequestSubmittedIntent=()=>assert.fail('Failed construction has not returned an intent');
  try{
    assert.throws(()=>f.view.intentCid(receipt,{...body}),{code:'ForeignInstalledSourceProducer'});
    assert.equal(calls,0);
    assert.throws(()=>f.view.intentCid(receipt,body),error=>error.code==='MoonBitHostFailure'&&error.cause===issue);
    assert.equal(calls,1);
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
});

test('normal default Request retains one parent before the original SDK snapshot growth',async()=>{
  const f=await fixture();const program=input();
  const receipt=f.view.beforeSourceSnapshot('program',program,undefined,connection);
  assert.deepEqual(f.calls,['control','policy-limits','admission','parent']);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:program,parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.finishSourceProducer(receipt,'failed');
  assert.equal(f.calls.filter(x=>x==='parent').length,1);assert.ok(f.shapes.length>0);
  assert.equal(f.calls.filter(x=>x==='abort-parent').length,1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(await f.view.close(),{pending:false});
});

test('normal Request opening throw preserves primary and cancels the exact initial admission once',async()=>{
  const failure=new Error('OriginalOpeningFailure');const f=await fixture({beginFailure:failure});
  assert.throws(()=>f.view.beforeSourceSnapshot('program',input(),undefined,connection),cause=>cause===failure);
  assert.deepEqual(f.calls,['control','policy-limits','admission','cancel-admission']);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(await f.view.close(),{pending:false});
});

test('invalid bootstrap quote refuses before producer slots or original input callbacks',async()=>{
  const f=await fixture({control:[0n,0n]});let getters=0;
  const program={get stages(){getters++;throw new Error('NoInputVisit');}};
  for(let index=0;index<33;index++)assert.throws(()=>f.view.beforeSourceSnapshot('program',program,undefined,connection),{code:'NodeLocalPreparationAdmissionUnavailable'});
  assert.equal(getters,0);assert.equal(f.original,undefined);assert.equal(f.calls.every(x=>x==='control'),true);
  assert.deepEqual(await f.view.close(),{pending:false});
});


test('native snapshot fence authenticates the actual ordinary producer receipt and retained Node original', async () => {
  const f = await fixture(), program = input();
  const receipt = f.view.beforeSourceSnapshot('program', program, undefined, connection);
  assert.throws(() => f.view.assertSourceSnapshotCurrent({}), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(f.view.assertSourceSnapshotCurrent(receipt), undefined);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
  f.view.finishSourceProducer(receipt, 'failed');
  assert.throws(() => f.view.assertSourceSnapshotCurrent(receipt), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.deepEqual(await f.view.close(), {pending: false});
});

test('normal SQL source retains one Request parent before SDK Parameter and option snapshot', async () => {
  const f = await fixture();
  let reads = 0;
  const parameters = {get n() {reads++; return 7;}};
  const options = {format: 'sql', parameters};
  const receipt = f.view.beforeSourceSnapshot('aql', 'SELECT @n AS n', options, connection);
  try {
    // The actual SDK owns the following getter/snapshot pass. The Host must
    // retain this original parent without pre-reading those same values.
    assert.equal(reads, 0);
    assert.equal(f.calls.filter(value => value === 'parent').length, 1);
    assert.ok(f.original);
  } finally {
    f.view.finishSourceProducer(receipt, 'failed');
    assert.deepEqual(await f.view.close(), {pending: false});
  }
});


test('normal SQL snapshot grows the same parent and observes Parameters exactly once', async () => {
  const f = await fixture();
  let reads = 0, coerced = 0;
  const number = Object.assign(new Number(1), {valueOf() {coerced++; return 7;}});
  const parameters = {get n() {reads++; return number;}};
  const receipt = f.view.beforeSourceSnapshot('aql', 'SELECT @n AS n', {parameters}, connection);
  const body = f.view.captureSourceSnapshot(receipt,
    {kind: 'aql', input: {text: 'SELECT @n AS n', format: 'sql'}, parameters}, snapshotClientRequest);
  assert.equal(reads, 1);assert.equal(coerced, 1);
  assert.deepEqual(body.parameters, {n: 7});
  assert.equal(f.calls.filter(value => value === 'parent').length, 1);
  assert.ok(f.calls.filter(value => value === 'snapshot-grow').length > 0);
  assert.equal(f.calls.includes('select'), false);
  assert.ok(f.shapes.at(-1).values>0n && f.shapes.at(-1).values<=f.shapes.at(-1).units);
  f.view.bindSourceSnapshot(receipt, body);
  f.view.finishSourceProducer(receipt, 'failed');
  assert.equal(f.calls.filter(value => value === 'abort-parent').length, 1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.deepEqual(await f.view.close(), {pending: false});
});


test('actual Request opening needs the original lifetime rather than Source or connection metadata', async () => {
  const f = await fixture();
  const state = {context: {runtime: f.context.runtime}};
  const original = Object.freeze({});
  let currents = 0;
  const current = () => {
    currents++;
    assert.throws(() => openRequestPreparation(state, original, current, () => false),
      {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.throws(() => cleanupRequestInput(state),
      {code: 'NodeLocalPreparationAdmissionUnavailable'});
  };
  assert.equal(openRequestPreparation(state, original, current, () => false), f.parent);
  assert.ok(currents > 0);assert.equal(state.opening, false);
  assert.equal(f.calls.filter(value => value === 'parent').length, 1);
  assert.throws(() => openRequestPreparation(state, original, current, () => false),
    {code: 'NodeLocalPreparationAdmissionUnavailable'});
  cleanupRequestInput(state);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.deepEqual(await f.view.close(), {pending: false});
});


test('actual initial opening selects its original Common policy without a Source or quote callback', async () => {
  const f = await fixture();
  const state = {context: {runtime: f.context.runtime}};
  const original = Object.freeze({});
  assert.equal(openRequestPreparation(state, original, () => {}, () => false), f.parent);
  assert.equal(f.calls.filter(value => value === 'policy-limits').length, 1);
  assert.equal(f.calls.includes('requirements'), false);
  const ports = resources.prepareOriginalLocalPreparationPorts(state.original, original);
  assert.equal(ports, null, 'the original sole ports were already retained by Common');
  cleanupRequestInput(state);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.deepEqual(await f.view.close(), {pending: false});
});


test('actual initial policy refusal precedes Resource opening and original current callbacks', async () => {
  for (const policyLimits of [[], [0n,0n,0n,0n,0n], [2147483648n,0n,0n,0n,0n,0n],
    [0n,0n,0n,0n,0n,9223372036854775808n], [0n,0n,0n,0n,0n,'0']]) {
    const f = await fixture({policyLimits});
    const state = {context: {runtime: f.context.runtime}};
    let currents = 0;
    assert.throws(() => openRequestPreparation(state, Object.freeze({}),
      () => {currents++;}, () => false), {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.equal(currents, 0);assert.equal(f.original, undefined);
    assert.deepEqual(f.calls, ['policy-limits']);assert.equal(state.opening, false);
    cleanupRequestInput(state);
    assert.deepEqual(await f.view.close(), {pending: false});
  }
});

// The actual openPreparedInstalledHost preparation method, with explicit Common
// constructor ports and the real ordinary Resource supplier. No runtime build,
// Source material/IO or full Host/physical acceptance is supplied by this test.
async function initialHostFixture({beginFailure = false} = {}) {
  const {parse} = await import('acorn');
  const {readFileSync} = await import('node:fs');
  const {openHostInitializationPreparation, closeHostInitializationPreparation} =
    await import('../local-node/request-preparation-adapter.mjs');
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let method, selectionMethod, servicesMethod;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'hostInitializationPreparation') method = node.value;
    if (node.type === 'Property' && node.key?.name === 'sourceInitializationServices') servicesMethod = node.value;
    if (node.type === 'FunctionDeclaration' && node.id?.name === 'assertSourceInitializationSelection') selectionMethod = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(ast); assert.ok(method); assert.ok(selectionMethod); assert.ok(servicesMethod);
  const policy = {}, parent = {}, record = {}, installation = {}, calls = [];
  let admission;
  const stop = () => {
    assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0), 0);
    assert.equal(admission.ports.status(2), 0); return ok(undefined);
  };
  const moon = {
    clientLocalResourcePolicyOriginal() {assert.equal(this,moon); calls.push('policy');return policy;},
    clientLocalPreparationResourceLimits(p) {assert.equal(p,policy);return [1n,1n,1n,10n,1000n,1000n];},
    clientProgramPrepareLocalPreparationAdmission(original, input) {
      assert.equal(input,installation);assert.equal(record.hostInitialization.original,original);
      admission = {original, ports:resources.prepareOriginalLocalPreparationPorts(original,input)};
      return ok(admission);
    },
    clientProgramBeginHostInitializationPreparation(actual,input,p) {
      assert.equal(actual,admission);assert.equal(input,installation);assert.equal(p,policy);
      assert.equal(record.hostInitialization.admission,admission);
      assert.equal(admission.ports.status(0),0);calls.push('initial');
      if (beginFailure) throw new Error('InitialConstructorFailed');
      return ok(parent);
    },
    clientProgramCloseHostInitializationPreparation(original) {assert.equal(original,parent);calls.push('close');return stop();},
    clientProgramCleanupLocalPreparationAdmission(original) {assert.equal(original,admission);calls.push('cleanup');return stop();},
  };
  record.runtime = moon;
  const code = `function(${method.params.map(p => source.slice(p.start,p.end)).join(',')})${source.slice(method.body.start,method.body.end)}`;
  const invoke = new Function('record','moon','originalInstallation','openHostInitializationPreparation',
    'assertInitialControlHostPreparation','assertInitialControlInstallationCurrent','clientOperationError',
    `let hostInitialization, sourceManaged, sourceInitializationSelection, project, control={}, originals={};
      ${source.slice(selectionMethod.start,selectionMethod.end)}
      return (${code});`)(
      record,moon,installation,openHostInitializationPreparation,()=>{},()=>{},
      code=>Object.assign(new Error(code),{code}));
  return {invoke,moon,parent,record,calls,close:()=>closeHostInitializationPreparation(record.hostInitialization),
    get original() {return admission.original;},source,ast,servicesMethod};
}

test('actual Host initialization retains the original before construction and reuses it across Requests', async () => {
  const f = await initialHostFixture();
  assert.equal(f.invoke(f.moon),f.parent);assert.equal(f.invoke(f.moon),f.parent);
  assert.deepEqual(f.calls,['policy','initial']);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,false);
  assert.throws(()=>f.invoke({...f.moon}),{code:'ForeignInstalledHostPreparation'});
  f.close();assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.throws(()=>f.invoke(f.moon),{code:'InstalledHostPreparationChanged'});
});

test('actual Host initial constructor failure keeps its same original admission for cleanup', async () => {
  const f = await initialHostFixture({beginFailure:true});
  assert.throws(()=>f.invoke(f.moon),/InitialConstructorFailed/);
  assert.ok(f.record.hostInitialization.admission);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,false);
  assert.throws(()=>f.invoke(f.moon),{code:'InstalledHostPreparationChanged'});
  f.close();assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(f.calls,['policy','initial','cleanup']);
});

test('actual Host passes its early original to installation services before Source loading', async () => {
  const f = await initialHostFixture();
  // The installed Source service now owns the same early preparation. Check
  // both its real constructor order and the actual loader's service selection.
  const servicesBody = f.source.slice(f.servicesMethod.body.start,f.servicesMethod.body.end);
  const initial = servicesBody.indexOf('const initialPreparation = preparation.hostInitializationPreparation(runtime);');
  const create = servicesBody.indexOf('sourceInitializationServices = createInstalledHostServices(',initial);
  assert.ok(initial >= 0 && create > initial);
  const servicesEnd = servicesBody.indexOf(';',create);
  assert.match(servicesBody.slice(create,servicesEnd),/moon: runtime, initialPreparation, assertCurrent/);
  const start = f.source.indexOf('const installationServices = preparation === undefined');
  const service = f.source.indexOf('preparation.sourceInitializationServices(moon, root, principalId, assertProjectRuntime)',start);
  const load = f.source.indexOf('await loadInstalledSources(', service);
  assert.ok(start >= 0 && service > start && load > service);
  assert.match(f.source.slice(load,f.source.indexOf(';',load)),/connectorTable, installationServices/);
  const sourceClose = f.source.indexOf('if (sourceManaged !== undefined) {', f.source.indexOf('const initialControl = Object.freeze'));
  const initialClose = f.source.indexOf('closeHostInitializationPreparation(hostInitialization)',sourceClose);
  const referenceClose = f.source.indexOf('retirePreparationReferences();',initialClose);
  assert.ok(sourceClose >= 0 && initialClose > sourceClose && referenceClose > initialClose);
});


test('normal generic Native Request prepares the original Parameters compiler module and body on one parent', async () => {
  const f=await fixture(),moon=f.context.runtime,request={};
  const program=input(),parameters={n:7,label:'日本語😀'};
  const receipt=f.view.beforeSourceSnapshot('program',program,{parameters},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:program,parameters},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  const prepared={},holder={},parametersCursor={},calls=[];
  moon.clientProgramPrepareRequestNativeComputation=function(parent,original,captured,supplied,environment,publication){
    assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
    assert.equal(captured,body.input);assert.equal(supplied,body.parameters);
    assert.equal(environment,undefined);assert.equal(publication,f.context.preparedEnvironment);
    calls.push('check-original');return ok(undefined);
  };
  moon.clientProgramPrepareRequestProgramModuleBody=function(parent,original,contracts,retained){
    assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
    assert.equal(contracts,selectedContract);assert.equal(retained,false);calls.push('module-original');return ok(undefined);
  };
  moon.clientProgramBorrowRequestProgramPlanInput=function(parent){
    assert.equal(parent,f.parent);calls.push('borrow-original');return ok(holder);
  };
  moon.clientProgramPreparationBorrowRead=value=>{assert.equal(value,holder);return prepared;};
  moon.clientProgramRequestParametersOriginal=function(parent,original){
    assert.equal(parent,f.parent);assert.equal(original,receipt);return ok(parametersCursor);
  };
  let returned=false;
  const abort=moon.clientProgramAbortRequestPreparation;
  moon.clientProgramAbortRequestPreparation=function(parent){
    assert.equal(parent,f.parent);
    // Model the actual Core pending-borrow result. Its first retire cannot
    // report physical completion while this same original holder remains.
    return returned ? Reflect.apply(abort,moon,[parent]) : {$tag:0,_0:{pendingOriginal:holder}};
  };
  moon.clientProgramPreparationBorrowRetirementStarted=value=>{assert.equal(value,holder);return true;};
  moon.clientProgramPreparationBorrowReturn=value=>{assert.equal(value,holder);returned=true;calls.push('return-original');return ok(false);};
  const selectedContract={};
  // The actual installation body is supplied by the existing manager fixture,
  // rather than replacing its original Source/Request callbacks with a driver.
  f.originals.installation={sequenceContractOriginal:{moon,admission:selectedContract}};
  try{
    const first=await f.view.fundedPreparation(request,undefined);
    const second=await f.view.fundedPreparation(request,undefined);
    assert.equal(first.prepared,prepared);assert.equal(second.prepared,prepared);
    assert.equal(first.kind,'effect_free');assert.equal(first.originalInputs.parametersCursor,parametersCursor);
    assert.equal(first.originalInputs.parameters,undefined);
    assert.deepEqual(calls,['check-original','borrow-original','module-original']);
    assert.equal(f.calls.filter(x=>x==='parent').length,1);assert.equal(f.calls.includes('select'),false);
  }finally{
    f.view.finishSourceProducer(receipt,'failed');await f.view.close();
  }
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(calls,['check-original','borrow-original','module-original','return-original']);
});

test('normal generic Native Request preserves its first semantic refusal without a second preparation', async () => {
  const f=await fixture(),moon=f.context.runtime,request={};
  const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};
  const issue={},failure=Object.assign(new Error('OriginalCompilerRefusal'),{cause:issue});let calls=0;
  moon.clientProgramPrepareRequestNativeComputation=function(parent,original){
    assert.equal(parent,f.parent);assert.equal(original,receipt);calls++;throw failure;
  };
  moon.clientProgramPrepareRequestProgramModuleBody=()=>assert.fail('No Plan after compiler refusal');
  try{
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    assert.equal(calls,1);
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
});

test('normal generic Native Request preserves failed Plan construction and rejects synchronous reentry', async () => {
  const f=await fixture(),moon=f.context.runtime,request={};
  const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};
  const failure=new Error('OriginalModuleConstructorFailed');let checks=0,modules=0,reentry;
  const prepared = {}, holder = {};
  moon.clientProgramBorrowRequestProgramPlanInput = () => ok(holder);
  moon.clientProgramPreparationBorrowRead = value => {assert.equal(value, holder); return prepared;};
  moon.clientProgramPreparationBorrowRetirementStarted = value => {assert.equal(value, holder); return true;};
  const abort = moon.clientProgramAbortRequestPreparation; let returned = false;
  moon.clientProgramAbortRequestPreparation = owner => returned
    ? Reflect.apply(abort, moon, [owner]) : {$tag: 0, _0: new Error('OriginalInputPending')};
  moon.clientProgramPreparationBorrowReturn = value => {assert.equal(value, holder); returned = true; return ok(true);};
  moon.clientProgramPrepareRequestNativeComputation=()=>{checks++;return ok(undefined);};
  moon.clientProgramPrepareRequestProgramModuleBody=function(){
    modules++;
    reentry=f.view.fundedPreparation(request,undefined);
    // Handler cleanup cannot retire the same constructor while it is live.
    assert.throws(()=>cleanupRequestInput({context:f.context,preparing:true}),
      {code:'NodeLocalPreparationAdmissionUnavailable'});
    throw failure;
  };
  try{
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    await assert.rejects(reentry,{code:'ForeignInstalledSourceProducer'});
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    assert.equal(checks,1);assert.equal(modules,1);
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
});

test('normal generic Native Request adopts the same Run and retains its current after handler completion', async () => {
  let accepting = true, duringRetained;
  const f=await fixture({validate() {assert.ok(accepting, 'NewPreparationRefused');}, validateRetained() {duringRetained?.();}}),moon=f.context.runtime,request={},prepared={},holder={},identity={},value={};
  const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};
  let retiring=false,returns=0,adopts=0;const compilation={};let compilationReads=0;
  moon.clientProgramInstalledManagedRunCompilationOriginal=function(actual,p){assert.equal(this,moon);assert.equal(actual,value);assert.equal(p,prepared);compilationReads++;return compilation;};
  moon.clientProgramClosedValuesCompilationOriginal=()=>assert.fail('The parent-only Run has no ClosedValues phase');
  moon.clientProgramPrepareRequestNativeComputation=()=>ok(undefined);
  moon.clientProgramPrepareRequestProgramModuleBody=()=>ok(undefined);
  moon.clientProgramBorrowRequestProgramPlanInput=()=>ok(holder);
  moon.clientProgramPreparationBorrowRead=actual=>{assert.equal(actual,holder);return prepared;};
  moon.clientProgramRequestParametersOriginal=()=>ok(undefined);
  moon.clientProgramAdoptRequestProgramPreparation=function(parent,actualIdentity){
    assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(actualIdentity,identity);adopts++;return ok(value);
  };
  moon.clientProgramPreparationBorrowRetirementStarted=actual=>{assert.equal(actual,holder);return retiring;};
  moon.clientProgramPreparationBorrowReturn=actual=>{assert.equal(actual,holder);returns++;return ok(true);};
  await f.view.fundedPreparation(request,undefined);
  const run=f.view.adoptPreparation(prepared,request,identity);
  assert.equal(run.original,f.original);assert.equal(run.value,value);assert.equal(adopts,1);
  assert.equal(f.view.compilationOriginal(prepared),compilation);assert.equal(compilationReads,1);
  f.view.finishSourceProducer(receipt,'returned');
  // Actual ordinary Resource calls its originally retained current callback.
  // Finishing the SDK producer must not invalidate this same live Run.
  assert.equal(f.view.publicationPreparation(prepared),value);
  accepting = false;
  assert.throws(() => f.view.beforeSourceSnapshot('program', input(), {}, connection), /NewPreparationRefused/);
  const publicationResource = {};
  moon.clientProgramReservePublication = (actual, p) => {assert.equal(actual, value); assert.equal(p, prepared); return ok(publicationResource);};
  assert.equal(f.view.reservePublication(prepared), publicationResource);
  assert.throws(() => f.view.reservePublication({}), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(()=>f.view.severPreparation(prepared,f.original),{code:'ForeignInstalledSourceProducer'});
  assert.equal(returns,0);
  duringRetained = () => {
    duringRetained = undefined; retiring = true;
    f.view.severPreparation(prepared, f.original);
  };
  assert.throws(() => f.view.reservePublication(prepared), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(returns, 1);
  f.view.severPreparation(prepared,f.original);assert.equal(returns,1);
  // The explicit Common fixture supplies no physical operation. Its original
  // Resource port still owns stop; the token return above was not that ACK.
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,false);
  f.context.runtime.clientProgramAbortRequestPreparation(f.parent);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  assert.throws(() => f.view.reservePublication(prepared), {code: 'ForeignInstalledSourceProducer'});
  f.view.retireSeveredPreparation(f.original);
  assert.throws(() => f.view.reservePublication(prepared), {code: 'ForeignInstalledSourceProducer'});
  assert.equal((await f.view.close()).pending,false);
});

test('normal generic Native cleanup keeps its original holder without the required registry retirement', () => {
  const parent={},holder={},prepared={};let returns=0;
  const runtime={
    clientProgramAbortRequestPreparation(actual){assert.equal(actual,parent);return {$tag:0,_0:{pending:holder}};},
    clientProgramPreparationBorrowRetirementStarted(actual){assert.equal(actual,holder);return true;},
    clientProgramPreparationBorrowReturn(){returns++;return ok(false);},
  };
  const state={context:{runtime},parent,holder,prepared};
  assert.throws(()=>cleanupRequestInput(state),{code:'NodeLocalPreparationAdmissionUnavailable'});
  assert.equal(returns,0);assert.equal(state.holder,holder);assert.equal(state.prepared,prepared);
});

test('normal generic Native Request retains an undefined foreign failure without another constructor', async () => {
  const f=await fixture(),moon=f.context.runtime,request={};
  const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};let constructors=0;
  moon.clientProgramPrepareRequestNativeComputation=()=>{constructors++;throw undefined;};
  try{
    for(let attempt=0;attempt<2;attempt++) {
      let rejected=false;
      await f.view.fundedPreparation(request,undefined).then(()=>assert.fail('Missing original failure'),value=>{
        rejected=true;assert.equal(value,undefined);
      });
      assert.equal(rejected,true);
    }
    assert.equal(constructors,1);
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
});


test('normal generic Native Request projects its retained typed semantic refusal once without a second check', async () => {
  // Real manager/ordinary Resource lifecycle, explicit nominal Core result ports.
  // These categories must be selected by Core, never reconstructed from JS tags.
  for (const [category,code] of [
    ['program_syntax','ClientProgramInvalidInput'],
    ['check_invalid_input','ClientProgramInvalidInput'],
    ['supplied_admission','ClientParametersInvalid'],
    ['needs_inputs','ClientProgramNeedsInputs'],
    ['source_unresolved','ClientProgramRejected'],
    [undefined,'MoonBitHostFailure'],
  ]) {
    const f=await fixture(),moon=f.context.runtime,request={};
    const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
    const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
    f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
    f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};
    const issue=Object.freeze({}),result=Object.freeze({$tag:0,_0:issue});
    let constructors=0,projections=0,originalFailure;
    moon.clientProgramPrepareRequestNativeComputation=function(parent,original){
      assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
      constructors++;return result;
    };
    moon.clientProgramRequestPreparationIssueCode=function(original){
      assert.equal(this,moon);assert.equal(original,result);projections++;return category;
    };
    moon.clientProgramPrepareRequestProgramModuleBody=()=>assert.fail('No Plan after typed refusal');
    try {
      await assert.rejects(f.view.fundedPreparation(request,undefined),error=>{
        assert.equal(error.code,code);assert.equal(error.cause,issue);originalFailure=error;return true;
      });
      await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===originalFailure);
      assert.equal(constructors,1);assert.equal(projections,1);
    } finally {f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});


test('normal default and empty options use the same Request without legacy ClosedValues exports', async () => {
  for (const options of [undefined, {}]) {
    const f=await fixture();
    for (const name of Object.keys(f.context.runtime)) if (name.includes('ClosedValues')) delete f.context.runtime[name];
    const never=()=>assert.fail('No semantic/module or legacy scanner work during SDK capture');
    for (const name of ['clientProgramPrepareRequestNativeComputation','clientProgramPrepareRequestProgramModuleBody',
      'clientProgramBorrowRequestProgramPlanInput','clientProgramRequestParametersOriginal',
      'clientProgramAdoptRequestProgramPreparation','clientProgramInstalledManagedRunCompilationOriginal',
      'clientProgramPreparationBorrowRead','clientProgramPreparationBorrowSibling',
      'clientProgramPreparationBorrowRetirementStarted','clientProgramPreparationBorrowReturn']) f.context.runtime[name]=never;
    const program=input(),stages=program.stages;let reads=0,receipt;
    stages[0].steps[0].values.schema.note={type:'string',nullable:false};
    stages[0].steps[0].values.rows[0].note='日本語😀';stages[0].results.rows.fields.push('note');
    Object.defineProperty(program,'stages',{enumerable:true,get(){reads++;return stages;}});
    try {
      receipt=f.view.beforeSourceSnapshot('program',program,options,connection);
      assert.equal(reads,0);
      assert.deepEqual(f.calls,['control','policy-limits','admission','parent']);
      const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:program,parameters:null},snapshotClientRequest);
      assert.equal(reads,1);assert.equal(body.input.stages[0].steps[0].values.rows[0].note,'日本語😀');
      assert.ok(f.shapes.length>0);f.view.bindSourceSnapshot(receipt,body);
    } finally {
      if (receipt!==undefined) f.view.finishSourceProducer(receipt,'failed');
      assert.deepEqual(await f.view.close(),{pending:false});
    }
    assert.equal(f.calls.filter(x=>x==='parent').length,1);
    assert.equal(f.calls.filter(x=>x==='abort-parent').length,1);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});


test('normal SQL and AQL Request keeps native Parameters declarations and one checked original before compiler completion', async () => {
  for (const format of ['sql','aql','aql-text']) {
    const f=await fixture(),moon=f.context.runtime,request={},prepared={},holder={},parametersCursor={};
    const source={format,text:format==='sql'?'SELECT @text AS label':
      'WITH seed AS (SELECT @text AS label) FROM seed |> SELECT label',
      parameterDeclarations:{text:{type:'string'}}};
    const parameters={text:'日本語😀'},receipt=f.view.beforeSourceQuery(format,source.text,parameters,{},connection);
    const body=f.view.captureSourceSnapshot(receipt,{kind:'aql',input:source,parameters},snapshotClientRequest);
    f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
    const contracts={},calls=[];
    f.originals.installation={sequenceContractOriginal:{moon,admission:contracts}};
    moon.clientProgramPrepareRequestNativeComputation=()=>assert.fail('A Query must not be reinterpreted as a native Program');
    moon.clientProgramPrepareRequestSourceComputation=function(parent,original,captured,supplied,environment,publication){
      assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
      assert.equal(captured,body.input);assert.equal(supplied,body.parameters);
      assert.equal(environment,undefined);assert.equal(publication,f.context.preparedEnvironment);
      assert.equal(captured.parameterDeclarations.text.type,'string');
      assert.equal(supplied.text,'日本語😀');calls.push('query-check-original');return ok(undefined);
    };
    moon.clientProgramPrepareRequestProgramModuleBody=function(parent,original,selected,retained){
      assert.equal(parent,f.parent);assert.equal(original,receipt);assert.equal(selected,contracts);
      assert.equal(retained,false);calls.push('module-original');return ok(undefined);
    };
    moon.clientProgramBorrowRequestProgramPlanInput=actual=>{assert.equal(actual,f.parent);return ok(holder);};
    moon.clientProgramPreparationBorrowRead=actual=>{assert.equal(actual,holder);return prepared;};
    moon.clientProgramRequestParametersOriginal=()=>ok(parametersCursor);
    let returned=false;const abort=moon.clientProgramAbortRequestPreparation;
    moon.clientProgramAbortRequestPreparation=function(parent){return returned||!calls.includes('module-original')?Reflect.apply(abort,moon,[parent]):{$tag:0,_0:{pendingOriginal:holder}};};
    moon.clientProgramPreparationBorrowRetirementStarted=actual=>{assert.equal(actual,holder);return true;};
    moon.clientProgramPreparationBorrowReturn=actual=>{assert.equal(actual,holder);returned=true;return ok(false);};
    try {
      for(let attempt=0;attempt<2;attempt++){
        const result=await f.view.fundedPreparation(request,undefined);
        assert.equal(result.prepared,prepared);assert.equal(result.kind,'effect_free');
        assert.equal(result.originalInputs.parametersCursor,parametersCursor);
      }
      assert.deepEqual(calls,['query-check-original','module-original']);
      assert.equal(f.calls.filter(x=>x==='parent').length,1);
    } finally {f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});

// This consumes the actual manager and explicit compiler ports. The separate
// Core case executes the unchanged parser/checker/compiler/Plan/Run itself.
test('normal JSON and YAML Source forwards one captured document and Parameters original', async () => {
  for (const format of ['json','aql-json','yaml','aql-yaml']) {
    const f=await fixture(),moon=f.context.runtime,request={},prepared={},holder={},parametersCursor={};
    const text=format.includes('json')?'{"version":"actql/0.1"}':'version: actql/0.1';
    const parameters={n:9},receipt=f.view.beforeSourceSnapshot('aql',text,{format,parameters},connection);
    const body=f.view.captureSourceSnapshot(receipt,{kind:'aql',input:{format,text},parameters},snapshotClientRequest);
    f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
    const contracts={},calls=[];f.originals.installation={sequenceContractOriginal:{moon,admission:contracts}};
    moon.clientProgramPrepareRequestNativeComputation=()=>assert.fail('Source document must keep its original text/format, not a native Program replacement');
    moon.clientProgramPrepareRequestSourceComputation=function(parent,original,captured,supplied,environment,publication){
      assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
      assert.equal(captured,body.input);assert.equal(captured.text,text);assert.equal(captured.format,format);
      assert.equal(supplied,body.parameters);assert.equal(supplied.n,9);
      assert.equal(publication,f.context.preparedEnvironment);calls.push('document');return ok(undefined);
    };
    moon.clientProgramPrepareRequestProgramModuleBody=function(parent,original,selected){
      assert.equal(parent,f.parent);assert.equal(original,receipt);assert.equal(selected,contracts);calls.push('module');return ok(undefined);
    };
    moon.clientProgramBorrowRequestProgramPlanInput=actual=>{assert.equal(actual,f.parent);return ok(holder);};
    moon.clientProgramPreparationBorrowRead=actual=>{assert.equal(actual,holder);return prepared;};
    moon.clientProgramRequestParametersOriginal=()=>ok(parametersCursor);
    let returned=false;const abort=moon.clientProgramAbortRequestPreparation;
    moon.clientProgramAbortRequestPreparation=function(parent){return returned||!calls.includes('module')?Reflect.apply(abort,moon,[parent]):{$tag:0,_0:{pendingOriginal:holder}};};
    moon.clientProgramPreparationBorrowRetirementStarted=actual=>{assert.equal(actual,holder);return true;};
    moon.clientProgramPreparationBorrowReturn=actual=>{assert.equal(actual,holder);returned=true;return ok(false);};
    try {
      for(let attempt=0;attempt<2;attempt++){
        const result=await f.view.fundedPreparation(request,undefined);
        assert.equal(result.prepared,prepared);assert.equal(result.originalInputs.parametersCursor,parametersCursor);
      }
      assert.deepEqual(calls,['document','module']);assert.equal(f.calls.filter(x=>x==='parent').length,1);
    } finally {f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});


test('normal first Request Plan keeps its original typed row refusal or unclassified failure without rebuilding', async () => {
  for (const [category, code] of [
    ['values_profile_unsupported', 'ClientProgramUnsupported'],
    ['source_free_capacity_exceeded', 'ClientProgramRejected'],
    [undefined, 'MoonBitHostFailure'],
  ]) {
    const diagnostics=[];
    const f = await fixture({observe:(event,facts)=>{
      diagnostics.push({event,facts});
      throw new Error('Observer failure cannot change original refusal');
    }}), moon = f.context.runtime, request = {};
    const receipt = f.view.beforeSourceSnapshot('program', input(), {}, connection);
    const body = f.view.captureSourceSnapshot(receipt,
      {kind: 'program', input: input(), parameters: null}, snapshotClientRequest);
    f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
    const contracts = {};
    f.originals.installation = {sequenceContractOriginal: {moon, admission: contracts}};
    const issue = Object.freeze({}), result = Object.freeze({$tag: 0, _0: issue});
    let checks = 0, modules = 0, projections = 0, first;
    moon.clientProgramPrepareRequestNativeComputation = function(parent, original) {
      assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
      checks++; return ok(undefined);
    };
    moon.clientProgramPrepareRequestProgramModuleBody = function(parent, original, selected) {
      assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
      assert.equal(selected, contracts); modules++; return result;
    };
    moon.clientProgramRequestProgramModuleIssueCode = function(original) {
      assert.equal(this, moon); assert.equal(original, result); projections++; return category;
    };
    moon.clientProgramRequestProgramModuleCapacityRefusal = function(original) {
      assert.equal(this,moon); assert.equal(original,result);
      assert.equal(category,'source_free_capacity_exceeded');
      return {_0:'source_free_plan',_1:'execution',_2:203770432n,_3:703186240n,
        _4:536870912n,_5:536870912n};
    };
    const prepared = {}, holder = {};
    moon.clientProgramBorrowRequestProgramPlanInput = (parent, original) => {
      assert.equal(parent, f.parent); assert.equal(original, receipt); return ok(holder);
    };
    moon.clientProgramPreparationBorrowRead = value => {assert.equal(value, holder); return prepared;};
    moon.clientProgramPreparationBorrowRetirementStarted = value => {assert.equal(value, holder); return true;};
    const abort = moon.clientProgramAbortRequestPreparation; let returned = false;
    moon.clientProgramAbortRequestPreparation = owner => returned
      ? Reflect.apply(abort, moon, [owner]) : {$tag: 0, _0: new Error('OriginalInputPending')};
    moon.clientProgramPreparationBorrowReturn = value => {assert.equal(value, holder); returned = true; return ok(true);};
    try {
      for (let attempt = 0; attempt < 2; attempt++) {
        await assert.rejects(f.view.fundedPreparation(request, undefined), error => {
          assert.equal(error.code ?? error.message, code);
          if (category !== undefined) assert.equal(error.cause, issue);
          if (attempt === 0) first = error; else assert.equal(error, first);
          return true;
        });
      }
      assert.deepEqual([checks, modules, projections], [1, 1, 1]);
      assert.equal(diagnostics.length,category==='source_free_capacity_exceeded'?1:0);
      if(diagnostics.length) {
        assert.equal(diagnostics[0].event,'preparation_capacity_refused');
        assert.ok(Object.isFrozen(diagnostics[0].facts));
        assert.deepEqual(diagnostics[0].facts,{phase:'source_free_plan',dimension:'execution',
          requiredRetentionBytes:'203770432',requiredExecutionBytes:'703186240',
          availableRetentionBytes:'536870912',availableExecutionBytes:'536870912'});
      }
    } finally { f.view.finishSourceProducer(receipt, 'failed'); await f.view.close(); }
  }
});

test('ordinary Effect Plan adopts the same Request input and typed compiler borrow without manager admission', async () => {
  const f = await fixture(), moon = f.context.runtime, sdkRequest = {}, identity = {}, plan = {}, parent = {};
  const program = input(), receipt = f.view.beforeSourceSnapshot('program', program, {}, connection);
  const body = f.view.captureSourceSnapshot(receipt, {kind: 'program', input: program}, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, sdkRequest);
  const prepared = {}, holder = {}, events = [];
  moon.clientProgramPrepareRequestNativeComputation = function(owner, original, captured) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    assert.equal(captured, body.input); events.push('check'); return ok(undefined);
  };
  moon.clientProgramFinishRequestComputation = function(owner, original, selected, publication) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    assert.equal(selected, undefined); assert.equal(publication, f.context.preparedEnvironment);
    events.push('compile'); return ok('effectful');
  };
  moon.clientProgramBorrowRequestEffectPlanInput = function(owner, original) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    events.push('borrow-effect-input'); return ok(holder);
  };
  moon.clientProgramEffectPreparationInputRead = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); return prepared;
  };
  moon.clientProgramEffectPreparationInputReturn = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); events.push('return-effect-input'); return ok(true);
  };
  moon.clientProgramEffectPreparationInputSibling = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); return ok({});
  };
  moon.clientProgramEffectPreparationInputRetirementStarted = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); return true;
  };
  moon.clientProgramRequestParametersOriginal = function(owner, original) {
    assert.equal(owner, f.parent); assert.equal(original, receipt); return ok(undefined);
  };
  moon.clientProgramCompleteRequestEffectPreparation = function(owner, original, actualPlan) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    assert.equal(actualPlan, plan); events.push('complete-effect'); return ok(undefined);
  };
  moon.clientProgramAdoptRequestEffectPreparation = function(owner, actualIdentity) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(actualIdentity, identity);
    events.push('adopt-effect'); return ok(parent);
  };
  moon.clientProgramPreparationBorrowRead = moon.clientProgramPreparationBorrowReturn = () => {
    assert.fail('Effect holder must never enter the Program-borrow ABI');
  };
  f.originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  // fixture.context retains no selected environment; undefined is its exact original.
  const selected = await f.view.fundedPreparation(sdkRequest, undefined);
  assert.equal(selected.kind, 'effectful'); assert.equal(selected.prepared, prepared);
  const actual = f.view.adoptEffectPreparation(prepared, sdkRequest, identity, plan);
  assert.equal(actual.value, parent); assert.equal(actual.original, f.original);
  assert.equal(actual.operationPlan, plan);
  assert.deepEqual(events, ['check', 'compile', 'borrow-effect-input', 'complete-effect', 'adopt-effect']);
  assert.equal(f.view.prepareEffectPlanRun, undefined, 'remove replaced independent ordinary Effect admission');
  assert.throws(() => f.view.adoptEffectPreparation(prepared, sdkRequest, identity, plan),
    {code: 'ForeignInstalledSourceProducer'});
});

async function originalEffectRequest({completeFailure, adoptFailure} = {}) {
  const f = await fixture(), moon = f.context.runtime, sdkRequest = {}, prepared = {}, holder = {}, identity = {}, plan = {}, parent = {};
  const receipt = f.view.beforeSourceSnapshot('program', input(), {}, connection);
  const body = f.view.captureSourceSnapshot(receipt, {kind: 'program', input: input()}, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, sdkRequest);
  f.originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  const events = []; let retiring = false, returned = false;
  moon.clientProgramPrepareRequestNativeComputation = () => {events.push('check'); return ok(undefined);};
  moon.clientProgramFinishRequestComputation = function(owner, original, selected, publication) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    assert.equal(selected, undefined); assert.equal(publication, f.context.preparedEnvironment);
    events.push('compile'); return ok('effectful');
  };
  moon.clientProgramBorrowRequestEffectPlanInput = function(owner, original) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt);
    events.push('borrow'); return ok(holder);
  };
  moon.clientProgramEffectPreparationInputRead = function(value) {assert.equal(this, moon); assert.equal(value, holder); return returned ? undefined : prepared;};
  moon.clientProgramEffectPreparationInputSibling = function(value) {assert.equal(this, moon); assert.equal(value, holder); events.push('sibling'); return ok({});};
  moon.clientProgramEffectPreparationInputRetirementStarted = function(value) {assert.equal(this, moon); assert.equal(value, holder); return retiring;};
  moon.clientProgramEffectPreparationInputReturn = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); assert(retiring); assert(!returned);
    events.push('return'); returned = true; return ok(true);
  };
  moon.clientProgramRequestParametersOriginal = () => ok(undefined);
  moon.clientProgramCompleteRequestEffectPreparation = function(owner, original, actualPlan) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(original, receipt); assert.equal(actualPlan, plan);
    events.push('complete'); if (completeFailure) throw completeFailure; return ok(undefined);
  };
  moon.clientProgramAdoptRequestEffectPreparation = function(owner, actualIdentity) {
    assert.equal(this, moon); assert.equal(owner, f.parent); assert.equal(actualIdentity, identity);
    events.push('adopt'); if (adoptFailure) throw adoptFailure; return ok(parent);
  };
  moon.clientProgramPreparationBorrowRead = moon.clientProgramPreparationBorrowReturn = () => assert.fail('no Program-holder cast');
  const abort = moon.clientProgramAbortRequestPreparation;
  moon.clientProgramAbortRequestPreparation = function(owner) {
    assert.equal(owner, f.parent); retiring = true;
    return returned ? Reflect.apply(abort, moon, [owner]) : {$tag: 0, _0: new Error('OriginalEffectBorrowPending')};
  };
  return {...f, moon, sdkRequest, prepared, holder, identity, plan, parent, requestParent: f.parent, receipt, events,
    markRetiring() {retiring = true;}, finishPhysicalRetirement() {return Reflect.apply(abort, moon, [f.parent]);}, async failedCleanup() {f.view.finishSourceProducer(receipt, 'failed'); await f.view.close();}};
}

test('installed Effect caller consumes actual Request manager adoption and same Plan with no independent admission', async () => {
  const f = await originalEffectRequest();
  const {prepareInstalledEffectManagedPlanRun: prepare, readInstalledEffectManagedPlanRun: read} = await import('./installed-effect-managed-run.mjs');
  const selected = await f.view.fundedPreparation(f.sdkRequest, undefined);
  const facts = Object.freeze({prepared: selected.prepared, identity: f.identity, compilation: {}, allowed: {},
    definition: {}, queryTimePreparation: undefined, modelCompiled: undefined}), runs = new WeakMap(), liveRuns = new Set();
  f.moon.clientProgramInstalledManagedRunRetire = () => ok(undefined);
  f.moon.clientProgramInstalledEffectOperationControlsRetain = () => ok(f.plan);
  f.moon.clientProgramInstalledEffectOperationControlConstructionBegin = () => ok(undefined);
  f.moon.clientProgramInstalledEffectOperationControlConstructionComplete = () => ok(undefined);
  f.moon.clientProgramInstalledEffectManagedOperationPlan = function(value, prepared, identity) {
    assert.equal(this, f.moon); assert.equal(value, f.parent); assert.equal(prepared, f.prepared); assert.equal(identity, f.identity); return ok(f.plan);
  };
  f.moon.clientProgramNodeEffectManagedPlanPrepare = f.moon.clientProgramInstalledEffectManagedPlanBegin = () => assert.fail('no independent admission');
  const options = {runs, liveRuns, runtime: f.moon, manager: f.view, prepared: f.prepared,
    request: f.identity, requestInput: f.sdkRequest, facts, inputs: {},
    selection: Object.freeze({prepareManagedPlan(actual) {assert.equal(actual, facts); f.events.push('select'); return f.plan;}}),
    assertCurrent() {}, checked: value => {if (value.$tag !== 1) throw value._0; return value._0;}};
  assert.equal(prepare(options), f.parent); assert.equal(prepare(options), f.parent);
  assert.equal(read(options).operationPlan, f.plan);
  assert.deepEqual(f.events, ['check', 'compile', 'borrow', 'select', 'complete', 'adopt']);
  assert.throws(() => prepare({...options, requestInput: {}}), {code: 'ForeignInstalledEffectManagedRun'});
  // Original Scope/parent retirement is an explicit Core port, never implied
  // by preparation completion or a terminal provider classification.
  f.markRetiring(); f.view.severPreparation(f.prepared, f.original);
  f.finishPhysicalRetirement();
  f.view.retireSeveredPreparation(f.original);
  f.view.finishSourceProducer(f.receipt, 'returned'); await f.view.close();
  assert.equal(f.events.at(-1), 'return');
});

test('failed Request Effect completion or adoption keeps typed input cleanup and cannot acquire another admission', async () => {
  for (const phase of ['completeFailure', 'adoptFailure']) {
    const failure = new Error(phase), f = await originalEffectRequest({[phase]: failure});
    await f.view.fundedPreparation(f.sdkRequest, undefined);
    assert.throws(() => f.view.adoptEffectPreparation(f.prepared, f.sdkRequest, f.identity, f.plan), error => error === failure);
    assert.throws(() => f.view.adoptEffectPreparation(f.prepared, f.sdkRequest, f.identity, f.plan), error => error === failure);
    await f.failedCleanup();
    assert.equal(f.events.filter(x => x === 'check').length, 1);
    assert.equal(f.events.filter(x => x === 'complete').length, 1);
    assert.equal(f.events.filter(x => x === 'return').length, 1);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  }
});

test('Request Effect borrowed methods keep original receiver and reject foreign input before completion', async () => {
  const f = await originalEffectRequest(); await f.view.fundedPreparation(f.sdkRequest, undefined);
  f.moon.clientProgramEffectPreparationInputRead = () => assert.fail('do not replace captured typed method');
  f.view.borrowPreparation(f.prepared, f.sdkRequest);
  assert.throws(() => f.view.adoptEffectPreparation(f.prepared, {}, f.identity, f.plan), {code: 'ForeignInstalledSourceProducer'});
  assert(!f.events.includes('complete')); await f.failedCleanup();
  assert.deepEqual(f.events, ['check', 'compile', 'borrow', 'sibling', 'return']);
});


test('captured Pure Request keeps its original compiler input before Source Plan construction', async () => {
  const f = await fixture(), moon = f.context.runtime, request = {}, prepared = {}, holder = {};
  const events = []; let retiring = false, returned = false;
  // Semantic compilation/typed capture are explicit Core ports; the actual
  // manager, snapshot, input receipt and original Resource parent are real.
  // This case establishes no Source I/O, Account authority or physical backing.
  f.originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  const originalInput = {version: 'actql/0.1', id: 'source-compute',
    results: {answer: {from: {result: 'r', stage: 'compute'}}}, stages: [
      {id: 'acquire', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
        results: {r: {fields: ['id'], from: 'captured'}},
        steps: [{as: 'filtered', filter: 'id > 0'}, {as: 'captured', select: ['id']}]},
      {id: 'compute', inputs: {x: {result: {result: 'r', stage: 'acquire'}}},
        results: {r: {fields: ['id'], from: 'out'}},
        steps: [{filter: 'id > 2'}, {as: 'out', select: ['id']}]},
    ]};
  const receipt = f.view.beforeSourceSnapshot('program', originalInput, {}, connection);
  const body = f.view.captureSourceSnapshot(receipt, {kind: 'program', input: originalInput, parameters: null}, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
  moon.clientProgramPrepareRequestNativeComputation = function(parent, original) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
    events.push('check'); return ok(undefined);
  };
  moon.clientProgramBorrowRequestProgramPlanInput = function(parent, original) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(original, receipt);
    events.push('input-borrow'); return ok(holder);
  };
  moon.clientProgramPreparationBorrowRead = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); return prepared;
  };
  moon.clientProgramAcquisitionCount = function(value) {
    assert.equal(this, moon); assert.equal(value, prepared); events.push('original-acquisition-count'); return 1;
  };
  moon.clientProgramPrepareRequestProgramModuleBody = () => assert.fail('captured Source must not enter the Source-free module constructor');
  moon.clientProgramBorrowRequestProgramPreparation = () => assert.fail('the original input holder must survive until actual capture Plan completion');
  moon.clientProgramRequestParametersOriginal = function(parent, original) {
    assert.equal(parent, f.parent); assert.equal(original, receipt); return ok(undefined);
  };
  moon.clientProgramPreparationBorrowRetirementStarted = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); return retiring;
  };
  moon.clientProgramPreparationBorrowReturn = function(value) {
    assert.equal(this, moon); assert.equal(value, holder); assert(retiring); assert(!returned);
    returned = true; events.push('input-return'); return ok(true);
  };
  const abort = moon.clientProgramAbortRequestPreparation;
  moon.clientProgramAbortRequestPreparation = function(parent) {
    assert.equal(this, moon); assert.equal(parent, f.parent); retiring = true;
    return returned || !events.includes('input-borrow')
      ? Reflect.apply(abort, moon, [parent]) : {$tag: 0, _0: new Error('OriginalCaptureInputPending')};
  };
  try {
    const selected = await f.view.fundedPreparation(request, undefined);
    assert.equal(selected.kind, 'effect_free'); assert.equal(selected.prepared, prepared);
    assert.deepEqual(events, ['check', 'input-borrow', 'original-acquisition-count']);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).admitted, true);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
  } finally {
    f.view.finishSourceProducer(receipt, 'failed'); await f.view.close();
  }
  assert.equal(events.filter(value => value === 'check').length, 1);
  assert.equal(events.filter(value => value === 'input-return').length, 1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});


async function originalCapturedRequest({moduleFailure, adoptFailure} = {}) {
  const f = await fixture(), moon = f.context.runtime, request = {}, prepared = {}, holder = {}, identity = {}, plan = {}, value = {};
  const events = []; let retiring = false, returned = false;
  f.originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  const originalInput = {version: 'actql/0.1', id: 'source-compute',
    results: {answer: {from: {result: 'r', stage: 'compute'}}}, stages: [
      {id: 'acquire', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
        results: {r: {fields: ['id'], from: 'captured'}},
        steps: [{as: 'filtered', filter: 'id > 0'}, {as: 'captured', select: ['id']}]},
      {id: 'compute', inputs: {x: {result: {result: 'r', stage: 'acquire'}}},
        results: {r: {fields: ['id'], from: 'out'}},
        steps: [{filter: 'id > 2'}, {as: 'out', select: ['id']}]},
    ]};
  const receipt = f.view.beforeSourceSnapshot('program', originalInput, {}, connection);
  const body = f.view.captureSourceSnapshot(receipt, {kind: 'program', input: originalInput, parameters: null}, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body); f.view.bindSourceRequest(receipt, body, request);
  moon.clientProgramPrepareRequestNativeComputation = () => {events.push('check'); return ok(undefined);};
  moon.clientProgramBorrowRequestProgramPlanInput = function(parent, input) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(input, receipt);
    events.push('borrow'); return ok(holder);
  };
  moon.clientProgramPreparationBorrowRead = original => {assert.equal(original, holder); return returned ? undefined : prepared;};
  moon.clientProgramAcquisitionCount = original => {assert.equal(original, prepared); return 1;};
  moon.clientProgramRequestParametersOriginal = () => ok(undefined);
  moon.clientProgramPrepareRequestProgramModuleBody = () => assert.fail('no Source-free module for captured Program');
  moon.clientProgramAdoptRequestProgramPreparation = () => assert.fail('no Source-free adoption for captured Program');
  moon.clientProgramPrepareRequestCaptureModuleBody = function(parent, input, selected) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(input, receipt); assert.equal(selected, plan);
    events.push('module'); if (moduleFailure) throw moduleFailure; return ok(undefined);
  };
  moon.clientProgramAdoptRequestCapturePreparation = function(parent, selected) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(selected, identity);
    events.push('adopt'); if (adoptFailure) throw adoptFailure; return ok(value);
  };
  const abort = moon.clientProgramAbortRequestPreparation;
  moon.clientProgramAbortRequestPreparation = parent => {
    assert.equal(parent, f.parent); retiring = true;
    return returned ? Reflect.apply(abort, moon, [parent]) : {$tag: 0, _0: new Error('OriginalCaptureInputPending')};
  };
  moon.clientProgramPreparationBorrowRetirementStarted = original => {assert.equal(original, holder); return retiring;};
  moon.clientProgramPreparationBorrowReturn = original => {
    assert.equal(original, holder); assert(retiring); assert(!returned);
    returned = true; events.push('return'); return ok(true);
  };
  return {...f, moon, request, prepared, identity, plan, value, receipt, events,
    failedCleanup: async () => {f.view.finishSourceProducer(receipt, 'failed'); await f.view.close();},
    retireAdopted: async () => {
      retiring = true; f.view.severPreparation(prepared, f.original);
      Reflect.apply(abort, moon, [f.parent]); f.view.retireSeveredPreparation(f.original);
      f.view.finishSourceProducer(receipt, 'returned'); await f.view.close();
    }};
}

test('captured Request completes one original Plan and adopts its same parent without an independent Run', async () => {
  const f = await originalCapturedRequest();
  await f.view.fundedPreparation(f.request, undefined);
  let constructors = 0;
  const construct = () => {
    constructors++;
    assert.throws(() => f.view.adoptCapturePreparation(f.prepared, f.request, f.identity, construct),
      {code: 'ForeignInstalledSourceProducer'});
    f.moon.clientProgramPrepareRequestCaptureModuleBody = f.moon.clientProgramAdoptRequestCapturePreparation =
      () => assert.fail('original Core methods and namespace receiver were captured before constructor entry');
    return f.plan;
  };
  assert.throws(() => f.view.adoptPreparation(f.prepared, f.request, f.identity), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => f.view.adoptCapturePreparation({...f.prepared}, f.request, f.identity, construct),
    {code: 'ForeignInstalledSourceProducer'});
  assert.equal(f.view.adoptCapturePreparation(f.prepared, {}, f.identity, construct), undefined);
  assert.equal(constructors, 0);
  const run = f.view.adoptCapturePreparation(f.prepared, f.request, f.identity, construct);
  assert.equal(run.original, f.original); assert.equal(run.value, f.value);
  assert.equal(constructors, 1); assert.deepEqual(f.events, ['check', 'borrow', 'module', 'adopt']);
  assert.equal(f.calls.filter(value => value === 'parent').length, 1);
  assert.throws(() => f.view.adoptCapturePreparation(f.prepared, f.request, f.identity, construct),
    {code: 'ForeignInstalledSourceProducer'});
  await f.retireAdopted();
  assert.equal(f.events.filter(value => value === 'return').length, 1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

test('captured Request keeps original failed completion or adoption without replaying its constructor', async () => {
  for (const phase of ['moduleFailure', 'adoptFailure']) {
    const failure = new Error(phase), f = await originalCapturedRequest({[phase]: failure});
    await f.view.fundedPreparation(f.request, undefined);
    let constructors = 0;
    const construct = () => {constructors++; return f.plan;};
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.throws(() => f.view.adoptCapturePreparation(f.prepared, f.request, f.identity, construct), error => error === failure);
    }
    assert.equal(constructors, 1); assert.equal(f.events.filter(value => value === 'module').length, 1);
    assert.equal(f.events.filter(value => value === 'adopt').length, phase === 'adoptFailure' ? 1 : 0);
    await f.failedCleanup();
    assert.equal(f.events.filter(value => value === 'return').length, 1);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  }
});


test('captured Request constructs its accounted module before original Run adoption on the same borrow', async () => {
  const f = await originalCapturedRequest(), seen = [];
  f.moon.clientProgramPrepareRequestCaptureModuleBody = function(parent, input, plan) {
    assert.equal(this, f.moon); assert.equal(parent, f.parent);
    assert.equal(input, f.receipt); assert.equal(plan, f.plan);
    seen.push('accounted-module'); return ok(undefined);
  };
  f.moon.clientProgramCompleteRequestCapturePreparation = () => assert.fail('bare Plan completion bypassed original accounted compilation');
  await f.view.fundedPreparation(f.request, undefined);
  let run;
  try {
    run = f.view.adoptCapturePreparation(f.prepared, f.request, f.identity, () => {
      seen.push('construct');
      f.moon.clientProgramPrepareRequestCaptureModuleBody = () => assert.fail('original module receiver/method was not captured');
      return f.plan;
    });
    assert.equal(run.value, f.value); assert.equal(run.original, f.original);
    assert.deepEqual(seen, ['construct', 'accounted-module']);
    assert.deepEqual(f.events, ['check', 'borrow', 'adopt']);
  } finally {
    if (run === undefined) await f.failedCleanup(); else await f.retireAdopted();
  }
  assert.equal(f.events.filter(value => value === 'return').length, 1);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});


test('captured Request refuses absent accounted module before invoking its Plan constructor', async () => {
  const f = await originalCapturedRequest();
  f.moon.clientProgramPrepareRequestCaptureModuleBody = undefined;
  f.moon.clientProgramCompleteRequestCapturePreparation = () => assert.fail('retired bare completion is not a fallback');
  await f.view.fundedPreparation(f.request, undefined);
  let constructors = 0;
  assert.throws(() => f.view.adoptCapturePreparation(f.prepared, f.request, f.identity,
    () => {constructors++; return f.plan;}), {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.equal(constructors, 0);
  await f.failedCleanup();
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

test('captured Request retains the original unclassified module issue and never retries construction', async () => {
  const f = await originalCapturedRequest(), issue = new Error('original module refusal');
  const outcome = {$tag: 0, _0: issue}; let constructors = 0, modules = 0, projections = 0;
  f.moon.clientProgramPrepareRequestCaptureModuleBody = function(parent, input, plan) {
    assert.equal(this, f.moon); assert.equal(parent, f.parent);
    assert.equal(input, f.receipt); assert.equal(plan, f.plan); modules++; return outcome;
  };
  f.moon.clientProgramRequestProgramModuleIssueCode = function(actual) {
    assert.equal(this, f.moon); assert.equal(actual, outcome); projections++; return undefined;
  };
  await f.view.fundedPreparation(f.request, undefined);
  let originalFailure;
  try {
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.throws(() => f.view.adoptCapturePreparation(f.prepared, f.request, f.identity,
        () => {constructors++; return f.plan;}), error => {
        assert.equal(error.code, 'MoonBitHostFailure'); assert.equal(error.cause, issue);
        if (originalFailure === undefined) originalFailure = error;
        return error === originalFailure;
      });
    }
    assert.deepEqual([constructors, modules, projections], [1, 1, 1]);
    assert.equal(f.events.includes('adopt'), false);
  } finally {await f.failedCleanup();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

// Execute the actual four installing facade methods. Managers, currentness
// and SDK lineage are explicit ports; no admission/Host/normal success is
// inferred from these plain opaque fixture values.
async function requestManagerFacadeFixture({source = true, compute = false} = {}) {
  const {parse} = await import('acorn');
  const {readFileSync} = await import('node:fs');
  const sourceText = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(sourceText, {ecmaVersion: 'latest', sourceType: 'module'});
  const wanted = ['requestPreparation', 'submittedIntentOriginal', 'fundedPreparation', 'borrowManagedPreparation'];
  let object;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'ObjectExpression' && wanted.every(name =>
      node.properties.some(property => property.type === 'Property' && property.key?.name === name))) object = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(ast); assert.ok(object);
  const methods = wanted.map(name => object.properties.find(property => property.key?.name === name));
  const sourceManager = {}, computeManager = {}, originals = {}, request = {}, originalRequest = {};
  const environment = {}, prepared = {}, intent = {}, borrow = {};
  const funded = Object.freeze({kind: 'effectful', prepared, originalInputs: Object.freeze({environment})});
  const calls = []; let currentFailure, preparationFailure, lineageFailure;
  for (const [kind, manager] of [['source', sourceManager], ['compute', computeManager]]) {
    Object.assign(manager, {
      submittedIntentOriginal(actual) {assert.equal(this, manager); assert.equal(actual, originalRequest); calls.push(kind + '-intent'); return intent;},
      fundedPreparation(actual, selected) {
        assert.equal(this, manager); assert.equal(actual, originalRequest); assert.equal(selected, environment);
        calls.push(kind + '-funded'); if (preparationFailure) throw preparationFailure; return funded;
      },
      borrowPreparation(value, actual) {assert.equal(this, manager); assert.equal(value, prepared); assert.equal(actual, originalRequest); calls.push(kind + '-borrow'); return borrow;},
    });
  }
  const validate = (kind, manager) => (actual, bag) => {
    assert.equal(actual, manager); assert.equal(bag, originals); calls.push(kind + '-current');
    if (currentFailure) throw currentFailure;
  };
  const view = new Function('sourceManaged', 'computeManaged', 'originals',
    'assertSourceManagedInstallationCurrent', 'assertManagedComputeInstallationCurrent',
    'originalSourceManagedHostRequest', 'clientOperationError',
    `return ({${methods.map(method => sourceText.slice(method.start, method.end)).join(',')}});`)(
    source ? sourceManager : undefined, compute ? computeManager : undefined, originals,
    validate('source', sourceManager), validate('compute', computeManager),
    (bag, actual) => {assert.equal(bag, originals); assert.equal(actual, request); calls.push('original-request'); if (lineageFailure) throw lineageFailure; return originalRequest;},
    code => Object.assign(new Error(code), {code}));
  return {view, sourceManager, computeManager, request, environment, prepared, funded, intent, borrow, calls,
    failCurrent(error) {currentFailure = error;}, failPreparation(error) {preparationFailure = error;},
    failLineage(error) {lineageFailure = error;}};
}

test('actual Request facade keeps the same selected Source manager through intent funded preparation and borrow', async () => {
  const f = await requestManagerFacadeFixture();
  assert.equal(f.view.requestPreparation(), f.sourceManager);
  assert.equal(f.view.submittedIntentOriginal(f.request), f.intent);
  assert.equal(await f.view.fundedPreparation(f.request, f.environment), f.funded);
  assert.equal(f.view.borrowManagedPreparation(f.prepared, f.request), f.borrow);
  assert.deepEqual(f.calls, ['source-current', 'source-current', 'original-request', 'source-intent',
    'source-current', 'original-request', 'source-funded', 'source-current', 'original-request', 'source-borrow']);
});

test('selected Source Request facade retains refusal and precedence without another manager fallback', async () => {
  const f = await requestManagerFacadeFixture({compute: true});
  assert.equal(f.view.requestPreparation(), f.sourceManager);
  assert.equal(await f.view.fundedPreparation(f.request, f.environment), f.funded);
  assert(!f.calls.some(call => call.startsWith('compute-')));
  const failure = new Error('same selected Source current refusal'); f.failCurrent(failure);
  for (const invoke of [() => f.view.submittedIntentOriginal(f.request),
    () => f.view.fundedPreparation(f.request, f.environment),
    () => f.view.borrowManagedPreparation(f.prepared, f.request)]) assert.throws(invoke, error => error === failure);
  assert(!f.calls.some(call => call.startsWith('compute-')));
  const failed = await requestManagerFacadeFixture({compute: true});
  const cause = new Error('same Source preparation refusal'); failed.failPreparation(cause);
  assert.throws(() => failed.view.fundedPreparation(failed.request, failed.environment), error => error === cause);
  assert(!failed.calls.some(call => call.startsWith('compute-')));
  const foreign = await requestManagerFacadeFixture({compute: true});
  const lineage = new Error('same original SDK lineage refusal'); foreign.failLineage(lineage);
  assert.throws(() => foreign.view.fundedPreparation(foreign.request, foreign.environment), error => error === lineage);
  assert(!foreign.calls.some(call => call.endsWith('-funded')));
});

test('Compute-only and absent Request facade keep their existing original selection behavior', async () => {
  const f = await requestManagerFacadeFixture({source: false, compute: true});
  assert.equal(f.view.requestPreparation(), f.computeManager);
  assert.equal(f.view.submittedIntentOriginal(f.request), f.intent);
  assert.equal(await f.view.fundedPreparation(f.request, f.environment), f.funded);
  assert.equal(f.view.borrowManagedPreparation(f.prepared, f.request), f.borrow);
  assert(!f.calls.some(call => call.startsWith('source-')));
  const absent = await requestManagerFacadeFixture({source: false});
  assert.throws(() => absent.view.requestPreparation(), {code: 'NodeManagedRunAdmissionUnavailable'});
  assert.equal(absent.view.submittedIntentOriginal(absent.request), undefined);
  assert.equal(absent.view.fundedPreparation(absent.request, absent.environment), undefined);
  assert.equal(absent.view.borrowManagedPreparation(absent.prepared, absent.request), undefined);
  assert.deepEqual(absent.calls, []);
});


// Actual Request/SDK snapshot manager and Resource original, with explicit
// typed Scope/compiler/adoption ports. No Model permission or normal backing
// is inferred from these ports or from their successful cleanup observations.
async function originalEffectModelRequest(options = {}) {
  const f = await originalEffectRequest(), scope = {};
  const outer = {manager: f.view, runtime: f.moon, preparationKind: 'effect-plan',
    prepared: f.prepared, request: f.identity, requestInput: f.sdkRequest,
    operationPlan: f.plan, original: undefined, modelScope: undefined, value: undefined, closed: false};
  let scopeFinished = false;
  const complete = f.moon.clientProgramCompleteRequestEffectPreparation;
  f.moon.clientProgramPrepareRequestEffectModelReadScope = function(parent, receipt, plan) {
    assert.equal(this, f.moon); assert.equal(parent, f.requestParent);
    assert.equal(receipt, f.receipt); assert.equal(plan, f.plan);
    assert.equal(outer.original, f.original); assert.equal(outer.modelScope, undefined);
    f.events.push('scope'); return ok(scope);
  };
  if (options.quantityCapacity !== undefined) {
    outer.modelSelection = Object.freeze({quantityCapacity: options.quantityCapacity});
    f.moon.clientProgramPrepareRequestEffectModelReadScopeWithQuantities = function(parent, receipt, plan, tokens, cost, duration) {
      assert.equal(this, f.moon); assert.equal(parent, f.requestParent);
      assert.equal(receipt, f.receipt); assert.equal(plan, f.plan);
      const limits = options.quantityCapacity.limits;
      assert.deepEqual([tokens, cost, duration], [limits.tokens, limits.costUnits, limits.durationMs]);
      assert.equal(outer.original, f.original); assert.equal(outer.modelScope, undefined);
      f.events.push('original quantities then scope'); return ok(scope);
    };
    f.moon.clientProgramPrepareRequestEffectModelReadScope = () => assert.fail('No unconfigured physical Model scope');
  }
  f.moon.clientProgramCompleteRequestEffectPreparation = function(...args) {
    assert.equal(this, f.moon); assert.equal(outer.modelScope, scope);
    if (options.phase === 'complete') {f.events.push('complete-failed'); throw options.failure;}
    return Reflect.apply(complete, f.moon, args);
  };
  f.moon.clientProgramAdoptRequestEffectModelPreparation = function(parent, identity, originalScope) {
    assert.equal(this, f.moon); assert.equal(parent, f.requestParent);
    assert.equal(identity, f.identity); assert.equal(originalScope, scope);
    assert.equal(outer.modelScope, scope); f.events.push('adopt-model');
    if (options.phase === 'adopt') throw options.failure;
    return ok(f.parent);
  };
  f.moon.clientProgramAdoptRequestEffectPreparation = () => assert.fail('no non-Model adoption');
  const abort = f.moon.clientProgramAbortRequestPreparation;
  f.moon.clientProgramAbortRequestPreparation = function(parent) {
    assert.equal(parent, f.requestParent);
    if (!scopeFinished && outer.modelScope !== undefined) return {$tag: 0, _0: new Error('OriginalScopePending')};
    return Reflect.apply(abort, f.moon, [parent]);
  };
  return {...f, scope, outer, finishScope() {scopeFinished = true;}};
}

test('Request Model Scope is retained before same Plan completion and captured original adoption', async () => {
  const f = await originalEffectModelRequest();
  await f.view.fundedPreparation(f.sdkRequest, undefined);
  f.moon.clientProgramPrepareRequestEffectModelReadScope =
    f.moon.clientProgramAdoptRequestEffectModelPreparation = () => assert.fail('use captured originals');
  const actual = f.view.adoptEffectModelPreparation(f.prepared, f.sdkRequest, f.identity, f.plan, f.outer);
  assert.equal(actual.original, f.original); assert.equal(actual.value, f.parent);
  assert.equal(actual.operationPlan, f.plan); assert.equal(f.outer.modelScope, f.scope);
  assert.equal(f.view.prepareEffectModelPlanRun, undefined);
  assert.deepEqual(f.events, ['check', 'compile', 'borrow', 'scope', 'complete', 'adopt-model']);
  assert.throws(() => f.view.adoptEffectModelPreparation(f.prepared, f.sdkRequest, f.identity, f.plan, f.outer),
    {code: 'ForeignInstalledSourceProducer'});
  // The real physical cleanup witness is an explicit port in this component.
  f.finishScope(); f.outer.modelScope = undefined;
  f.markRetiring(); f.view.severPreparation(f.prepared, f.original);
  f.finishPhysicalRetirement(); f.view.retireSeveredPreparation(f.original);
  f.view.finishSourceProducer(f.receipt, 'returned'); await f.view.close();
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

test('Request Model partial completion and adoption retain Scope and original thrown undefined until cleanup', async () => {
  for (const [phase, failure] of [['complete', new Error('ExactModelCompletionFailure')], ['adopt', undefined]]) {
    const f = await originalEffectModelRequest({phase, failure});
    await f.view.fundedPreparation(f.sdkRequest, undefined);
    for (let attempt = 0; attempt < 2; attempt++) {
      let thrown = false;
      try {f.view.adoptEffectModelPreparation(f.prepared, f.sdkRequest, f.identity, f.plan, f.outer);}
      catch (cause) {thrown = true; assert.equal(cause, failure);}
      assert.equal(thrown, true);
    }
    assert.equal(f.outer.modelScope, f.scope); assert.equal(f.outer.original, f.original);
    assert.equal(f.events.filter(value => value === 'scope').length, 1);
    await assert.rejects(f.failedCleanup());
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
    assert.equal(f.events.includes('return'), false);
    f.finishScope(); f.outer.modelScope = undefined;
    await f.failedCleanup();
    assert.equal(f.events.filter(value => value === 'return').length, 1);
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  }
});

test('Request Model refuses foreign input Run Plan and accessor carrier before Scope', async () => {
  const f = await originalEffectModelRequest(); await f.view.fundedPreparation(f.sdkRequest, undefined);
  for (const [request, plan, outer] of [
    [{}, f.plan, f.outer], [f.sdkRequest, {}, f.outer],
    [f.sdkRequest, f.plan, {...f.outer, manager: {}}],
    [f.sdkRequest, f.plan, {...f.outer, get request() {assert.fail('no accessor read');}}],
  ]) assert.throws(() => f.view.adoptEffectModelPreparation(f.prepared, request, f.identity, plan, outer),
    {code: 'ForeignInstalledSourceProducer'});
  assert.equal(f.events.includes('scope'), false);
  await f.failedCleanup();
});

// Actual manager/Request/Resource parent with explicit Core phase ports.
// The Option is deliberately opaque: JavaScript must only forward it.
async function originalTimedRequest({captured=false, compilationFailure, invocationFailure, moduleFailure, invocationBackingFailure}={}) {
  const f=await originalCapturedRequest(), artifact={}, option=new Proxy({}, {get(){assert.fail('opaque original Option inspected by JS');}});
  f.moon.clientProgramAcquisitionCount=actual=>{assert.equal(actual,f.prepared);return captured?1:0;};
  f.moon.clientProgramRequiresQueryTime=function(actual,nodes,work){assert.equal(this,f.moon);assert.equal(actual,f.prepared);assert.equal(nodes,100000);assert.equal(work,100000);f.events.push('requires-time');return ok(true);};
  f.moon.clientProgramPrepareRequestProgramCompilation=function(parent,input,contracts,retained){
    assert.equal(this,f.moon);assert.equal(parent,f.parent);assert.equal(input,f.receipt);
    assert.equal(contracts,f.originals.installation.sequenceContractOriginal.admission);assert.equal(retained,false);
    f.events.push('artifact');if(compilationFailure)throw compilationFailure;return ok(artifact);
  };
  f.moon.clientProgramReserveRequestQueryTimeInvocation=function(parent,input,original){
    assert.equal(this,f.moon);assert.equal(parent,f.parent);assert.equal(input,f.receipt);assert.equal(original,artifact);
    f.events.push('invocation-backing');if(invocationBackingFailure)throw invocationBackingFailure;return ok(undefined);
  };
  const module=function(...args){
    assert.equal(this,f.moon);assert.equal(args[0],f.parent);assert.equal(args[1],f.receipt);
    if(captured){assert.equal(args[2],f.plan);assert.equal(args[3],option);assert.equal(args.length,4);}
    else {assert.equal(args[2],f.originals.installation.sequenceContractOriginal.admission);assert.equal(args[3],false);assert.equal(args[4],option);assert.equal(args.length,5);}
    f.events.push('timed-module');if(moduleFailure)throw moduleFailure;return ok(undefined);
  };
  f.moon[captured?'clientProgramPrepareRequestCaptureModuleBody':'clientProgramPrepareRequestProgramModuleBody']=module;
  if(!captured)f.moon.clientProgramAdoptRequestProgramPreparation=function(parent,identity){assert.equal(this,f.moon);assert.equal(parent,f.parent);assert.equal(identity,f.identity);f.events.push('adopt');return ok(f.value);};
  const construct=actual=>{assert.equal(actual,artifact);f.events.push('bind-original');if(invocationFailure)throw invocationFailure;return option;};
  const adopt=callback=>captured?f.view.adoptCapturePreparation(f.prepared,f.request,f.identity,()=>{f.events.push('capture-plan');return f.plan;},callback):f.view.adoptPreparation(f.prepared,f.request,f.identity,callback);
  return {...f,artifact,option,captured,construct,adopt};
}

test('timed Request original defers module through one borrower and forwards opaque invocation before adoption',async()=>{
  for(const captured of [false,true]){
    const f=await originalTimedRequest({captured});let run;
    try{
      for(let n=0;n<2;n++)assert.equal((await f.view.fundedPreparation(f.request,undefined)).prepared,f.prepared);
      assert.deepEqual(f.events,['check','borrow','requires-time']);
      run=f.adopt(actual=>{
        assert.throws(()=>f.adopt(f.construct),{code:'ForeignInstalledSourceProducer'});
        f.moon[captured?'clientProgramPrepareRequestCaptureModuleBody':'clientProgramPrepareRequestProgramModuleBody']=()=>assert.fail('replaced module');
        if(captured)f.moon.clientProgramAdoptRequestCapturePreparation=()=>assert.fail('replaced adopt');
        return f.construct(actual);
      });
      assert.equal(run.value,f.value);assert.equal(run.original,f.original);
      assert.deepEqual(f.events,['check','borrow','requires-time','artifact','invocation-backing','bind-original',...(captured?['capture-plan']:[]),'timed-module','adopt']);
    }finally{if(run)await f.retireAdopted();else await f.failedCleanup();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});

test('timed Request original retains compiler invocation and module failures without repeating construction',async()=>{
  for(const captured of [false,true])for(const phase of ['compilationFailure','invocationFailure','moduleFailure']){
    const failure=Object.assign(new Error(phase),{cleanupPending:true,cleanupHandle:{original:phase}}),f=await originalTimedRequest({captured,[phase]:failure});
    try{
      await f.view.fundedPreparation(f.request,undefined);
      for(let n=0;n<2;n++)assert.throws(()=>f.adopt(f.construct),error=>error===failure);
      assert.equal(f.events.filter(x=>x==='artifact').length,1);
      assert.equal(f.events.filter(x=>x==='bind-original').length,phase==='compilationFailure'?0:1);
      assert.equal(f.events.filter(x=>x==='timed-module').length,phase==='moduleFailure'?1:0);
      assert(!f.events.includes('adopt'));
    }finally{await f.failedCleanup();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});

test('timed Request original refuses absent handoff or compiler before any module or adoption',async()=>{
  for(const captured of [false,true])for(const missing of ['callback','compiler']){
    const f=await originalTimedRequest({captured});
    try{
      await f.view.fundedPreparation(f.request,undefined);
      if(missing==='compiler')f.moon.clientProgramPrepareRequestProgramCompilation=undefined;
      assert.throws(()=>f.adopt(missing==='callback'?undefined:f.construct),{code:'NodeManagedRunRuntimeUnavailable'});
      assert(!f.events.includes('artifact'));assert(!f.events.includes('bind-original'));assert(!f.events.includes('timed-module'));assert(!f.events.includes('adopt'));
    }finally{await f.failedCleanup();}
  }
});

test('timed Request original refuses malformed time requirement before selecting any module',async()=>{
  const f=await originalTimedRequest();f.moon.clientProgramRequiresQueryTime=()=>ok('true');
  try{await assert.rejects(f.view.fundedPreparation(f.request,undefined),{code:'InvalidHostRuntimeResult'});assert.deepEqual(f.events,['check','borrow']);}
  finally{await f.failedCleanup();}
});


test('timed whole Source manager hands the same opaque invocation to Plan before Module and adoption',async()=>{
  const f=await originalTimedRequest({captured:true});let run;
  try{
    await f.view.fundedPreparation(f.request,undefined);
    run=f.view.adoptCapturePreparation(f.prepared,f.request,f.identity,invocation=>{
      assert.equal(invocation,f.option);f.events.push('exact-timed-plan');return f.plan;
    },f.construct);
    assert.equal(run.value,f.value);
    assert.deepEqual(f.events,['check','borrow','requires-time','artifact','invocation-backing','bind-original','exact-timed-plan','timed-module','adopt']);
  }finally{if(run)await f.retireAdopted();else await f.failedCleanup();}
});


test('timed Request backs invocation before constructor and retains original refusal without replay',async()=>{
  for(const captured of [false,true]){
    const marker=Object.freeze(Error('same original invocation backing refusal'));
    const f=await originalTimedRequest({captured,invocationBackingFailure:marker});
    await f.view.fundedPreparation(f.request,undefined);
    for(let n=0;n<2;n++)assert.throws(()=>f.adopt(f.construct),error=>error===marker);
    assert.deepEqual(f.events,['check','borrow','requires-time','artifact','invocation-backing']);
    await f.failedCleanup();assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  }
});

test('an unadopted original Request cannot borrow retained Run currentness after ingress closes', async () => {
  let accepting = true;
  const f = await fixture({validate() {assert.ok(accepting, 'NewPreparationRefused');},
    validateRetained() {assert.fail('No Run was adopted');}});
  const receipt = f.view.beforeSourceSnapshot('program', input(), {}, connection);
  accepting = false;
  assert.throws(() => resources.assertOrdinaryManagedRunCurrent(f.original, receipt),
    /NewPreparationRefused/);
  assert.throws(() => f.view.reservePublication({}), {code: 'ForeignInstalledSourceProducer'});
  f.view.finishSourceProducer(receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

test('Remote Request uses the existing managed parent and rejects mixed transport ownership', async () => {
  const remote = Object.freeze({mode: 'remote', owner: 'remote',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const f = await fixture();
  const receipt = f.view.beforeSourceSnapshot('aql', 'SELECT 1 AS n', {}, remote);
  const body = f.view.captureSourceSnapshot(receipt, {
    kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null,
  }, snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt, body);
  f.view.bindSourceRequest(receipt, body, {});
  assert.deepEqual(f.calls.slice(0, 4), ['control', 'policy-limits', 'admission', 'parent']);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, false);
  f.view.finishSourceProducer(receipt, 'failed');
  await f.view.close();
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  for (const selected of [{mode: 'remote', owner: 'local'}, {mode: 'local', owner: 'remote'},
    {mode: 'hybrid', owner: 'hybrid'}]) {
    const invalid = await fixture();
    assert.throws(() => invalid.view.beforeSourceSnapshot('aql', 'SELECT 1 AS n', {},
      Object.freeze({...selected, consentRefs: Object.freeze([]), runners: Object.freeze([])})),
    {code: 'NodeLocalPreparationAdmissionUnavailable'});
    assert.equal(invalid.calls.includes('admission'), false);
    await invalid.view.close();
  }
});

// Same actual manager/Resource parent; typed Check and report results remain
// explicit ports here. The compiled projection is exercised separately.
async function originalCheckFixture(project) {
  const environment = {}, f = await fixture({environment}), moon = f.context.runtime;
  const request = {}, originalResult = {$tag: 0, _0: {originalCheckIssue: true}};
  let checks = 0;
  if (project !== undefined) moon.clientProgramProjectRequestCheckOutcome = project;
  moon.clientProgramPrepareRequestNativeComputation = function(parent, receipt) {
    assert.strictEqual(this, moon); assert.strictEqual(parent, f.parent);
    assert.strictEqual(receipt, selected); checks++; return originalResult;
  };
  moon.clientProgramRequestPreparationIssueCode = function(result) {
    assert.strictEqual(this, moon); assert.strictEqual(result, originalResult); return 'check_invalid_input';
  };
  f.originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  const selected = f.view.beforeSourceSnapshot('program', input(), {parameters: null}, connection);
  const body = f.view.captureSourceSnapshot(selected, {kind: 'program', input: input(), parameters: null}, snapshotClientRequest);
  f.view.bindSourceSnapshot(selected, body); f.view.bindSourceRequest(selected, body, request);
  let failure;
  await assert.rejects(f.view.fundedPreparation(request, environment), error => {
    assert.equal(error.code, 'ClientProgramInvalidInput'); failure = error; return true;
  });
  return {...f, moon, request, receipt: selected, originalResult, failure, get checks() {return checks;}};
}

const originalReportMetadata = Object.freeze(['visible', 'context', 'program', 'revision', 17,
  undefined, 0, undefined, 0, 'correlation', undefined, undefined]);

test('original Request Check projection retains exact result receiver and receipt without another preparation', async () => {
  let f, calls = 0;
  const project = function(parent, receipt, result, ...metadata) {
    assert.strictEqual(this, f.moon); assert.strictEqual(parent, f.parent);
    assert.strictEqual(receipt, f.receipt); assert.strictEqual(result, f.originalResult);
    assert.deepEqual(metadata, originalReportMetadata); calls++; return ok('original public wire');
  };
  f = await originalCheckFixture(project);
  try {
    f.moon.clientProgramProjectRequestCheckOutcome = () => assert.fail('Use the captured original method');
    assert.equal(f.view.observeOriginalCheckOutcome(f.request, new Error('same-looking refusal'), () => assert.fail('No metadata visitor for a foreign failure')), undefined);
    assert.equal(f.view.observeOriginalCheckOutcome(f.request, f.failure, project => project(originalReportMetadata)), 'original public wire');
    await assert.rejects(f.view.fundedPreparation(f.request, f.context.environment), error => error === f.failure);
    assert.equal(f.checks, 1); assert.equal(calls, 1);
    f.view.finishSourceProducer(f.receipt, 'failed');
    assert.equal(f.view.observeOriginalCheckOutcome(f.request, f.failure, project => project(originalReportMetadata)), undefined);
    assert.equal(calls, 1);
  } finally {await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});

test('original Request Check projection omits absent or unavailable typed observation without decoding Option', async () => {
  for (const project of [undefined, () => ok(undefined)]) {
    const f = await originalCheckFixture(project);
    try {
      assert.equal(f.view.observeOriginalCheckOutcome(f.request, f.failure, project => project(originalReportMetadata)), undefined);
      assert.equal(f.checks, 1);
    } finally {f.view.finishSourceProducer(f.receipt, 'failed'); await f.view.close();}
    assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
  }
});

test('original Request Check projection fences retirement reentry before returning its wire', async () => {
  let f;
  f = await originalCheckFixture(() => {
    f.view.finishSourceProducer(f.receipt, 'failed'); return ok('must not escape after retirement');
  });
  try {
    assert.throws(() => f.view.observeOriginalCheckOutcome(f.request, f.failure, project => project(originalReportMetadata)),
      {code: 'ForeignInstalledSourceProducer'});
    assert.equal(f.checks, 1);
  } finally {await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});


test('original Request availability omits a policy failure before all metadata work', async () => {
  const f = await policyRequestFixture('program', () => assert.fail('No original failed Check to project')),
    failure = new Error('original policy failure after successful Check');
  let metadataCalls = 0;
  try {
    await assert.rejects(f.view.fundedPreparation(f.request, f.environment, async () => {throw failure;}),
      error => error === failure);
    // Execute the actual installed callback, with only its connection and
    // metadata entrances supplied as explicit ports. This catches ordering
    // before the manager, rather than testing an invented outer protocol.
    const {readFileSync} = await import('node:fs');
    const {parse} = await import('acorn');
    const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
    const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
    let selected;
    const walk = node => {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'Property' && node.key.name === 'observeOriginalPreparationFailure') selected = node.value;
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(walk);
        else if (value && typeof value === 'object' && value.type) walk(value);
      }
    };
    walk(ast); assert.ok(selected);
    let connections = 0;
    const observer = Function('preparation', 'checkSource', 'hostConnection', 'clientOperationError',
      'return (' + source.slice(selected.start, selected.end) + ');')({
      observeOriginalCheckOutcome: (request, cause, visit) => f.view.observeOriginalCheckOutcome(request, cause, visit),
    }, {projectOriginal() {metadataCalls++;}}, () => {connections++; return true;}, code => new Error(code));
    assert.equal(await observer(failure, f.request), undefined);
    assert.equal(metadataCalls, 0, 'No Source/account/namespace metadata for an unavailable original Check');
    assert.equal(connections, 2, 'Keep both existing connection-current fences');
    assert.deepEqual(f.events, ['check', 'subjects', 'read-0']);
  } finally {await f.finish();}
});

test('original Request availability keeps the same state across metadata await and refuses retirement', async () => {
  const f = await originalCheckFixture(() => ok('must not escape a retired Request'));
  let entered, release;
  const visiting = new Promise(resolve => {entered = resolve;});
  const held = new Promise(resolve => {release = resolve;});
  const pending = f.view.observeOriginalCheckOutcome(f.request, f.failure, async project => {
    entered(); await held; return project(originalReportMetadata);
  });
  try {
    await visiting; f.view.finishSourceProducer(f.receipt, 'failed'); release();
    await assert.rejects(pending, {code: 'ForeignInstalledSourceProducer'});
  } finally {release(); await pending.catch(() => {}); await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped, true);
});


test('physical Effect Model configures its SAME selected quantity limits before original Scope completion and adoption', async () => {
  const quantityCapacity = Object.freeze({limits: Object.freeze({tokens: 33n, costUnits: 0n, durationMs: 500n}),
    perAttempt: Object.freeze({tokens: 33n, costUnits: 0n, durationMs: 500n})});
  const f = await originalEffectModelRequest({quantityCapacity});
  await f.view.fundedPreparation(f.sdkRequest, undefined);
  f.moon.clientProgramPrepareRequestEffectModelReadScopeWithQuantities = () => assert.fail('Use captured same-original constructor');
  const actual = f.view.adoptEffectModelPreparation(f.prepared, f.sdkRequest, f.identity, f.plan, f.outer);
  assert.equal(f.outer.modelSelection.quantityCapacity, quantityCapacity);
  assert.equal(actual.original, f.original); assert.equal(actual.value, f.parent);
  assert.deepEqual(f.events, ['check', 'compile', 'borrow', 'original quantities then scope', 'complete', 'adopt-model']);
  f.finishScope(); f.outer.modelScope = undefined;
  f.markRetiring(); f.view.severPreparation(f.prepared, f.original);
  f.finishPhysicalRetirement(); f.view.retireSeveredPreparation(f.original);
  f.view.finishSourceProducer(f.receipt, 'returned'); await f.view.close();
});

// Actual manager/Request registration with explicit Core material/selection
// ports. This admits no Source read, Model dispatch or normal backing claim.
async function restoredModelRecoveryFixture(options) {
  const f = await fixture(options), moon = f.context.runtime;
  const request = {}, identity = {}, definition = {wire: '{}'}, prepared = {},
    compiled = {}, graph = {}, selected = {}, events = [];
  const original = Object.freeze({materialsWire: '{"original":"saved-model"}',
    resultPolicyOriginal: Object.freeze({kind: 'data_policy', cid: 'fixture', wire: '{}'})});
  const restored = Object.freeze({prepared, compiled, graph, runDefinition: definition});
  moon.clientProgramReserveRequestModelRecoveryMaterials = function(parent, receipt, actualRequest, actualDefinition, count, wireAt, containers) {
    assert.equal(this, moon); assert.equal(parent, f.parent); assert.equal(receipt, recovery.receipt);
    assert.equal(actualRequest, identity); assert.equal(actualDefinition, definition);
    events.push(['before constructor', count, Array.from({length: count}, (_, index) => wireAt(index)), containers]);
    return ok(undefined);
  };
  moon.clientProgramSelectInstalledSourceInput = function(actual, pair, stage, sourceIndex) {
    assert.equal(this, moon); assert.equal(actual, prepared); assert.equal(pair, identity);
    assert.equal(stage, 3); assert.equal(sourceIndex, 1); events.push('same Source occurrence');
    return ok(selected);
  };
  const recovery = f.view.retainModelRecovery(request, identity, definition,
    () => events.push('original recovery current'), () => false);
  assert.equal(f.view.restoreModelOriginal(request, original, definition, identity, () => restored), restored);
  return {...f, moon, recovery, request, identity, definition, prepared, compiled, graph, selected, original, restored, events};
}

test('cold Model Source selection consumes the same restored Request without an ordinary preparation holder', async () => {
  const f = await restoredModelRecoveryFixture();
  assert.equal(f.view.selectDomainSourceInput(f.prepared, f.request, f.identity, 3, 1), f.selected);
  assert.equal(f.events.filter(value => value === 'same Source occurrence').length, 1);
  assert.equal(f.events.filter(Array.isArray).length, 2, 'saved material then Source construction each funded before its callback');
  const quote = f.events.filter(Array.isArray).at(-1);
  assert.deepEqual(quote[2], [f.original.materialsWire]);
  f.view.finishSourceProducer(f.recovery.receipt, 'returned');
  await f.view.close();
});

async function recoveryReadFixture({readFailure, failRead = false, afterScopes, validate} = {}) {
  const f = await restoredModelRecoveryFixture({validate}), scope = {}, read = {}, bounds = {}, savedScope = {}, events = [];
  const budget = Object.freeze({modelRetainedBytes: 11n, modelExecutionBytes: 13n,
    readRetainedBytes: 7n, readExecutionBytes: 5n, maxReservations: 20, maxHoldings: 20, maxDelegations: 20});
  const selection = Object.freeze({graph: f.graph, restoredRun: f.restored});
  const control = {
    prepareCheckedClientRequestModelRecoveryReadScopes(...args) {
      assert.deepEqual(args, [f.parent, f.recovery.receipt, f.identity, f.definition, f.prepared, f.compiled,
        [f.graph], [bounds], [11n], [13n], [7n], [5n], 20, 20, 20, undefined]);
      events.push('same parent Scope'); return [scope];
    },
    prepareCheckedClientInferOriginalRead(compiled, definition, graph, actualScope, actualBudget) {
      assert.equal(compiled, f.compiled); assert.equal(definition, f.definition); assert.equal(graph, f.graph);
      assert.equal(actualScope, scope); assert.equal(actualBudget, budget); events.push('same Scope Read');
      if (failRead) throw readFailure;
      return read;
    },
    startCheckedClientOriginalRestoredComposedInferExecution() {},
    stopCheckedClientInferOriginalReadPreparation(c, d, g, s, r) {
      assert.equal(r, read); assert.equal(s, scope); events.push('stop original Read');
    },
    settleCheckedClientInferOriginalReadPreparation(c, d, g, r, complete) {
      assert.equal(r, read); assert.equal(complete, true); events.push('settle original Read');
    },
    finishCheckedClientInferOriginalReadScope(c, d, g, s, complete) {
      assert.equal(s, scope); assert.equal(complete, true); events.push('finish original Scope'); return true;
    },
  };
  const model = {prepared: f.prepared, selection, graph: f.graph, compiled: f.compiled,
    runDefinition: f.definition, selectedBounds: bounds, budget, control,
    publicationCapacity: () => 'original publication capacity'};
  if (afterScopes) Object.defineProperty(model, 'scopes', {configurable: true,
    set(value) {Object.defineProperty(model, 'scopes', {value, writable: true, configurable: true}); afterScopes(f, model, value);}});
  return {...f, model, selection, control, scope, read, savedScope, readEvents: events,
    prepare() {return f.view.prepareModelRecoveryPlan(f.prepared, f.request,
      {compiled: f.compiled, runDefinition: f.definition}, selection, model);}};
}

test('cold Model recovery view retains original Scope before current and restores one original Read', async () => {
  const f = await recoveryReadFixture();
  const original = f.prepare(); assert.equal(f.model.scope, f.scope); assert.equal(f.model.scopes[0], f.scope);
  assert.equal(f.prepare(), original, 'Same original preparation is not issued twice');
  original.retain(); assert.throws(() => original.restoreRead({}), {code: 'InstalledModelRecoveryRuntimeUnavailable'});
  const result = original.restoreRead({savedScope: f.savedScope});
  assert.equal(result.read, f.read); assert.equal(result.scope, f.scope);
  assert.equal(result.publicationCapacity(), 'original publication capacity');
  assert.throws(() => original.prepareRead(), {code: 'ForeignInstalledModelRecoveryScope'});
  assert.equal(await original.retire(), true); assert.equal(await original.retire(), true);
  assert.deepEqual(f.readEvents, ['same parent Scope', 'same Scope Read', 'stop original Read', 'settle original Read', 'finish original Scope']);
  f.view.finishSourceProducer(f.recovery.receipt, 'returned'); await f.view.close();
});

test('cold Model recovery keeps thrown undefined sticky and cannot replace its original Scope', async () => {
  const f = await recoveryReadFixture({failRead: true, readFailure: undefined});
  const original = f.prepare(); original.retain();
  for (let index = 0; index < 2; index++) {
    let caught = false;
    try {original.restoreRead({savedScope: f.savedScope});} catch (cause) {caught = true; assert.equal(cause, undefined);}
    assert.equal(caught, true);
  }
  assert.equal(f.readEvents.filter(event => event === 'same Scope Read').length, 1);
  assert.equal(await original.retire(), true);
  f.view.finishSourceProducer(f.recovery.receipt, 'failed'); await f.view.close();
});

test('cold Model recovery retains returned Scope through current reentry failure', async () => {
  const failure = new Error('original current failed'); let failing = false;
  const f = await recoveryReadFixture({validate() {if (failing) throw failure;}, afterScopes(f, model, scopes) {
    assert.equal(scopes.length, 1); failing = true;
  }});
  assert.throws(() => f.prepare(), cause => cause === failure);
  assert.equal(f.model.scopes[0], f.scope); assert.equal(f.model.scope, f.scope);
  // Explicit original native child cleanup: the failed constructor retained it.
  f.control.finishCheckedClientInferOriginalReadScope(f.compiled, f.definition, f.graph, f.scope, true);
  failing = false;
  f.view.finishSourceProducer(f.recovery.receipt, 'failed'); await f.view.close();
});


test('cold Model recovery opens captured Local host and observes cleanup on the same original ledger', async () => {
  const f = await recoveryReadFixture(), ledger = {}, capture = {}, provider = {}, dag = {}, setup = {}, admission = {};
  const contracts = Object.freeze({values: 'values', expression: 'fragment', ordered: 'ordered'});
  f.originals.installation = {sequenceContractOriginal: {moon: f.moon, admission, contracts}};
  f.moon.clientProgramAcquisitionCount = actual => {assert.equal(actual, f.prepared); return 1;};
  let coordinates = 0;
  f.control.checkedClientRequestModelRecoverySourceCoordinates = function(...args) {
    assert.equal(this, f.control); assert.deepEqual(args, [f.parent,f.recovery.receipt,f.identity,f.definition,f.prepared]);
    coordinates++; return [[3,1,0]];
  };
  f.control.checkedClientRequestModelRecoveryLedger = function(...args) {
    assert.equal(this, f.control); assert.deepEqual(args,[f.parent,f.recovery.receipt,f.identity,f.definition]);return ledger;
  };
  f.control.openCheckedClientRequestModelRecoveryHost = function(...args) {
    assert.equal(this, f.control); assert.deepEqual(args,[f.parent,f.recovery.receipt,f.identity,f.definition,f.prepared,
      [capture],admission,'values','fragment','ordered',[provider]]); return setup;
  };
  f.control.checkedClientRequestModelRecoveryUsageIsolated = function(...args) {
    assert.equal(this, f.control); assert.deepEqual(args,[f.parent,f.recovery.receipt,f.identity,f.definition,dag]);return true;
  };
  const original = f.prepare(); original.retain();
  assert.deepEqual(original.sourceCoordinates, [[3,1,0]]); assert.equal(Object.isFrozen(original.sourceCoordinates),true);
  assert.equal(coordinates,1);assert.equal(original.sourceLedger(),ledger);
  assert.equal(original.openCapturedHost([{capture: {source: () => capture}}],[provider]),setup);
  assert.throws(() => original.openCapturedHost([{capture: {source: () => capture}}],[provider]),{code:'ForeignInstalledModelRecoveryScope'});
  assert.equal(await original.retire(),true);assert.equal(original.setupUsageIsolated(dag),true);
  f.view.finishSourceProducer(f.recovery.receipt,'returned');await f.view.close();
});
