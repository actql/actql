// Actual checked capture and durable Ledger boundaries; no physical Table I/O.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {preparePinnedEffectSourceHoldings} from './effect-input-export.mjs';
import {completedTableCaptureOptions} from './fixtures/table-completed-capture.mjs';
import {issueCompletedEffectfulComputationEvidence, prepareCompletedEffectfulPublication,
  retireCompletedEffectfulCapture, suspendCompletedEffectfulComputation}
  from '../host-common/completed-run-publication.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';
import {settleSavedTableCommit} from './table-commit-outcome.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const seal = (body, field) => ({...body, [field]: `sha256:${createHash('sha256')
  .update(canonicalJson(body, {dataKeys: true})).digest('hex')}`});

test('Table scope binding rejects foreign Preview keys and standalone saved settlement', async t =>
  exerciseEffectSourceSet(t, {onTablePreview: async f => {
    const {sourceControl: control, effect, tableLimits: limits} = f;
    const foreignScope = effect.logicalRequestScope(cid('e'), 'table-bind-foreign', 128);
    assert.notEqual(effect.logicalRequestScopeCid(foreignScope), effect.logicalRequestScopeCid(f.scope));
    const {request_cid: ignored, ...body} = f.operations[0];
    const operation = seal({...body, logical_request_scope_cid: effect.logicalRequestScopeCid(foreignScope)},
      'request_cid');
    const input = control.bindTableInput(f.prepared, f.inputs, 0, f.artifact,
      f.identity, foreignScope, canonicalJson(operation), limits);
    const draft = structuredClone(f.template);
    draft.effects[0].changes[0].target_row_identity = operation.request_cid;
    draft.effects[0].changes[0].intended_changes.value = operation;
    const original = f.bindPreview(draft, f.scope);
    const foreign = f.bindPreview(draft, foreignScope);
    assert.equal(JSON.parse(original.authored._0).effect_preview_cid,
      JSON.parse(foreign.authored._0).effect_preview_cid);
    assert.notDeepEqual(original.authored._1, foreign.authored._1);
    assert.throws(() => control.bindTablePreview(input, original.captured, 0),
      {code: 'MoonBitHostFailure'});
    const valid = control.bindTablePreview(input, foreign.captured, 0);
    const binding = control.tablePreviewLedgerBinding(valid);
    const member = JSON.parse(original.authored._0).effects[0];
    const key = original.authored._1[0][0];
    const correlation = canonicalJson(operation.request_cid);
    const locator = effect.logicalItemLocator(f.scope, 'table-scope-program', 'unit-1',
      member.effect_id, correlation, 128, 256, 16, 4);
    const basis = effect.ledgerBasis(f.scope, locator, key, cid('6'),
      member.effect_member_preview_cid, member.changes[0].row_preview_cid,
      operation.request_cid, cid('0'), 'unavailable', cid('1'), cid('2'));
    const claim = {scope: f.scope, locator, key, basis,
      intentFingerprintCid: member.changes[0].row_preview_cid,
      canonicalRequestCid: operation.request_cid};
    assert.throws(() => control.admitTablePreviewClaim(valid, claim), {code: 'MoonBitHostFailure'});
    const ledger = openEffectLedger({moon: f.moon, root: join(f.directory, 'table-scope-ledger'),
      authorityScopeCid: cid('e'), callerRequestId: 'table-bind', maxEntryBytes: 8192});
    try {
      const receipt = seal({version: 'actql-table-receipt/0.1',
        request_cid: operation.request_cid, effect_identity_cid: operation.effect_identity_cid,
        catalog_identity_cid: operation.catalog_identity_cid,
        table_uuid: '11111111-2222-3333-4444-555555555555', generation_cid: cid('b'),
        metadata_location: 'file:///table/generation.json', snapshot_id: '123', row_count: 2,
        schema_cid: operation.schema_cid, storage_mapping_cid: operation.storage_mapping_cid}, 'receipt_cid');
      const response = canonicalJson({ok: true, result: receipt}, {dataKeys: true});
      // Retain a matching receipt under A without calling the Table dispatcher.
      // Standalone settlement must still reject typed Preview B, leaving the
      // original response and reconciliation duty untouched, with no outcome.
      await captureClaimedEffectResponse({ledger, claim, requestCid: operation.request_cid,
        execute: async () => ({observation: {useCid: cid('7'), statusCode: 200,
          body: Buffer.from(response)}})});
      assert.equal(control.tablePreviewCommitOutcome(valid, response, 200, limits),
        canonicalJson({state: 'applied', result: receipt}, {dataKeys: true}));
      assert.throws(() => settleSavedTableCommit({control, ledger, tablePreview: valid, claim, limits}),
        {code: 'MoonBitHostFailure'});
      assert.equal(ledger.readClaimedOutcome(claim), undefined);
      assert.equal(ledger.readClaimedResponse(claim).responseBytes.toString('utf8'), response);
    } finally { ledger.close(); }

    const contractLimits = f.options.contractLimits, context = f.options.localEvidenceContext;
    const authoring = control.admitRunEvidence('authoring_context',
      JSON.stringify(JSON.parse(original.authored._0).authoring_context), contractLimits);
    const preview = control.admitEffectComputationPreview(original.authored._0,
      context.runDefinition, authoring, contractLimits);
    const retained = preparePinnedEffectSourceHoldings({sources: f.sources, store: f.store,
      control, preview, invocation: context.runInvocation,
      resultArtifacts: f.sources.members.map(({payload}) => payload.localResultArtifact)});
    await retained.commit();
    const options = await completedTableCaptureOptions({fixture: {...f, authored: original.authored},
      retained, preview, tableInputs: [input], tablePreviews: [valid]});
    let computation;
    try {
      computation = await issueCompletedEffectfulComputationEvidence(options);
      const inventory = prepareCompletedEffectfulPublication({execution: f.execution, store: f.physicalStore,
        control, storedResults: options.storedResults, computation, preview});
      // The real saved capture contains operation B with derived Preview keys A.
      // Its recovery constructor must reject even when given operation scope B;
      // the pre-existing wrong-supplied-scope case alone does not detect this.
      assert.throws(() => control.bindRecoveredTablePreview(inventory.preview, 0,
        inventory.chain.invocation, inventory.effectSources[0], inventory.chain.capturedRun,
        foreignScope, f.storage.wire, f.physicalStore.storeAuthorityCid, contractLimits, limits),
      {code: 'MoonBitHostFailure'});
    } finally {
      if (computation) await suspendCompletedEffectfulComputation({execution: f.execution,
        store: f.physicalStore, storedResults: options.storedResults, control, computation, preview});
      await retireCompletedEffectfulCapture({store: f.physicalStore,
        control, runDefinition: context.runDefinition, contractLimits});
    }
    assert.equal(binding.operationWire, canonicalJson(operation));
  }}));
