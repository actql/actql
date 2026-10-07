// Real optional Iceberg I/O consumes the installed Table hooks. This is an
// internal Effect Site boundary test, not packed public Host/Source acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {createInstalledTableEffect} from './installed-table-effect.mjs';
import {tableFixturePublicationPlan} from './fixtures/table-completed-capture.mjs';
import {createIcebergPhysicalBridge} from './table-iceberg-process.mjs';
import {applyCapturedEffectSet, applyRecoveredEffectSet} from './effect-run-apply.mjs';
import {recoverCompletedEffectfulComputation, suspendCompletedEffectfulComputation,
  releaseCompletedRunPreparedPayloads, retireCompletedEffectfulCapture}
  from '../host-common/completed-run-publication.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {ensureCheckpointRuntime, accountConfiguration, accountEntry,
  fixtureAuthorization} from './authorization-fixture.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const python = pathToFileURL(process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(
  new URL('../../.venv-table/bin/python', import.meta.url)));
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const plain = value => JSON.parse(JSON.stringify(value));
const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
const scope = {connection: 'table', resource: 'catalog'};

for (const empty of [false,true]) {
for (const partial of [false,true]) {
  test(`installed Table runtime ${empty ? 'empty' : 'nonempty'} commits original operations after approval and recovery${partial ? ' with partial apply restart' : ''}`,
    async t => exerciseEffectSourceSet(t, {empty, target: targetRef, mappingRef,
      minimumApproval: 'required', onTablePreview: async f => {
        ensureCheckpointRuntime();
        const {moon,sourceControl: control} = f;
        const plan = tableFixturePublicationPlan(f);
        const catalog = {database: join(f.directory,'catalog.db'),
          warehouse: join(f.directory,'warehouse'), catalogCid: cid('3'),
          limits: {bytes: 16777216, files: 128, operations: 16}};
        const setup = spawnSync(fileURLToPath(python), ['-c',
          'import json,sys; from catalog import TableCatalog; c=json.loads(sys.argv[1]); t=TableCatalog(c["database"],c["warehouse"],c["catalogCid"],c["limits"]); t.create_namespace("analytics"); t.engine.dispose()',
          JSON.stringify(catalog)], {cwd: fileURLToPath(new URL('../table-iceberg/', import.meta.url)),
          encoding: 'utf8', timeout: 20000});
        assert.ifError(setup.error); assert.equal(setup.status, 0, setup.stderr);
        const commits = () => {
          const observed = spawnSync(fileURLToPath(python), ['-c',
            'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT COUNT(*) FROM actql_table_commits").fetchone()[0]); c.close()',
            catalog.database], {encoding: 'utf8', timeout: 10000});
          assert.ifError(observed.error); assert.equal(observed.status,0,observed.stderr);
          return Number(observed.stdout.trim());
        };
        const bridge = createIcebergPhysicalBridge({python, run: 'installed-table', catalog});
        const physicalOperations = new WeakMap();
        const inspected = [], sent = [];
        const observedBridge = Object.freeze({...bridge,
          prepareWrite(options) {
            const prepared = bridge.prepareWrite(options);
            physicalOperations.set(prepared, options.operation);
            return prepared;
          },
          inspect(prepared, signal) {
            inspected.push(physicalOperations.get(prepared).table_name);
            return bridge.inspect(prepared, signal);
          },
          execute(prepared, options) {
            sent.push(physicalOperations.get(prepared).request_cid);
            return bridge.execute(prepared, options);
          },
        });
        const readAuthorization = await fixtureAuthorization([accountEntry('current-read','allow',
          {...scope,operation:'read'})]);
        const options = {moon, environmentWire: '{}', connectorId: 'table',
          connectorRegistration: 'table', connectorRevision: 'table/0.1', connection: 'table',
          runtimeBundleCid: cid('8'), bindingCid: cid('9'), catalogCid: cid('3'),
          targets: ['first','second'].map((effectId,index) => ({effectId, resource: 'catalog',
            targetRef, mappingRef, mappingCid: f.fixture.mappingCid,
            action: 'create', catalogCid: cid('3'), namespace: ['analytics'], tableName: `rows_${index}`,
            expectedTable: null, permissions: ['scope:store'], footprint: f.template.effects[index].write_footprint})),
          bridge: observedBridge, authorization: readAuthorization, ledgerRoot: join(f.directory,'installed-table-ledger'),
          limits: {maxMembers: 2, maxInputBytes: 100000, material: f.tableLimits,
            reservation: {bytes: 1048576, files: 16}}};
        const factory = await createInstalledTableEffect(options);
        const identity = moon.clientProgramEffectRequestIdentity(f.prepared,cid('e'),'table-bind',cid('b'));
        const program = JSON.parse(f.fixture.document);
        const facts = {moon, control, store: f.physicalStore, execution: f.execution,
          checkedHost: f.checkedHost, prepared: f.prepared, identity, publicationPlan: plan,
          unit: {programId: program.id, stageId: program.stages[0].id,
            stageIndex: 0, effectIds: ['first','second']},
          previewContext: {runDefinition: f.definition, runInvocation: f.invocation, compiledPlan: f.evidence[3]}};
        let stage, recoveredStage, durable, checkpoint, gate;
        let store = f.physicalStore;
        const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
        const configuration = accountConfiguration([
          accountEntry('commit','delegate',{...scope,operation:'effect'}),
          accountEntry('target-read','allow',{...scope,operation:'read'})]);
        let clock = Date.parse('2026-10-07T00:00:00.000Z');
        const now = () => clock;
        const openCheckpoint = () => installRemoteCheckpoints({root: join(f.directory,'approval'),
          namespaceId: 'table-host', authorityScopeCid: cid('e'), ownerPrincipal: 'owner',
          siteKey: 'table', realizationKey: 'catalog', environmentCid: moon.clientProgramEffectEnvironmentCid(f.prepared),
          contractControl: control, now, authorization: {accountConfiguration: configuration,
            leaseMs: 60000, resumeAfterAnswer: false, reviewReaders: ['reviewer'],
            reviewers: [{keyId:'reviewer-key',reviewerId:'reviewer',principalId:'reviewer', publicKey:pem(reviewer.publicKey)}],
            hostKey:{keyId:'host-key',privateKey:pem(host.privateKey)}}});
        const continuation = () => ({runId:'source-set-run', runDefinitionCid: plan.runDefinition.identity,
          unitId:'unit-1',declaredResults:['rows'],
          reviewWire: control.effectComputationPreviewWire(stage.preview),
          continuationWire: stage.continuationWire,
          beforeDefer: () => stage.apply.ledger.prepareCapturedSetIntents(stage.apply.capturedInputs,
            stage.apply.members, 100)});
        try {
          stage = await factory.prepareCaptured(facts);
          checkpoint = await openCheckpoint();
          gate = await checkpoint.effectAuthorization(continuation());
          const waiting = await applyCapturedEffectSet({...stage.apply,
            authorization: {gate, scopes: stage.scopes}});
          assert.equal(waiting.status,'waiting'); assert.equal(waiting.dispatched,0);
          assert.equal(commits(),0);
          const saved = JSON.parse(stage.continuationWire);
          const originalRequests = stage.apply.members.map(member => member.claims[0].canonicalRequestCid);
          await suspendCompletedEffectfulComputation({execution:f.execution,store,control,
            storedResults:stage.storedResults,computation:stage.computation,preview:stage.preview});
          stage.releaseInputs(); await stage.dispose();
          gate.close(); await checkpoint.close();
          await store.close();
          store = await openLocalPublicationStore(f.storeConfiguration,control);
          f.replaceStoreForCleanup(store);
          durable = await recoverCompletedEffectfulComputation({store,control,
            runDefinition:plan.runDefinition,contractLimits:plan.contractLimits});
          const recovered = {requestIdentity:identity,requestScope:moon.clientRequestLogicalScope(identity),computation:durable};
          recoveredStage = await factory.prepareRecovered({moon,control,store,recovered,continuation:{provider:saved}});
          assert.deepEqual(recoveredStage.receipt.members.map(member => member.rowOwners[0].claim.canonicalRequestCid),originalRequests);
          checkpoint = await openCheckpoint();
          const page = await checkpoint.listCheckpoints({principalId:'reviewer',after:'',limit:10});
          assert.equal(page.items.length,1);
          const answer = await signedAnswer(page.items[0],'approved',{keyId:'reviewer-key',reviewerId:'reviewer',
            authorityScopeCid:cid('e'),sign:bytes=>sign(null,bytes,reviewer.privateKey)},new Date(now()).toISOString());
          assert.equal((await checkpoint.resolve({principalId:'reviewer',items:[answer]})).results[0].status,'committed');
          gate = await checkpoint.effectAuthorization(continuation());
          const approved = () => ({gate,scopes:recoveredStage.scopes,
            resume:{journal:checkpoint.journal,runId:'source-set-run',
              claimant:'table-resumer',leaseMs:60000,binding:checkpoint.binding}});
          let firstResponse, firstOutcome;
          if (partial) {
            const bind = recoveredStage.apply.bindDispatch;
            // Interrupt only after the first real commit and durable Applied
            // outcome. The second member has not entered its send claim.
            await assert.rejects(applyRecoveredEffectSet({...recoveredStage.apply,
              authorization:approved(),bindDispatch:binding => {
                const dispatch = bind(binding);
                return row => {
                  if (row.memberIndex === 1) throw Object.assign(new Error('FixturePartialApplyStop'),
                    {code:'FixturePartialApplyStop'});
                  return dispatch(row);
                };
              }}),{code:'FixturePartialApplyStop'});
            assert.equal(commits(),1);
            assert.deepEqual(sent,[originalRequests[0]]);
            const claims = recoveredStage.receipt.members.map(member => member.rowOwners[0].claim);
            firstResponse = recoveredStage.apply.ledger.readClaimedResponse(claims[0]).responseBytes;
            firstOutcome = recoveredStage.apply.ledger.readClaimedOutcome(claims[0]).outcomeJson;
            assert.equal(JSON.parse(firstOutcome).typed_outcome.state,'applied');
            assert.equal(recoveredStage.apply.ledger.readClaimedResponse(claims[1]),undefined);
            assert.equal(recoveredStage.apply.ledger.readClaimedOutcome(claims[1]),undefined);
            await suspendCompletedEffectfulComputation({execution:null,store,control,
              storedResults:durable.storedResults,computation:durable.computation,preview:durable.preview});
            await recoveredStage.dispose();
            gate.close(); await checkpoint.close(); await store.close();
            store = await openLocalPublicationStore(f.storeConfiguration,control);
            f.replaceStoreForCleanup(store);
            durable = await recoverCompletedEffectfulComputation({store,control,
              runDefinition:plan.runDefinition,contractLimits:plan.contractLimits});
            const restartedFactory = await createInstalledTableEffect(options);
            recoveredStage = await restartedFactory.prepareRecovered({moon,control,store,
              recovered:{requestIdentity:identity,requestScope:moon.clientRequestLogicalScope(identity),computation:durable},
              continuation:{provider:saved}});
            // Expire the interrupted claim's lease; the same durable journal
            // reconciles its entered admission, never a fresh approval.
            clock += 60001;
            checkpoint = await openCheckpoint();
            gate = await checkpoint.effectAuthorization(continuation());
            inspected.length = 0; sent.length = 0;
          }
          const applied = await applyRecoveredEffectSet({...recoveredStage.apply,
            authorization:approved()});
          assert.equal(applied.dispatched,partial ? 1 : 2); assert.equal(commits(),2);
          if (partial) {
            assert.deepEqual(inspected,['rows_1']);
            assert.deepEqual(sent,[originalRequests[1]]);
            const claim = recoveredStage.receipt.members[0].rowOwners[0].claim;
            assert.deepEqual(recoveredStage.apply.ledger.readClaimedResponse(claim).responseBytes,firstResponse);
            assert.equal(recoveredStage.apply.ledger.readClaimedOutcome(claim).outcomeJson,firstOutcome);
          }
          const receipts = recoveredStage.receipt.members.map(member => JSON.parse(
            recoveredStage.apply.ledger.readClaimedOutcome(member.rowOwners[0].claim).outcomeJson).typed_outcome.result);
          const expected = empty ? [] : [{id:1},{id:2}];
          for (const receipt of receipts) assert.deepEqual(plain((await bridge.read(receipt,JSON.parse(f.storage.wire))).result),expected);
          const replay = await applyRecoveredEffectSet({...recoveredStage.apply,authorization:undefined,
            bindDispatch:()=>assert.fail('Settled Table operation resent')});
          assert.equal(replay.dispatched,0); assert.equal(commits(),2);
          assert.equal(f.execution.completed.length,1);
          await recoveredStage.dispose();
          await releaseCompletedRunPreparedPayloads(durable.storedResults,control);
          await retireCompletedEffectfulCapture({store,control,runDefinition:plan.runDefinition,
            contractLimits:plan.contractLimits});
          assert.equal(store.status().reservedBytes,0);
          for (const receipt of receipts) assert.deepEqual(plain((await bridge.read(receipt,JSON.parse(f.storage.wire))).result),expected);
        } finally {
          gate?.close(); await checkpoint?.close(); readAuthorization.close();
          await recoveredStage?.dispose(); await stage?.dispose();
          if (durable) await releaseCompletedRunPreparedPayloads(durable.storedResults,control);
          if (stage) await retireCompletedEffectfulCapture({store,control,
            runDefinition:plan.runDefinition,contractLimits:plan.contractLimits});
        }
      }}));
}
}
