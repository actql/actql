import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import * as runStateAccess from '../host-common/run-state-access.mjs';

// Execute the actual Local observation statement with explicit owner ports.
// These caller tests do not instantiate a full Host or Common runtime.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const statements = [];
const resumeObservers = [], resumeAssignments = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
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
