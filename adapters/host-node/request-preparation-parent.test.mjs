import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import resources from './ordinary-node-resource-runtime.cjs';
import {openRequestPreparation, cleanupClosedValuesInput} from '../local-node/closed-values-preparation-adapter.mjs';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';

// Actual normal manager/adapter/Resource originals; Core phase/shape results
// are explicit ports. This does not certify a matching Common or body tariff.
const ok = value => ({$tag:1, _0:value});
const input = () => ({version:'actql/0.1',id:'parent',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{
  schema:{n:{type:'number',nullable:false}},rows:[{n:1}],
}}],results:{rows:{from:'v',fields:['n']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});
const connection = Object.freeze({mode:'local',owner:'local',consentRefs:Object.freeze([]),runners:Object.freeze([])});
async function fixture({selectFailure, control=[1024n,0n], policyLimits=[10000n,10000n,10000n,100000n,100000n,100000n]}={}) {
  const calls=[],shapes=[],policy={},parent={},phase={},work={};let admission;
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
      assert.equal(admission.ports.status(0),0);calls.push('parent');return ok(parent);
    },
    clientProgramReserveRequestSnapshot(actual,receipt,units,values){
      assert.equal(this,moon);assert.equal(actual,parent);assert.equal(receipt,admission.receipt);
      assert.equal(typeof units,'bigint');assert.equal(typeof values,'bigint');
      assert.ok(units>=values && values>0n);shapes.push({units,values});calls.push('snapshot-grow');return ok(undefined);
    },
    clientProgramSelectClosedValuesPreparation(actual,receipt){
      assert.equal(this,moon);assert.equal(actual,parent);assert.equal(receipt,admission.receipt);calls.push('select');
      if(selectFailure!==undefined) throw selectFailure;return ok(phase);
    },
    clientProgramBeginClosedValuesHeader(actual){assert.equal(actual,phase);calls.push('header');return ok(work);},
    clientProgramSpendPreparationPhaseWork(actual){assert.equal(actual,work);return ok(undefined);},
    clientProgramBeginClosedValuesScan(actual){assert.equal(actual,phase);return ok(work);},
    clientProgramFinishClosedValuesScan(){return ok(undefined);},
    clientProgramBeginClosedValuesTextCheck(){return ok(work);},
    clientProgramFinishClosedValuesTextCheck(){return ok(undefined);},
    clientProgramReserveClosedValuesSnapshot(actual){assert.equal(actual,phase);calls.push('snapshot-reserve');return ok(undefined);},
    clientProgramBindClosedValuesDocument(actual,document){assert.equal(actual,phase);calls.push('snapshot-bind');assert.equal(JSON.parse(document).id,'parent');return ok(undefined);},
    clientProgramAbortRequestPreparation(actual){assert.equal(this,moon);assert.equal(actual,parent);calls.push('abort-parent');return stop();},
    clientProgramAbortClosedValuesPreparationAfterCleanup(actual){assert.equal(this,moon);assert.equal(actual,phase);calls.push('abort-body');return stop();},
    clientProgramPrepareClosedValuesModuleBody(){assert.fail('No body compilation selected');},
    clientProgramCompleteClosedValuesBody(){},clientProgramAdoptClosedValuesPreparation(){},
  };
  const context=Object.freeze({runtime:moon,preparedEnvironment:{},retainedRelationOutput:false});
  const originals={};const view=await prepareOrdinarySourceManagedInstallation(originals,{
    validator(actual){assert.equal(actual,originals);},
    preparationContext(actual){assert.equal(actual,originals);return context;},
    retireInitialPreparation(actual,prepared){assert.equal(actual,originals);assert.ok(prepared);calls.push('retire-registry-original');},
  },false);
  return {view,calls,shapes,context,originals,get parent(){return parent;},get original(){return admission?.original;}};
}

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

test('normal request manager retains one parent before header and original snapshot reservation',async()=>{
  const f=await fixture();const program=input();
  const receipt=f.view.beforeSourceSnapshot('program',program,undefined,connection);
  assert.deepEqual(f.calls.slice(0,6),['control','policy-limits','admission','parent','select','header']);
  assert.equal(f.calls.filter(x=>x==='parent').length,1);assert.equal(f.calls.filter(x=>x==='snapshot-reserve').length,1);
  const body={kind:'program',input:JSON.parse(JSON.stringify(program)),parameters:null};
  f.view.bindSourceSnapshot(receipt,body);f.view.finishSourceProducer(receipt,'failed');
  assert.equal(f.calls.filter(x=>x==='abort-body').length,1);assert.equal(f.calls.includes('abort-parent'),false);
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(await f.view.close(),{pending:false});
});

test('normal selection throw preserves primary and cleans the exact unselected parent once',async()=>{
  const failure=new Error('OriginalSelectionFailure');const f=await fixture({selectFailure:failure});
  assert.throws(()=>f.view.beforeSourceSnapshot('program',input(),undefined,connection),cause=>cause===failure);
  assert.deepEqual(f.calls,['control','policy-limits','admission','parent','select','abort-parent']);
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
    assert.throws(() => cleanupClosedValuesInput(state),
      {code: 'NodeLocalPreparationAdmissionUnavailable'});
  };
  assert.equal(openRequestPreparation(state, original, current, () => false), f.parent);
  assert.ok(currents > 0);assert.equal(state.opening, false);
  assert.equal(f.calls.filter(value => value === 'parent').length, 1);
  assert.throws(() => openRequestPreparation(state, original, current, () => false),
    {code: 'NodeLocalPreparationAdmissionUnavailable'});
  cleanupClosedValuesInput(state);
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
  cleanupClosedValuesInput(state);
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
    cleanupClosedValuesInput(state);
    assert.deepEqual(await f.view.close(), {pending: false});
  }
});

// The actual connectEmbeddedLocal preparation method, with explicit Common
// constructor ports and the real ordinary Resource supplier. No runtime build,
// Source material/IO or full Host/physical acceptance is supplied by this test.
async function initialHostFixture({beginFailure = false} = {}) {
  const {parse} = await import('acorn');
  const {readFileSync} = await import('node:fs');
  const {openHostInitializationPreparation, closeHostInitializationPreparation} =
    await import('../local-node/closed-values-preparation-adapter.mjs');
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let method;
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'hostInitializationPreparation') method = node.value;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(ast); assert.ok(method);
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
    `let hostInitialization, sourceManaged, control={}, originals={};return (${code});`)(
      record,moon,installation,openHostInitializationPreparation,()=>{},()=>{},
      code=>Object.assign(new Error(code),{code}));
  return {invoke,moon,parent,record,calls,close:()=>closeHostInitializationPreparation(record.hostInitialization),
    get original() {return admission.original;},source,ast};
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
  const start = f.source.indexOf('const initialPreparation = preparation?.hostInitializationPreparation(moon);');
  const service = f.source.indexOf('const installationServices = createInstalledHostServices(', start);
  const load = f.source.indexOf('await loadInstalledSources(', service);
  assert.ok(start >= 0 && service > start && load > service);
  const servicesEnd = f.source.indexOf(';',service);
  assert.match(f.source.slice(service,servicesEnd),/assertCurrent: assertProjectRuntime, initialPreparation/);
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
    calls.push('compile-original');return ok('effect_free');
  };
  moon.clientProgramPrepareRequestProgramModuleBody=function(parent,original,contracts,retained){
    assert.equal(this,moon);assert.equal(parent,f.parent);assert.equal(original,receipt);
    assert.equal(contracts,selectedContract);assert.equal(retained,false);calls.push('module-original');return ok(undefined);
  };
  moon.clientProgramBorrowRequestProgramPreparation=function(parent){
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
    assert.deepEqual(calls,['compile-original','module-original','borrow-original']);
    assert.equal(f.calls.filter(x=>x==='parent').length,1);assert.equal(f.calls.includes('select'),false);
  }finally{
    f.view.finishSourceProducer(receipt,'failed');await f.view.close();
  }
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
  assert.deepEqual(calls,['compile-original','module-original','borrow-original','return-original']);
});

test('normal generic Native Request preserves its first compiler refusal without a second preparation', async () => {
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
  const failure=new Error('OriginalModuleConstructorFailed');let compiles=0,modules=0,reentry;
  moon.clientProgramPrepareRequestNativeComputation=()=>{compiles++;return ok('effect_free');};
  moon.clientProgramPrepareRequestProgramModuleBody=function(){
    modules++;
    reentry=f.view.fundedPreparation(request,undefined);
    // Handler cleanup cannot retire the same constructor while it is live.
    assert.throws(()=>cleanupClosedValuesInput({context:f.context,preparing:true}),
      {code:'NodeLocalPreparationAdmissionUnavailable'});
    throw failure;
  };
  try{
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    await assert.rejects(reentry,{code:'ForeignInstalledSourceProducer'});
    await assert.rejects(f.view.fundedPreparation(request,undefined),error=>error===failure);
    assert.equal(compiles,1);assert.equal(modules,1);
  }finally{f.view.finishSourceProducer(receipt,'failed');await f.view.close();}
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,true);
});

test('normal generic Native Request adopts the same Run and retains its current after handler completion', async () => {
  const f=await fixture(),moon=f.context.runtime,request={},prepared={},holder={},identity={},value={};
  const receipt=f.view.beforeSourceSnapshot('program',input(),{},connection);
  const body=f.view.captureSourceSnapshot(receipt,{kind:'program',input:input(),parameters:null},snapshotClientRequest);
  f.view.bindSourceSnapshot(receipt,body);f.view.bindSourceRequest(receipt,body,request);
  f.originals.installation={sequenceContractOriginal:{moon,admission:{}}};
  let retiring=false,returns=0,adopts=0;
  moon.clientProgramPrepareRequestNativeComputation=()=>ok('effect_free');
  moon.clientProgramPrepareRequestProgramModuleBody=()=>ok(undefined);
  moon.clientProgramBorrowRequestProgramPreparation=()=>ok(holder);
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
  f.view.finishSourceProducer(receipt,'returned');
  // Actual ordinary Resource calls its originally retained current callback.
  // Finishing the SDK producer must not invalidate this same live Run.
  assert.equal(f.view.publicationPreparation(prepared),value);
  assert.throws(()=>f.view.severPreparation(prepared,f.original),{code:'ForeignInstalledSourceProducer'});
  assert.equal(returns,0);
  retiring=true;
  f.view.severPreparation(prepared,f.original);assert.equal(returns,1);
  f.view.severPreparation(prepared,f.original);assert.equal(returns,1);
  // The explicit Common fixture supplies no physical operation. Its original
  // Resource port still owns stop; the token return above was not that ACK.
  assert.equal(resources.ordinaryManagedRunStatus(f.original).stopped,false);
  f.context.runtime.clientProgramAbortRequestPreparation(f.parent);
  f.view.retireSeveredPreparation(f.original);
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
  assert.throws(()=>cleanupClosedValuesInput(state),{code:'NodeLocalPreparationAdmissionUnavailable'});
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


test('normal generic Native Request projects its retained typed refusal once without a second compiler', async () => {
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
