// Fault-injected physical ports verify the actual installed caller's custody
// order. Core binding, one-shot claims and ledger census have separate actual
// Common/compiled Node tests; these fixture sizes are not a numerical profile.
import assert from 'node:assert/strict';
import test from 'node:test';
import {retainInferOriginalReadInstallation} from './infer-original-installation.mjs';
const {installNodeInferRun} = await import(process.env.ACTQL_ORIGINAL_CLEANUP_MODULE ??
  './installed-infer-run.mjs');

function fixture({startIssue, stopComplete = true, modelCleanupComplete = true,
  installation = false, readIssue, scopeIssue, waiting=false,
  authorization='dispatch',cutIssue,afterAuthorize,scopeBindingIssue,requestModel=false} = {}) {
  const calls = [], active = {}, read = {}, scope = {}, compiled = {}, consumer = {};
  const preparedProgram = {}, graph = {};
  const runDefinition = {wire: '{"run_id":"original-cleanup"}'};
  const issue = {kind: 'OriginalFixtureBindingRefused'};
  let custody, physicalComplete = false, physicalPending = true, physicalFailure;
  let allowScope = true, stoppedRead = false, settledRead = false;
  let hostClosing=false,scopeLive=requestModel;
  const runtimeView={}, scopeView={};
  let stop = stopComplete, modelCleanup = modelCleanupComplete;
  let advances=0;
  const nextIssue={kind:'NextModelAdvanceFixtureStop'};
  const preparedCallSet={};
  const moon = {
    clientProgramInferPlanBoundary: () => ({_0: 0}),
    clientProgramStartOriginalInferExecution() {
      calls.push('originalStart');
      return startIssue === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startIssue};
    },
    clientProgramStartScopedInferExecution() {
      calls.push('unownedStart'); return {$tag: 1, _0: active};
    },
    clientProgramRequireInferCallEntry: () => ({$tag: 1, _0: undefined}),
    clientProgramBindInferPhysicalPreflightCurrent:()=>({$tag:1,_0:undefined}),
    clientProgramBindInferModelObservation:()=>true,
    clientProgramBindInferQuantityCapacity: () => waiting ? {$tag:1,_0:undefined}:({$tag: 0, _0: issue}),
    clientProgramCancelInferExecution() { calls.push('modelStopRequest'); },
    clientProgramInferExecutionStopped: () => stop,
    clientProgramAdvanceInferExecution: () => {
      if(!waiting)return {$tag: 1, _0: stop ? 'stopped' : 'waiting'};
      calls.push('advance');advances++;
      return advances===1?{$tag:1,_0:'waiting'}:{$tag:1,_0:'failed'};
    },
    clientProgramInferExecutionPollIssue:()=>nextIssue,
    clientProgramInferPreparedCallSet:()=>preparedCallSet,
    clientProgramInferCallSettlement:()=>undefined,
    clientProgramResultCount:()=>1,
    clientProgramResultName:()=> 'answer',
    clientProgramInferExecutionPollKind: value => value,
    clientProgramCleanupInferExecution() {
      calls.push('modelCleanup'); return {$tag: 1, _0: modelCleanup};
    },
  };
  const exact = (actualCompiled, definition, actualGraph) => {
    assert.equal(actualCompiled, compiled); assert.equal(definition, runDefinition);
    assert.equal(actualGraph, graph);
  };
  const control = {
    bindCheckedClientInferRun(actualCompiled,actualActive,definition){
      assert.equal(actualCompiled,compiled);assert.equal(actualActive,active);assert.equal(definition,runDefinition);
      calls.push('bindRun');},
    beginCheckedClientInferOriginalReadScope(...args) {
      exact(...args); assert.notEqual(custody, undefined);
      assert.equal(args[3].quantityCapacity, selected.quantityCapacity);
      calls.push('scopeBegin');
      if (scopeIssue !== undefined) throw scopeIssue;
      scopeLive=true;
      return scope;
    },
    checkedClientInferOriginalReadScopeLive(...args){
      exact(...args);return args[3]===scope&&scopeLive;
    },
    prepareCheckedClientInferNodeReadLayout(...args) {
      exact(...args); assert.equal(args[3], scope); calls.push('readPrepare');
      if (readIssue !== undefined) throw readIssue;
      return read;
    },
    claimCheckedClientInferNodePreparationLayout(...args) {
      exact(...args); assert.equal(args[3], read); calls.push('claim'); return consumer;
    },
    startCheckedClientInferOriginalPreparation(...args) {
      assert.equal(args[0], compiled); assert.equal(args[1], runDefinition);
      assert.equal(args[8], consumer);
      return assertChecked(moon.clientProgramStartOriginalInferExecution());
    },
    stopCheckedClientInferOriginalReadPreparation(...args) {
      exact(...args); assert.equal(args[3], scope); assert.equal(args[4], read);
      calls.push('readStop'); stoppedRead = true;
    },
    settleCheckedClientInferOriginalReadPreparation(...args) {
      exact(...args); assert.equal(args[3], read); assert.equal(args[4], true);
      assert.equal(stoppedRead, true);
      if (installation) assert.equal(modelCleanup, true);
      else { assert.equal(physicalComplete, true); assert.equal(physicalPending, false); }
      calls.push('readSettle'); settledRead = true;
    },
    finishCheckedClientInferOriginalReadScope(...args) {
      exact(...args); assert.equal(args[3], scope); assert.equal(args[4], true);
      assert.equal(settledRead || installation &&
        (readIssue !== undefined || scopeBindingIssue !== undefined), true);
      calls.push('scopeFinish');if(allowScope)scopeLive=false;return allowScope;
    },
  };
  function assertChecked(value) {
    if (value.$tag === 0) throw Object.assign(new Error('MoonBitHostFailure'),
      {code: 'MoonBitHostFailure', cause: value._0});
    return value._0;
  }
  const physicalCustody = {
    async close() {
      calls.push('physicalClose'); assert.equal(stoppedRead, true);
      if (physicalFailure !== undefined) throw physicalFailure;
      physicalPending = !physicalComplete; return physicalComplete;
    },
    async cleanup() {
      calls.push('physicalRetry'); assert.equal(stoppedRead, true);
      if (physicalFailure !== undefined) throw physicalFailure;
      physicalPending = !physicalComplete; return physicalComplete;
    },
    cleanupPending: () => physicalPending,
  };
  const originalPreparation = {compiled, runDefinition, control, read, scope, physicalCustody,
    readRetainedBytes: 7n, readExecutionBytes: 5n,
    modelRetainedBytes: 100n, modelExecutionBytes: 5n,
    nodeInstallation: {layout: {}, installation: {}, runtimeArtifactCid: 'runtime',
      layoutArtifactCid: 'layout', probability: undefined}};
  const plan = {compiled, runDefinition, inferGraph: graph};
  const selected = {graph, step: 0, provider() { assert.fail('no physical send'); },
    // Explicit Host-current counters, not a real runtime coverage/profile.
    currentProvider:()=>true,assertTrustedRuntime:()=>{},
    assertNewTrustedRuntime(){
      if(hostClosing)throw Object.assign(new Error('ClientHostClosing'),{code:'ClientHostClosing'});
      selected.assertTrustedRuntime();
    },
    bindTrustedRuntimeScope(actual,actualCompiled,definition,actualGraph){
      exact(actualCompiled,definition,actualGraph);assert.equal(actual,scope);
      assert.equal(scopeLive,true);assert.notEqual(runtimeView,scopeView);
      if(scopeBindingIssue!==undefined)throw scopeBindingIssue;
      return scopeView;
    },
    assertTrustedRuntimeScope(actual,view,actualCompiled,definition,actualGraph){
      exact(actualCompiled,definition,actualGraph);assert.equal(actual,scope);
      assert.equal(view,scopeView);assert.equal(scopeLive,true);
      // Existing borrow ignores Host closing, not actual original loss.
      selected.assertTrustedRuntime();
    },
    finishTrustedRuntimeScope(actual,view,actualCompiled,definition,actualGraph){
      assert.equal(actual,scope);assert.equal(view,scopeView);
      return control.finishCheckedClientInferOriginalReadScope(
        actualCompiled,definition,actualGraph,actual,true);
    },
    quantityCapacity: {limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}}};
  if (installation) selected.originalReadInstallation = retainInferOriginalReadInstallation({
    bootstrap: {bootstrapRetainedBytes: 20n, bootstrapExecutionBytes: 20n,
      maxReservations: 8, maxHoldings: 8, maxDelegations: 8},
    modelRetainedBytes: 100n, modelExecutionBytes: 5n,
    currentStateCodec:{quantum:1,comparisonWork:5,decode:{maxWork:20000,
      parse:{max_input_bytes:10000,max_nodes:1000,max_depth:20},
      tree:{max_nodes:1000,max_depth:20,max_string_bytes:10000,max_total_string_bytes:10000}}},
    // Independent declaration DATA only; these tests allocate no publication.
    publicationCapacity:{retainedBytes:1n,workspaceBytes:0n},
    nodeInstallation: {...originalPreparation.nodeInstallation, layout: {
      response_profile: {}, runtime_artifact_cid: 'runtime', layout_artifact_cid: 'layout',
      program_definition_cid: 'program', parameter_values_cid: 'parameters',
      barrier_cid: 'barrier', prepared_rows: 1n, retained_bytes: 7n, execution_bytes: 5n}}});
  let discovered = [];
  const modelController = {discover: () => discovered,
    prime() { assert.fail('fresh original preparation cannot prime restored input'); },
    release(token) { assert.equal(token, undefined); },
    unresolved:()=>false,
    async open(options) {
      if(!waiting)assert.fail('a binding refusal cannot authorize a Model call');
      assert.equal(options.preparedCallSet,preparedCallSet);calls.push('openContinuation');
      return {observe(){},entry(){},async authorize(){calls.push('authorize');afterAuthorize?.();return {status:authorization};},
        async prepareOriginalResourcesForDispatch(){calls.push('originalCut');if(cutIssue!==undefined)throw cutIssue;}};
    }};
  const requestCarrier = {prepared: preparedProgram, control, compiled, runDefinition, graph,
    originalReadInstallation: selected.originalReadInstallation, scope, scopeFinished: false,
    read: undefined, readAttempted: false, taken: false,
    budget: {readRetainedBytes: 7n, readExecutionBytes: 5n, modelRetainedBytes: 100n, modelExecutionBytes: 5n}};
  const runInfer = installNodeInferRun({moon, core: {publicationControl: control},
    selections: new Map([[preparedProgram, selected]]), modelController,
    prepareOriginalModelRun: !requestModel ? undefined : (p, originalPlan, originalSelected) => {
      assert.equal(p, preparedProgram); assert.equal(originalPlan, plan); assert.equal(originalSelected, selected);
      return requestCarrier;
    }});
  const input = {preparedProgram, plan, originalPreparation,
    signal: new AbortController().signal,
    retainExecution(value) { assert.equal(custody, undefined); custody = value; },
    beginPhysicalWork() { if(!waiting)assert.fail('refused execution cannot begin physical work');calls.push('physicalBegin'); }};
  if (installation) delete input.originalPreparation;
  return {run: () => runInfer(input), input, issue, nextIssue, calls, originalPreparation, selected, control, requestCarrier,
    custody: () => custody,
    physical(complete, pending = !complete) { physicalComplete = complete; physicalPending = pending; },
    failPhysical(error) { physicalFailure = error; },
    scopeAllowed(value) { allowScope = value; },
    modelStopped(value) { stop = value; },
    modelClean(value) { modelCleanup = value; },
    hostClosing(value){hostClosing=value;},
    existing(value) { discovered = value; }};
}

test('installed read supplier creates one original scope and read before one-shot Model start', async () => {
  const f = fixture({installation: true});
  await assert.rejects(f.run(), typed(f.issue));
  assert.deepEqual(f.calls, ['scopeBegin', 'readPrepare', 'claim', 'originalStart', 'modelStopRequest']);
  assert.equal(await f.custody().close(), true);
  assert.equal(f.calls.includes('unownedStart'), false);
  assert.equal(f.calls.filter(value => value === 'readStop').length, 1);
  assert.equal(f.calls.filter(value => value === 'readSettle').length, 1);
  assert.equal(f.calls.filter(value => value === 'scopeFinish').length, 1);
  await f.custody().cleanup();
  assert.equal(f.calls.filter(value => value === 'scopeBegin').length, 1);
  assert.equal(f.calls.filter(value => value === 'originalStart').length, 1);
});

test('missing original state codec is refused before child allocation or physical preparation', async () => {
  const f=fixture({installation:true});
  f.selected.originalReadInstallation=retainInferOriginalReadInstallation({
    ...f.selected.originalReadInstallation,currentStateCodec:undefined});
  await assert.rejects(f.run(),{code:'InferOriginalStateCodecUnavailable'});
  assert.deepEqual(f.calls,[]);
  assert.equal(f.custody(),undefined);
});

test('missing Host runtime association refuses before scope read or Entry creation',async()=>{
  const f=fixture({installation:true});
  delete f.selected.assertTrustedRuntime;
  await assert.rejects(f.run(),/InferTrustedRuntimeViewUnavailable/u);
  assert.deepEqual(f.calls,[]);
  assert.notEqual(f.custody(),undefined, 'admitted dispatch retains the same original cleanup');
  assert.equal(await f.custody().cleanup(),true);
  assert.deepEqual(f.calls,[], 'no synthetic Scope/physical cleanup is invented');
});

test('foreign installed provider refuses before original child allocation',async()=>{
  const f=fixture({installation:true});f.selected.currentProvider=()=>false;
  await assert.rejects(f.run(),/InferTrustedRuntimeViewUnavailable/u);
  assert.deepEqual(f.calls,[]);
  assert.notEqual(f.custody(),undefined);
  assert.equal(await f.custody().cleanup(),true);
  assert.deepEqual(f.calls,[]);
});

test('Host closing refuses a new original Scope without claiming an existing borrow',async()=>{
  const f=fixture({installation:true});f.hostClosing(true);
  await assert.rejects(f.run(),{code:'ClientHostClosing'});
  assert.deepEqual(f.calls,[]);
  assert.notEqual(f.custody(),undefined);
  assert.equal(await f.custody().cleanup(),true);
  assert.deepEqual(f.calls,[]);
});

test('fallible runtime binding happens after actual Scope issuance and retains same cleanup custody',async()=>{
  const issue=Object.assign(new Error('InferTrustedRuntimeScopeUnavailable'),
    {code:'InferTrustedRuntimeScopeUnavailable'});
  const f=fixture({installation:true,scopeBindingIssue:issue});
  await assert.rejects(f.run(),error=>error===issue);
  assert.deepEqual(f.calls,['scopeBegin']);
  assert.notEqual(f.custody(),undefined);
  assert.equal(f.custody().cleanupPending(),true);
  assert.equal(await f.custody().cleanup(),true);
  assert.deepEqual(f.calls,['scopeBegin','scopeFinish']);
  await f.custody().cleanup();
  assert.equal(f.calls.filter(value=>value==='scopeBegin').length,1);
  assert.equal(f.calls.filter(value=>value==='scopeFinish').length,1);
});

test('entered Run keeps its same Scope during graceful Host drain without cancellation',async()=>{
  let f;
  f=fixture({installation:true,waiting:true,stopComplete:false,
    afterAuthorize:()=>f.hostClosing(true)});
  await assert.rejects(f.run(),typed(f.nextIssue));
  assert.equal(f.calls.filter(value=>value==='scopeBegin').length,1);
  assert.equal(f.calls.filter(value=>value==='advance').length,2);
  assert.equal(f.calls.includes('originalCut'),true);
  assert.equal(f.calls.includes('modelStopRequest'),false);
  assert.equal(f.custody().cleanupPending(),true);
});

test('runtime loss after approval keeps the same original custody and blocks another advance',async()=>{
  const f=fixture({installation:true,waiting:true,stopComplete:false});
  const unavailable=Object.assign(new Error('InferTrustedRuntimeViewRetired'),
    {code:'InferTrustedRuntimeViewRetired'});
  f.selected.assertTrustedRuntime=()=>{
    if(f.calls.includes('authorize'))throw unavailable;
  };
  await assert.rejects(f.run(),error=>error===unavailable);
  assert.equal(f.calls.filter(value=>value==='scopeBegin').length,1);
  assert.equal(f.calls.filter(value=>value==='advance').length,1);
  assert.equal(f.calls.includes('originalCut'),false);
  assert.equal(f.custody().cleanupPending(),true);
});

test('missing original publication supply is refused before creating a scope or sending',async()=>{
  const f=fixture({installation:true});
  f.selected.originalReadInstallation=retainInferOriginalReadInstallation({
    ...f.selected.originalReadInstallation,publicationCapacity:undefined});
  await assert.rejects(f.run(),{code:'InferOriginalPublicationCapacityUnavailable'});
  assert.deepEqual(f.calls,[]);assert.equal(f.custody(),undefined);
});

test('installed original dispatch completes its cut after authorization and before the next Model advance',async()=>{
  const f=fixture({installation:true,waiting:true,stopComplete:false});
  await assert.rejects(f.run(),typed(f.nextIssue));
  assert.deepEqual(f.calls,['scopeBegin','readPrepare','claim','originalStart',
    'physicalBegin','bindRun','advance','openContinuation','authorize','originalCut','advance']);
});

test('installed original waiting approval does not run cut or another Model advance',async()=>{
  const f=fixture({installation:true,waiting:true,stopComplete:false,authorization:'waiting_checkpoint'});
  assert.deepEqual(await f.run(),{status:'waiting_checkpoint'});
  assert.equal(f.calls.includes('originalCut'),false);
  assert.equal(f.calls.filter(value=>value==='advance').length,1);
});

test('installed original failed cut cannot reach next Model advance or replace the original child',async()=>{
  const cutIssue=Object.assign(new Error('CheckpointJournalCommitOutcomeUnknown'),
    {code:'CheckpointJournalCommitOutcomeUnknown',outcome:'unknown'});
  const f=fixture({installation:true,waiting:true,stopComplete:false,cutIssue});
  await assert.rejects(f.run(),error=>error===cutIssue);
  assert.equal(f.calls.filter(value=>value==='advance').length,1);
  assert.equal(f.calls.filter(value=>value==='originalStart').length,1);
  assert.equal(f.calls.filter(value=>value==='originalCut').length,1);
  assert.equal(f.custody().cleanupPending(),true);
});

test('installed read supplier retains only the original scope after typed read refusal', async () => {
  const readIssue = Object.assign(new Error('MoonBitHostFailure'),
    {code: 'MoonBitHostFailure', cause: {kind: 'LayoutMismatch'}});
  const f = fixture({installation: true, readIssue});
  await assert.rejects(f.run(), error => error === readIssue);
  assert.deepEqual(f.calls, ['scopeBegin', 'readPrepare']);
  f.scopeAllowed(false);
  assert.equal(await f.custody().close(), false);
  assert.equal(f.custody().cleanupPending(), true);
  f.scopeAllowed(true);
  assert.equal(await f.custody().cleanup(), true);
  assert.deepEqual(f.calls, ['scopeBegin', 'readPrepare', 'scopeFinish', 'scopeFinish']);
});

test('installed read supplier atomic scope refusal cannot leave fictitious read cleanup pending', async () => {
  const scopeIssue = Object.assign(new Error('MoonBitHostFailure'),
    {code: 'MoonBitHostFailure', cause: {kind: 'InvalidBootstrap'}});
  const f = fixture({installation: true, scopeIssue});
  await assert.rejects(f.run(), error => error === scopeIssue);
  assert.equal(await f.custody().close(), true);
  assert.equal(f.custody().cleanupPending(), false);
  assert.deepEqual(f.calls, ['scopeBegin']);
});

test('installed read supplier never treats consumer stop as its actual child cleanup', async () => {
  const f = fixture({installation: true, modelCleanupComplete: false});
  await assert.rejects(f.run(), typed(f.issue));
  await assert.rejects(f.custody().close(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(f.calls.includes('readStop'), false);
  assert.equal(f.calls.includes('readSettle'), false);
  f.modelClean(true);
  assert.equal(await f.custody().cleanup(), true);
  assert.equal(f.calls.filter(value => value === 'claim').length, 1);
  assert.equal(f.calls.filter(value => value === 'originalStart').length, 1);
});

test('installed read supplier rejects restored, composed and competing original preparation', async () => {
  for (const mutate of [
    f => { f.input.replay = true; },
    f => { f.input.acquiredInfer = {}; },
    f => { f.selected.components = []; },
    f => { f.input.originalPreparation = f.originalPreparation; },
  ]) {
    const f = fixture({installation: true}); mutate(f);
    await assert.rejects(f.run(), /InstalledInferOriginalReadInstallationUnavailable/u);
    assert.deepEqual(f.calls, []);
  }
  const f = fixture({installation: true}); f.existing([{inventory: {taskIndex: 0}}]);
  await assert.rejects(f.run(), /RestoredInferOriginalPreparationUnavailable/u);
  assert.deepEqual(f.calls, []);
});

test('installed read supplier refuses incomplete consumer API without an unowned fallback', async () => {
  const f = fixture({installation: true});
  f.control.prepareCheckedClientInferNodeReadLayout = undefined;
  await assert.rejects(f.run(), /InstalledInferOriginalReadRuntimeUnavailable/u);
  assert.deepEqual(f.calls, []);
});

test('installed read supplier retains no scope before the existing custody accepts ownership', async () => {
  const f = fixture({installation: true});
  f.input.retainExecution = () => { throw new Error('CustodyRefused'); };
  await assert.rejects(f.run(), /CustodyRefused/u);
  assert.deepEqual(f.calls, []);
});

const typed = cause => error => error.code === 'MoonBitHostFailure' && error.cause === cause;

test('installed original cleanup retains the same physical read before read and whole Run retirement', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  assert.equal(f.calls.includes('unownedStart'), false);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
  const custody = f.custody();
  assert.equal(await custody.close(), false);
  assert.equal(custody.cleanupPending(), true);
  assert.deepEqual(f.calls.slice(-3), ['modelCleanup', 'readStop', 'physicalClose']);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true); f.scopeAllowed(false);
  assert.equal(await custody.cleanup(), false);
  assert.deepEqual(f.calls.slice(-3), ['physicalRetry', 'readSettle', 'scopeFinish']);
  assert.equal(custody.cleanupPending(), true, 'read retirement is not whole-Run cleanup');
  f.scopeAllowed(true);
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
  await custody.close(); await custody.cleanup();
  assert.equal(f.calls.filter(call => call === 'claim').length, 1);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
  assert.equal(f.calls.filter(call => call === 'physicalClose').length, 1);
  assert.equal(f.calls.filter(call => call === 'physicalRetry').length, 1);
  assert.equal(f.calls.filter(call => call === 'readStop').length, 1);
  assert.equal(f.calls.filter(call => call === 'readSettle').length, 1);
  assert.equal(f.calls.filter(call => call === 'scopeFinish').length, 2);
});

test('installed original cleanup preserves a thrown close and retries only the same physical custody', async () => {
  const f = fixture(), failure = new Error('OriginalPhysicalCloseUnknown');
  await assert.rejects(f.run(), typed(f.issue));
  f.failPhysical(failure);
  await assert.rejects(f.custody().close(), error => error === failure);
  assert.equal(f.custody().cleanupPending(), true);
  assert.equal(f.calls.includes('readSettle'), false);
  f.failPhysical(undefined); f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
  assert.deepEqual(f.calls.slice(-3), ['physicalRetry', 'readSettle', 'scopeFinish']);
  assert.equal(f.calls.filter(call => call === 'claim').length, 1);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
});

test('installed original cleanup stops the never-constructed consumer without replaying start', async () => {
  const issue = {kind: 'OriginalCapacity', detail: 'NoModelAllocation'};
  const f = fixture({startIssue: issue});
  await assert.rejects(f.run(), typed(issue));
  f.physical(true);
  assert.equal(await f.custody().close(), true);
  assert.deepEqual(f.calls, ['claim', 'originalStart', 'readStop', 'physicalClose',
    'readSettle', 'scopeFinish']);
});

test('installed original cleanup does not turn cancellation or Model stop alone into physical release', async () => {
  const f = fixture({stopComplete: false, modelCleanupComplete: false});
  await assert.rejects(f.run(), typed(f.issue));
  await assert.rejects(f.custody().close(), /ClientDispatchCleanupPending/u);
  assert.equal(f.calls.includes('readStop'), false);
  f.modelStopped(true);
  assert.equal(await f.custody().cleanup(), false);
  assert.equal(f.calls.includes('readStop'), false, 'Model physical stop is not Model cleanup');
  f.modelClean(true);
  assert.equal(await f.custody().cleanup(), false);
  assert.equal(f.calls.includes('readStop'), true);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
});

test('installed original preparation rejects foreign, incomplete and restored custody before claim', async () => {
  for (const mutate of [
    f => { f.originalPreparation.control = {}; },
    f => { f.originalPreparation.compiled = {}; },
    f => { f.originalPreparation.runDefinition = {}; },
    f => { delete f.originalPreparation.scope; },
    f => { delete f.originalPreparation.read; },
    f => { delete f.originalPreparation.nodeInstallation; },
    f => { f.originalPreparation.extra = true; },
    f => { f.originalPreparation.physicalCustody.cleanupPending = undefined; },
    f => { f.input.acquiredInfer = {}; },
    f => { f.input.replay = true; },
  ]) {
    const f = fixture(); mutate(f);
    await assert.rejects(f.run(), /InvalidInstalledInferOriginalPreparation/u);
    assert.deepEqual(f.calls, []);
    assert.equal(f.custody(), undefined);
  }
  const f = fixture(); f.existing([{inventory: {taskIndex: 0}}]);
  await assert.rejects(f.run(), /RestoredInferOriginalPreparationUnavailable/u);
  assert.deepEqual(f.calls, []);
});

test('installed original cleanup requires physical cleanupPending false, not a fulfilled close alone', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  // A physical owner may finish its Promise but still retain cleanup custody.
  const child = f.originalPreparation.physicalCustody;
  child.close = async () => { f.calls.push('physicalClose'); return true; };
  assert.equal(await f.custody().close(), false);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
});

test('installed original cleanup coalesces concurrent close and retry through the same custody', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  let reached, complete;
  const entered = new Promise(resolve => { reached = resolve; });
  const child = f.originalPreparation.physicalCustody;
  child.close = () => {
    f.calls.push('physicalClose'); reached();
    return new Promise(resolve => { complete = resolve; });
  };
  const first = f.custody().close();
  await entered;
  assert.equal(f.custody().cleanup(), first);
  assert.equal(f.custody().close(), first);
  assert.equal(f.calls.includes('readSettle'), false);
  assert.equal(f.calls.includes('physicalRetry'), false);
  f.physical(true); complete(true);
  assert.equal(await first, true);
  assert.equal(f.custody().cleanup(), first);
  assert.equal(f.calls.filter(call => call === 'readSettle').length, 1);
  assert.equal(f.calls.filter(call => call === 'scopeFinish').length, 1);
});

test('installed original cleanup fixes the original record across an awaited physical close', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  let reached, complete;
  const entered = new Promise(resolve => { reached = resolve; });
  const child = f.originalPreparation.physicalCustody;
  child.close = () => {
    f.calls.push('physicalClose'); reached();
    return new Promise(resolve => { complete = resolve; });
  };
  const closed = f.custody().close();
  await entered;
  // Neither a later caller mutation nor a replacement physical Owner may
  // redirect the already-retained cleanup acknowledgement to another read.
  f.originalPreparation.read = {};
  f.originalPreparation.scope = {};
  f.originalPreparation.control = {};
  f.originalPreparation.physicalCustody = {cleanup() { assert.fail('replacement physical custody'); }};
  f.physical(true); complete(true);
  assert.equal(await closed, true);
  assert.equal(f.calls.filter(call => call === 'readSettle').length, 1);
  assert.equal(f.calls.filter(call => call === 'scopeFinish').length, 1);
});


test('Request-owned installed Model reuses its adopted Scope and retains original read until physical cleanup', async () => {
  const f = fixture({installation: true, requestModel: true, modelCleanupComplete: false});
  await assert.rejects(f.run(), typed(f.issue));
  assert.equal(f.calls.includes('scopeBegin'), false);
  assert.equal(f.requestCarrier.read, f.originalPreparation.read);
  assert.equal(f.requestCarrier.readAttempted, true); assert.equal(f.requestCarrier.taken, true);
  assert.equal(await f.custody().close(), false);
  assert.equal(f.requestCarrier.scopeFinished, false); assert(f.requestCarrier.read);
  f.modelClean(true); assert.equal(await f.custody().cleanup(), true);
  assert.equal(f.requestCarrier.read, undefined); assert.equal(f.requestCarrier.scopeFinished, true);
  assert.equal(f.calls.filter(value => value === 'readPrepare').length, 1);
  assert.equal(f.calls.filter(value => value === 'scopeFinish').length, 1);
});

test('Request-owned installed Model keeps failed read or Scope binding on the same carrier without independent admission', async () => {
  for (const phase of ['readIssue', 'scopeBindingIssue']) {
    const primary = new Error('original Request ' + phase);
    const f = fixture({installation: true, requestModel: true, [phase]: primary});
    await assert.rejects(f.run(), cause => cause === primary);
    assert.equal(f.calls.includes('scopeBegin'), false); assert.equal(f.requestCarrier.taken, true);
    assert.equal(f.requestCarrier.read, undefined); assert.equal(f.requestCarrier.scopeFinished, false);
    f.scopeAllowed(false); assert.equal(await f.custody().cleanup(), false);
    assert.equal(f.requestCarrier.scopeFinished, false);
    f.scopeAllowed(true); assert.equal(await f.custody().cleanup(), true);
    assert.equal(f.requestCarrier.scopeFinished, true); assert.equal(f.calls.includes('unownedStart'), false);
  }
});
