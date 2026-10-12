// Actual encrypted Store + compiled Model/Resource comparison. The layout
// allowances and unlinked cut data are explicit fixtures, not a funded normal
// installation, journal current-cut COMMIT or public INFER acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const digest = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
const originFields = ['run_id', 'run_definition_cid', 'prepared_invocation_cid',
  'host_policy_cid', 'execution_context_cid', 'program_definition_cid',
  'parameter_values_cid', 'barrier_cid', 'runtime_artifact_cid',
  'layout_artifact_cid', 'response_profile_cid', 'storage_binding_cid'];
const decoderLimits = {
  parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
  tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000},
  maxWork: 20000,
};

test('same original encrypted Store bytes pass actual parked origin and Resource census comparison', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-current-resource-store-'));
  const control = runtimeCore(moon).publicationControl;
  const keys = generateKeyPairSync('ed25519');
  const port = await installRemoteCheckpoints({root, namespaceId: 'scope',
    authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
    realizationKey: 'source-free-values', environmentCid: cid('4'), contractControl: control,
    authorization: {resumeAfterAnswer: false,
      accountConfiguration: canonicalText({version: 'actql-execution-account-config/0.1', account_id: 'local', entries: []}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: 'reviewer',
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}});
  // Park remains unresolved: preserve this exact Store/key/ledger as original
  // diagnostic custody, instead of deleting it or claiming successful cleanup.
  t.after(() => port.close());
  t.diagnostic(`Original fixture Store retained at ${root}`);
  const f = await currentResourceFixture(moon, control, 'current-store', {metadataAcquisition: {
    metadata: {maxWireBytes: 2048, maxLedgerEntries: 3},
    directory: {maxWireBytes: 1024, maxDirectoryEntries: 8},
    retainedBytes: 7000n, workspaceBytes: 3000n}});
  const binding = await port.observeModelOriginalStorageBinding();
  const selectedStorage = await port.modelOriginalStorageBindingEvidence(binding);
  const origin = Object.fromEntries(originFields.map(field => [field,
    control.checkedClientInferOriginalResourceOriginField(f.compiled,
      f.runDefinition, f.graph, f.scope, f.selected, selectedStorage, field)]));
  const park = f.operation.parkOriginalResourcesForStateWrite();
  assert.equal(f.operation.originalParkedReadCapacityAvailable(park, 7000n, 3000n), true);
  assert.equal(f.operation.originalParkedReadCapacityAvailable(park, 7001n, 3000n), false);
  assert.equal(f.operation.originalParkedReadCapacityAvailable(park, 7000n, 3001n), false);
  const writer = f.operation.prepareOriginalCurrentStateWriter(park,
    {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20});
  assert.equal(f.operation.advanceOriginalCurrentStateWriter(park, writer, 19).kind, 'complete');
  const stateWire = f.operation.finishOriginalCurrentStateWriter(park, writer);
  // Independent unlinked cut-shaped DATA only. It never enters a journal
  // issuer or supplies originalModelStateSaved/current-cut/restore authority.
  const bodyWire = canonicalText({version: 'actql-model-original-resource-state/0.1',
    origin, resource_state: JSON.parse(stateWire), resource_state_cid: digest(stateWire),
    resource_phase: 'parked', cut: {scope_cid: cid('8'), input_artifact_cid: cid('7'),
      fixed_input_receipt_cid: cid('6'), run_version: 1, continuation: null, slots: []}});
  const receipt = await port.retainOriginalModelState({runDefinition: f.runDefinition,
    storageBinding: binding, bodyWire});
  assert.equal(receipt.cid, digest(bodyWire));
  let inspected = 0;
  const forbidden = {get runDefinition() {inspected++; throw Error('ArgsMustNotBeRead');}};
  for (const fake of [undefined, true, 'sha256:' + '0'.repeat(64), {kind: 'original-infer-metadata-acquisition'}]) {
    await assert.rejects(port.readOriginalModelStateSelected(forbidden, fake),
      {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  }
  assert.equal(inspected, 0);
  const acquisition = f.operation.originalMetadataAcquisition(park);
  const selectedLoaded = await port.readOriginalModelStateSelected({runDefinition: f.runDefinition,
    storageBinding: binding, receipt}, acquisition);
  assert.equal(selectedLoaded.wire, bodyWire);
  // The same real Store issues a historical saved-byte observation. These
  // cut-shaped data identities still confer no actual journal/restore grant.
  const identity = {runId: 'current-store', runDefinitionCid: f.runDefinition.identity,
    preparedInvocationCid: origin.prepared_invocation_cid, scopeCid: cid('8'),
    inputArtifactCid: cid('7'), providerBindingCid: cid('5'), taskIndex: 0, strategyRevision: 0};
  const savedArgs = {runDefinition: f.runDefinition, storageBinding: binding, receipt, identity};
  const saved = await port.confirmOriginalModelStateSavedSelected(savedArgs, acquisition);
  const savedFacts = port.originalModelStateSavedFacts(saved);
  assert.equal(savedFacts.documentWire, bodyWire);
  assert.equal(savedFacts.documentCid, receipt.cid);
  assert.equal(savedFacts.phase, 'parked');
  assert.strictEqual(await port.confirmOriginalModelStateSavedSelected(savedArgs, acquisition), saved);
  assert.strictEqual(await port.confirmOriginalModelStateSaved(savedArgs), saved);
  await assert.rejects(port.confirmOriginalModelStateSavedSelected(savedArgs, {...acquisition}),
    {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  await assert.rejects(port.readOriginalModelStateSelected({runDefinition: f.runDefinition,
    storageBinding: binding, receipt}, {...acquisition}), {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  const loaded = await port.readOriginalModelState({runDefinition: f.runDefinition,
    storageBinding: binding, receipt});
  assert.equal(loaded.wire, bodyWire);
  const currentStorage = await port.modelOriginalStorageBindingEvidence(binding);
  control.checkCheckedClientInferOriginalParkedStorageOrigin(f.compiled, f.runDefinition,
    f.graph, f.scope, park, loaded, f.selected, currentStorage);
  const changed = control.readModelOriginalResourceDocument(canonicalText({
    ...JSON.parse(bodyWire), origin: {...origin, layout_artifact_cid: cid('5')}}),
  {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20});
  assert.throws(() => control.checkCheckedClientInferOriginalParkedStorageOrigin(f.compiled,
    f.runDefinition, f.graph, f.scope, park, changed, f.selected, currentStorage), {code: 'MoonBitHostFailure'});
  assert.throws(() => control.checkCheckedClientInferOriginalParkedStorageOrigin(f.compiled,
    f.runDefinition, f.graph, f.scope, park, {...loaded}, f.selected, currentStorage), TypeError);
  const decoder = f.operation.startOriginalCurrentStateDecode(park, loaded.wire, decoderLimits);
  let document;
  for (let i = 0; i < 20000; i++) {
    const poll = f.operation.advanceOriginalCurrentStateDecode(park, decoder, 1);
    if (poll.kind === 'complete') {document = poll.document; break;}
    assert.equal(poll.kind, 'continue');
  }
  assert.notEqual(document, undefined);
  const comparison = f.operation.startOriginalCurrentStateComparison(park, document, 5);
  assert.equal(f.operation.advanceOriginalCurrentStateComparison(park, comparison, 5).kind, 'complete');
  f.operation.retireOriginalCurrentStateDocument(document);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  assert.equal(f.operation.cleanupPending(), true);
  assert.strictEqual(port.originalModelStateSavedObservationCurrent(saved), saved);
  assert.strictEqual(port.originalModelStateSavedFacts(saved), savedFacts);
  await assert.rejects(port.readOriginalModelStateSelected({runDefinition: f.runDefinition,
    storageBinding: binding, receipt}, acquisition), {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  await assert.rejects(port.confirmOriginalModelStateSavedSelected(savedArgs, acquisition),
    {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  assert.equal(f.sends(), 0);
});
