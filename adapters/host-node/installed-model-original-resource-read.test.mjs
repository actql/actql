// Actual installed controller, encrypted Store and checked original Scope.
// Synthetic layout allowances and journal-projected cut DATA are not normal funding,
// a journal current-cut grant, public INFER or a real Provider execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp} from 'node:fs/promises';
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

async function originalFixture(t) {
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
  const cp = selectedCp = await installRemoteCheckpoints({root, namespaceId: 'scope',
    authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
    realizationKey: 'source-free-values', environmentCid: cid('4'), contractControl: control,
    modelResumeVerifier: controller.verifier,
    authorization: {resumeAfterAnswer: false,
      accountConfiguration: canonicalText({version: 'actql-execution-account-config/0.1', account_id: 'local', entries: []}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: 'reviewer',
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}});
  t.after(() => cp.close());
  t.diagnostic(`Original installed Store retained at ${root}`);
  const abort = new AbortController();
  const f = await currentResourceFixture(moon, control, 'installed-resource', {signal: abort.signal, metadataAcquisition: {
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
    const result = originalExec.call(this, sql, ...args);
    if (sql === 'COMMIT') {commits++; throw Error('OriginalInvalidationCommitResponseLost');}
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
