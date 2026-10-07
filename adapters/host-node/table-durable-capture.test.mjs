// Exercise actual completed computation/capture owners, not a Catalog mock.
// This boundary prepares public installation but is not its packed acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {preparePinnedEffectSourceHoldings} from './effect-input-export.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {issueCompletedEffectfulComputationEvidence,
  storeCompletedRunResultSet, suspendCompletedEffectfulComputation,
  retireCompletedEffectfulCapture} from '../host-common/completed-run-publication.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const childRecovery = `
import fs from 'node:fs';
import * as moon from './_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './adapters/host-common/runtime-core.mjs';
import {openLocalPublicationStore} from './adapters/store-local/publication-store.mjs';
import {recoverCompletedEffectfulComputation, prepareCompletedEffectfulPublication,
  suspendCompletedEffectfulComputation} from './adapters/host-common/completed-run-publication.mjs';
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const control = runtimeCore(moon).publicationControl;
const store = await openLocalPublicationStore({...input.store,
  privateEvidenceKey: Buffer.alloc(32, 4)}, control);
const runDefinition = control.admit('run_definition', input.runWire, input.limits);
const recovered = await recoverCompletedEffectfulComputation({store, control,
  runDefinition, contractLimits: input.limits});
const inventory = prepareCompletedEffectfulPublication({execution: null, store, control,
  storedResults: recovered.storedResults, computation: recovered.computation,
  preview: recovered.preview});
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
  execution: recovered.execution, holdings};
await suspendCompletedEffectfulComputation({execution: null, store, control,
  storedResults: recovered.storedResults, computation: recovered.computation,
  preview: recovered.preview});
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
        connectorRecovery: [], contractLimits: limits};
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
              runWire: context.runDefinition.wire, limits})});
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
