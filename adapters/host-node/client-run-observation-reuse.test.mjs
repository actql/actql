import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import * as runStateAccess from '../host-common/run-state-access.mjs';

// Execute actual Local statements. The original composition cases use explicit
// owner ports; the metadata case uses real Common and SQLite. Neither qualifies
// a full Host, physical provider or normal resource funding.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const statements = [], waitStatements = [];
const resumeObservers = [], resumeAssignments = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclaration' && node.declarations.some(declaration =>
      ['waitWork', 'subscribeWaitWork', 'wait'].includes(declaration.id.name))) {
    waitStatements.push(source.slice(node.start, node.end));
  }
  if (node.type === 'VariableDeclaration' &&
      node.declarations.some(declaration => declaration.id.name === 'observeRun')) {
    statements.push(source.slice(node.start, node.end));
  }
  if (node.type === 'VariableDeclaration' && node.declarations.some(declaration =>
      declaration.id.name === 'observeCancellation' && declaration.init?.type === 'CallExpression' &&
      declaration.init.callee.property?.name === 'observeRunCancellation' &&
      declaration.init.arguments[3]?.name === 'retained')) resumeObservers.push(source.slice(node.start,node.end));
  if (node.type === 'AssignmentExpression' && node.left.name === 'sourceResume' &&
      node.right.type === 'ObjectExpression') resumeAssignments.push(source.slice(node.start,node.end));
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  }
}
visit(ast);
assert.equal(statements.length, 1);
const names = ['principalId', 'namespaceId', 'authorityScopeCid', 'journal', 'moon',
  'control', 'store', 'inspectAuthorizedRunState', 'observeAuthorizedRunState', 'stateService', 'checkpoints',
  'dispatchOwner', 'modelResumeFlights', 'issueInstalledUnpublishedRunState', 'now',
  'projectRunObservation', 'clientOperationError'];
const compile = new Function(...names, `${statements[0]}; return observeRun;`);

function sourceResumeFixture({probe = () => ({cancellationRequested:false}), leaseFailure, admitFailure} = {}) {
  assert.equal(resumeObservers.length,1);assert.equal(resumeAssignments.length,1);
  const ref = {}, moon = {}, control = {}, retained = {}, claimed = {claim:{}},
    view = {checkpointCid:'original-checkpoint'}, continuation = {}, admission = {};
  const counts = {observers:0,probes:0,admissions:0};
  const journal = {
    observeRunCancellation(actual,requestControl,publicationControl,original) {
      assert.strictEqual(actual,ref);assert.strictEqual(requestControl,moon);
      assert.strictEqual(publicationControl,control);assert.strictEqual(original,retained);
      counts.observers++;
      return () => {counts.probes++;return probe();};
    },
    lookupRunDefinition() {assert.fail('A cancellation probe must not reconstruct the admitted Run');},
  };
  const checkpoints = {journal:{admitResume(claim,options) {
    assert.strictEqual(claim,claimed.claim);assert.deepEqual(options,{checkpointCid:view.checkpointCid});
    counts.admissions++;if(admitFailure)throw admitFailure;return admission;
  }}};
  const values = {journal,ref,moon,control,retained,claimed,view,continuation,leaseFailure,checkpoints};
  const resume = new Function(...Object.keys(values),
    `${resumeObservers[0]}; let sourceResume; ${resumeAssignments[0]}; return sourceResume;`)(...Object.values(values));
  return {resume,counts,admission};
}

test('Source resume probes reuse one same-original cancellation observer per flight',()=>{
  let cancelled = false;
  const f = sourceResumeFixture({probe:()=>({cancellationRequested:cancelled})});
  for(let index=0;index<50;index++)assert.strictEqual(f.resume.assertCurrent(),f.admission);
  assert.deepEqual(f.counts,{observers:1,probes:50,admissions:50});
  cancelled = true;
  assert.throws(()=>f.resume.assertCurrent(),{code:'ClientRunCancellationRequested'});
  assert.deepEqual(f.counts,{observers:1,probes:51,admissions:50});
  const next = sourceResumeFixture();next.resume.assertCurrent();
  assert.deepEqual(next.counts,{observers:1,probes:1,admissions:1});
});

test('Source resume cancellation probes preserve lease priority, read failures and current admission refusal',()=>{
  const leaseFailure = new Error('OriginalLeaseFailure');
  const lease = sourceResumeFixture({leaseFailure});
  assert.throws(()=>lease.resume.assertCurrent(),error=>error===leaseFailure);
  assert.deepEqual(lease.counts,{observers:1,probes:0,admissions:0});
  for(const failure of [new Error('OriginalJournalReadFailure'),undefined]) {
    const f = sourceResumeFixture({probe:()=>{throw failure;}});
    let thrown = false;
    try {f.resume.assertCurrent();}catch(error){thrown=true;assert.strictEqual(error,failure);}
    assert.equal(thrown,true);assert.deepEqual(f.counts,{observers:1,probes:1,admissions:0});
  }
  const refusal = Object.assign(new Error('ResumeClaimStale'),{code:'ResumeClaimStale'});
  const current = sourceResumeFixture({admitFailure:refusal});
  assert.throws(()=>current.resume.assertCurrent(),error=>error===refusal);
  assert.deepEqual(current.counts,{observers:1,probes:1,admissions:1});
});

function fixture({change = false, missing = false, conflict = false} = {}) {
  const ref = Object.freeze({namespaceId: 'namespace', authorityScopeCid: 'scope',
    runDefinitionCid: 'run'});
  const moon = {}, control = {runDefinitionRunId: definition => definition.id};
  const counts = {lookup: 0, probe: 0, publish: 0, store: 0, state: 0};
  let selected;
  const journal = {
    lookupRunDefinition(actual, requestControl, publicationControl) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control);
      counts.lookup++;
      return selected = Object.freeze({ref, revision: counts.lookup,
        runDefinition: Object.freeze({id: 'original-run'})});
    },
    observeRunCancellation(actual, requestControl, publicationControl, original) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control);
      assert.strictEqual(original, selected, 'The probe must receive the actual admitted frame');
      return () => {
        counts.probe++;
        return missing ? undefined : {revision: original.revision +
          (change && counts.probe === 1 ? 1 : 0)};
      };
    },
    publishRunState(original, state, requestControl, publicationControl) {
      assert.strictEqual(original, selected); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control); counts.publish++;
      if (conflict && counts.publish === 1) {
        throw Object.assign(new Error('RunStateObservationChanged'), {code: 'RunStateObservationChanged'});
      }
      return JSON.stringify(state);
    },
  };
  const observe = compile('actor', ref.namespaceId, ref.authorityScopeCid, journal,
    moon, control, {async confirmCommittedIndex(actual) {
      assert.strictEqual(actual, ref); counts.store++; return {};
    }}, async () => {counts.state++; return {status: 'succeeded'};},
    async () => {counts.store++; counts.state++; return {status: 'succeeded'};}, {}, undefined,
    {live: () => false}, new Map(), () => assert.fail('No unpublished state'),
    () => assert.fail('No unpublished clock'), () => {},
    code => Object.assign(new Error(code), {code}));
  return {counts, observe, ref, start: () => observe({ref, principalId: 'actor'})};
}

test('Local Run observation reuses its original admission for the post-Store probe', async () => {
  const f = fixture();
  assert.deepEqual(await f.start(), {status: 'succeeded'});
  assert.deepEqual(f.counts, {lookup: 1, probe: 1, publish: 1, store: 1, state: 1});
  await f.start();
  assert.equal(f.counts.lookup, 2, 'A new observation acquires its own current original');
});

test('Local Run observation retries changed control and final publication conflicts', async () => {
  for (const options of [{change: true}, {conflict: true}]) {
    const f = fixture(options);
    assert.deepEqual(await f.start(), {status: 'succeeded'});
    assert.equal(f.counts.lookup, 2); assert.equal(f.counts.probe, 2);
    assert.equal(f.counts.publish, options.change ? 1 : 2);
  }
});

test('Local Run observation preserves missing-row exhaustion and entry denial', async () => {
  const missing = fixture({missing: true});
  await assert.rejects(missing.start, {message: 'RunStateObservationUnstable'});
  assert.equal(missing.counts.lookup, 8); assert.equal(missing.counts.publish, 0);
  const denied = fixture();
  await assert.rejects(() => denied.observe({ref: denied.ref, principalId: 'foreign'}),
    {code: 'RunStateAccessDenied'});
  assert.equal(denied.counts.lookup, 0); assert.equal(denied.counts.store, 0);
});

function selectedPublicationFixture({legacy = false, missing = false, failRead = false,
  denyAt, malformed = false, invalidPort = false} = {}) {
  const cid = digit => 'sha256:' + digit.repeat(64);
  const ref = Object.freeze({namespaceId: 'namespace', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')});
  const entry = Object.freeze({public_index_entry_cid: cid('c'), publication_attempt_cid: cid('d'),
    result_manifest_cid: cid('e'), run_definition_cid: ref.runDefinitionCid});
  const index = Object.freeze({original: 'selected-index'});
  const counts = {probe: 0, indexRead: 0, selected: 0, request: 0, response: 0};
  const store = {
    async confirmCommittedIndex() { counts.probe++; return missing ? undefined : entry; },
    async readPublicationContract(_cid, name) { if (name === 'public_index_entry') { counts.indexRead++; return index; } return {}; },
    async latestRecordContract() { return {}; },
    async observeTrustedClock() { assert.fail('Empty inventory has no retention clock'); },
    async withCommittedResult() { assert.fail('Empty inventory has no Result'); },
    async readCommittedResultRetentionExtension() { assert.fail('Empty inventory has no Result'); },
    ...legacy ? {} : {async readCommittedPublication(key) {
      assert.strictEqual(this, store); assert.deepEqual(key, ref); counts.selected++;
      if (failRead) throw Object.assign(new Error('selected original failed'), {code: 'EIO'});
      return missing ? undefined : malformed === 'null' ? {entry, index: null}
        : malformed ? {entry} : Object.freeze({entry, index});
    }},
  };
  if (invalidPort) store.readCommittedPublication = null;
  const control = {manifestResultNames: () => [], resultReadDefinitionCid() {},
    resultReadRetentionPolicyCid() {}, resultReadAvailability() {}, resultReadExtendedAvailability() {},
    resultRetentionClockContractCid() {}, runDefinitionRunId: () => 'original-run',
    projectCommittedPublicationState(_record, original) { assert.strictEqual(original, index); return 'succeeded'; },
    issueSucceededRunState: () => JSON.stringify({run_id: 'original-run', status: 'succeeded'}),
  };
  const service = runStateAccess.installRunStateService({store, control,
    authority: runStateAccess.installRunStateAuthority({authorizeRunState({stage}) {
      counts[stage]++; return denyAt !== stage;
    }, resultPolicyAvailable: () => true}),
    now: () => '2026-10-22T00:00:00.000Z', limits: {maxWireBytes: 4096, maxNodes: 100, maxDepth: 10}});
  const frame = Object.freeze({ref, revision: 0, resultNames: [], runDefinition: {},
    dispatchReserved: false, physicalStartReserved: false, observedTerminalOutcome: null});
  const journal = {lookupRunDefinition: () => frame, observeRunCancellation: () => () => ({revision: 0}),
    publishRunState: (_original, state) => JSON.stringify(state)};
  // The old strict entry makes this same actual-caller test a useful original
  // counter before the optional observation entry exists. Product has no such fallback.
  const observe = compile('actor', ref.namespaceId, ref.authorityScopeCid, journal, {}, control,
    store, runStateAccess.inspectAuthorizedRunState,
    runStateAccess.observeAuthorizedRunState ?? runStateAccess.inspectAuthorizedRunState,
    service, undefined, {live: () => true}, new Map(), () => ({status: 'running'}),
    () => '2026-10-22T00:00:00.000Z', () => {}, code => Object.assign(new Error(code), {code}));
  return {counts, service, ref, run: () => observe({ref, principalId: 'actor'})};
}

test('selected publication observation acquires its Index once in the actual Local observer', async () => {
  const f = selectedPublicationFixture();
  assert.equal((await f.run()).status, 'succeeded');
  assert.deepEqual(f.counts, {probe: 0, indexRead: 0, selected: 1, request: 1, response: 1});
  await f.run();
  assert.equal(f.counts.selected, 2, 'A distinct public operation acquires a fresh selected original');
});

test('selected publication observation preserves legacy Store reads and authorized absence', async () => {
  const legacy = selectedPublicationFixture({legacy: true});
  assert.equal((await legacy.run()).status, 'succeeded');
  assert.equal(legacy.counts.probe, 1); assert.equal(legacy.counts.indexRead, 1);
  const missing = selectedPublicationFixture({missing: true});
  assert.equal((await missing.run()).status, 'running');
  assert.equal(missing.counts.selected, 1); assert.equal(missing.counts.response, 0);
  await assert.rejects(runStateAccess.inspectAuthorizedRunState(missing.service,
    {indexKey: missing.ref, principalId: 'actor', purpose: 'inspect'}), {code: 'RunStateAccessDenied'});
});

test('selected publication observation never treats denial failure or malformed original as absence', async () => {
  for (const options of [{denyAt: 'request'}, {denyAt: 'response'}, {failRead: true}, {malformed: true}, {malformed: 'null'}]) {
    const f = selectedPublicationFixture(options);
    await assert.rejects(f.run);
    assert.equal(f.counts.probe, 0, 'No fallback physical read after a selected failure');
    assert.equal(f.counts.indexRead, 0, 'An invalid supplied original is not the omitted-port case');
    if (options.denyAt === 'request') assert.equal(f.counts.selected, 0);
  }
  assert.throws(() => selectedPublicationFixture({invalidPort: true}), {code: 'InvalidRunStateService'});
});


test('actual wait borrows one same-Journal frame while fresh SQL and current gates remain live', async t => {
  const {mkdtemp, rm} = await import('node:fs/promises');
  const {tmpdir} = await import('node:os');
  const {join} = await import('node:path');
  const {DatabaseSync} = await import('node:sqlite');
  const {openClientRequestJournal} = await import('./client-request-journal.mjs');
  const {runtimeCore} = await import('../host-common/runtime-core.mjs');
  const {issueUpdateTargetInstallation, createUpdateTargetOriginalShapeControl} =
    await import('./update-target-original-shape.mjs');
  const {issueInstalledUnpublishedRunState, installedRunWaitDecision} =
    await import('../host-common/run-state-observation.mjs');
  const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ??
    new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
  const control = runtimeCore(moon).publicationControl, cid = digit => 'sha256:' + digit.repeat(64);
  const path = await mkdtemp(join(tmpdir(), 'actql-wait-frame-'));
  let journal;
  t.after(async () => {journal?.close(); await rm(path, {recursive:true});});
  const identity = moon.clientRequestAdmitRecord(cid('a'), 'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52', cid('b'),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert(identity);
  const definition = control.seal('run_definition', JSON.stringify({version:'actql-run-definition/0.1',
    scope_id:'original-scope', run_id:'original-run', compiled_plan_cid:cid('1'),
    invocation_template_cid:cid('2'), authorization_context_cid:cid('3'), input_artifact_set_cid:cid('4'),
    created_at:'2026-10-16T00:00:00.000Z', valid_until:'2098-01-01T00:00:00.000Z'}),
    {maxWireBytes:65536,maxNodes:4096,maxDepth:64});
  const installation = issueUpdateTargetInstallation(moon, {binding_cid:cid('c'), connection:'fixture',
    connector_registration:'update_target_fixture', connector_revision:'update_target_fixture/0.1',
    continuation_binding:cid('e'), runtime_bundle_cid:cid('d'),
    profile:{continuation:'actql-installed-row-effect-continuation/0.1',continuationBinding:'binding_cid',
      dispatch:'actql-installed-row-effect-dispatch/0.1',recovery:'actql-installed-row-effect-recovery/0.1',
      source:'actql-installed-row-effect-source/0.1',targetCheck:'actql-installed-row-effect-check/0.1',
      unit:'actql-installed-row-effect-unit/0.1'}});
  // Metadata DATA fixture: actual Core shape/evidence correspondence, not an
  // admitted UPDATE computation, permission, provider or full Host fixture.
  const evidence = {prepared:'prepared', authorization:'authorized', updateTargetRunOriginal:{
    installations:[installation], materialsWire:JSON.stringify({version:'actql-remote-run-materials/0.1',
      effect_target_selections_json:'[]',prepared_invocation:'prepared',run_authorization:'authorized'})}};
  const originalShape = createUpdateTargetOriginalShapeControl(moon);
  let completedShapes = 0, completedLookups = 0, currentGates = 0, denied = false;
  journal = openClientRequestJournal(path, {updateOriginalControl:{run(...args) {
    const result = originalShape.run(...args); if (result) completedShapes++; return result;
  }}});
  const ref = journal.acceptDefinition(identity,{namespaceId:'namespace',runDefinition:definition,
    lookupExpiresAt:'2099-01-01T00:00:00.000Z',resultNames:['answer'],runAdmissionEvidence:evidence},moon,control).ref;
  const priorFrames = [], frames = [], timers = new Map(); let nextTimer = 0;
  const observedJournal = {...journal, lookupRunDefinition(...args) {
    const result = journal.lookupRunDefinition(...args); completedLookups++;
    priorFrames.push(args[3]); frames.push(result); return result;
  }};
  const compileWait = new Function(...names,'effectResumeFlights','installedRunWaitDecision',
    'setTimeout','clearTimeout', statements[0]+'\n'+waitStatements.join('\n')+';return {wait,observeRun};');
  const owner = compileWait('actor',ref.namespaceId,ref.authorityScopeCid,observedJournal,moon,control,
    {},async()=>assert.fail('No physical index path'),async()=>{
      currentGates++;if(denied)throw Object.assign(new Error('CurrentDeny'),{code:'CurrentDeny'});
      return undefined;
    },{},undefined,{live:()=>true,operation:()=>undefined},new Map(),issueInstalledUnpublishedRunState,
    ()=>'2026-10-16T00:00:00.000Z',()=>{},code=>Object.assign(new Error(code),{code}),
    new Map(),installedRunWaitDecision,(callback,delay)=>{
      assert.equal(delay,100);const id=++nextTimer;timers.set(id,callback);return id;
    },id=>timers.delete(id));
  const flush = async () => {for(let i=0;i<40;i++)await Promise.resolve();};
  const tick = async () => {assert.equal(timers.size,1);const [id,callback]=timers.entries().next().value;
    timers.delete(id);callback();await flush();};
  const abort = new AbortController();
  const flight = owner.wait({ref,principalId:'actor',until:null,since:null,signal:abort.signal});
  const rejection = flight.then(() => assert.fail('Pending wait must not report ready'), error => error);
  try {
    await flush(); completedShapes = 0;
    // First publication may change the exact SQL row. Admit that changed row
    // once, then two unchanged completed polls must not repeat original shape.
    await tick(); const baseline = completedShapes;
    await tick(); await tick();
    console.log('ACTQL_WAIT_FRAME_WORK '+JSON.stringify({completedLookups,currentGates,
      shapeChecksAfterChangedPublication:completedShapes-baseline}));
    assert.equal(completedLookups,4);assert.equal(currentGates,4);
    assert.equal(completedShapes-baseline,0);
    assert.strictEqual(priorFrames[0],undefined);
    assert.strictEqual(frames[2],priorFrames[2]);assert.strictEqual(frames[3],priorFrames[3]);
    const writer = new DatabaseSync(join(path,'client-requests.sqlite3'));
    try {writer.prepare('UPDATE client_requests SET lookup_expires_at=?').run('2099-02-01T00:00:00.000Z');}
    finally {writer.close();}
    await tick();assert.equal(completedShapes,baseline+1,'Changed bytes without revision require full admission');
    denied=true;await tick();assert.equal((await rejection).code,'CurrentDeny');assert.equal(timers.size,0);
    denied=false;const nextAbort=new AbortController();
    const next=owner.wait({ref,principalId:'actor',until:null,since:null,signal:nextAbort.signal});
    const stopped=assert.rejects(next,{code:'WaitAborted'});await flush();
    assert.strictEqual(priorFrames.at(-1),undefined,'A distinct wait cannot inherit the prior invocation frame');
    nextAbort.abort();await stopped;
  } finally {abort.abort();await flight.catch(()=>{});}
});
