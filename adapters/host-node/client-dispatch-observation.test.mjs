import {publicationOriginalFixture} from './fixtures/local-publication-original.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';
import {fileURLToPath} from 'node:url';

const commonRuntimePath=process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME ??
  fileURLToPath(new URL(
    '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    import.meta.url));

// Execute the original declarations with explicit ports. No runtime, Model
// permission, Store commit or physical capacity is issued by these fixtures.
const source = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = ast.body.flatMap(node => {
  const value = node.type === 'ExportNamedDeclaration' ? node.declaration : node;
  // Retirement's diagnostic-only field inventory is an actual module-level
  // dependency. Keep its original declaration, not a fixture-maintained copy.
  const retirementInventory = value?.type === 'VariableDeclaration' &&
    value.declarations.some(entry => entry.id.type === 'Identifier' && entry.id.name === 'dispatchFailureFields');
  return value?.type === 'FunctionDeclaration' || retirementInventory
    ? [source.slice(value.start, value.end)] : [];
});
const installNodeClientDispatchOwner = compileFunction(
  declarations.join('\n') + '\nreturn installNodeClientDispatchOwner;',
  ['diagnosticObserver', 'CapturedRunPublicationError', 'runtimeTag', 'runPublishedCapturedStrategy'])(
  diagnosticObserver, class ExplicitPublicationError extends Error {}, () => undefined,
  () => assert.fail('No fixture Relation execution'));
const observation = retained => ({emit() {}, retainOperation(promise) {retained.push(promise);}});

// This distinct component uses the selected original Common namespace and real
// fresh Journal/Store. Account/current entry is an explicit component port;
// it makes no public submission or statement about a prior stopped Run.
async function actualScalarFailureStop(t,managed,interleaveObservation=false){
  const {pathToFileURL}=await import('node:url');
  const moon=await import(pathToFileURL(commonRuntimePath));
  const {mkdtemp,readFile,mkdir}=await import('node:fs/promises');
  const {tmpdir}=await import('node:os');
  const {join}=await import('node:path');
  const {inspect}=await import('node:util');
  const {runtimeCore}=await import('../host-common/runtime-core.mjs');
  const {openFundedClientPreparation}=await import('./funded-client-preparation.fixture.mjs');
  const {installLocalPreparationRegistry}=await import('./local-preparation-registry.mjs');
  const {sourceFreeValuesPlan,sourceFreeValuesAdmissionEvidence}=await import('./local-values-plan.mjs');
  const {createNodeHostEntry,CapturedRunExecutionError}=await import('./entry.mjs');
  const {installStrategyContributions}=await import('../connectors-builtin/strategy.generated.mjs');
  const {installNodeClientDispatchOwner:installActualDispatch}=await import('./client-dispatch-owner.mjs');
  const {openClientRequestJournal}=await import('./client-request-journal.mjs');
  const {openLocalPublicationStore}=await import('../store-local/publication-store.mjs');
  const {installLocalSnapshotStore}=await import('../local-node/retained-store.mjs');
  const {createLocalRetainedStore}=await import('../store-local/files.mjs');
  const {checked}=await import('../host-common/runtime-result.mjs');
  const {issueInstalledUnpublishedRunState}=await import('../host-common/run-state-observation.mjs');
  const directory=await mkdtemp(join(tmpdir(),'actql-failed-compute-component-'));
  t.diagnostic(`Fresh failure component retained at ${directory}`);
  const environmentWire=(await readFile(new URL('../../spec/local-check-environment.json',import.meta.url),'utf8')).trimEnd();
  const environment=moon.clientProgramCheckEnvironment(environmentWire,JSON.parse(environmentWire).evidence_bundle_cid,
    false,false,true,false,false,false,false);
  assert(environment);
  let funded,preparedProgram,journal,store,failure,execution,dispatch,managedRun;
  t.after(async()=>{
    // The Request parent closes only after the actual consumers retire. A
    // pending physical/managed close stops this chain and retains that parent.
    if(dispatch)try{await dispatch.drain();}
    catch(cause){
      t.diagnostic(JSON.stringify({originalCleanupFailures:cause.failures?.map(value=>({
        primary:value.primary,close:value.close,cleanup:value.cleanup,
        finish:value.finish,release:value.release,preparation:value.preparation}))}));
      throw cause;
    }
    await store?.close();journal?.close();
    await funded?.close();
  });
  funded=await openFundedClientPreparation({moon,environment});
  const preparationRequest={kind:'aql',
    input:{text:'SELECT TRY_TIMESTAMP(CAST(1 / 0 AS STRING)) AS value',format:'sql'},parameters:null};
  preparedProgram=await funded.prepare(preparationRequest);
  const control=runtimeCore(moon).publicationControl;
  const authorityScopeCid='sha256:'+'a'.repeat(64),storeAuthorityCid='sha256:'+'7'.repeat(64),namespaceId='failed-compute-component';
  const now=()=> '2026-10-23T00:00:00.000Z';
  const request=moon.clientProgramRequestIdentity(preparedProgram,authorityScopeCid,
    'original-failed-compute',moon.clientProgramSourceFreeInputIntentCid());
  assert(request);
  const plan=sourceFreeValuesPlan({moon,control,preparedProgram,publicationOriginal:publicationOriginalFixture(moon,preparedProgram),authorityScopeCid,namespaceId,storeAuthorityCid,now});
  journal=openClientRequestJournal(join(directory,'requests'));
  const accepted=journal.acceptDefinition(request,{namespaceId,runDefinition:plan.runDefinition,
    runAdmissionEvidence:sourceFreeValuesAdmissionEvidence(plan),resultNames:['main'],
    lookupExpiresAt:'2099-01-01T00:00:00.000Z'},moon,control);
  store=await openLocalPublicationStore({directory:join(directory,'publication'),storeAuthorityCid,
    capacityBytes:512*1024*1024,maxObjectBytes:10000000,maxObjects:100,maxContractNodes:100000,maxContractDepth:64},control);
  const snapshot=join(directory,'snapshots');
  const local=installLocalSnapshotStore(async(_key,bytes,frame)=>{
    await mkdir(snapshot,{recursive:true});
    return createLocalRetainedStore({parentDirectory:snapshot,capacityBytes:bytes,maxFrameBytes:frame,maxEntries:1});
  });
  const aoa=JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json',import.meta.url),'utf8'));
  const values=JSON.stringify(aoa.execution_contracts['REL.values']),fragment=JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered=JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  const registry=funded.installedContracts;
  const entry=createNodeHostEntry(()=>Promise.resolve(moon),installStrategyContributions);
  let observations=0;
  const selectedStore=interleaveObservation?Object.freeze({...store,async confirmCommittedIndex(ref){
    const result=await store.confirmCommittedIndex(ref);
    if(observations===0){
      const before=journal.lookupRunDefinition(ref,moon,control);
      assert.equal(before.physicalStartReserved,true);
      const running=issueInstalledUnpublishedRunState(moon,{
        runId:control.runDefinitionRunId(before.runDefinition),observedAt:now(),resultNames:['main'],
        dispatchReserved:true,preDispatchFailureConfirmed:false,cancelledBeforeStart:false,
        observedTerminalOutcome:'none',executionUnknown:false});
      journal.publishRunState(before,running,moon,control);
      const after=journal.lookupRunDefinition(ref,moon,control,before);
      assert.notStrictEqual(after,before,'A real observation write changes its complete physical row');
      assert.equal(after.revision,before.revision,'No control mutation is injected');
      observations++;
    }
    return result;
  }}):store;
  {
    let preparationCustody;
    const submission={principalId:'component',connection:{},requestId:'original-failed-compute'};
    if(managed){
      // Retain the same funded Request through the ordinary dispatch registry.
      // The real Core sibling is returned only after original stop/cleanup.
      let adopted;
      preparationCustody=installLocalPreparationRegistry(value=>value===preparedProgram,
        value=>{
          try{checked(moon.clientProgramInstalledManagedRunRetire(managedRun));}
          catch(cause){
            if(moon.clientProgramInstalledPreparationPayloadSevered(managedRun,request)!==true)throw cause;
          }
          funded.manager.severPreparation(value,adopted.original);
          funded.retireOriginal(value);
          return ()=>{
            checked(moon.clientProgramInstalledManagedRunRetire(managedRun));
            funded.manager.retireSeveredPreparation(adopted.original);
          };
        }, {runtime:moon,
          borrow:value=>funded.manager.borrowPreparation(value,preparationRequest)});
      preparationCustody.attach(submission,preparationCustody.adopt(preparedProgram,preparationRequest));
      adopted=funded.manager.adoptPreparation(preparedProgram,preparationRequest,request);
      managedRun=adopted.value;
    }else{
      submission.preparedProgram=preparedProgram;
    }
    dispatch=installActualDispatch({moon,control,journal,store:selectedStore,namespaceId,authorityScopeCid,storeAuthorityCid,now,
      registry,values,fragment,ordered,hostConnection:()=>true,
      observed(name,detail){if(name==='dispatch_failed')t.diagnostic(JSON.stringify({
        originalDispatchFailure:detail.code,primaryCode:detail.primaryCode,
        issueTag:detail.issueTag,nestedIssueTag:detail.nestedIssueTag}));},
      startRun:()=>journal.reserveDispatch(request,{namespaceId,currentAuthorization:true},moon,control),
      planFor:()=>plan,computeConfigurations:{local},preparationCustody,
      async runPublished(...args){
        const retain=args[5];args[5]=value=>{execution=value;retain(value);};
        try{return await entry.runPublishedCapturedStrategy(...args);}
        catch(error){failure=error;t.diagnostic(`Original dispatch failure: ${error.code}; typed cause ${inspect(error.primaryFailure?.cause,{depth:4})}`);throw error;}
      }});
    await dispatch.start(submission,request,accepted,{plan,...(managedRun===undefined?{}:{managedRun})});
    await dispatch.operation(accepted.ref);
    assert(failure instanceof CapturedRunExecutionError,'The actual failed execution must retain its original wrapper');
    assert.strictEqual(failure.execution,execution);
    assert.equal(execution.status,'host-tasks-failed');
    const frame=journal.lookupRunDefinition(accepted.ref,moon,control);
    assert.equal(frame.physicalCloseConfirmed,true,'The actual retained execution must complete stop before terminal projection');
    assert.equal(frame.observedTerminalOutcome,'failed');
    assert.equal(await store.confirmCommittedIndex(accepted.ref),undefined);
    assert.equal(observations,interleaveObservation?1:0);
  }
}

test('actual demanded scalar failure retains its execution and records physical stop',t=>actualScalarFailureStop(t,false));
test('actual installed managed scalar failure retains its execution and records physical stop',t=>actualScalarFailureStop(t,true));
test('actual installed failed Compute observes stop across public observation publication',t=>actualScalarFailureStop(t,true,true));

// Frame/Store ports below isolate inspection ordering. The cancellation
// decision is still the selected actual Common predicate; these ports do not
// claim an authenticated Journal, physical stop or publication COMMIT.
async function stopInspectionFixture(change,{observationOnly=false}={}){
  const {pathToFileURL}=await import('node:url');
  const moon=await import(pathToFileURL(commonRuntimePath));
  const {runtimeCore}=await import('../host-common/runtime-core.mjs');
  const {observeNodeRestoredModelStop}=await import('./client-dispatch-owner.mjs');
  const originalControl=runtimeCore(moon).publicationControl;
  const ref={runDefinitionCid:'explicit-stop-inspection'};
  let frame=Object.freeze({revision:1,stateRevision:0,cancellationRequested:false,physicalCloseConfirmed:false,runDefinition:{}});
  let inspections=0;
  const marks=[];
  const facts={ref,moon,cleanupConfirmed:true,physicalStopConfirmed:true,
    control:{runDefinitionRunId:()=> 'explicit-stop-run',
      runCancellationConfirmed:originalControl.runCancellationConfirmed},
    journal:{lookupRunDefinition:()=>frame,lookupReconciliationState:()=>undefined,
      ...(observationOnly?{canReinspectRunStopAfterStatePublication:(before,after)=>
        before!==undefined&&after!==undefined&&before.revision===after.revision&&before.cancellationRequested===after.cancellationRequested&&
        before.stateRevision<after.stateRevision}:{}),
      markPhysicalClose(actual,outcome,selected){assert.strictEqual(actual,ref);assert.strictEqual(selected,frame);marks.push(outcome);}},
    store:{async confirmCommittedIndex(){
      inspections++;
      const result=change({frame,inspection:inspections,setFrame(value){frame=value;}});
      return result;
    }},
  };
  return{observe:()=>observeNodeRestoredModelStop(facts),marks,inspections:()=>inspections};
}

test('stop reinspection retains changed cancellation instead of stale failure',async()=>{
  const f=await stopInspectionFixture(({frame,inspection,setFrame})=>{
    if(inspection===1)setFrame(Object.freeze({...frame,revision:2,cancellationRequested:true}));
  });
  await assert.rejects(f.observe(),{message:'ClientRunStopObservationChanged'});
  assert.equal(f.inspections(),1);assert.deepEqual(f.marks,[]);
});

test('stop reinspection retains continuously changed originals after its finite bound',async()=>{
  const f=await stopInspectionFixture(({frame,setFrame})=>setFrame(Object.freeze({...frame,stateRevision:frame.stateRevision+1})),
    {observationOnly:true});
  await assert.rejects(f.observe(),{message:'ClientRunStopObservationChanged'});
  assert.equal(f.inspections(),2);assert.deepEqual(f.marks,[]);
});

test('stop reinspection cannot convert a missing original into a stop',async()=>{
  const f=await stopInspectionFixture(({setFrame})=>setFrame(undefined));
  await assert.rejects(f.observe(),{message:'ClientRunStopObservationChanged'});
  assert.equal(f.inspections(),1);assert.deepEqual(f.marks,[]);
});

test('stop reinspection preserves a selected committed publication',async()=>{
  const f=await stopInspectionFixture(()=>Object.freeze({explicitCommittedIndexPort:true}));
  await f.observe();assert.equal(f.inspections(),1);assert.deepEqual(f.marks,[null]);
});

const entrySource = readFileSync(new URL('./entry.mjs', import.meta.url), 'utf8');
const entryAst = parse(entrySource, {ecmaVersion: 'latest', sourceType: 'module'});
const publicationErrorClass = entryAst.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'ClassDeclaration' && node.id?.name === 'CapturedRunPublicationError');
const OriginalPublicationError = compileFunction(
  entrySource.slice(publicationErrorClass.start, publicationErrorClass.end) +
    '\nreturn CapturedRunPublicationError;', [])();
function dispatchFailureCallback(node) {
  if (node?.type === 'CallExpression' && node.callee?.property?.name === 'catch') {
    const callback = node.arguments[0];
    if (callback?.type === 'ArrowFunctionExpression' &&
        source.slice(callback.start, callback.end).includes("diagnostic('dispatch_failed'")) return callback;
  }
  if (node === null || typeof node !== 'object') return undefined;
  for (const value of Object.values(node)) {
    for (const child of Array.isArray(value) ? value : [value]) {
      const found = dispatchFailureCallback(child);
      if (found !== undefined) return found;
    }
  }
}
const failureCallback = dispatchFailureCallback(ast);
assert.ok(failureCallback, 'The original dispatch failure callback must be selected');

for (const property of ['code', 'cause']) {
  test(`dispatch failure retains cleanup when diagnostic ${property} access throws`, async () => {
    const primary = new Error('OriginalComputeFailure');
    Object.defineProperty(primary, property, {get() {throw new Error('DiagnosticReadFailed');}});
    const execution = {};
    const failure = new OriginalPublicationError(primary, execution);
    const entry = {reserved: false, physicalStarted: true};
    let cleaned = 0, finished = 0;
    const handle = compileFunction(`return (${source.slice(failureCallback.start, failureCallback.end)});`,
      ['diagnostic', 'accepted', 'runtimeTag', 'runtimeOptionalField', 'entry',
        'CapturedRunPublicationError', 'settleCleanup', 'finishRun'])(
      () => {}, {ref: {}}, () => undefined, () => undefined, entry,
      OriginalPublicationError, async actual => {
        assert.equal(actual.primaryFailure, failure);
        assert.equal(actual.cleanupOwner, execution);
        assert.equal(actual.stopObservationPending, true);
        cleaned++;
      }, async () => {finished++;});
    await handle(failure);
    assert.equal(cleaned, 1);
    assert.equal(finished, 1);
    assert.equal(entry.primaryFailure, failure);
  });
}

test('dispatch observation retains the original operation beyond its start barrier', async () => {
  let finish, committed = false;
  const pending = new Promise(resolve => {finish = resolve;});
  const retained = [], stopped = [], ref = {runDefinitionCid: 'observed-dispatch'};
  const definition = {wire: 'explicit-definition'};
  const row = {cancellationRequested: false, revision: 1, runDefinition: definition};
  const owner = installNodeClientDispatchOwner({observation: observation(retained),
    moon: {}, control: {runDefinitionRunId: () => 'explicit-run', runCancellationConfirmed: () => false},
    journal: {reservePhysicalStart: () => true,
      lookupRunDefinition: () => row,
      lookupReconciliationState: () => undefined,
      markPhysicalClose: (...args) => stopped.push(args)},
    store: {confirmCommittedIndex: async () => committed ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    planFor: () => ({kind: 'infer', runDefinition: definition}),
    runInfer: async ({retainExecution}) => {
      retainExecution({async close() {}, cleanup: () => true, cleanupPending: () => false});
      await pending; committed = true;
    }});
  const started = owner.start({preparedProgram: {}, principalId: 'owner', connection: {},
    requestId: 'explicit-request'}, {}, {ref, runDefinition: definition,
    dispatchReserved: false, cancellationRequested: false}, {});
  const original = owner.operation(ref);
  try {
    assert.equal(await started, 'started');
    assert.deepEqual(retained, [original]);
    assert.equal(owner.live(ref), true);
    assert.deepEqual(stopped, []);
  } finally {finish(); await owner.drain();}
  assert.deepEqual(stopped, [[ref, null, row]]);
});

test('tracked observation settlement cannot retire unresolved physical cleanup', async () => {
  const retained = [], ref = {runDefinitionCid: 'observed-pending-cleanup'};
  let ready = false, runs = 0;
  const owner = installNodeClientDispatchOwner({observation: observation(retained)});
  const run = ({beginPhysicalWork, retainExecution}) => {
    runs++; beginPhysicalWork();
    retainExecution({async close() {}, cleanup: () => ready, cleanupPending: () => !ready});
  };
  const original = owner.track(ref, {run, observeStopped() {}});
  await assert.rejects(original, {message: 'ClientDispatchCleanupPending'});
  try {
    assert.deepEqual(retained, [original]);
    assert.equal(owner.operation(ref), original);
    assert.equal(owner.track(ref, {run, observeStopped() {}}), original);
    assert.deepEqual(retained, [original]);
    await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
  } finally {ready = true; await owner.drain();}
  assert.equal(owner.operation(ref), undefined);
  assert.equal(runs, 1);
});

test('optional dispatch observation cannot change execution or create another invocation', async () => {
  for (const selected of [undefined, {emit() {}, retainOperation() {throw new Error('OptionalObserverFailed');}}]) {
    let runs = 0;
    const result = {}, ref = {runDefinitionCid: 'explicit-optional-observation'};
    const owner = installNodeClientDispatchOwner({observation: selected});
    assert.equal(await owner.track(ref, {run() {runs++; return result;},
      observeStopped() {assert.fail('No physical operation to acknowledge');}}), result);
    assert.equal(runs, 1);
    assert.equal(owner.operation(ref), undefined);
    await owner.drain();
  }
});

test('installed observation follows the actual tracked work after ingress returns', async () => {
  const records = [], ref = {namespaceId: 'explicit-namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  const trace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
  const projection = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), include: ['run'],
    measurements: {include: ['rows']}, events: {level: 'diagnostic'},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  let release, flight;
  const gate = new Promise(resolve => {release = resolve;});
  const owner = installNodeClientDispatchOwner({observation: projection});
  const accepted = {};
  try {
    assert.equal(await projection.run('submit', trace, () => {
      flight = owner.track(ref, {run: async () => {
        await gate;
        projection.diagnostic('selected_rows_observed', {ref, rowOwner: 'request-journal',
          selection: 'run-definition', rowKind: 'run', returnedRows: 1, unrelatedRows: 0,
          coverage: 'selected-returned'});
      }, observeStopped() {assert.fail('No physical operation in this port fixture');}});
      return accepted;
    }), accepted);
    assert.equal(projection.status().activeSegments, 1);
    release(); await flight;
    assert.equal(projection.status().activeSegments, 0);
    await projection.close();
    const rows = records.filter(record => record.event === 'selected_rows_observed');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].attributes['actql.rows.returned'], 1);
    assert.deepEqual(rows[0].parent, trace);
    assert.deepEqual(projection.status().loss, {});
  } finally {release(); if (flight) await flight; await owner.drain(); await projection.close();}
});

test('preparation custody retires only after original dispatch and clears held plan first', async () => {
  const ref = {runDefinitionCid: 'preparation-custody'};
  const prepared = {}, held = {plan: {raw: prepared}};
  let begin = 0, retired = 0, reads = 0, claims = 0;
  let finish;
  const barrier = new Promise(resolve => {finish = resolve;});
  const owner = installNodeClientDispatchOwner({
    startRun: async () => {claims++; await barrier; return {kind: 'existing'};},
    preparationCustody: {begin(submission) {
      begin++; assert.equal(submission.preparedProgram, prepared);
      return {get preparedProgram() {reads++; return prepared;}, retire() {
        assert.equal(held.plan, undefined); retired++;
      }};
    }},
  });
  const submission = {preparedProgram: prepared, requestId: 'custody-request'};
  const accepted = {ref, dispatchReserved: false};
  const started = owner.start(submission, {}, accepted, held);
  assert.equal(await owner.start(submission, {}, accepted, held), 'not_started');
  assert.equal(begin, 1); assert.equal(retired, 0);
  finish(); await started; await owner.drain();
  assert.equal(claims, 1); assert.equal(reads, 1); assert.equal(retired, 1);
  await owner.drain(); assert.equal(retired, 1);
});

test('preparation retirement failure retains original owner for drain without dispatch retry', async () => {
  const ref = {runDefinitionCid: 'preparation-retirement-retry'};
  let attempts = 0, begins = 0, claims = 0;
  const held = {plan: {}};
  const owner = installNodeClientDispatchOwner({
    startRun: async () => {claims++; return {kind: 'existing'};},
    preparationCustody: {begin() {begins++; return {preparedProgram: {}, retire() {
      assert.equal(held.plan, undefined);
      if (++attempts < 3) throw new Error('RetirementPending');
    }};}},
  });
  await owner.start({requestId: 'retry'}, {}, {ref, dispatchReserved: false}, held);
  assert.equal(attempts, 1);
  await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
  await owner.drain();
  assert.equal(attempts, 3); assert.equal(begins, 1); assert.equal(claims, 1);
  assert.equal(owner.operation(ref), undefined);
});

test('preparation custody remains borrowed while original cleanup is pending', async () => {
  const {installLocalPreparationRegistry} = await import('./local-preparation-registry.mjs');
  const registry = installLocalPreparationRegistry(() => true);
  const prepared = {}, handle = registry.adopt(prepared);
  const submission = Object.freeze(registry.attach({requestId: 'pending-custody'}, handle));
  const candidate = Object.freeze(registry.attach({}, handle));
  let pending = true, claims = 0;
  const cleanupHandle = {status: () => ({pending}), retry: async () => {}};
  const owner = installNodeClientDispatchOwner({
    preparationCustody: registry,
    startRun: async () => {
      claims++;
      throw Object.assign(new Error('OriginalCleanupPending'), {cleanupPending: true, cleanupHandle});
    },
  });
  const ref = {runDefinitionCid: 'pending-custody'};
  await owner.start(submission, {}, {ref, dispatchReserved: false}, {});
  await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(candidate.preparedProgram, prepared);
  assert.notEqual(owner.operation(ref), undefined);
  pending = false;
  await owner.drain();
  assert.equal(claims, 1);
  assert.equal(owner.operation(ref), undefined);
  assert.throws(() => candidate.preparedProgram, /BorrowReleased|Retired/);
});

// Execute the exact single-Source dispatch call and the actual imported plan
// adapter. Native/physical ports stop at invocation; this is caller evidence.
async function singleSourcePublicationPolicyFixture(selectedPolicy) {
  const {acquiredTaskPublicationPlan}=await import('./local-values-plan.mjs');
  const calls=[];
  function select(node) {
    if (!node||typeof node!=='object') return;
    if (node.type==='CallExpression'&&node.callee.type==='Identifier'&&
        node.callee.name==='acquiredTaskPublicationPlan') calls.push(node);
    for(const value of Object.values(node)){
      if(Array.isArray(value))for(const child of value)select(child);
      else if(value&&typeof value==='object')select(value);
    }
  }
  select(ast);assert.equal(calls.length,1,'Select the original single-Source publication call only');
  const preparedProgram={},compiled={},definition={},nativeCapture={},identity={},logicalInput={},
    sourceEvidence=Object.freeze({name:'source_evidence',identity:'source-evidence-original'});
  const readPolicy='sha256:'+'a'.repeat(64),resultPolicy='sha256:'+'b'.repeat(64),
    sentinel=Error('OriginalInvocationPortBoundary');
  const capture=Object.freeze({source:()=>nativeCapture});
  const captured=Object.freeze({capture,identity,logicalInput,
    checkedSource:Object.freeze({sourceDataPolicyCid:readPolicy})});
  const held={plan:Object.freeze({compiled,runDefinition:definition})},entry={sourceCapture:captured};
  const counts={policy:0,owner:0,source:0,invocation:0};
  const moon={clientProgramPublicationDataPolicyCid(original){
    assert.equal(original,preparedProgram);counts.policy++;
    return selectedPolicy===undefined?resultPolicy:selectedPolicy();
  },clientProgramCapturedSourceMatches(original,source){
    assert.equal(original,preparedProgram);assert.equal(source,nativeCapture);counts.source++;return true;
  }};
  const authorityScopeCid='sha256:'+'c'.repeat(64),captureStartedAt='2026-10-30T00:00:00.000Z',
    captureCompletedAt='2026-10-30T00:00:01.000Z';
  const control={checkClientCompiledRunOwner(original,prepared){
    assert.equal(original,compiled);assert.equal(prepared,preparedProgram);counts.owner++;
  },issueCheckedClientCompiledInvocation(original,run,fields,_limits,preparation,prepared){
    counts.invocation++;assert.equal(original,compiled);assert.equal(run,definition);
    assert.equal(fields.dataPolicyCid,resultPolicy,'Result publication uses the checked Program policy');
    assert.equal(fields.source.captured,captured);assert.equal(fields.source.sourceEvidence,sourceEvidence);
    assert.equal(fields.source.captured.checkedSource.sourceDataPolicyCid,readPolicy,
      'The original Source observation retains its distinct read policy');
    assert.equal(fields.source.authorityScopeCid,authorityScopeCid);
    assert.equal(fields.source.captureStartedAt,captureStartedAt);
    assert.equal(fields.source.captureCompletedAt,captureCompletedAt);
    assert.equal(preparation,undefined);assert.equal(prepared,preparedProgram);throw sentinel;
  }};
  const ports={moon,control,acquiredTaskPublicationPlan,held,preparedProgram,entry,sourceEvidence,
    authorityScopeCid,captureStartedAt,captureCompletedAt,namespaceId:'explicit-policy-component',
    submission:{requestId:'original-explicit-request'},storeAuthorityCid:'sha256:'+'d'.repeat(64),
    now:()=>captureCompletedAt};
  const run=()=>compileFunction(`return (${source.slice(calls[0].start,calls[0].end)});`,Object.keys(ports))(...Object.values(ports));
  return {run,counts,sentinel,readPolicy,resultPolicy,captured,sourceEvidence};
}

test('single Source publication selects checked Result policy and retains original Source policy evidence',async()=>{
  const f=await singleSourcePublicationPolicyFixture();
  assert.throws(f.run,error=>error===f.sentinel);
  assert.deepEqual(f.counts,{policy:1,owner:1,source:1,invocation:1});
});

test('single Source publication missing or refused checked Result policy never falls back to read policy',async()=>{
  const missing=await singleSourcePublicationPolicyFixture(()=>undefined);
  assert.throws(missing.run,{message:'InvalidAcquiredTaskPublication'});
  assert.deepEqual(missing.counts,{policy:1,owner:1,source:0,invocation:0});
  const primary=Error('OriginalCheckedPolicyRefusal'),refused=await singleSourcePublicationPolicyFixture(()=>{throw primary;});
  assert.throws(refused.run,error=>error===primary);
  assert.deepEqual(refused.counts,{policy:1,owner:0,source:0,invocation:0});
});

const observeRestoredLocal = compileFunction(declarations.join('\n') +
  '\nreturn observeNodeRestoredLocalStop;')();

test('restored local stop separates proven failure from pending cleanup and rechecks original custody', async () => {
  for (const mode of ['pending-cleanup','later-owner','none','committed','cancel-requested','publication-unknown']) {
    const ref={}, frame={runDefinition:{},physicalCloseConfirmed:false,cancellationRequested:mode==='cancel-requested'};
    let owner=true; const stopped=[];
    const facts={ref,moon:{},control:{runCancellationConfirmed(){assert.fail('Not a cancellation observation');}},
      journal:{lookupRunDefinition:()=>frame,lookupReconciliationState:()=>undefined,
        observeStoppedLocalExecutionOwner:()=>owner&&!frame.physicalCloseConfirmed,
        markPhysicalClose(actual,outcome,original){assert.equal(actual,ref);assert.equal(original,frame);
          stopped.push(outcome);frame.physicalCloseConfirmed=true;}},
      store:{localExecutionCleanupConfirmed(){assert.fail('Physical stop is not cleanup acknowledgement');},
        async confirmCommittedIndex(){
          if(mode==='later-owner')owner=false;
          if(mode==='publication-unknown')throw Error('PublicationObservationUnknown');
          return mode==='committed'?{}:undefined;}}};
    if(mode==='publication-unknown')await assert.rejects(observeRestoredLocal(facts), /PublicationObservationUnknown/);
    else await observeRestoredLocal(facts);
    assert.deepEqual(stopped,mode==='later-owner'||mode==='publication-unknown'?[]:mode==='committed'?[null]:['failed']);
    if(mode!=='publication-unknown')await observeRestoredLocal(facts);
    assert.ok(stopped.length<=1,'repeat observation never issues a second stop');
  }
});

test('restored local stop refuses changed originals and permits only nominal bounded state reinspection', async () => {
  for (const reinspect of [false, true]) {
    const original={runDefinition:{},physicalCloseConfirmed:false}, next={...original};
    let frame=original, inspections=0; const stopped=[];
    const facts={ref:{},moon:{},control:{},journal:{lookupRunDefinition:()=>frame,
      observeStoppedLocalExecutionOwner:()=>true,lookupReconciliationState:()=>undefined,
      canReinspectRunStopAfterStatePublication:(before,after)=>reinspect&&before===original&&after===next,
      markPhysicalClose(_ref,outcome,retained){assert.equal(retained,next);stopped.push(outcome);}},
      store:{async confirmCommittedIndex(){inspections++;frame=next;return undefined;}}};
    if(reinspect){await observeRestoredLocal(facts);assert.deepEqual(stopped,['failed']);assert.equal(inspections,2);}
    else{await assert.rejects(observeRestoredLocal(facts),/ClientRunStopObservationChanged/);assert.deepEqual(stopped,[]);}
  }
});


// These execute the original private helper declarations with explicit Core
// ports. They do not construct a Host, issue capacity or certify physical stop.
function requiredDispatchBorrowFixture() {
  const selected = ast.body.filter(node => node.type === 'FunctionDeclaration' &&
    ['retainDispatchPreparationHost', 'releaseDispatchPreparationHost'].includes(node.id.name));
  assert.equal(selected.length, 2);
  const {checked} = awaitResultReader;
  return compileFunction(selected.map(node => source.slice(node.start, node.end)).join('\n') +
    '\nreturn retainDispatchPreparationHost;', ['checked'])(checked);
}
const awaitResultReader = await import('../host-common/runtime-result.mjs');

test('required dispatch preparation never skips a missing or legacy None borrow', () => {
  for (const mode of ['missing', 'legacy-none']) {
    const moon = mode === 'missing' ? {} : {
      clientProgramInstalledManagedPreparationBorrow: () => ({$tag: 1, _0: undefined}),
      clientProgramPreparationBorrowRead: () => assert.fail('No holder to read'),
      clientProgramPreparationBorrowReturn: () => assert.fail('No holder to return'),
    };
    assert.throws(() => requiredDispatchBorrowFixture(moon)({}, moon, {}, {}, {}, true),
      /PreparationHostCustodyUnavailable/u);
  }
});

test('required installed preparation rejects missing owner before installation metadata', async () => {
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const declaration = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost');
  assert.ok(declaration);
  const firstRead = declaration.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.init?.type === 'Identifier' && value.init.name === 'originalInstallation'));
  assert.ok(firstRead);
  // Select the actual entry prefix through its first installation read. The
  // unrelated later module loader/import.meta is outside this explicit port.
  const prefix = text.slice(declaration.body.start + 1, firstRead.end);
  const open = compileFunction('return async function(originalInstallation, preparation) {' + prefix + '};', [])();
  let reads = 0;
  const installation = new Proxy({}, {get() {reads++; throw new Error('UnexpectedInstallationMetadataRead');}});
  await assert.rejects(open(installation, undefined), /InstalledRequestPreparationUnavailable/u);
  assert.equal(reads, 0);
});


test('required preparation borrow keeps exact originals and returns a foreign holder through the original helper', () => {
  const prepared = {}, request = {}, run = {}, holder = {};
  for (const foreign of [false, true]) {
    let returns = 0;
    const moon = {
      clientProgramInstalledManagedPreparationBorrow(actualRun, actualPrepared, actualRequest) {
        assert.strictEqual(this, moon); assert.strictEqual(actualRun, run);
        assert.strictEqual(actualPrepared, prepared); assert.strictEqual(actualRequest, request);
        return {$tag: 1, _0: holder};
      },
      clientProgramPreparationBorrowRead(actual) {assert.strictEqual(this, moon); assert.strictEqual(actual, holder);
        return foreign ? {} : prepared;},
      clientProgramPreparationBorrowReturn(actual) {assert.strictEqual(this, moon); assert.strictEqual(actual, holder);
        returns++; return {$tag: 1, _0: undefined};},
    };
    const retain = requiredDispatchBorrowFixture(moon), entry = {};
    if (foreign) {
      assert.throws(() => retain(entry, moon, run, prepared, request, true), /ForeignPreparationHostCustody/u);
      assert.equal(returns, 1); assert.equal(entry.preparationHostBorrow, undefined);
    } else {
      retain(entry, moon, run, prepared, request, true);
      assert.strictEqual(entry.preparationHostBorrow, holder); assert.equal(returns, 0);
      const node = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'releaseDispatchPreparationHost');
      const release = compileFunction('return (' + source.slice(node.start, node.end) + ');', ['checked'])(awaitResultReader.checked);
      release(entry); release(entry);
      assert.equal(returns, 1); assert.equal(entry.preparationHostBorrow, undefined);
    }
  }
});

test('required installed preparation forwards only its same funded callback without raw serialization', async () => {
  const text = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  let options;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'installNodeClientProgramPreparation') options = node.arguments[0];
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object' && value.type) walk(value);
    }
  };
  walk(tree); assert.ok(options);
  const environment = {}, prepared = {}, request = {kind: 'program', input: {
    toJSON() {assert.fail('Funded caller must not serialize a second document');}}, parameters: null};
  let calls = 0;
  const preparation = {fundedPreparation(actual, selected) {
    assert.strictEqual(this, preparation); assert.strictEqual(actual, request); assert.strictEqual(selected, environment);
    calls++; return {kind: 'effect_free', prepared, originalInputs: {environment}};
  }};
  const names = ['moon', 'environment', 'sourcePublication', 'valuesMaxRows', 'check', 'preparation',
    'preparedSourceEnvironment', 'getPreparedSourceEnvironment', 'verifyRequestValuePolicy',
    'updateTargetOriginals', 'control', 'calendarArtifact', 'localContractLimits', 'effectInstallation'];
  const selected = compileFunction('return (' + text.slice(options.start, options.end) + ');', names)(
    {}, environment, undefined, undefined, undefined, preparation, undefined, undefined, undefined,
    {}, {}, undefined, {}, undefined);
  assert.equal(typeof selected.getFundedPreparation, 'function');
  const {installNodeClientProgramPreparation} = await import('./client-program-preparation.mjs');
  const prepare = installNodeClientProgramPreparation(selected);
  assert.strictEqual(await prepare(request), prepared); assert.equal(calls, 1);
  prepare.retireOriginal(prepared); prepare.retireReferences();
});

test('dispatch final usage observes the same ledger only after original preparation retirement', () => {
  const install = ast.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'installNodeClientDispatchOwner').declaration;
  const declarations = ['retirementReady', 'retire'].map(name => {
    const declaration = install.body.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
    assert(declaration, `Missing original retirement declaration: ${name}`);
    return source.slice(declaration.start, declaration.end);
  }).join('\n');
  const entries = new Map(), events = [], ledger = {retained: 7}, ref = {runDefinitionCid: 'original-retirement'};
  const retire = compileFunction(declarations + '\nreturn retire;',
    ['entries','keyOf','diagnostic','resourceUsage'])(entries, value => value.runDefinitionCid,
    (name, detail) => events.push({name, detail}), value => {
      assert.equal(value, ledger); return {reservedRetentionBytes: String(value.retained)};
    });
  let attempts = 0, allow = false;
  const entry = {ref, acquisitionLedger: ledger, settled: true, finishPending: true,
    retirePreparation() {attempts++; if (!allow) throw new Error('OriginalPreparationPending'); ledger.retained = 0;}};
  entries.set(ref.runDefinitionCid, entry);
  retire(entry); assert.equal(attempts, 0); assert.equal(events.length, 0);
  entry.finishPending = false; retire(entry);
  assert.equal(attempts, 1); assert.equal(entries.get(ref.runDefinitionCid), entry);
  assert.equal(events.length, 0, 'failed original retirement cannot publish final-zero usage');
  allow = true; retire(entry);
  assert.equal(attempts, 2); assert.equal(entries.has(ref.runDefinitionCid), false);
  assert.deepEqual(events, [{name: 'dispatch_cleanup_completed', detail: {ref,
    resourceUsage: {reservedRetentionBytes: '0'}}}]);
  retire(entry); assert.equal(events.length, 1, 'same original retirement reports once');
  for (const failureAt of ['usage', 'observer']) {
    const retained = new Map(), selected = {ref, acquisitionLedger: ledger, settled: true};
    retained.set(ref.runDefinitionCid, selected);
    const observeRetirement = compileFunction(declarations + '\nreturn retire;',
      ['entries','keyOf','diagnostic','resourceUsage'])(retained, value => value.runDefinitionCid,
      () => {throw new Error('ObserverUnavailable');}, () => {
        if (failureAt === 'usage') throw new Error('ObservationUnavailable');
        return {reservedRetentionBytes: '0'};
      });
    assert.doesNotThrow(() => observeRetirement(selected));
    assert.equal(retained.size, 0, 'optional diagnostic failure cannot resurrect original custody');
    assert.doesNotThrow(() => observeRetirement(selected));
  }
});
