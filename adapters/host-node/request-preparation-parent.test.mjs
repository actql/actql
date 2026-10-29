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
  },false);
  return {view,calls,shapes,context,get parent(){return parent;},get original(){return admission?.original;}};
}

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
