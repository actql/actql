// Exercise actual completed computation/capture owners, not a Catalog mock.
// This boundary prepares public installation but is not its packed acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {preparePinnedEffectSourceHoldings} from './effect-input-export.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {capturedTableRecoveryRecord} from './table-capture-recovery.mjs';
import {issueCompletedEffectfulComputationEvidence,
  storeCompletedRunResultSet, suspendCompletedEffectfulComputation,
  retireCompletedEffectfulCapture} from '../host-common/completed-run-publication.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
// Independent receipt-shaped content exercises projection only. No Catalog
// commit is performed or inferred by these capture/recovery tests.
function receiptFixture(operation, rowCount) {
  const body = {version: 'actql-table-receipt/0.1',
    request_cid: operation.request_cid, effect_identity_cid: operation.effect_identity_cid,
    catalog_identity_cid: operation.catalog_identity_cid, schema_cid: operation.schema_cid,
    storage_mapping_cid: operation.storage_mapping_cid,
    table_uuid: '11111111-2222-3333-4444-555555555555', generation_cid: cid('b'),
    metadata_location: 'file:///table/generation.json', snapshot_id: rowCount ? '123' : null,
    row_count: rowCount};
  const receipt = {...body, receipt_cid: `sha256:${createHash('sha256')
    .update(canonicalJson(body, {dataKeys: true})).digest('hex')}`};
  return {response: canonicalJson({ok: true, result: receipt}, {dataKeys: true}),
    outcome: canonicalJson({state: 'applied', result: receipt}, {dataKeys: true})};
}
const childRecovery = `
import fs from 'node:fs';
import assert from 'node:assert/strict';
import * as moon from './_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './adapters/host-common/runtime-core.mjs';
import {openLocalPublicationStore} from './adapters/store-local/publication-store.mjs';
import {recoverCompletedEffectfulComputation, prepareCompletedEffectfulPublication,
  suspendCompletedEffectfulComputation} from './adapters/host-common/completed-run-publication.mjs';
import {prepareRecoveredTableInput, readRecoveredTableInput}
  from './adapters/host-node/table-capture-recovery.mjs';
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const control = runtimeCore(moon).publicationControl;
const physicalStore = await openLocalPublicationStore({...input.store,
  privateEvidenceKey: Buffer.alloc(32, 4)}, control);
let interruptInspection, reads = 0;
// The wrapper only schedules a real owner release at an existing Store await.
// All capture, inspection and physical read operations use the actual Store.
const store = Object.freeze({...physicalStore,
  async inspectPhysicalHolding(holdingCid) {
    const holding = await physicalStore.inspectPhysicalHolding(holdingCid);
    await interruptInspection?.(holdingCid);
    return holding;
  },
  consumePhysicalHolding(...args) {
    reads++;
    return physicalStore.consumePhysicalHolding(...args);
  }});
const runDefinition = control.admit('run_definition', input.runWire, input.limits);
const recovered = await recoverCompletedEffectfulComputation({store, control,
  runDefinition, contractLimits: input.limits});
const inventory = prepareCompletedEffectfulPublication({execution: null, store, control,
  storedResults: recovered.storedResults, computation: recovered.computation,
  preview: recovered.preview});
const effect = runtimeCore(moon).effectApplicationControl;
const scope = effect.logicalRequestScope('sha256:' + 'e'.repeat(64), 'table-bind', 128);
const options = {recovered, store, control, memberIndex: 0, requestScope: scope,
  contractLimits: input.limits, tableLimits: input.tableLimits};
const table = await prepareRecoveredTableInput(options);
const tableRows = await readRecoveredTableInput({prepared: table, maxBytes: 100000});
const tableBinding = control.tablePreviewLedgerBinding(table.tablePreview);
assert.equal(control.tablePreviewCommitOutcome(table.tablePreview,
  input.receipt.response, 200, input.tableLimits), input.receipt.outcome);
assert.throws(() => control.tablePreviewCommitOutcome(table.tablePreview,
  input.foreignRowCount.response, 200, input.tableLimits), {code: 'MoonBitHostFailure'});
assert.throws(() => control.tablePreviewCommitOutcome(table.tablePreview,
  input.receipt.response, 500, input.tableLimits), {code: 'MoonBitHostFailure'});
assert.equal(control.recoveredTablePreviewMatchesSource(table.tablePreview,
  inventory.effectSources[0]), true);
assert.equal(control.recoveredTablePreviewMatchesSource(table.tablePreview,
  inventory.effectSources[1]), false);
assert.throws(() => control.tablePreviewLedgerBinding({...table.tablePreview}), {name: 'TypeError'});
assert.throws(() => control.tablePreviewInputAvailable(table.tablePreview), {name: 'TypeError'});
await assert.rejects(readRecoveredTableInput({prepared: {...table}, maxBytes: 100000}),
  {code: 'ForeignRecoveredTableInput'});
await assert.rejects(prepareRecoveredTableInput({...options, memberIndex: 1}),
  {code: 'MissingTableRecoveryMaterial'});
await assert.rejects(prepareRecoveredTableInput({...options,
  requestScope: effect.logicalRequestScope('sha256:' + 'e'.repeat(64), 'another-request', 128)}),
  {code: 'MoonBitHostFailure'});
const original = recovered.connectorRecovery[0];
const changed = JSON.parse(original.wire);
changed.operation_wire = changed.operation_wire.replace('rows_0', 'another_table');
await assert.rejects(prepareRecoveredTableInput({...options, recovered: {...recovered,
  connectorRecovery: [{...original, wire: JSON.stringify(changed)}]}}),
  {code: 'ForeignTableRecoveryOperation'});
const mapping = JSON.parse(JSON.parse(original.wire).mapping_wire);
mapping.columns[0].value_field_id = 9;
const badMapping = {...JSON.parse(original.wire), mapping_wire: JSON.stringify(mapping)};
await assert.rejects(prepareRecoveredTableInput({...options, recovered: {...recovered,
  connectorRecovery: [{...original, wire: JSON.stringify(badMapping)}]}}),
  {code: 'MoonBitHostFailure'});
const holdings = [];
for (const source of inventory.effectSources) {
  const holdingCid = control.capturedEffectSourceHoldingCid(source);
  const holding = await store.inspectPhysicalHolding(holdingCid);
  const chunks = [];
  await store.consumePhysicalHolding(holdingCid, 0, c => chunks.push(Buffer.from(c)));
  holdings.push({holdingCid, manifestCid: holding.manifest_cid,
    rows: JSON.parse(Buffer.concat(chunks).toString('utf8'))});
}
const result = {captureCid: recovered.computation.capturedRun.identity,
  previewWire: control.effectComputationPreviewWire(recovered.preview),
  execution: recovered.execution, holdings, table: {operationWire: table.operationWire,
    mappingWire: table.mappingWire, subjectCid: table.tablePreview.subjectCid,
    memberIndex: tableBinding.memberIndex, rowPreviewCid: tableBinding.rowPreviewCid,
    rows: tableRows}};
const firstHolding = control.capturedEffectSourceHoldingCid(inventory.effectSources[0]);
let inspected = 0;
const readsBeforeRelease = reads;
interruptInspection = async holdingCid => {
  // The first visit is capture-custody confirmation, the second is the final
  // physical read's inspection. Release there must prevent consuming bytes.
  if (holdingCid !== firstHolding || ++inspected !== 2) return;
  interruptInspection = undefined;
  await suspendCompletedEffectfulComputation({execution: null, store, control,
    storedResults: recovered.storedResults, computation: recovered.computation,
    preview: recovered.preview});
};
await assert.rejects(readRecoveredTableInput({prepared: table, maxBytes: 100000}),
  {code: 'InvalidCompletedEffectfulRunOwner'});
assert.equal(inspected, 2);
assert.equal(reads, readsBeforeRelease);
await assert.rejects(readRecoveredTableInput({prepared: table, maxBytes: 100000}),
  {code: 'InvalidCompletedEffectfulRunOwner'});
// Receipt projection remains immutable after release; it is not availability
// or permission to resend this operation.
assert.equal(control.tablePreviewCommitOutcome(table.tablePreview,
  input.receipt.response, 200, input.tableLimits), input.receipt.outcome);
await store.close();
process.stdout.write(JSON.stringify(result));
`;

for (const empty of [false, true]) {
  test(`Table durable capture restores ${empty ? 'empty' : 'nonempty'} semantic Preview in a new process`,
    async t => exerciseEffectSourceSet(t, {empty, onTablePreview: async f => {
      const control = f.sourceControl;
      const limits = f.options.contractLimits;
      const context = f.options.localEvidenceContext;
      const previewBody = JSON.parse(f.authored._0);
      const authoring = control.admitRunEvidence('authoring_context',
        JSON.stringify(previewBody.authoring_context), limits);
      const preview = control.admitEffectComputationPreview(f.authored._0,
        context.runDefinition, authoring, limits);
      const retained = preparePinnedEffectSourceHoldings({sources: f.sources,
        store: f.store, control, preview, invocation: context.runInvocation,
        resultArtifacts: f.sources.members.map(({payload}) => payload.localResultArtifact)});
      await retained.commit();
      const storedResults = await storeCompletedRunResultSet({
        // The source-export counter belongs to grouped source preparation.
        // Named Result export is a separate existing owner in the same Store.
        execution: f.execution, store: f.physicalStore, control,
        runDefinition: context.runDefinition, invocation: context.runInvocation,
        results: f.execution.resultInventory.map(() => ({retention: f.options.retention,
          evidenceContext: {computationContractCid: cid('2'), inputRelationCids: [],
            scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'), authorityScopeCid: cid('a')}})),
        outputLimits: f.outputLimits,
        contractLimits: limits,
      });
      const normalizationJournal = control.sealRunEvidence('normalization_journal',
        JSON.stringify({version: 'actql-normalization-journal/0.1',
          rule_catalog_cid: cid('1'), entries: []}), limits);
      const options = {execution: f.execution, store: f.physicalStore, storedResults, control,
        admission: context.admission, runDefinition: context.runDefinition,
        invocation: context.runInvocation, observation: context.observation,
        normalizationJournal, authoringContext: authoring,
        receiptEvidence: {bindings: [], sourceEvidence: [], modelEvidence: [],
          barrierAttemptReceiptCids: []},
        captureEvidence: {pendingSourceStateAdvances: [], modelEvidence: []},
        preview, plans: [], effectSourceHoldings: retained.holdings,
        connectorRecovery: [capturedTableRecoveryRecord({control,
          tableInput: f.tableInput, tablePreview: f.tablePreview})], contractLimits: limits};
      let computation;
      let retirementStore = f.physicalStore;
      let storeClosed = false;
      try {
        assert.notEqual(previewBody.effects[0].result_artifact_cid,
          retained.holdings[0].artifact.identity);
        assert.equal(previewBody.effects[0].result_artifact_cid, f.artifact.identity);
        // A foreign local-evidence token is rejected before capture sync.
        await assert.rejects(issueCompletedEffectfulComputationEvidence({...options,
          effectSourceHoldings: [{...retained.holdings[0], localEvidence:
            {...retained.holdings[0].localEvidence}}, retained.holdings[1]]}),
        {name: 'TypeError'});
        computation = await issueCompletedEffectfulComputationEvidence(options);
        const captured = JSON.parse(computation.capturedRun.wire).effect_context;
        for (const [index, member] of previewBody.effects.entries()) {
          assert.equal(captured.effect_source_holding_cids[member.effect_id],
            retained.holdings[index].holdingCid);
          assert.equal(captured.effect_source_artifacts[member.effect_id].result_artifact_cid,
            retained.holdings[index].artifact.identity);
          assert.equal(captured.effect_source_local_inventory[member.effect_id]
            .artifact.result_artifact_cid, member.result_artifact_cid);
        }
        await suspendCompletedEffectfulComputation({execution: f.execution,
          store: f.physicalStore, storedResults, control, computation, preview});
        for (const payload of f.sources.payloads) await payload.prepared.release();
        await f.store.close();
        storeClosed = true;
        const child = spawnSync(process.execPath, ['--input-type=module', '-e', childRecovery],
          {cwd: new URL('../..', import.meta.url), encoding: 'utf8', timeout: 30000,
            maxBuffer: 1024 * 1024, input: JSON.stringify({
              store: {...f.storeConfiguration, privateEvidenceKey: undefined},
              runWire: context.runDefinition.wire, limits, tableLimits: f.tableLimits,
              receipt: receiptFixture(f.operations[0], empty ? 0 : 2),
              foreignRowCount: receiptFixture(f.operations[0], empty ? 1 : 3)})});
        assert.equal(child.status, 0, child.stderr);
        assert.equal(child.error, undefined);
        const recovered = JSON.parse(child.stdout);
        assert.equal(recovered.execution, null);
        assert.equal(recovered.captureCid, computation.capturedRun.identity);
        assert.equal(recovered.previewWire, f.authored._0);
        assert.deepEqual(recovered.holdings.map(({holdingCid}) => holdingCid),
          retained.holdings.map(holding => holding.holdingCid));
        assert.deepEqual(recovered.holdings.map(({rows}) => rows),
          [empty ? [] : [{id: 1}, {id: 2}], empty ? [] : [{id: 1}, {id: 2}]]);
        assert.deepEqual(recovered.holdings.map(({manifestCid}) => manifestCid),
          retained.holdings.map(holding => holding.artifact.identity));
        assert.deepEqual(recovered.table, {operationWire: f.tableInput.wire,
          mappingWire: f.storage.wire, subjectCid: f.tablePreview.subjectCid,
          memberIndex: 0,
          rowPreviewCid: control.tablePreviewLedgerBinding(f.tablePreview).rowPreviewCid,
          rows: empty ? [] : [{id: 1}, {id: 2}]});
        assert.equal(f.execution.completed.length, 1);
        retirementStore = await openLocalPublicationStore(f.storeConfiguration, control);
        f.replaceStoreForCleanup(retirementStore);
        storeClosed = false;
        await retireCompletedEffectfulCapture({store: retirementStore, control,
          runDefinition: context.runDefinition, contractLimits: limits});
        for (const holding of retained.holdings) {
          assert.equal(await retirementStore.inspectPhysicalHolding(holding.holdingCid), undefined);
        }
      } finally {
        if (storeClosed) {
          retirementStore = await openLocalPublicationStore(f.storeConfiguration, control);
          f.replaceStoreForCleanup(retirementStore);
        }
        if (computation !== undefined) await retireCompletedEffectfulCapture({store: retirementStore,
          control, runDefinition: context.runDefinition, contractLimits: limits});
      }
    }}));
}
