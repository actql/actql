// Actual installed controller, encrypted Store and checked original Scope.
// Synthetic layout allowances and journal-projected cut DATA are not normal funding,
// a journal current-cut grant, public INFER or a real Provider execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {admitInstalledModelProviderBinding} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const digest = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;

async function originalFixture(t, {unretained=false, retainState,
  storeBootstrap={maxWireBytes: 4096, maxDirectoryEntries: 22}, currentStateCodec=codec()}={}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-original-resource-'));
  const control = runtimeCore(moon).publicationControl;
  const keys = generateKeyPairSync('ed25519');
  const account = moon.executionAuthorizationAdmit(canonicalText({
    version: 'actql-execution-account-config/0.1', account_id: 'local',
    entries: [{entry_id: 'model', outcome: 'allow', principal: {any_of: ['owner']},
      connection: {any_of: ['models/fixture']}, resource: {all: true},
      operation: {any_of: ['infer']}, exclusions: []}]}));
  let selectedCp;
  const controller = await installNodeModelContinuation({moon, control,
    namespaceId: 'scope', authorityScopeCid: cid('3'),
    now: () => '2026-10-12T00:00:00.000Z', getCheckpoints: () => selectedCp});
  const actualCp = await installRemoteCheckpoints({root, namespaceId: 'scope',
    authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
    realizationKey: 'source-free-values', environmentCid: cid('4'), contractControl: control,
    modelResumeVerifier: controller.verifier,
    authorization: {resumeAfterAnswer: false,
      accountConfiguration: canonicalText({version: 'actql-execution-account-config/0.1', account_id: 'local', entries: []}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: 'reviewer',
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}});
  const retains = [], selectedRetains = [];
  // Physical instrumentation only: the same actual CP/Store still admits,
  // saves and verifies bytes. This wrapper issues no receipt of its own.
  const cp = selectedCp = Object.freeze({...actualCp,
    async retainOriginalModelState(args) {
      retains.push(args);
      return retainState === undefined ? actualCp.retainOriginalModelState(args)
        : retainState(args, actualCp);
    },
    async retainOriginalModelStateSelected(args, acquisition) {
      retains.push(args);
      selectedRetains.push(acquisition);
      return retainState === undefined ? actualCp.retainOriginalModelStateSelected(args, acquisition)
        : retainState(args, actualCp, acquisition);
    }});
  let closeFlight;
  const closeFixture = () => closeFlight ??= cp.close();
  t.after(closeFixture);
  t.diagnostic(`Original installed Store retained at ${root}`);
  const abort = new AbortController();
  const f = await currentResourceFixture(moon, control, 'installed-resource', {signal: abort.signal,
    // Independent fresh fixture: root18 + input/state objects2 + holdings2.
    // This Store acquisition clamp is not a normal numerical capacity grant.
    storeBootstrap, currentStateCodec, metadataAcquisition: {
    metadata: {maxWireBytes: 4096, maxLedgerEntries: 4},
    directory: {maxWireBytes: 1024, maxDirectoryEntries: 8},
    retainedBytes: 7000n, workspaceBytes: 3000n}});
  const providerBinding = admitInstalledModelProviderBinding(moon, 'models/fixture', {
    bindingOriginals: providerBindingOriginals('models/fixture', {selector: 'fixture-risk-model'})});
  const opened = await controller.open({operation: f.operation, preparedCallSet: f.preparedCallSet,
    originalPreparation: f.originalPreparation, plan: {compiled: f.compiled, runDefinition: f.runDefinition},
    selected: {graph: f.graph, step: f.step, providerBinding, observeAccount: () => account},
    principalId: 'owner', declaredResults: ['answer'], submission: {fixture: 'selected-read'}});
  assert.equal(opened.token.available, true);
  assert.equal(cp.journal.getRunState('installed-resource'), undefined);
  cp.journal.registerImmediateModelCallSet({modelCallSet: opened.originals,
    declaredResults: ['answer']});
  const journalPort = opened.originalJournalInstallation();
  assert.strictEqual(cp.journal.originalModelJournalPortCurrent(journalPort), journalPort);
  const observation = cp.journal.observeOriginalModelJournal(opened.inventory);
  const journalFacts = cp.journal.originalModelJournalObservationFacts(observation);
  const cut = controller.verifier.projectOriginalCurrentCut({facts: journalFacts});
  assert.equal(cut.scope_cid, opened.scope.identity);
  assert.equal(cut.fixed_input_receipt_cid, opened.token.receipt.cid);
  // The independent generated Program authors one row, id=a/text=hello.
  // prepared_rows=2 is a synthetic capacity ceiling, not an observed count.
  assert.deepEqual(cut.slots.map(slot => slot.state), ['Unsent']);
  const storageBinding = await cp.observeModelOriginalStorageBinding();
  const origin = await opened.originalResourceOrigin(storageBinding);
  if (unretained) return {root, cp, actualCp, closeFixture, selectedCp: value => {selectedCp = value;},
    controller, f, opened, storageBinding, origin, observation, abort, retains, selectedRetains};
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const writer = f.operation.prepareOriginalCurrentStateWriter(park,
    {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20});
  assert.equal(f.operation.advanceOriginalCurrentStateWriter(park, writer, 19).kind, 'complete');
  const stateWire = f.operation.finishOriginalCurrentStateWriter(park, writer);
  const bodyWire = canonicalText({version: 'actql-model-original-resource-state/0.1',
    origin, resource_state: JSON.parse(stateWire), resource_state_cid: digest(stateWire),
    resource_phase: 'parked', cut});
  const receipt = await cp.retainOriginalModelState({runDefinition: f.runDefinition,
    storageBinding, bodyWire});
  return {cp, selectedCp: value => {selectedCp = value;}, controller, f, opened, park,
    storageBinding, receipt, bodyWire, observation, abort};
}

const codec = () => ({quantum: 1, comparisonWork: 5,
  decode: {maxWork: 20000,
    parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
    tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000}}});

test('original dispatch caller completes actual save COMMIT and fence consume once without a Model send grant', async t=>{
  const {root,cp,f,opened,retains,selectedRetains}=await originalFixture(t,{unretained:true});
  const first=opened.prepareOriginalResourcesForDispatch();
  assert.strictEqual(opened.prepareOriginalResourcesForDispatch(),first);
  await first;
  assert.equal(retains.length,1);
  assert.equal(selectedRetains.length,1,'first dispatch must use selected save, not ordinary Evidence');
  assert.equal(selectedRetains[0]?.kind,'original-infer-metadata-acquisition');
  assert.deepEqual(await originalFixtureStoreInventory(root),{root:18,objects:2,holdings:2,total:22});
  assert.deepEqual(JSON.parse(retains[0].bodyWire).cut.slots.map(slot=>slot.state),['Unsent']);
  assert.equal(cp.journal.readModelCalls(opened.inventory).slots[0].state,'Unsent');
  assert.strictEqual(opened.prepareOriginalResourcesForDispatch(),first);
  assert.equal(f.sends(),0);
});

test('original dispatch caller retains failed physical save and does not repeat park or Store send', async t=>{
  const issue=Object.assign(new Error('OriginalStoreResponseLost'),{code:'OriginalStoreResponseLost'});
  const {root,cp,f,opened,retains}=await originalFixture(t,{unretained:true,
    async retainState(args,actual,acquisition){
      await actual.retainOriginalModelStateSelected(args,acquisition);throw issue;}});
  const first=opened.prepareOriginalResourcesForDispatch();
  await assert.rejects(first,error=>error===issue);
  assert.strictEqual(opened.prepareOriginalResourcesForDispatch(),first);
  assert.equal(retains.length,1);
  assert.deepEqual(await originalFixtureStoreInventory(root),{root:18,objects:2,holdings:2,total:22});
  assert.equal(cp.journal.readModelCalls(opened.inventory).slots[0].state,'Unsent');
  assert.equal(opened.close(),false);
  assert.equal(opened.token.available,true);
  assert.equal(f.sends(),0);
});

test('original dispatch caller preserves exact opening refusal after real save with no COMMIT or resend', async t=>{
  const {root,cp,f,opened,retains}=await originalFixture(t,{unretained:true,
    storeBootstrap:{maxWireBytes:4096,maxDirectoryEntries:21}});
  const first=opened.prepareOriginalResourcesForDispatch();
  await assert.rejects(first,{code:'PublicationStoreBootstrapEntriesLimit'});
  assert.strictEqual(opened.prepareOriginalResourcesForDispatch(),first);
  assert.equal(retains.length,1);
  assert.deepEqual(await originalFixtureStoreInventory(root),{root:18,objects:2,holdings:2,total:22});
  assert.equal(cp.journal.readModelCalls(opened.inventory).slots[0].state,'Unsent');
  assert.equal(opened.close(),false);
  assert.equal(f.sends(),0);
});

test('original dispatch caller keeps actual invalidation COMMIT loss parked and never blindly repeats',async t=>{
  const {cp,f,opened,retains}=await originalFixture(t,{unretained:true});
  const originalExec=DatabaseSync.prototype.exec;
  let linked=false,losses=0;
  DatabaseSync.prototype.exec=function(sql,...args){
    const cut=sql==='COMMIT'?this.prepare(
      'SELECT current_cut_link_json FROM resume_model_scopes WHERE scope_cid = ?')
      .get(opened.inventory.scopeCid)?.current_cut_link_json:undefined;
    const result=originalExec.call(this,sql,...args);
    if(cut!==undefined&&cut!==null)linked=true;
    else if(sql==='COMMIT'&&linked&&cut===null){losses++;throw Error('OriginalInvalidationCommitResponseLost');}
    return result;
  };
  let first;
  try {
    first=opened.prepareOriginalResourcesForDispatch();
    await assert.rejects(first,error=>error.code==='CheckpointJournalCommitOutcomeUnknown'&&error.outcome==='unknown');
  } finally {DatabaseSync.prototype.exec=originalExec;}
  assert.equal(linked,true);assert.equal(losses,1);
  assert.strictEqual(opened.prepareOriginalResourcesForDispatch(),first);
  assert.equal(retains.length,1);
  assert.equal(opened.close(),false);
  assert.equal(opened.cleanupPending(),true);
  assert.equal(opened.token.available,true);
  assert.equal(cp.journal.readModelCalls(opened.inventory).slots[0].state,'Unsent');
  assert.equal(f.sends(),0);
});

test('original save caller uses Common Writer envelope then actual Store ACK and same journal COMMIT', async t => {
  const {root, cp, closeFixture, controller, f, opened, storageBinding, origin, retains} =
    await originalFixture(t, {unretained: true});
  assert.deepEqual(await originalFixtureStoreInventory(root), {root: 18, objects: 1, holdings: 1, total: 20});
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const selectedCodec = codec(), originWire = canonicalText(origin);
  const promise = opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec);
  assert.strictEqual(opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec), promise);
  assert.throws(() => opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, codec()),
    {code: 'ModelOriginalCurrentCutBindingMismatch'});
  selectedCodec.quantum = 0;
  selectedCodec.decode.maxWork = 0;
  const saved = await promise;
  assert.deepEqual(await originalFixtureStoreInventory(root), {root: 18, objects: 2, holdings: 2, total: 22});
  assert.ok(Object.isFrozen(saved));
  assert.strictEqual(saved.park, park);
  assert.equal(retains.length, 1);
  const body = JSON.parse(retains[0].bodyWire);
  assert.deepEqual(body.origin, origin);
  assert.equal(body.resource_state_cid, digest(canonicalText(body.resource_state)));
  assert.equal(body.resource_phase, 'parked');
  assert.deepEqual(body.cut.slots.map(slot => slot.state), ['Unsent']);
  const actual = await opened.readOriginalResourceState(park, storageBinding, saved.receipt);
  assert.equal(actual.wire, retains[0].bodyWire);
  assert.strictEqual(controller.verifier.originalResourceCut.current(park), park);
  cp.journal.commitOriginalModelCurrentCut(saved.reference);
  const request = opened.beginOriginalResourceInvalidation(saved.reference, park);
  assert.strictEqual(controller.verifier.originalResourceCut.invalidationCurrent(request, park), request);
  opened.completeOriginalResourceInvalidation();
  assert.equal(cp.journal.originalModelCurrentCutOperationStatus(saved.reference).state, 'invalidated');
  assert.equal(f.operation.originalResourceParkCurrent(park), undefined);
  assert.equal(f.sends(), 0);
  assert.equal(retains.length, 1);
  assert.throws(() => opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec),
    {code: 'ModelOriginalResourceReadUnavailable'});
  await closeFixture();
  assert.deepEqual(await originalFixtureStoreInventory(root), {root: 18, objects: 2, holdings: 2, total: 22});
});

// Test observation only, not a production acquisition or capacity supplier.
// The independent expected layout is fixed; extra records must not silently
// become part of a changed expected count or an enlarged positive ceiling.
async function originalFixtureStoreInventory(root) {
  const store = join(root, 'checkpoints', 'private-store');
  const expected = ['attempts', 'clocks', 'contracts', 'deletions', 'deliveries',
    'effect-capture-custody', 'indexes', 'manifest-reads', 'metadata-deletions',
    'metadata-inventories', 'objects', 'physical-holding-deletions', 'physical-holdings',
    'prepared-custody', 'prepared-schemas', 'retention-extensions', 'staging', 'store.json'];
  const names = (await readdir(store)).sort();
  assert.deepEqual(names, expected);
  for (const name of expected.filter(name => !['store.json', 'objects', 'physical-holdings'].includes(name))) {
    assert.deepEqual(await readdir(join(store, name)), []);
  }
  const objects = (await readdir(join(store, 'objects'))).length;
  const holdings = (await readdir(join(store, 'physical-holdings'))).length;
  return {root: names.length, objects, holdings, total: names.length + objects + holdings};
}

test('original save caller preserves lost Store response and never blindly saves or unpark retries', async t => {
  let historicalReceipt;
  const {cp, f, opened, storageBinding, origin, retains} = await originalFixture(t,
    {unretained: true, async retainState(args, actual, acquisition) {
      historicalReceipt = await actual.retainOriginalModelStateSelected(args, acquisition);
      throw Object.assign(Error('OriginalStoreResponseLost'), {code: 'OriginalStoreResponseLost'});
    }});
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const selectedCodec = codec(), originWire = canonicalText(origin);
  const promise = opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec);
  await assert.rejects(promise, {code: 'OriginalStoreResponseLost'});
  assert.strictEqual(opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec), promise);
  await assert.rejects(promise, {code: 'OriginalStoreResponseLost'});
  assert.equal(retains.length, 1);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(opened.token.available, true);
  const actual = await cp.readOriginalModelState({runDefinition: f.runDefinition,
    storageBinding, receipt: historicalReceipt});
  assert.equal(actual.wire, retains[0].bodyWire);
  assert.equal(f.sends(), 0);
  assert.equal(opened.close(), false);
  assert.equal(opened.token.available, true);
});

test('original save caller preserves explicit eight and one-short21 Store refusals without a cut or unpark', async t => {
  for (const entries of [8, 21]) {
    const {root, f, opened, storageBinding, origin, retains} = await originalFixture(t,
      {unretained: true, storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: entries}});
    assert.deepEqual(await originalFixtureStoreInventory(root), {root: 18, objects: 1, holdings: 1, total: 20});
    const park = f.operation.parkOriginalResourcesForStateWrite();
    const selectedCodec = codec(), originWire = canonicalText(origin);
    const promise = opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec);
    await assert.rejects(promise, {code: 'PublicationStoreBootstrapEntriesLimit'});
    assert.strictEqual(opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec), promise);
    assert.equal(retains.length, 1, 'one selected save call; an opening refusal never retries it');
    // With selected write acquisition, eight refuses the first Store opening
    // before any new object. Twenty-one admits the original20, saves the new
    // object/holding, then refuses the exact22 readback. Do not confuse the
    // different physical stages or widen either independent fixture ceiling.
    assert.deepEqual(await originalFixtureStoreInventory(root), entries === 8
      ? {root: 18, objects: 1, holdings: 1, total: 20}
      : {root: 18, objects: 2, holdings: 2, total: 22});
    assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
    assert.equal(opened.token.available, true);
    assert.equal(opened.close(), false);
    assert.equal(opened.token.available, true);
    assert.equal(f.sends(), 0);
  }
});

test('original save caller holds pending Store responsibility across close and cancellation', async t => {
  let proceed;
  const blocked = new Promise(resolve => {proceed = resolve;});
  let markEntered;
  const entered = new Promise(resolve => {markEntered = resolve;});
  let promise;
  // Drain the actual original wait before closing its fixture Host, including
  // a failed assertion. The focused wrapper retains the same child30 budget.
  t.after(async () => {proceed(); if (promise !== undefined) await promise.catch(() => {});});
  let savedReceipt;
  const {cp, f, opened, storageBinding, origin, retains, abort} = await originalFixture(t,
    {unretained: true, async retainState(args, actual, acquisition) {
      // Block the response after the actual selected write/recheck. Blocking
      // before write and then bypassing currentness with ordinary save would
      // not exercise a historical saved result arriving after cancellation.
      savedReceipt = await actual.retainOriginalModelStateSelected(args, acquisition);
      markEntered();
      await blocked;
      return savedReceipt;
    }});
  const park = f.operation.parkOriginalResourcesForStateWrite();
  promise = opened.retainOriginalResourceCurrentCut(park, storageBinding, canonicalText(origin), codec());
  // Attach rejection handling immediately; await a real physical boundary,
  // not a scheduling-dependent number of zero-work polls.
  const observed = promise.then(() => undefined, error => error);
  await Promise.race([entered, observed.then(error => {if (error !== undefined) throw error;})]);
  assert.equal(retains.length, 1);
  const stopped = assert.rejects(promise);
  assert.equal(opened.close(), false);
  assert.equal(opened.cleanupPending(), true);
  assert.equal(opened.token.available, true);
  abort.abort();
  assert.equal(f.sends(), 0);
  proceed();
  await stopped;
  assert.equal(retains.length, 1);
  // A save may finish after stop. It remains historical custody, never proof
  // of unsaved data or permission to create another Entry/transport.
  const actual = await cp.readOriginalModelState({runDefinition: f.runDefinition,
    storageBinding, receipt: savedReceipt});
  assert.equal(actual.wire, retains[0].bodyWire);
  assert.equal(opened.close(), false);
  assert.equal(opened.token.available, true);
});

test('original save caller rejects foreign origin and exhausted Writer before Store saving', async t => {
  for (const variant of ['origin', 'writer', 'foreign-park']) {
    const {f, opened, storageBinding, origin, retains} = await originalFixture(t, {unretained: true});
    const park = f.operation.parkOriginalResourcesForStateWrite();
    const selectedCodec = codec();
    if (variant === 'writer') selectedCodec.decode.parse.max_input_bytes = 1;
    const originWire = canonicalText(variant === 'origin' ? {...origin, run_id: 'foreign'} : origin);
    if (variant === 'foreign-park') {
      assert.throws(() => opened.retainOriginalResourceCurrentCut({...park}, storageBinding, originWire, selectedCodec),
        {code: 'ModelOriginalResourceReadUnavailable'});
    } else {
      const promise = opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec);
      await assert.rejects(promise);
      assert.strictEqual(opened.retainOriginalResourceCurrentCut(park, storageBinding, originWire, selectedCodec), promise);
    }
    assert.equal(retains.length, 0);
    assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
    assert.equal(f.sends(), 0);
    assert.equal(opened.token.available, true);
  }
});

test('opened original controller reads only its own selected Scope and fixed actual journal', async t => {
  const {cp, selectedCp, f, opened, park, storageBinding, receipt, bodyWire, observation, abort} =
    await originalFixture(t);
  const document = await opened.readOriginalResourceState(park, storageBinding, receipt);
  assert.equal(document.wire, bodyWire);
  const identity = Object.fromEntries(['runId', 'runDefinitionCid', 'preparedInvocationCid',
    'scopeCid', 'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision']
    .map(field => [field, opened.inventory[field]]));
  const saved = await opened.confirmOriginalResourceStateSaved(park, storageBinding, receipt);
  assert.strictEqual(await opened.confirmOriginalResourceStateSaved(park, storageBinding, receipt), saved);
  assert.deepEqual(cp.originalModelStateSavedFacts(saved).identity, identity);
  assert.equal(cp.originalModelStateSavedFacts(saved).documentWire, bodyWire);
  assert.strictEqual(cp.journal.reconfirmOriginalModelJournal(observation), observation);
  // Actual Store ACK and actual journal data still cannot fabricate a missing
  // nominal Resource-cut issuer or a COMMIT/invalidation grant.
  assert.throws(() => cp.journal.prepareOriginalModelCurrentCut(observation,
    {parkReceipt: park, savedReceipt: saved}),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  await assert.rejects(opened.readOriginalResourceState({...park}, storageBinding, receipt),
    {code: 'ModelOriginalResourceReadUnavailable'});
  await assert.rejects(opened.confirmOriginalResourceStateSaved({...park}, storageBinding, receipt),
    {code: 'ModelOriginalResourceReadUnavailable'});
  selectedCp({...cp});
  await assert.rejects(opened.readOriginalResourceState(park, storageBinding, receipt),
    {code: 'InstalledModelJournalChanged'});
  selectedCp(cp);
  const pendingRead = opened.readOriginalResourceState(park, storageBinding, receipt);
  selectedCp({...cp});
  await assert.rejects(pendingRead, {code: 'InstalledModelJournalChanged'});
  selectedCp(cp);
  const pendingSaved = opened.confirmOriginalResourceStateSaved(park, storageBinding, receipt);
  selectedCp({...cp});
  await assert.rejects(pendingSaved, {code: 'InstalledModelJournalChanged'});
  selectedCp(cp);
  const stoppedSaved = opened.confirmOriginalResourceStateSaved(park, storageBinding, receipt);
  abort.abort(new Error('OriginalMetadataReadStopped'));
  await assert.rejects(stoppedSaved, {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  // Abort refuses new metadata acquisition; it does not prove physical stop,
  // terminal cancellation, reclaimed park or loss of a historical Store ACK.
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(opened.close(), false);
  assert.equal(opened.cleanupPending(), true);
  assert.equal(opened.token.available, true);
  await assert.rejects(opened.readOriginalResourceState(park, storageBinding, receipt),
    {code: 'ModelOriginalResourceReadUnavailable'});
  await assert.rejects(opened.confirmOriginalResourceStateSaved(park, storageBinding, receipt),
    {code: 'ModelOriginalResourceReadUnavailable'});
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.strictEqual(cp.originalModelStateSavedObservationCurrent(saved), saved);
  assert.equal(cp.originalModelStateSavedFacts(saved).documentWire, bodyWire);
  assert.equal(f.sends(), 0);
});

test('actual original Resource match and Store ACK bind same-journal COMMIT then consume once', async t => {
  const {cp, controller, f, opened, park, storageBinding, receipt} = await originalFixture(t);
  const selectedCodec = codec();
  const pending = opened.prepareOriginalResourceCurrentCut(park, storageBinding, receipt, selectedCodec);
  assert.strictEqual(opened.prepareOriginalResourceCurrentCut(park, storageBinding, receipt, selectedCodec), pending);
  // The private limit snapshot is immutable even if its original DATA changes
  // during physical Store awaits; it is not a replacement capacity grant.
  selectedCodec.quantum = 0;
  selectedCodec.decode.maxWork = 0;
  const reference = await pending;
  const facts = controller.verifier.originalResourceCut.inspect(park);
  assert.ok(Object.isFrozen(facts));
  assert.equal(facts.identity.scopeCid, opened.scope.identity);
  assert.equal(facts.phase, 'parked');
  assert.strictEqual(controller.verifier.originalResourceCut.current(park), park);
  assert.throws(() => controller.verifier.originalResourceCut.inspect({...park}),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.strictEqual(cp.journal.commitOriginalModelCurrentCut(reference), reference);
  const request = opened.beginOriginalResourceInvalidation(reference, park);
  assert.strictEqual(controller.verifier.originalResourceCut.invalidationCurrent(request, park), request);
  const invalidation = opened.completeOriginalResourceInvalidation();
  assert.equal(cp.journal.originalModelCurrentCutOperationStatus(reference).state, 'invalidated');
  assert.equal(f.operation.originalResourceParkCurrent(park), undefined);
  assert.equal(controller.verifier.originalResourceCut.current(park), undefined);
  assert.throws(() => opened.completeOriginalResourceInvalidation(),
    {code: 'ModelOriginalResourceInvalidationUnavailable'});
  assert.ok(Object.isFrozen(invalidation));
  assert.equal(f.sends(), 0);
});

test('actual lost invalidation COMMIT preserves original park and matched custody with no blind retry', async t => {
  const {cp, controller, f, opened, park, storageBinding, receipt} = await originalFixture(t);
  const reference = await opened.prepareOriginalResourceCurrentCut(park, storageBinding, receipt, codec());
  cp.journal.commitOriginalModelCurrentCut(reference);
  const request = opened.beginOriginalResourceInvalidation(reference, park);
  const originalExec = DatabaseSync.prototype.exec;
  let commits = 0;
  DatabaseSync.prototype.exec = function(sql, ...args) {
    // Installation/currentness performs earlier read-only transactions. Lose
    // only the COMMIT of THIS exact scope's actual successful invalidation CAS,
    // not a preceding observation's COMMIT or a foreign transaction.
    const invalidating = sql === 'COMMIT' && this.prepare(
      'SELECT current_cut_link_json FROM resume_model_scopes WHERE scope_cid = ?')
      .get(opened.inventory.scopeCid)?.current_cut_link_json === null;
    const result = originalExec.call(this, sql, ...args);
    if (invalidating) {commits++; throw Error('OriginalInvalidationCommitResponseLost');}
    return result;
  };
  try {
    assert.throws(() => opened.completeOriginalResourceInvalidation(),
      error => error.code === 'CheckpointJournalCommitOutcomeUnknown' && error.outcome === 'unknown');
  } finally {DatabaseSync.prototype.exec = originalExec;}
  assert.equal(commits, 1);
  assert.equal(cp.journal.originalModelCurrentCutOperationStatus(reference).state, 'unknown');
  assert.strictEqual(controller.verifier.originalResourceCut.current(park), park);
  assert.strictEqual(controller.verifier.originalResourceCut.invalidationCurrent(request, park), request);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.throws(() => opened.completeOriginalResourceInvalidation(),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.equal(opened.close(), false);
  assert.equal(opened.cleanupPending(), true);
  assert.equal(opened.token.available, true);
  assert.strictEqual(controller.verifier.originalResourceCut.current(park), park);
  assert.equal(f.sends(), 0);
});
