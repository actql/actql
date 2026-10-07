// Optional real Table installation I/O. The shared fixture supplies an actual
// checked Program, captured Relation and sealed whole-Relation Preview. This
// closes approved internal apply, not public Table installation/Source reads.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {exerciseEffectSourceSet} from './client-program-bridge.test.mjs';
import {ensureCheckpointRuntime, accountConfiguration, accountEntry} from './authorization-fixture.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {preparePinnedEffectSourceHoldings, readPinnedEffectTableInput} from './effect-input-export.mjs';
import {createIcebergPhysicalBridge} from './table-iceberg-process.mjs';
import {prepareCapturedTableCommit, bindApprovedTableCommitDispatch,
  refreshCapturedTableTargets, capturedTableCommitPhysicalStatus,
  cleanupCapturedTableCommit} from './table-commit-apply.mjs';
import {applyCapturedEffectSet} from './effect-run-apply.mjs';
import {openEffectLedger} from './effect-ledger.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const python = pathToFileURL(process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(
  new URL('../../.venv-table/bin/python', import.meta.url)));
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const sameData = value => JSON.parse(JSON.stringify(value));
const target = 'connector://table/catalog';
const mappingRef = 'mapping:table.catalog.v1';
const scope = Object.freeze({connection: 'table', resource: 'catalog'});

for (const empty of [false, true]) {
  test(`approved captured Table ${empty ? 'empty' : 'nonempty'} commit uses one operation per member`,
    async t => exerciseEffectSourceSet(t, {empty, target, mappingRef,
      minimumApproval: 'required', onTablePreview: async f => {
        ensureCheckpointRuntime();
        const {moon, sourceControl: control, effect, tableLimits: limits} = f;
        const publicationPreview = control.admitEffectComputationPreview(f.authored._0,
          control.admit('run_definition', moon.strategyPublicationContractJson(f.definition),
            f.options.contractLimits),
          control.admitRunEvidence('authoring_context', JSON.stringify(
            JSON.parse(f.authored._0).authoring_context), f.options.contractLimits),
          f.options.contractLimits);
        const retained = preparePinnedEffectSourceHoldings({sources: f.sources,
          store: f.store, control, preview: publicationPreview,
          invocation: f.options.invocation,
          resultArtifacts: f.sources.members.map(({payload}) => payload.localResultArtifact)});
        let ledger, installed, gate;
        try {
        await retained.commit();
        const catalog = {database: join(f.directory, 'catalog.db'),
          warehouse: join(f.directory, 'warehouse'), catalogCid: cid('3'),
          limits: {bytes: 16777216, files: 128, operations: 16}};
        const setup = spawnSync(fileURLToPath(python), ['-c',
          'import json,sys; from catalog import TableCatalog; c=json.loads(sys.argv[1]); t=TableCatalog(c["database"],c["warehouse"],c["catalogCid"],c["limits"]); t.create_namespace("analytics"); t.engine.dispose()',
          JSON.stringify(catalog)], {cwd: fileURLToPath(new URL('../table-iceberg/', import.meta.url)),
          encoding: 'utf8', timeout: 20000});
        assert.ifError(setup.error);
        assert.equal(setup.status, 0, setup.stderr);
        const countCommits = () => {
          const result = spawnSync(fileURLToPath(python), ['-c',
            'import sqlite3,sys; db=sqlite3.connect(sys.argv[1]); print(db.execute("SELECT COUNT(*) FROM actql_table_commits").fetchone()[0]); db.close()',
            catalog.database], {encoding: 'utf8', timeout: 10000});
          assert.ifError(result.error);
          assert.equal(result.status, 0, result.stderr);
          return Number(result.stdout.trim());
        };
        const countAllocations = () => {
          const result = spawnSync(fileURLToPath(python), ['-c',
            'import sqlite3,sys; db=sqlite3.connect(sys.argv[1]); print(db.execute("SELECT COUNT(*) FROM actql_table_allocations").fetchone()[0]); db.close()',
            catalog.database], {encoding: 'utf8', timeout: 10000});
          assert.ifError(result.error);
          assert.equal(result.status, 0, result.stderr);
          return Number(result.stdout.trim());
        };
        const bridge = createIcebergPhysicalBridge({python, run: 'captured-table', catalog});
        const tablePreviews = [], materials = [], members = [];
        const preview = JSON.parse(f.authored._0);
        for (const [index, member] of preview.effects.entries()) {
          const identity = index === 0 ? f.identity : control.issueSourceFreeLocalEffectIdentity(
            f.prepared, f.inputs, index, f.artifact, limits);
          const input = index === 0 ? f.tableInput : control.bindTableInput(
            f.prepared, f.inputs, index, f.artifact, identity, f.scope,
            canonicalValueJson(f.operations[index], {dataKeys: true}), limits);
          const tablePreview = index === 0 ? f.tablePreview : control.bindTablePreview(input, f.captured, index);
          tablePreviews.push(tablePreview);
          // The fixture's live source is not re-executed. Its actual retained
          // bytes alone supply material, including the zero-row case.
          await assert.rejects(readPinnedEffectTableInput({holding: {...retained.holdings[index]},
            store: f.store, control, tableInput: input, identity, maxBytes: 100000}),
          {name: 'TypeError'});
          materials.push(await prepareCapturedTableCommit({control, store: f.store,
            holding: retained.holdings[index], tableInput: input, identity,
            tablePreview, bridge, reservation: {bytes: 1048576, files: 16},
            maxBytes: 100000, limits}));
          const locator = effect.logicalItemLocator(f.scope, 'captured-table', 'unit-1',
            member.effect_id, JSON.stringify(f.operations[index].request_cid), 128, 256, 16, 4);
          const basis = effect.ledgerBasis(f.scope, locator, f.authored._1[index][0], cid('6'),
            member.effect_member_preview_cid, member.changes[0].row_preview_cid,
            f.operations[index].request_cid, cid('0'), 'unavailable', cid('1'), cid('2'));
          members.push({claims: [{scope: f.scope, locator, key: f.authored._1[index][0], basis,
            intentFingerprintCid: member.changes[0].row_preview_cid,
            canonicalRequestCid: f.operations[index].request_cid}]});
        }
        const discarded = await prepareCapturedTableCommit({control, store: f.store,
          holding: retained.holdings[0], tableInput: f.tableInput, identity: f.identity,
          tablePreview: f.tablePreview, bridge, reservation: {bytes: 1048576, files: 16},
          maxBytes: 100000, limits});
        assert.deepEqual(capturedTableCommitPhysicalStatus(discarded),
          {attempted: false, stopped: false});
        assert.deepEqual(await cleanupCapturedTableCommit({prepared: discarded}),
          {ok: true, result: {retained: false, pending: false, removed: 0}});
        assert.throws(() => capturedTableCommitPhysicalStatus(discarded),
          {code: 'ForeignTableCommitMaterial'});
        assert.throws(() => capturedTableCommitPhysicalStatus({...materials[0]}),
          {code: 'ForeignTableCommitMaterial'});
        assert.equal(countCommits(), 0);
        assert.equal(countAllocations(), 0);
        const route = () => checked(moon.clientProgramEffectApplyCapabilityFromCodes(
          cid('d'), 0, 0, 0, true, true, 2, 1));
        const preflight = {proofs: [], sources: [cid('c'), cid('c')],
          contracts: [f.fixture.mappingCid, f.fixture.mappingCid],
          capabilities: [cid('d'), cid('d')], authorities: [cid('e'), cid('e')],
          observedRows: [], guardVersions: [], routes: [route(), route()],
          reviewProjectionCid: '', authorityScopeCid: '', policyCid: '',
          validityCid: '', issuerCid: '', authenticationCid: '', issuerKind: '',
          decision: '', requestScope: f.scope, keys: f.authored._1,
          maxMembers: 2, maxRows: 2, maxFootprintWork: 4, maxWork: 100};
        const ledgerRoot = join(f.directory, 'approved-table-ledger');
        const openLedger = () => openEffectLedger({moon, root: ledgerRoot,
          authorityScopeCid: cid('e'), callerRequestId: 'table-bind', maxEntryBytes: 8192});
        ledger = openLedger();
        const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
        const configuration = accountConfiguration([
          accountEntry('commit', 'delegate', {...scope, operation: 'effect'}),
          accountEntry('target-read', 'allow', {...scope, operation: 'read'})]);
        const now = () => Date.parse('2026-10-07T00:00:00.000Z');
        const openCheckpoint = () => installRemoteCheckpoints({root: join(f.directory, 'approval'),
          namespaceId: 'table-host', authorityScopeCid: cid('e'), ownerPrincipal: 'owner',
          siteKey: 'table', realizationKey: 'catalog', environmentCid: moon.clientProgramEffectEnvironmentCid(f.prepared),
          contractControl: control, now, authorization: {accountConfiguration: configuration,
            leaseMs: 60000, resumeAfterAnswer: false, reviewReaders: ['reviewer'],
            reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId: 'reviewer',
              publicKey: pem(reviewer.publicKey)}], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
        installed = await openCheckpoint();
          const continuation = () => ({runId: 'source-set-run',
            runDefinitionCid: moon.strategyPublicationContractIdentity(f.definition),
            unitId: 'unit-1', declaredResults: ['rows'], reviewWire: f.authored._0,
            continuationWire: JSON.stringify({request_cids: f.operations.map(value => value.request_cid)}),
            beforeDefer: () => retained.commit()});
          gate = await installed.effectAuthorization(continuation());
          const options = () => ({moon, capturedInputs: f.captured, preflight, ledger,
            members, maxFrontierWork: 64,
            refreshPreflight: ({preflight, signal}) => refreshCapturedTableTargets(
              {prepared: materials, preflight, signal}),
            authorization: {gate, scopes: [scope, scope]},
            bindDispatch: binding => bindApprovedTableCommitDispatch({control, ledger,
              prepared: materials, scopes: [scope, scope], credentialUseCid: cid('7'), limits}, binding)});
          const waiting = await applyCapturedEffectSet(options());
          assert.equal(waiting.status, 'waiting');
          assert.equal(waiting.dispatched, 0);
          assert.equal(countCommits(), 0);
          assert.equal(countAllocations(), 0);
          assert.equal(authorizationDispatchFacts(waiting.authorization[0]), undefined);
          const page = await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10});
          assert.equal(page.items.length, 1);
          const summary = page.items[0];
          assert.equal(summary.requiredArtifact.cid, f.tablePreview.subjectCid);
          const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key',
            reviewerId: 'reviewer', authorityScopeCid: cid('e'),
            sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(now()).toISOString());
          assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]})).results[0].status,
            'committed');
          gate.close();
          await installed.close();
          installed = await openCheckpoint();
          gate = await installed.effectAuthorization(continuation());
          const approved = options();
          approved.authorization.resume = {journal: installed.journal, runId: 'source-set-run',
            claimant: 'table-resumer', leaseMs: 60000, binding: installed.binding};
          let approvedBinding;
          const bind = approved.bindDispatch;
          approved.bindDispatch = binding => {
            approvedBinding = binding;
            assert.throws(() => bind({...binding, decisions: binding.decisions.map(value => ({...value}))}),
              {code: 'TableCommitApprovalRequired'});
            return bind(binding);
          };
          const applied = await applyCapturedEffectSet(approved);
          assert.equal(applied.status, 'applied');
          assert.equal(applied.dispatched, 2);
          assert.equal(countCommits(), 2);
          assert.equal(countAllocations(), 2);
          assert.ok(authorizationDispatchFacts(approvedBinding.decisions[0]));
          for (const prepared of materials) {
            assert.deepEqual(capturedTableCommitPhysicalStatus(prepared),
              {attempted: true, stopped: true});
            // Catalog publication prevents staged-file cleanup from deleting
            // a committed generation, independent of subsequent source release.
            assert.deepEqual(sameData(await cleanupCapturedTableCommit({prepared})),
              {ok: true, result: {retained: true, pending: false, removed: 0}});
          }
          // Independent values from the shared values.json Program: this
          // fixture has no split-source/take stage that changes them to 2/3.
          const expected = empty ? [] : [{id: 1}, {id: 2}];
          const receipts = members.map(member => JSON.parse(
            ledger.readClaimedOutcome(member.claims[0]).outcomeJson).typed_outcome.result);
          ledger.close();
          ledger = openLedger();
          const replay = await applyCapturedEffectSet({...options(), authorization: undefined,
            refreshPreflight: undefined, bindDispatch: () => assert.fail('Terminal operation resent')});
          assert.equal(replay.dispatched, 0);
          assert.equal(countCommits(), 2);
          for (const receipt of receipts) {
            assert.equal(receipt.row_count, expected.length);
            assert.deepEqual(sameData((await bridge.read(receipt, JSON.parse(f.storage.wire))).result), expected);
          }
          // Origin input holdings may be retired after settlement. Iceberg's
          // retained generation is independent and remains readable afterwards.
          for (const holding of retained.holdings) {
            assert.equal((await f.store.retirePhysicalHolding(holding.holdingCid)).deleted, true);
          }
          for (const receipt of receipts) {
            assert.deepEqual(sameData((await bridge.read(receipt, JSON.parse(f.storage.wire))).result), expected);
          }
        } finally {
          gate?.close();
          await installed?.close();
          ledger?.close();
          for (const holding of retained.holdings) {
            await f.store.retirePhysicalHolding(holding.holdingCid);
          }
        }
      }}));
}
