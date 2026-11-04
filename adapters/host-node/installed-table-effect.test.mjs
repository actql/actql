// Hook acceptance uses the real checked computation, private capture, Store
// and Ledger. The physical spy proves preparation/recovery sends nothing;
// real Iceberg commits and public installed Host acceptance are separate gates.
import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {createInstalledTableEffect} from './installed-table-effect.mjs';
import {tableFixturePublicationPlan, tableFixtureWriteFootprint} from './fixtures/table-completed-capture.mjs';
import {issueIcebergStorageMapping, admitIcebergStorageMapping, projectIcebergCommitResponse,
  supportsIcebergTableOperation}
  from '../connectors/local/host/iceberg-process.mjs';
import {recoverCompletedEffectfulComputation, suspendCompletedEffectfulComputation,
  releaseCompletedRunPreparedPayloads, retireCompletedEffectfulCapture}
  from '../host-common/completed-run-publication.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const targetRef = 'connector://table/catalog';
const mappingRef = 'mapping:table.catalog.v1';

for (const kind of ['frozen', 'nested', 'primitive']) {
  test(`installed Table preparation retains ${kind} failure and cleanup custody`,
    async t => exerciseEffectSourceSet(t, {target: targetRef, mappingRef,
      minimumApproval: 'required', onCompletedTableRun: async f => {
        const {moon, sourceControl: control} = f;
        let innerPending = true, innerRetries = 0;
        const inner = Object.freeze({status: () => ({pending: innerPending}),
          async retry() { innerRetries++; innerPending = false; }});
        const original = kind === 'primitive' ? 'original preparation failure'
          : Object.freeze(Object.assign(new Error('OriginalTablePreparationFailure'),
            {code: 'OriginalTablePreparationFailure', ...(kind === 'nested'
              ? {cleanupPending: true, cleanupHandle: inner} : {})}));
        const cleanupFailure = new Error('FirstTableCleanupFailure');
        let preparations = 0, cleanupCalls = 0;
        const bridge = {
          supportsOperation: supportsIcebergTableOperation,
          issueStorageMapping: issueIcebergStorageMapping,
          admitStorageMapping: admitIcebergStorageMapping,
          projectCommitResponse: projectIcebergCommitResponse,
          prepareWrite() { if (++preparations === 2) throw original; return Object.freeze({}); },
          status: () => ({attempted: true, stopped: true}),
          async cleanup() {
            cleanupCalls++;
            if (cleanupCalls === 1) throw cleanupFailure;
            return {ok: true, result: {pending: false}};
          },
          execute() { assert.fail('Preparation failure cannot send'); },
          inspect() { assert.fail('Preparation failure cannot inspect'); },
          reconcileOperation() { assert.fail('Preparation failure cannot reconcile'); },
        };
        const factory = await createInstalledTableEffect({moon, environmentWire: '{}',
          connectorId: 'table', connectorRegistration: 'table', connectorRevision: 'table/0.1',
          connection: 'table', runtimeBundleCid: cid('8'), bindingCid: cid('9'), catalogCid: cid('3'),
          targets: ['first', 'second'].map((effectId, index) => ({effectId,
            resource: 'catalog', targetRef, mappingRef, mappingCid: f.fixture.mappingCid,
            action: 'create', catalogCid: cid('3'), namespace: ['analytics'], tableName: `rows_${index}`,
            expectedTable: null, permissions: ['scope:store'],
            footprint: tableFixtureWriteFootprint(index)})), bridge,
          authorization: {authorize() { assert.fail('Preparation cannot authorize a provider read'); }},
          ledgerRoot: join(f.directory, 'installed-table-failure-ledger'),
          limits: {maxMembers: 2, maxInputBytes: 100000,
            material: f.tableLimits, reservation: {bytes: 1048576, files: 16}}});
        const identity = moon.clientProgramEffectRequestIdentity(f.prepared, cid('e'), 'table-bind', cid('b'));
        const plan = tableFixturePublicationPlan(f), program = JSON.parse(f.fixture.document);
        let failure;
        try {
          try { await factory.prepareCaptured({moon, control, store: f.physicalStore,
            execution: f.execution, checkedHost: f.checkedHost, prepared: f.prepared,
            identity, publicationPlan: plan,
            unit: {programId: program.id, stageId: program.stages[0].id,
              stageIndex: 0, effectIds: ['first', 'second']},
            previewContext: {runDefinition: f.definition, runInvocation: f.invocation,
              compiledPlan: f.evidence[3]}}); } catch (error) { failure = error; }
          assert.equal(failure?.cause, original);
          assert.equal(failure.primaryFailure, original);
          assert.equal(failure.cleanupPending, true);
          assert.equal(failure.cleanupHandle.status().pending, true);
          assert.equal(cleanupCalls, 1);
          assert.equal((await failure.cleanupHandle.retry()).pending, false);
          assert.equal(failure.cleanupHandle.status().pending, false);
          assert.equal(cleanupCalls, 2);
          assert.equal(innerRetries, kind === 'nested' ? 1 : 0);
          await failure.cleanupHandle.retry();
          assert.equal(cleanupCalls, 2);
          assert.equal(innerRetries, kind === 'nested' ? 1 : 0);
        } finally {
          if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
          await retireCompletedEffectfulCapture({store: f.physicalStore, control,
            runDefinition: plan.runDefinition, contractLimits: plan.contractLimits});
        }
      }}));
}

for (const sparseTableInput of [false, true]) for (const empty of [false,true]) {
  test(`installed Table hooks ${sparseTableInput ? 'sparse private ' : ''}${empty ? 'empty' : 'nonempty'} preserve original capture and claims`,
    async t => exerciseEffectSourceSet(t, {empty, sparseTableInput,
      privateTableInput: sparseTableInput, target: targetRef, mappingRef,
      minimumApproval: 'required', onCompletedTableRun: async f => {
        const {moon,sourceControl: control} = f;
        const originalCompleted = f.execution.completed.slice();
        const writes = [], inspections = [];
        const materials = new WeakMap();
        let cleanupCalls = 0, testCleanup = false, finishCleanup = false;
        const bridge = {
          supportsOperation: supportsIcebergTableOperation,
          issueStorageMapping: issueIcebergStorageMapping,
          admitStorageMapping: admitIcebergStorageMapping,
          projectCommitResponse: projectIcebergCommitResponse,
          prepareWrite(value) {
            const token = Object.freeze({}); materials.set(token,value); return token;
          },
          status: () => ({attempted: testCleanup, stopped: testCleanup}),
          execute() { writes.push('send'); assert.fail('Preparation cannot send'); },
          inspect() { inspections.push('inspect'); assert.fail('Preparation cannot inspect'); },
          async cleanup() {
            assert.equal(testCleanup, true);
            cleanupCalls++;
            await Promise.resolve();
            return {ok: true, result: {pending: !finishCleanup}};
          },
          reconcileOperation() { assert.fail('Prepared intents are not uncertain sends'); },
        };
        const options = {moon, environmentWire: '{}', connectorId: 'table',
          connectorRegistration: 'table', connectorRevision: 'table/0.1', connection: 'table',
          runtimeBundleCid: cid('8'), bindingCid: cid('9'), catalogCid: cid('3'),
          targets: ['first','second'].map((effectId,index) => ({effectId,
            resource: 'catalog', targetRef, mappingRef, mappingCid: f.fixture.mappingCid,
            action: 'create', catalogCid: cid('3'), namespace: ['analytics'], tableName: `rows_${index}`,
            expectedTable: null, permissions: ['scope:store'],
            footprint: tableFixtureWriteFootprint(index)})), bridge,
          authorization: {authorize() { assert.fail('No provider read during preparation'); }},
          ledgerRoot: join(f.directory,'installed-table-ledger'),
          limits: {maxMembers: 2, maxInputBytes: 100000,
            material: f.tableLimits, reservation: {bytes: 1048576, files: 16}}};
        await assert.rejects(createInstalledTableEffect({...options,
          targets: [...options.targets, ...options.targets]}), {code: 'DuplicateInstalledTableMapping'});
        await assert.rejects(createInstalledTableEffect({...options,
          bridge: {...bridge, supportsOperation: () => false}}),
        {code: 'UnsupportedTableCarrierOperation'});
        await assert.rejects(createInstalledTableEffect({...options,
          bridge: {...bridge, supportsOperation: undefined}}),
        {code: 'InvalidInstalledTableEffect'});
        assert.deepEqual(writes, []);
        assert.deepEqual(inspections, [], 'An absent declared operation cannot start physical I/O');
        const factory = await createInstalledTableEffect(options);
        const identity = moon.clientProgramEffectRequestIdentity(f.prepared, cid('e'), 'table-bind', cid('b'));
        const plan = tableFixturePublicationPlan(f);
        const program = JSON.parse(f.fixture.document);
        const facts = {moon, control, store: f.physicalStore, execution: f.execution,
          checkedHost: f.checkedHost, prepared: f.prepared, identity, publicationPlan: plan,
          unit: {programId: program.id, stageId: program.stages[0].id,
            stageIndex: 0, effectIds: ['second','first']},
          previewContext: {runDefinition: f.definition, runInvocation: f.invocation,
            compiledPlan: f.evidence[3]}};
        let stage, recoveredStage, durable, recoveryOwner;
        try {
          stage = await factory.prepareCaptured(facts);
          const body = JSON.parse(control.effectComputationPreviewWire(stage.preview));
          assert.deepEqual(body.effects.map(member => member.effect_id), ['first','second']);
          for (const [index,member] of body.effects.entries()) {
            assert.equal(member.count, 1);
            assert.equal(member.max_items, 1);
            assert.equal(member.approval, 'required');
            assert.equal(member.effect_kind, 'store');
            assert.equal(stage.apply.members[index].claims.length, 1);
            assert.equal(stage.apply.members[index].claims[0].canonicalRequestCid,
              member.changes[0].intended_changes.value.request_cid);
            assert.equal(member.changes[0].intended_changes.value.table_name, `rows_${index}`);
          }
          assert.notEqual(stage.apply.members[0].claims[0].canonicalRequestCid,
            stage.apply.members[1].claims[0].canonicalRequestCid);
          assert.deepEqual(writes, []);
          assert.deepEqual(inspections, []);
          assert.deepEqual(f.execution.completed, originalCompleted);
          if (!sparseTableInput) assert.equal(f.execution.completed.length, 1);
          stage.apply.ledger.prepareCapturedSetIntents(stage.apply.capturedInputs,
            stage.apply.members, 100);
          const provider = JSON.parse(stage.continuationWire);
          await suspendCompletedEffectfulComputation({execution: f.execution, store: f.physicalStore,
            control, storedResults: stage.storedResults, computation: stage.computation, preview: stage.preview});
          stage.releaseInputs();
          // Inject physical cleanup replies only, not commit/receipt evidence.
          // Pending retains the same stage and Ledger until verified cleanup.
          testCleanup = true;
          await assert.rejects(stage.dispose(), {code: 'TableCleanupPending'});
          assert.equal(stage.cleanupOwner.cleanupPending(), true);
          assert.equal(cleanupCalls, 1);
          finishCleanup = true;
          let schemaReleases = 0;
          if (sparseTableInput) {
            // Inject only a failed release of the real Store lease. The
            // pending schema and Ledger must remain in the same stage custody.
            const schema = stage.cleanupOwner.schemas[0];
            assert.equal(schema.status().pending, true);
            stage.cleanupOwner.schemas[0] = Object.freeze({
              status: () => schema.status(),
              async release() {
                if (++schemaReleases === 1) throw new Error('TableSchemaReleaseFailure');
                return schema.release();
              },
            });
            await assert.rejects(stage.dispose(), {message: 'TableSchemaReleaseFailure'});
            assert.equal(stage.cleanupOwner.cleanupPending(), true);
            assert.equal(schema.status().pending, true);
            assert.equal(cleanupCalls, 3);
          }
          await Promise.all([stage.dispose(), stage.dispose()]);
          assert.equal(cleanupCalls, 3);
          assert.equal(schemaReleases, sparseTableInput ? 2 : 0);
          await stage.dispose();
          assert.equal(cleanupCalls, 3);
          assert.equal(schemaReleases, sparseTableInput ? 2 : 0);
          testCleanup = false;
          assert.equal(stage.cleanupOwner.cleanupPending(), false);
          durable = await recoverCompletedEffectfulComputation({store: f.physicalStore, control,
            runDefinition: plan.runDefinition, contractLimits: plan.contractLimits});
          assert.equal(durable.execution, null);
          assert.equal(durable.connectorRecovery.length, 2);
          assert.equal(durable.computation.capturedRun.identity, stage.computation.capturedRun.identity);
          recoveredStage = await factory.prepareRecovered({moon, control, store: f.physicalStore,
            recovered: {requestIdentity: identity, requestScope: moon.clientRequestLogicalScope(identity),
              computation: durable}, continuation: {provider},
            retainRecoveryOwner(owner) { recoveryOwner = owner; }});
          assert.equal(recoveredStage.cleanupOwner, recoveryOwner);
          assert.equal(recoveredStage.publication.execution, null);
          assert.equal(recoveredStage.apply.computation, durable.computation);
          assert.equal(recoveredStage.apply.preview, durable.preview);
          assert.equal(recoveredStage.continuationWire, stage.continuationWire);
          assert.deepEqual(recoveredStage.receipt.members.map(member =>
            member.rowOwners[0].claim.canonicalRequestCid),
          stage.apply.members.map(member => member.claims[0].canonicalRequestCid));
          assert.deepEqual(writes, []);
          assert.deepEqual(inspections, []);
          const changed = await createInstalledTableEffect({...options, runtimeBundleCid: cid('f')});
          await assert.rejects(changed.prepareRecovered({moon, control, store: f.physicalStore,
            recovered: {requestIdentity: identity, requestScope: moon.clientRequestLogicalScope(identity),
              computation: durable}, continuation: {provider}}), {code: 'InstalledTableInstallationChanged'});
          await recoveredStage.dispose();
          await recoveredStage.dispose();
          assert.equal(recoveryOwner.cleanupPending(), false);
          assert.deepEqual(f.execution.completed, originalCompleted);
          if (!sparseTableInput) assert.equal(f.execution.completed.length, 1);
          // The real recovered Ledger remains owned after a close failure,
          // even when its primary preparation exception is immutable.
          const originalFailure = Object.freeze(Object.assign(new Error('RecoveredTablePreparationFailure'),
            {code: 'RecoveredTablePreparationFailure'}));
          const originalClose = DatabaseSync.prototype.close;
          let ledgerCloses = 0;
          const closeMock = t.mock.method(DatabaseSync.prototype, 'close', function (...args) {
            if (++ledgerCloses === 1) throw new Error('RecoveredLedgerCloseFailure');
            return originalClose.apply(this, args);
          });
          try {
            let failure;
            try { await factory.prepareRecovered({moon,
              control: {...control, effectComputationPreviewLedgerIdentity() { throw originalFailure; }},
              store: f.physicalStore, recovered: {requestIdentity: identity,
                requestScope: moon.clientRequestLogicalScope(identity), computation: durable},
              continuation: {provider}}); } catch (error) { failure = error; }
            assert.equal(failure?.cause, originalFailure);
            assert.equal(failure.cleanupHandle.status().pending, true);
            assert.equal(ledgerCloses, 1);
            assert.equal((await failure.cleanupHandle.retry()).pending, false);
            assert.equal(failure.cleanupHandle.status().pending, false);
            assert.equal(ledgerCloses, 2);
            await failure.cleanupHandle.retry();
            assert.equal(ledgerCloses, 2);
          } finally { closeMock.mock.restore(); }
        } finally {
          await recoveredStage?.dispose();
          await stage?.dispose();
          if (durable) await releaseCompletedRunPreparedPayloads(durable.storedResults, control);
          if (stage) await retireCompletedEffectfulCapture({store: f.physicalStore, control,
            runDefinition: plan.runDefinition, contractLimits: plan.contractLimits});
        }
      }}));
}
