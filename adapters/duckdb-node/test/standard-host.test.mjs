import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { chmod, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase, withComputeDatabase } from '../session.mjs';
import { runNativeHostQuery, runRetainedNativeHostQuery, runRetainedStrategyNativeHostQuery, runRetainedFixedHostCompute, runRetainedStrategyHostCompute, importRetainedComputeInput, runStrategyNativeHostQuery, runBroadHostQuery, runFixedHostCompute, runStrategyHostCompute, runManagedColumnStrategyHostCompute, managedColumnCodecContractCid, encodeManagedColumnFrame,
  openResidentStrategyEnvironment, importResidentStrategyInput, runResidentStrategyHostCompute } from '../host.mjs';
import { exerciseOwnedFixedTransport } from './owned-fixed-transport.mjs';
import { exerciseManagedExample } from './managed-example.mjs';
import { exerciseNativeFilePlan } from './native-file-plan.mjs';
import {runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from '../../host-node/entry.mjs';
import {runInstalledStrategy} from '../../host-common/strategy.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {duckdbStrategyContribution} from '../strategy-bundle.mjs';
import {
  prepareManagedIdentityPolicy,
} from '../../host-node/managed-identity-policy.mjs';
import { prepareDuckDBStrategyConfiguration } from '../configuration.mjs';
import { checked } from '../runtime-result.mjs';
import { runExample } from '../examples/physical-strategy.mjs';
import {installCompletionObserver} from '../../host-common/completion-observer.mjs';
import {retainedStorageBody} from '../../store-local/representations.mjs';
import {runFixedCompute, matchesFixedCompute, releaseFixedCompute} from '../fixed-compute.mjs';
import {createLocalRetainedStore} from '../../store-local/files.mjs';
import {registerManagedInput,
  managedInputCodecContractCid, withManagedInputFiles} from
  '../../store-local/managed-representations.mjs';
import {managedRepresentation} from
  '../../store-local/managed-memory-representations.mjs';
import {managedPhysicalRepresentation} from
  '../../store-local/managed-physical-representation.mjs';
import {computePhysicalCapacity} from '../physical-capacity.mjs';
import {ownedHostFailure} from '../failure-envelope.mjs';
import {managedParquetCodecContractCid} from '../managed-parquet-codec.mjs';
import {beginExecutionSiteTeardown, createInProcessExecutionSite,
  executionSiteStatus, prepareExecutionSitePolicy, revokeExecutionSite} from
  '../../host-common/execution-sites.mjs';
import {createManagedMemoryTransferProvider} from
  '../../store-local/managed-memory-transfer.mjs';
import {openLocalPublicationStore} from
  '../../store-local/publication-store.mjs';
import {
  deliverAuthorizedResult,
  installNodeResultAccessService,
  installResultAccessAuthority,
} from '../../host-node/result-access.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const publicationResultExportLimits = Object.freeze({
  maxResultFields: 10,
  maxResultMappingWork: 1000,
  maxResultOrderWork: 10000,
  maxResultWorkspaceEntries: 100,
  maxRows: 100,
  maxValueNodes: 10000,
  maxValueTextBytes: 100000,
  maxValueDepth: 64,
  maxValueWork: 100000,
  maxWireBytes: 100000,
  maxWireNodes: 10000,
  maxWireDepth: 64,
  maxColumns: 10,
  maxOrderWork: 10000,
  maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003,
  maxLogicalWireDepth: 66,
  maxSchemaFields: 10,
  maxSchemaBytes: 100000,
  maxSchemaNodes: 10000,
  maxSchemaDepth: 64,
  maxBatchBytes: 4096,
});

function standardPublicationPlan(
  runtime,
  programDefinitionCid,
  resultCount,
  attemptId,
) {
  const control = runtime.publicationControl;
  const contractLimits = Object.freeze({
    maxWireBytes: 100000,
    maxNodes: 10000,
    maxDepth: 64,
  });
  const effectiveDataPolicyCid = hash('effective-policy');
  const template = control.sealRunEvidence(
    'bound_invocation_template',
    JSON.stringify({
      version: 'actql-bound-invocation-template/0.1',
      program_definition_cid: programDefinitionCid,
      parameter_values_cid: hash('parameter-values'),
      invocation_bindings_cid: hash('invocation-bindings'),
      check_environment_cid: hash('check-environment'),
      grammar_manifest_cid: hash('grammar-manifest'),
      required_profile_contracts: [],
      barrier_contract_manifest_cid: hash('barrier-contract-manifest'),
      source_evidence: 'unbound',
    }),
    contractLimits,
  );
  const compiledPlan = control.seal('compiled_plan', JSON.stringify({
    version: 'actql-compiled-plan/0.1',
    compiler_version: 'compiler-test-0.1',
    aoa_ir_version: 'aoa-ir-test-0.1',
    executable_plan_cid: hash('executable-plan'),
    program_definition_cid: programDefinitionCid,
    program_semantics_cid: hash('program-semantics'),
    aoa_contract_cid: hash('aoa-contract'),
    aoa_logical_cid: hash('aoa-logical'),
  }), contractLimits);
  const prepared = control.sealRunEvidence(
    'prepared_invocation',
    JSON.stringify({
      version: 'actql-prepared-invocation/0.1',
      invocation_template_cid: template.identity,
      compiled_plan_cid: compiledPlan.identity,
      execution_context_cid: hash('execution-context'),
      host_policy_cid: hash('host-policy'),
      policy_decision: 'allow',
      expires_at: '2026-09-18T03:00:00.000Z',
    }),
    contractLimits,
  );
  const authorization = control.sealRunEvidence(
    'run_authorization',
    JSON.stringify({
      version: 'actql-run-authorization/0.1',
      prepared_invocation_cid: prepared.identity,
      execution_context_cid: hash('execution-context'),
      host_policy_cid: hash('host-policy'),
      decision: 'allowed',
    }),
    contractLimits,
  );
  const admission = control.admitRunPublication(
    template,
    prepared,
    authorization,
    compiledPlan,
  );
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'standard-publication-scope',
    runId: `standard-publication-${attemptId}`,
    inputArtifactSetCid: hash('input-artifact-set'),
    createdAt: '2026-09-18T00:00:00.000Z',
    validUntil: '2026-09-18T02:30:00.000Z',
  }, contractLimits);
  const observation = control.sealRunEvidence(
    'observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [],
      captured_input_artifact_cids: [],
      consistency: 'no_external_sources',
      capture_started_at: null,
      capture_completed_at: null,
      replayability: {
        materialized: false,
        availability_evidence_cids: [],
      },
      data_policy_cid: effectiveDataPolicyCid,
    }),
    contractLimits,
  );
  const invocation = control.issueRunInvocation(
    template,
    observation,
    contractLimits,
  );
  const retention = control.seal(
    'result_retention_policy',
    JSON.stringify({
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: hash('retention-contract'),
      effective_data_policy_cid: effectiveDataPolicyCid,
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T02:00:00.000Z',
      extension_ceiling_at: '2026-09-18T03:00:00.000Z',
      metadata_retention_policy_cid: hash('metadata-retention'),
      clock_contract_cid: hash('clock-contract'),
    }),
    contractLimits,
  );
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal',
    JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: hash('rule-catalog'),
      entries: [],
    }),
    contractLimits,
  );
  const authoringContext = control.sealRunEvidence(
    'authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: programDefinitionCid,
      annotations: [],
    }),
    contractLimits,
  );
  return Object.freeze({
    admission,
    runDefinition,
    invocation,
    observation,
    normalizationJournal,
    authoringContext,
    results: Object.freeze(Array.from({length: resultCount}, (_, index) =>
      Object.freeze({
        retention,
        evidenceContext: Object.freeze({
          computationContractCid: hash(`checked-computation-${index}`),
          inputRelationCids: Object.freeze([]),
          scopeCid: hash(`result-scope-${index}`),
          effectiveDataPolicyCid,
          authorityScopeCid: hash('authority-scope'),
        }),
      }))),
    receiptEvidence: Object.freeze({
      bindings: Object.freeze([]),
      sourceEvidence: Object.freeze([]),
      modelEvidence: Object.freeze([]),
      barrierAttemptReceiptCids: Object.freeze([]),
    }),
    captureEvidence: Object.freeze({
      pendingSourceStateAdvances: Object.freeze([]),
      modelEvidence: Object.freeze([]),
    }),
    request: Object.freeze({
      tenantId: 'tenant-a',
      authorityScopeCid: hash('authority-scope'),
      publicationPolicyCid: hash('publication-policy'),
      publicationTargetCid: hash('publication-target'),
      requestedAt: '2026-09-18T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId,
      fenceCid: hash('publication-fence'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-18T00:00:01.000Z',
    }),
    outputLimits: publicationResultExportLimits,
    contractLimits,
    now: () => '2026-09-18T00:00:02.000Z',
  });
}
const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

// Conformance-only contribution body. It uses the selected product
// configuration and real Store/session boundaries, but deliberately keeps the
// session unsettled after its native command so cancellation can return before
// actual access stops. It is not a product configuration hook.
async function runDelayedManagedStop(
  moon, prepared, suppliedLimits, signal, control,
) {
  const capacity = computePhysicalCapacity(suppliedLimits);
  let run;
  let sessionStarted = false;
  let taskCleanupConfirmed = false;
  try {
    run = checked(moon.managedStrategyHostOpen(
      prepared.configuration,
      capacity.transferBytes,
      capacity.executionBytes,
      () => !signal?.aborted,
      () => true,
    ));
    const inputCount = moon.managedStrategyInputCount(run);
    assert.equal(inputCount, prepared.inputs.length);
    const inputs = Array.from({length: inputCount}, (_, index) =>
      checked(moon.managedStrategyInputAt(run, index)));
    const views = inputs.map((_, index) =>
      prepared.inputCodecContractCids[index] === managedColumnCodecContractCid
        ? moon.managedStrategyInputFileViewSqlAt(
          run, index, suppliedLimits.maxSqlBytes,
        )
        : prepared.inputCodecContractCids[index] ===
            managedParquetCodecContractCid
          ? moon.managedStrategyInputParquetViewSqlAt(
            run, index, suppliedLimits.maxSqlBytes,
          )
          : undefined);
    assert(views.every(value => typeof value === 'string'));
    control.representations = prepared.inputs.map(input =>
      managedRepresentation(input.material));
    const accounting = Object.freeze({
      started() { sessionStarted = true; },
      chargeTransfer(bytes) {
        checked(moon.managedStrategyCharge(run, BigInt(bytes)));
      },
      settled(confirmed) {
        control.settlements.push(confirmed);
        checked(moon.managedStrategySettle(run, confirmed));
      },
    });
    await withManagedInputFiles(
      inputs.map((input, index) => ({
        material: prepared.inputs[index].material,
        input,
        codecContractCid: prepared.inputCodecContractCids[index],
      })),
      () => !signal?.aborted,
      files => withComputeDatabase(
        {...suppliedLimits, cancelWaitMs: 0},
        async session => {
          for (let index = 0; index < files.length; index++) {
            await session.createFileView(
              views[index], files[index].path, () => {},
            );
          }
          if (control.mode === 'command-unsettled') {
            const tables = views.map(sql => {
              const matched = /^CREATE TEMP VIEW\s+("(?:[^"]|"")+")\s+AS\s+/u
                .exec(sql);
              assert(matched, `missing managed input table in ${sql}`);
              return matched[1];
            });
            control.commandStarted = true;
            try {
              await session.command(
                `SELECT count(*) AS n FROM ${tables[0]} l CROSS JOIN ${tables[1]} r`,
                [],
                async () => {
                  control.entered();
                  await control.wait;
                },
              );
            } finally {
              control.commandSettled = true;
            }
          } else {
            control.entered();
            await control.wait;
          }
        },
        signal,
        accounting,
        files.map(file => file.path),
      ),
      signal,
      (indices, bytes) => checked(moon.managedStrategyCharge(
        run, BigInt(bytes * (indices.length + 1)),
      )),
    );
    throw new Error('DelayedStopDidNotCancel');
  } catch (reason) {
    const failure = ownedHostFailure(reason, 'DelayedManagedStopFailed');
    const native = failure.cleanupHandle;
    if (run) {
      if (!sessionStarted) checked(moon.managedStrategySettle(run, true));
      moon.managedStrategyClose(run);
      taskCleanupConfirmed = checked(
        moon.managedStrategyCleanupRefresh(run),
      );
    }
    if (failure.cleanupPending === true && native) {
      failure.cleanupHandle = Object.freeze({
        status() {
          const state = native.status();
          return Object.freeze({
            pending: state.pending || !taskCleanupConfirmed,
            errors: state.errors,
          });
        },
        async retry() {
          const state = await native.retry();
          if (run) {
            taskCleanupConfirmed = checked(
              moon.managedStrategyCleanupRefresh(run),
            );
          }
          return Object.freeze({
            pending: state.pending || !taskCleanupConfirmed,
            errors: state.errors,
          });
        },
      });
    }
    throw failure;
  }
}

test('standard native and broad Node Hosts own verification through real capture and consumer', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/retained_host_bridge'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/process_host_bridge'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors_builtin_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/duckdb_conformance'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/physical_strategy_example'], { cwd: root });
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
  const publicApi = await readFile(join(root, 'src/query_planning/pkg.generated.mbti'), 'utf8');
  assert.doesNotMatch(publicApi, /DuckDB|MockQuery|duckdb_broad_attempt/);
  const connectorApi = await readFile(join(root, 'src/connectors/duckdb/acquisition/pkg.generated.mbti'), 'utf8');
  assert.doesNotMatch(connectorApi, /pub fn duckdb_broad_attempt_output\(/);
  assert.match(connectorApi, /pub fn duckdb_broad_attempt_row_count\(/);
  // Caller-controlled transport options cannot install semantic verification,
  // replacement SQL or another MoonBit runtime into either standard entry.
  const forbidden = () => assert.fail('standard Host used caller replacement');
  const suppliedLimits = { ...limits, verifier: forbidden, verify: forbidden,
    runtime: { nativeHostOpen: forbidden, broadHostOpen: forbidden }, sql: forbidden };
  // Independent fixed setup stays in conformance. The product entry loads only
  // connectors/duckdb/host_node and cannot receive these test functions as its verifier.
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const source = await readFile(join(root, 'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
  const contracts = [...source.matchAll(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/g)].map(match => JSON.parse(match[1]));
  const args = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'), 'utf8')];
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'standard-host-'));
  try {
    for (const kind of ['valid', 'empty', 'invalid-unused']) {
      const path = join(directory, `${kind}.duckdb`);
      const db = await DuckDBInstance.create(path);
      const connection = await db.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
        if (kind !== 'empty') await connection.run(kind === 'invalid-unused'
          ? "INSERT INTO records VALUES (3,30),(1,'Infinity'::DOUBLE)"
          : 'INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      } finally { connection.closeSync(); db.closeSync(); }
      const grant = await authorizeLocalDatabase(path);
      for (const strategy of ['native', 'broad']) {
        const native = strategy === 'native';
        const create = count => native ? fixture.issuedNativeCreate(...args, count, () => true)
          : fixture.issuedBroadCreate(...args.slice(0, -1), count, () => true);
        const configure = native ? fixture.issuedNativeConfiguration : fixture.issuedBroadConfiguration;
        const close = native ? fixture.issuedNativeClose : fixture.issuedBroadClose;
        const execute = native ? runNativeHostQuery : runBroadHostQuery;
        const prepared = create(100);
        const setup = configure(prepared);
        close(prepared); // unused test issuer is not the product issuer
        if (native) {
          const retention = { parentDirectory: directory, maxFrameBytes: 4096,
            wire: { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_columns: 10, max_order_work: 10000 } };
          const executeRetained = () => runRetainedNativeHostQuery(grant, setup, limits, retention).catch(async error => {
            await error?.cleanupHandle?.retry();
            assert.equal(error?.cleanupHandle?.status().pending ?? false, false);
            throw error;
          });
          if (kind === 'invalid-unused') {
            await assert.rejects(executeRetained(), { code: 'MoonBitHostFailure' });
          } else {
            if (kind === 'valid') {
              await assert.rejects(runRetainedNativeHostQuery(grant, setup, limits,
                { ...retention, maxFrameBytes: 1 }).catch(async error => {
                assert.ok(error.cleanupHandle);
                await error.cleanupHandle.retry();
                assert.equal(error.cleanupHandle.status().pending, false);
                throw error;
              }), { code: 'MoonBitHostFailure' });
            }
            const retained = await executeRetained();
            let heldOutput;
            try {
              assert(Object.isFrozen(retained.diagnostics));
              for (const duration of Object.values(retained.diagnostics)) {
                assert(Number.isFinite(duration) && duration >= 0);
              }
              const expected = kind === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
              assert.equal(JSON.parse(retained.document()).output.rows_cid, hash(expected));
              heldOutput = retained.output();
              assert.equal(retained.output(), heldOutput);
              assert.ok(retained.source());
              assert.equal(fixture.issuedNativeConsumeOutput(prepared, heldOutput, 100), 'null');
              const read = fixture.issuedNativeRetainedInput(prepared, heldOutput);
              assert.ok(read);
              const memory = await importRetainedComputeInput(heldOutput, read, {
                maxRows: 100, maxBatchBytes: 4096,
                values: { max_nodes: 10000, max_text_bytes: 100000, max_depth: 10, max_work: 200000 },
                wire: retention.wire,
                row: { max_bytes: 4096, max_nodes: 100, max_depth: 10, max_text_bytes: 4096 },
                frames: { maxBytes: 100000, maxRows: 100, maxRowBytes: 4096, maxDepth: 10, maxFrameBytes: 4096 },
              });
              assert.equal(fixture.issuedNativeConsumeOutput(prepared, memory, 100), hash(expected));
              assert.equal(retained.storageUsage().holdings, 1);
              assert.equal(retained.storageUsage().admittedWriteBytes, Buffer.byteLength(JSON.stringify(expected)));
              const fixed = fixture.ownedFixedCreate(prepared, heldOutput, ...contracts);
              const hostMoon = await import(pathToFileURL(join(root,
                '_build/js/release/build/connectors/duckdb/host_node/host_node.js')));
              exerciseNativeFilePlan(hostMoon, fixture.ownedFixedConfiguration(fixed), retention.wire);
              const computed = await runRetainedFixedHostCompute(fixture.ownedFixedConfiguration(fixed),
                limits, { maxRows: 100, maxCells: 1000 }, retention);
              try {
                const computedOutput = computed.output();
                assert.equal(fixture.ownedFixedRetainedCid(fixed, computedOutput), hash(expected.filter(row => row.id > 2)));
                assert.equal(fixture.ownedFixedConsumeOutput(fixed, computedOutput), 'null');
                // The finished Compute is independent of the acquisition's live
                // capture. Its retained file feeds another real DB directly.
                retained.close();
                const next = fixture.ownedFixedNext(fixed, computedOutput, ...contracts);
                const downstream = await runFixedHostCompute(fixture.ownedFixedConfiguration(next),
                  limits, { maxRows: 100, maxCells: 1000 });
                try {
                  assert.equal(fixture.ownedFixedConsumeOutput(next, downstream.output()), hash(expected.filter(row => row.id > 2)));
                } finally { downstream.close(); }
              } finally {
                computed.close();
                await computed.cleanupHandle.retry();
              }
            } finally {
              retained.close();
              await retained.cleanupHandle.retry();
            }
            assert.equal(retained.cleanupHandle.status().pending, false);
            assert.equal(retained.storageUsage().reservedBytes, 0);
            assert.equal(fixture.issuedNativeRetainedInput(prepared, heldOutput), undefined);
          }
        }
        if (kind === 'invalid-unused') {
          await assert.rejects(execute(grant, setup, limits), error => {
            assert.equal(error.code, 'MoonBitHostFailure');
            assert(error.cause); // Preserve the typed admission failure, not a JS ABI error.
            return true;
          });
          continue;
        }
        const captured = await execute(grant, setup, suppliedLimits);
        const expected = kind === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
        const observation = JSON.parse(captured.document());
        assert.equal(observation.output.rows_cid, hash(expected));
        assert.equal(observation.output.row_count, expected.length);
        if (native) {
          const evidence = captured.evidence();
          assert(Object.isFrozen(evidence));
          assert.deepEqual(evidence.receipts.map(value => value.role),
            ['validation_scan', 'native_result']);
          assert.deepEqual(evidence.records.map(value => value.role),
            ['source_validation', 'filter', 'select']);
          assert.deepEqual(evidence.observation, observation);
          assert.equal(evidence.observation.accesses.validation_scan_cid,
            hash(evidence.receipts[0]));
          assert.equal(evidence.observation.accesses.native_result_cid,
            hash(evidence.receipts[1]));
          assert.equal(evidence.observation.coverage.source_validation_evidence_cid,
            hash(evidence.records[0]));
          assert.equal(evidence.observation.coverage.filter_evidence_cid,
            hash(evidence.records[1]));
          assert.equal(evidence.observation.coverage.select_evidence_cid,
            hash(evidence.records[2]));
          for (const item of [...evidence.receipts, ...evidence.records]) {
            assert.equal(item.issuer, evidence.observation.execution.issuer);
            assert.equal(item.attempt, evidence.observation.execution.attempt);
            assert.equal(item.read_view, evidence.observation.execution.read_view);
            assert.equal(item.requirement_cid, evidence.observation.requirement_cid);
          }
          for (const record of evidence.records) {
            assert.deepEqual(record.accesses, evidence.observation.accesses);
            assert.deepEqual(record.output, evidence.observation.output);
          }
        }
        const materialize = () => native ? captured.output()
          : captured.bindInput(fixture.issuedBroadConsumer(prepared), 0);
        const consume = native ? fixture.issuedNativeConsumeOutput : fixture.issuedBroadConsumeInput;
        const output = materialize();
        let assertFixedUnavailable;
        if (native) {
          // Only our uniquely created fixture file is moved, then restored.
          // Compute must work even when the authorized source path is absent.
          const heldPath = `${path}.held`;
          await rename(path, heldPath);
          try {
            assertFixedUnavailable = await exerciseOwnedFixedTransport(
              fixture, prepared, output, contracts, limits, kind === 'empty' ? [] : [3, 3],
            );
          } finally { await rename(heldPath, path); }
        }
        if (expected.length) assert.equal(consume(prepared, output, 0), 'null');
        assert.equal(consume(prepared, output, 100), hash(expected));
        const foreign = create(100);
        assert.equal(consume(foreign, output, 100), 'null');
        if (!native) assert.throws(() => captured.bindInput(fixture.issuedBroadConsumer(foreign), 0),
          { code: 'MoonBitHostFailure' });
        close(foreign);
        assert.equal(consume(prepared, materialize(), 100), hash(expected));
        if (native) {
          const fixed = fixture.ownedFixedCreate(prepared, output, ...contracts);
          const setup = fixture.ownedFixedConfiguration(fixed);
          const result = await runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 });
          const fixedOutput = result.output();
          const expectedFixed = hash(kind === 'empty' ? [] : [{ id: 3 }, { id: 3 }]);
          const countFixture = fixture.ownedCountCreate(prepared, output, ...contracts);
          const countResult = await runFixedHostCompute(fixture.ownedFixedConfiguration(countFixture),
            limits, { maxRows: 100, maxCells: 1000 });
          const countOutput = countResult.output();
          const expectedCount = hash([{ id: expected.length }]);
          const joinFixture = fixture.ownedJoinCreate(prepared, output, ...contracts);
          const joinSetup = fixture.ownedFixedConfiguration(joinFixture);
          const joinResult = await runFixedHostCompute(joinSetup, limits, { maxRows: 100, maxCells: 1000 });
          const joinOutput = joinResult.output();
          // Fixed source [3,2,3] joined with itself: left-major/right-minor.
          const expectedJoin = hash(kind === 'empty' ? [] : [{ id: 3 }, { id: 3 }, { id: 2 }, { id: 3 }, { id: 3 }]);
          assert.equal(joinResult.importedRows, kind === 'empty' ? 0 : 6);
          assert.equal(joinResult.importedCells, kind === 'empty' ? 0 : 6);
          assert.equal(joinResult.usage.statements, kind === 'empty' ? 3 : 9);
          try {
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            assert.equal(fixture.ownedFixedConsumeOutput(countFixture, countOutput), expectedCount);
            assert.equal(fixture.ownedFixedLocalCid(countFixture), expectedCount);
            assert.equal(fixture.ownedFixedConsumeOutput(joinFixture, joinOutput), expectedJoin);
            assert.equal(fixture.ownedFixedLocalCid(joinFixture), expectedJoin);
            captured.close();
            assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), expectedFixed);
            assert.equal(fixture.ownedFixedConsumeOutput(countFixture, countOutput), expectedCount);
            assert.equal(fixture.ownedFixedConsumeOutput(joinFixture, joinOutput), expectedJoin);
            await assert.rejects(runFixedHostCompute(joinSetup, limits, { maxRows: 100, maxCells: 1000 }));
            await assert.rejects(runFixedHostCompute(setup, limits, { maxRows: 100, maxCells: 1000 }));
          } finally { result.close(); countResult.close(); joinResult.close(); }
          assert.equal(fixture.ownedFixedConsumeOutput(fixed, fixedOutput), 'null');
          assert.equal(fixture.ownedFixedConsumeOutput(countFixture, countOutput), 'null');
          assert.equal(fixture.ownedFixedConsumeOutput(joinFixture, joinOutput), 'null');
        }
        captured.close();
        assertFixedUnavailable?.();
        assert.throws(materialize, { code: 'IssuerClosed' });
        assert.equal(consume(prepared, output, 100), 'null');
        const cancelled = new AbortController();
        cancelled.abort();
        await assert.rejects(execute(grant, setup, limits, cancelled.signal));
        await assert.rejects(execute({}, setup, limits));
        const limited = create(0);
        if (expected.length) await assert.rejects(execute(grant,
          configure(limited), limits), { code: 'MoonBitHostFailure' });
        close(limited);
      }
      if (kind === 'valid') await exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

async function exerciseStrategyGraph(fixture, args, path, grant, suppliedLimits) {
  const hostRuntime = await import(pathToFileURL(join(root, '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')));
  const stage = (id, producer, filter) => ({ id, inputs: { x: { result: { stage: producer, result: 'r' } } },
    steps: [{ filter }, { select: ['id'], as: 'out' }],
    results: { r: { from: 'out', fields: ['id'] } } });
  const program = JSON.stringify({ version: 'actql/0.1', id: 'p',
    params: { minimum: { type: 'number', nullable: false } },
    stages: [{ id: 'a', inputs: { remote: { connector: 'crm/main', resource: 'r' } },
      steps: [{ filter: 'id > $minimum', as: 'filtered' }, { select: ['id'], as: 'captured' }],
      results: { r: { from: 'captured', fields: ['id'] } } },
    stage('compute_a', 'a', 'id > 2'), stage('compute_b', 'a', 'id > 0'), stage('compute_c', 'compute_a', 'id < 9')],
    results: { b: { from: { stage: 'compute_b', result: 'r' } }, c: { from: { stage: 'compute_c', result: 'r' } } } });
  async function replaceRows(sql) {
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try { await connection.run('DELETE FROM records'); await connection.run(sql); }
    finally { connection.closeSync(); db.closeSync(); }
  }
  // The same fixed capture can run with no DuckDB Compute registration or
  // settings. The standard entry/bridge are unchanged for the third module.
  const numericProgram = JSON.parse(program);
  numericProgram.stages[3].steps[0].filter = 'id > 2';
  for (const mode of [0, 1, 2, 3]) {
    for (const cancel of [false, true]) {
      await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      const f = fixture.strategyFixtureCreate(...args, JSON.stringify(numericProgram));
      const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
      let execution;
      try {
        assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
        const setup = mode === 3 ? fixture.strategyFixtureDuckDBOnly(f) : fixture.strategyFixtureModuleSubset(f, mode);
        const absent = new Proxy({}, {get() { assert.fail('unused Compute provider settings accessed'); }});
        const controller = new AbortController();
        const settings = mode === 3
          ? {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: {maxRows: 100, maxCells: 1000}}), local: absent}
          : {duckdb: absent};
        if (cancel) controller.abort();
        if (cancel) {
          await assert.rejects(runCapturedStrategy(setup, settings, controller.signal), {name:'AbortError'});
          continue;
        }
        execution = await runCapturedStrategy(setup, settings, controller.signal);
        assert.equal(execution.status, cancel ? 'host-tasks-failed' : 'host-tasks-completed',
          `mode=${mode}: ${String(execution.failure)}`);
        if (cancel) {
          assert.equal(execution.completed.length, 0);
          assert.equal(execution.usage().attempts, 0n);
        } else {
          assert.deepEqual(execution.completed.map(item => item.realization),
            Array(3).fill(mode === 0 ? 'local' : mode === 3 ? 'duckdb' : 'reference-numeric'));
          assert.equal(fixture.strategyFixtureCid(f, 3), hash([{id:3}, {id:3}]));
          if (mode === 3) assert.ok(execution.usage().transferredBytes > 0n);
          else assert.equal(execution.usage().transferredBytes, 0n);
          if (mode === 0 || mode === 3) {
            const runtime = runtimeCore(hostRuntime);
            const publicationDirectory = await mkdtemp(join(
              root, '_build/duckdb-fixtures/publication-payload-',
            ));
            const publicationStore = await openLocalPublicationStore({
              directory: publicationDirectory,
              storeAuthorityCid: hash('publication-store'),
              capacityBytes: 4 * 1024 * 1024,
              maxObjectBytes: publicationResultExportLimits.maxWireBytes,
              maxObjects: 100,
              maxContractNodes: 10000,
              maxContractDepth: 64,
            }, runtime.publicationControl);
            try {
              const effectiveDataPolicyCid = hash('effective-policy');
              const contractLimits = {
                maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64,
              };
              const runDefinition = runtime.publicationControl.seal(
                'run_definition',
                JSON.stringify({
                  version: 'actql-run-definition/0.1',
                  scope_id: 'publication-test-scope',
                  run_id: 'publication-test-run',
                  compiled_plan_cid: hash('compiled-plan'),
                  invocation_template_cid: hash('invocation-template'),
                  authorization_context_cid: hash('authorization-context'),
                  input_artifact_set_cid: hash('input-artifact-set'),
                  created_at: '2026-09-18T00:00:00.000Z',
                  valid_until: '2026-09-18T04:00:00.000Z',
                }),
                contractLimits,
              );
              const invocation = runtime.publicationControl.seal(
                'run_invocation',
                JSON.stringify({
                  version: 'actql-run-invocation/0.1',
                  invocation_template_cid: hash('invocation-template'),
                  observation_set_cid: hash('observation-set'),
                }),
                contractLimits,
              );
              const retention = runtime.publicationControl.seal(
                'result_retention_policy',
                JSON.stringify({
                  version: 'actql-result-retention-policy/0.1',
                  retention_contract_cid: hash('retention-contract'),
                  effective_data_policy_cid: effectiveDataPolicyCid,
                  available_until: '2026-09-18T01:00:00.000Z',
                  delete_by: '2026-09-18T02:00:00.000Z',
                  extension_ceiling_at: '2026-09-18T03:00:00.000Z',
                  metadata_retention_policy_cid: hash('metadata-retention'),
                  clock_contract_cid: hash('clock-contract'),
                }),
                contractLimits,
              );
              const stored = await execution.storePublicationResult(
                0,
                publicationStore,
                {
                  outputLimits: publicationResultExportLimits,
                  contractLimits,
                  runDefinition,
                  invocation,
                  retention,
                  evidenceContext: {
                    computationContractCid: hash('checked-computation'),
                    inputRelationCids: [],
                    scopeCid: hash('result-scope'),
                    effectiveDataPolicyCid,
                    authorityScopeCid: hash('authority-scope'),
                  },
                },
                controller.signal,
              );
              const identity = stored.orderedRows;
              const payload = [];
              await publicationStore.consumeObject(
                stored.physical.cid,
                chunk => payload.push(Buffer.from(chunk)),
              );
              assert.deepEqual(JSON.parse(Buffer.concat(payload)
                .toString('utf8')), [{id: 3}, {id: 2}, {id: 3}]);
              assert.match(identity.logicalRelationCid,
                /^sha256:[0-9a-f]{64}$/u);
              assert.match(identity.resultSchemaCid,
                /^sha256:[0-9a-f]{64}$/u);
              const derivation = JSON.parse(
                stored.publication.derivation.wire,
              );
              const ordering = JSON.parse(stored.publication.ordering.wire);
              assert.equal(derivation.producer_contract_cid,
                stored.occurrence.definition.identity);
              assert.equal(derivation.logical_value_cid,
                identity.logicalRelationCid);
              assert.equal(derivation.relation_schema_cid,
                identity.resultSchemaCid);
              assert.deepEqual(ordering.witness_evidence, [{
                kind: 'derivation',
                cid: stored.publication.derivation.identity,
              }]);
              const artifactValue = JSON.parse(
                stored.publication.artifact.wire,
              );
              assert.deepEqual(stored.publication.snapshot, {
                kind: 'captured-result-snapshot',
              });
              assert.equal(artifactValue.logical_result_cid,
                identity.logicalRelationCid);
              assert.equal(artifactValue.result_schema_cid,
                identity.resultSchemaCid);
              assert.equal(artifactValue.actual_row_count, 3);
              assert.equal(artifactValue.ordering_evidence_cid,
                stored.publication.ordering.identity);
              const bindingValue = JSON.parse(
                stored.publication.durableBinding.wire,
              );
              assert.equal(bindingValue.run_definition_cid,
                runDefinition.identity);
              assert.equal(bindingValue.result_definition_cid,
                stored.occurrence.definition.identity);
              assert.equal(bindingValue.material_generation_cid,
                stored.physical.cid);
              assert.equal(bindingValue.codec_contract_cid,
                identity.codecContractCid);
              assert.equal(bindingValue.store_authority_cid,
                publicationStore.storeAuthorityCid);
              assert.equal(bindingValue.byte_count, stored.physical.bytes);
              assert.equal(await stored.prepared.release(), true);

              const programDefinitionCid = execution.programDefinitionCid;
              const template = runtime.publicationControl.sealRunEvidence(
                'bound_invocation_template',
                JSON.stringify({
                  version: 'actql-bound-invocation-template/0.1',
                  program_definition_cid: programDefinitionCid,
                  parameter_values_cid: hash('parameter-values'),
                  invocation_bindings_cid: hash('invocation-bindings'),
                  check_environment_cid: hash('check-environment'),
                  grammar_manifest_cid: hash('grammar-manifest'),
                  required_profile_contracts: [],
                  barrier_contract_manifest_cid:
                    hash('barrier-contract-manifest'),
                  source_evidence: 'unbound',
                }),
                contractLimits,
              );
              const compiledPlan = runtime.publicationControl.seal(
                'compiled_plan',
                JSON.stringify({
                  version: 'actql-compiled-plan/0.1',
                  compiler_version: 'compiler-test-0.1',
                  aoa_ir_version: 'aoa-ir-test-0.1',
                  executable_plan_cid: hash('executable-plan'),
                  program_definition_cid: programDefinitionCid,
                  program_semantics_cid: hash('program-semantics'),
                  aoa_contract_cid: hash('aoa-contract'),
                  aoa_logical_cid: hash('aoa-logical'),
                }),
                contractLimits,
              );
              const preparedInvocation =
                runtime.publicationControl.sealRunEvidence(
                  'prepared_invocation',
                  JSON.stringify({
                    version: 'actql-prepared-invocation/0.1',
                    invocation_template_cid: template.identity,
                    compiled_plan_cid: compiledPlan.identity,
                    execution_context_cid: hash('execution-context'),
                    host_policy_cid: hash('host-policy'),
                    policy_decision: 'allow',
                    expires_at: '2026-09-18T03:00:00.000Z',
                  }),
                  contractLimits,
                );
              const authorization =
                runtime.publicationControl.sealRunEvidence(
                  'run_authorization',
                  JSON.stringify({
                    version: 'actql-run-authorization/0.1',
                    prepared_invocation_cid: preparedInvocation.identity,
                    execution_context_cid: hash('execution-context'),
                    host_policy_cid: hash('host-policy'),
                    decision: 'allowed',
                  }),
                  contractLimits,
                );
              const admission =
                runtime.publicationControl.admitRunPublication(
                  template,
                  preparedInvocation,
                  authorization,
                  compiledPlan,
                );
              const publishedRun =
                runtime.publicationControl.issueRunDefinition(admission, {
                  scopeId: 'standard-host-publication-scope',
                  runId: 'standard-host-publication-run',
                  inputArtifactSetCid: hash('input-artifact-set'),
                  createdAt: '2026-09-18T00:00:00.000Z',
                  validUntil: '2026-09-18T02:30:00.000Z',
                }, contractLimits);
              const publishedObservation =
                runtime.publicationControl.sealRunEvidence(
                  'observation_set',
                  JSON.stringify({
                    version: 'actql-observation-set/0.1',
                    invocation_template_cid: template.identity,
                    source_evidence_cids: [],
                    captured_input_artifact_cids: [],
                    consistency: 'no_external_sources',
                    capture_started_at: null,
                    capture_completed_at: null,
                    replayability: {
                      materialized: false,
                      availability_evidence_cids: [],
                    },
                    data_policy_cid: effectiveDataPolicyCid,
                  }),
                  contractLimits,
                );
              const publishedInvocation =
                runtime.publicationControl.issueRunInvocation(
                  template, publishedObservation, contractLimits,
                );
              const publishedRetention = runtime.publicationControl.seal(
                'result_retention_policy',
                JSON.stringify({
                  version: 'actql-result-retention-policy/0.1',
                  retention_contract_cid: hash('retention-contract'),
                  effective_data_policy_cid: effectiveDataPolicyCid,
                  available_until: '2026-09-18T01:00:00.000Z',
                  delete_by: '2026-09-18T02:00:00.000Z',
                  extension_ceiling_at: '2026-09-18T03:00:00.000Z',
                  metadata_retention_policy_cid:
                    hash('metadata-retention'),
                  clock_contract_cid: hash('clock-contract'),
                }),
                contractLimits,
              );
              const normalizationJournal =
                runtime.publicationControl.sealRunEvidence(
                  'normalization_journal',
                  JSON.stringify({
                    version: 'actql-normalization-journal/0.1',
                    rule_catalog_cid: hash('rule-catalog'),
                    entries: [],
                  }),
                  contractLimits,
                );
              const authoringContext =
                runtime.publicationControl.sealRunEvidence(
                  'authoring_context',
                  JSON.stringify({
                    version: 'actql-authoring-context/0.1',
                    program_definition_cid: programDefinitionCid,
                    annotations: [],
                  }),
                  contractLimits,
                );
              const publicationPlan = {
                admission,
                runDefinition: publishedRun,
                invocation: publishedInvocation,
                observation: publishedObservation,
                normalizationJournal,
                authoringContext,
                results: execution.publicationInventory.occurrences.map(
                  (occurrence, resultIndex) => ({
                    retention: publishedRetention,
                    evidenceContext: {
                      computationContractCid: hash(
                        `checked-computation-${resultIndex}`,
                      ),
                      inputRelationCids: [],
                      scopeCid: hash(`result-scope-${resultIndex}`),
                      effectiveDataPolicyCid,
                      authorityScopeCid: hash('authority-scope'),
                    },
                  }),
                ),
                receiptEvidence: {
                  bindings: [],
                  sourceEvidence: [],
                  modelEvidence: [],
                  barrierAttemptReceiptCids: [],
                },
                captureEvidence: {
                  pendingSourceStateAdvances: [],
                  modelEvidence: [],
                },
                request: {
                  tenantId: 'tenant-a',
                  authorityScopeCid: hash('authority-scope'),
                  publicationPolicyCid: hash('publication-policy'),
                  publicationTargetCid: hash('publication-target'),
                  requestedAt: '2026-09-18T00:00:00.000Z',
                },
                attempt: {
                  attemptId: 'standard-host-attempt',
                  fenceCid: hash('publication-fence'),
                  externalIdempotencyKey: undefined,
                  startedAt: '2026-09-18T00:00:01.000Z',
                },
                outputLimits: publicationResultExportLimits,
                contractLimits,
                now: () => '2026-09-18T00:00:02.000Z',
              };
              const lateRejectionDirectory = await mkdtemp(join(
                root,
                '_build/duckdb-fixtures/rejected-late-publication-',
              ));
              let lateRejectionStore;
              try {
                lateRejectionStore = await openLocalPublicationStore({
                  directory: lateRejectionDirectory,
                  storeAuthorityCid: hash('rejected-late-publication-store'),
                  capacityBytes: 1024,
                  maxObjectBytes:
                    publicationResultExportLimits.maxWireBytes,
                  maxObjects: 100,
                  maxContractNodes: 10000,
                  maxContractDepth: 64,
                }, runtime.publicationControl);
                const attempts = execution.usage().attempts;
                const expectLateRejection = async (plan, code) => {
                  await assert.rejects(execution.publishEffectFreeRun(
                    lateRejectionStore,
                    plan,
                    controller.signal,
                  ), {code});
                  assert.equal(execution.usage().attempts, attempts);
                  assert.equal(lateRejectionStore.status().storedBytes, 0);
                  assert.equal(lateRejectionStore.status().reservedBytes, 0);
                  assert.equal(lateRejectionStore.status().objectCount, 0);
                  assert.equal(lateRejectionStore.status().reservedObjects, 0);
                };
                await expectLateRejection({
                  ...publicationPlan,
                  results: publicationPlan.results.map((result, index) =>
                    index === 0 ? {retention: result.retention} : result),
                }, 'InvalidRunPublicationPreflight');
                await expectLateRejection({
                  ...publicationPlan,
                  request: {
                    ...publicationPlan.request,
                    authorityScopeCid: hash('foreign-authority-scope'),
                  },
                }, 'IncompatibleRunPublicationPreflight');
                const foreignRetention =
                  runtime.publicationControl.seal(
                    'result_retention_policy',
                    JSON.stringify({
                      version: 'actql-result-retention-policy/0.1',
                      retention_contract_cid:
                        hash('retention-contract'),
                      effective_data_policy_cid:
                        hash('foreign-effective-policy'),
                      available_until: '2026-09-18T01:00:00.000Z',
                      delete_by: '2026-09-18T02:00:00.000Z',
                      extension_ceiling_at:
                        '2026-09-18T03:00:00.000Z',
                      metadata_retention_policy_cid:
                        hash('metadata-retention'),
                      clock_contract_cid: hash('clock-contract'),
                    }),
                    contractLimits,
                  );
                await expectLateRejection({
                  ...publicationPlan,
                  results: publicationPlan.results.map(result => ({
                    ...result,
                    retention: foreignRetention,
                  })),
                }, 'IncompatibleRunPublicationPreflight');
                await assert.rejects(execution.publishEffectFreeRun(
                  lateRejectionStore,
                  publicationPlan,
                  controller.signal,
                ), {code: 'RunPublicationCapacityUnsupported'});
                assert.equal(execution.usage().attempts, attempts);
                assert.equal(lateRejectionStore.status().storedBytes, 0);
                assert.equal(lateRejectionStore.status().reservedBytes, 0);
                assert.equal(lateRejectionStore.status().objectCount, 0);
                assert.equal(lateRejectionStore.status().reservedObjects, 0);
              } finally {
                await lateRejectionStore?.close();
                await rm(lateRejectionDirectory, {
                  recursive: true,
                  force: true,
                });
              }
              const published = await execution.publishEffectFreeRun(
                publicationStore,
                publicationPlan,
                controller.signal,
              );
              assert.equal(published.publication.state, 'succeeded');
              assert.equal(published.results.length,
                execution.publicationInventory.occurrences.length);
              assert.equal(published.evidence.artifacts.length,
                execution.publicationInventory.occurrences.length);
              for (const occurrence of
                execution.publicationInventory.occurrences) {
                const received = [];
                await publicationStore.consumeCommittedResult({
                  tenantId: 'tenant-a',
                  authorityScopeCid: hash('authority-scope'),
                  runDefinitionCid: publishedRun.identity,
                }, occurrence.definitionContract.identity,
                  () => true, chunk => received.push(Buffer.from(chunk)));
                assert.ok(received.length > 0);
              }
              const accessAuthority = installResultAccessAuthority({
                admitResultRead: () => ({
                  authorizationContextCid: hash('authorization-context'),
                  dataCeilingCid: hash('data-ceiling'),
                  egressAdmissionCid: hash('egress-admission'),
                  expiresAt: '2026-09-18T01:00:00.000Z',
                  maxBytes: 100000,
                  maxUses: 1,
                }),
                authorizeResultRead: () => true,
              });
              const accessService = installNodeResultAccessService({
                store: publicationStore,
                control: runtime.publicationControl,
                authority: accessAuthority,
                now: () => '2026-09-18T00:30:00.000Z',
                limits: contractLimits,
                frameLimits: {
                  maxRowBytes: 4096,
                  maxDepth: 32,
                  maxFrameBytes: 4096,
                },
              });
              const expectedDelivery = {
                b: {
                  json: '[{"id":3},{"id":2},{"id":3}]',
                  jsonl: '{"id":3}\n{"id":2}\n{"id":3}\n',
                  csv: '"id"\n3\n2\n3\n',
                },
                c: {
                  json: '[{"id":3},{"id":3}]',
                  jsonl: '{"id":3}\n{"id":3}\n',
                  csv: '"id"\n3\n3\n',
                },
              };
              for (const occurrence of
                execution.publicationInventory.occurrences) {
                for (const format of ['json', 'jsonl', 'csv']) {
                  const delivered = [];
                  const result = await deliverAuthorizedResult(
                    accessService,
                    {
                      indexKey: {
                        tenantId: 'tenant-a',
                        authorityScopeCid: hash('authority-scope'),
                        runDefinitionCid: publishedRun.identity,
                      },
                      principalId: 'principal-a',
                      purpose: 'download',
                      resultName: occurrence.name,
                      format,
                      attemptId:
                        `standard-host-${mode}-${occurrence.name}-${format}`,
                    },
                    {
                      async write(bytes) {
                        delivered.push(Buffer.from(bytes));
                        return {confirmedBytes: bytes.byteLength};
                      },
                    },
                    controller.signal,
                  );
                  assert.equal(result.idempotent, false);
                  assert.equal(
                    Buffer.concat(delivered).toString('utf8'),
                    expectedDelivery[occurrence.name][format],
                  );
                }
              }
            } finally {
              await publicationStore.close();
              await rm(publicationDirectory, {recursive: true, force: true});
            }
          }
        }
      } finally { execution?.close(); capture.close(); }
      assert.equal(execution.cleanupPending(), false);
      assert.equal(await execution.cleanup(), true);
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
    }
  }
  await replaceRows(
    'INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)',
  );
  for (const mode of [0, 3]) {
    const publicationFixture = fixture.strategyFixtureCreate(
      ...args,
      JSON.stringify(numericProgram),
    );
    const publicationCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(publicationFixture),
      suppliedLimits,
    );
    const publicationDirectory = await mkdtemp(join(
      root,
      `_build/duckdb-fixtures/standard-publication-entry-${mode}-`,
    ));
    let publicationOwner;
    let publicationStore;
    try {
      assert.equal(
        fixture.strategyFixtureOpen(
          publicationFixture,
          publicationCapture.source(),
        ),
        true,
      );
      const setup = mode === 3
        ? fixture.strategyFixtureDuckDBOnly(publicationFixture)
        : fixture.strategyFixtureModuleSubset(publicationFixture, mode);
      const runtime = runtimeCore(hostRuntime);
      const resultCount = runtime.resultInventory(setup).length;
      const programDefinitionCid = runtime.programDefinitionCid(setup);
      publicationStore = await openLocalPublicationStore({
        directory: publicationDirectory,
        storeAuthorityCid: hash(`standard-publication-entry-store-${mode}`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime,
        programDefinitionCid,
        resultCount,
        `standard-publication-entry-attempt-${mode}`,
      );
      const absent = new Proxy({}, {
        get() {
          assert.fail('unused Compute provider settings accessed');
        },
      });
      const settings = mode === 3
        ? {duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000},
        })}
        : {duckdb: absent};
      publicationOwner = await runPublishedCapturedStrategy(
        setup,
        {store: publicationStore, plan},
        settings,
        new AbortController().signal,
      );
      assert.equal(publicationOwner.status, 'published');
      assert.equal(
        publicationOwner.execution.status,
        'host-tasks-completed',
      );
      assert.deepEqual(
        publicationOwner.execution.completed.map(value => value.realization),
        Array(3).fill(mode === 3 ? 'duckdb' : 'local'),
      );
      assert.equal(
        publicationOwner.publication.publication.state,
        'succeeded',
      );
      assert.equal(
        publicationOwner.publication.results.length,
        resultCount,
      );
      assert.equal(
        publicationOwner.publication.evidence.artifacts.length,
        resultCount,
      );
      assert.equal(
        publicationOwner.execution.publicationPreflight.request.identity,
        publicationOwner.publication.publication.request.identity,
      );
      assert.deepEqual(
        await publicationStore.inspectCommittedIndex({
          tenantId: plan.request.tenantId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }),
        JSON.parse(publicationOwner.publication.publication.index.wire),
      );
    } finally {
      if (publicationOwner !== undefined) {
        await publicationOwner.close();
        assert.equal(publicationOwner.cleanupPending(), false);
        assert.equal(await publicationOwner.cleanup(), true);
        assert.equal(publicationOwner.execution.usage().heldBytes, 0n);
        assert.equal(
          publicationOwner.execution.usage().reservedExecutionBytes,
          0n,
        );
      }
      publicationCapture.close();
      await publicationStore?.close();
      await rm(publicationDirectory, {recursive: true, force: true});
    }
  }
  const rejectedPublicationFixture = fixture.strategyFixtureCreate(
    ...args,
    JSON.stringify(numericProgram),
  );
  const rejectedPublicationCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(rejectedPublicationFixture),
    suppliedLimits,
  );
  const rejectedPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/rejected-standard-publication-entry-',
  ));
  let rejectedPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(
        rejectedPublicationFixture,
        rejectedPublicationCapture.source(),
      ),
      true,
    );
    const setup = fixture.strategyFixtureModuleSubset(
      rejectedPublicationFixture,
      0,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    rejectedPublicationStore = await openLocalPublicationStore({
      directory: rejectedPublicationDirectory,
      storeAuthorityCid: hash('rejected-standard-publication-store'),
      capacityBytes: 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'rejected-standard-publication-attempt',
    );
    await assert.rejects(runPublishedCapturedStrategy(
      setup,
      {store: rejectedPublicationStore, plan},
      {},
      new AbortController().signal,
    ), {
      code: 'RunPublicationCapacityUnsupported',
    });
    assert.equal(
      fixture.strategyFixtureUsage(rejectedPublicationFixture, 3),
      0n,
    );
    assert.equal(
      fixture.strategyFixtureUsage(rejectedPublicationFixture, 4),
      0n,
    );
    assert.equal(rejectedPublicationStore.status().reservedBytes, 0);
    assert.equal(rejectedPublicationStore.status().reservedObjects, 0);
  } finally {
    rejectedPublicationCapture.close();
    await rejectedPublicationStore?.close();
    await rm(rejectedPublicationDirectory, {
      recursive: true,
      force: true,
    });
  }
  // The runnable application reads user-supplied documents, not conformance
  // exports or test catalogs. Tests supply their own documents at its boundary.
  const exampleDirectory = await mkdtemp(join(root, '_build/duckdb-fixtures/example-input-'));
  try {
    await exerciseManagedExample(path, args[0], args[1], hash([{id: 3}, {id: 3}]));
    const environment = join(exampleDirectory, 'environment.json');
    const programFile = join(exampleDirectory, 'program.json');
    const parameters = join(exampleDirectory, 'parameters.json');
    const exampleProgram = await readFile(join(root, 'adapters/duckdb-node/examples/program.json'), 'utf8');
    await Promise.all([writeFile(environment, args[0]), writeFile(programFile, exampleProgram),
      writeFile(parameters, '{"minimum":1}')]);
    for (const [estimate, expected] of [['1', ['duckdb', 'duckdb', 'duckdb']],
      ['20', ['local', 'local', 'local']], ['5', ['duckdb', 'duckdb', 'local']]]) {
      const result = await runExample({ database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate });
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.equal(result.report.program_success, false);
        assert.deepEqual(result.report.completed.map(item => item.realization), expected);
        assert.equal(result.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
        assert(BigInt(result.report.explanation.ledger.transferred_bytes) > 0n);
      } finally { result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    for (const [fileWork, native, imports, expected] of [
      ['0', '1', undefined, ['duckdb', 'duckdb', 'duckdb']],
      ['100', '1', undefined, ['local', 'local', 'local']],
      ['0', '5', '0', ['duckdb', 'duckdb', 'local']],
    ]) {
      const beforeFiles = (await readdir(exampleDirectory)).sort();
      const evidenceRuntime = await import(pathToFileURL(join(root, '_build/js/release/build/retained_host_bridge/retained_host_bridge.js')));
      const observed = [];
      const observer = installCompletionObserver(({task, output}) => {
        const retained = expected[observed.length] === 'duckdb';
        if (!retained) {
          observed.push({task});
          return;
        }
        const evidence = checked(evidenceRuntime.retainedCompletionEvidence(output, 10, 10));
        const descriptor = evidenceRuntime.retainedCompletionDescriptor(evidence);
        assert.equal(evidenceRuntime.retainedCompletionCanHandoff(evidence, output), true);
        assert.equal(descriptor.input_count, 1);
        assert.equal(descriptor.output_step, 1);
        observed.push({task, output, evidence, descriptor});
      });
      const result = await runExample({database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: native,
        localImportWorkMilliseconds: imports,
        retainedWorkMilliseconds: fileWork,
        retainedOutput: {parentDirectory: exampleDirectory, maxFrameBytes: 100000,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000}}}, observer);
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.deepEqual(result.report.completed.map(item => item.realization), expected);
        assert.equal(result.report.internal_output_cids[2].cid, hash([{id: 3}, {id: 3}]));
        assert.deepEqual(observed.map(value => value.task), result.report.completed.map(value => value.task));
        for (const record of observed) {
          if (record.descriptor) assert.equal(record.descriptor.rows_cid,
            result.report.internal_output_cids.find(value => value.task === record.task).cid);
        }
        if (imports !== undefined) {
          assert.equal(result.report.completed[2].importedRows, 2);
          assert.equal(result.report.completed[2].importedBytes, '19');
        }
        if (expected.includes('duckdb')) {
          assert(result.report.completed.filter(item => item.realization === 'duckdb')
            .every(item => item.outputRepresentation === 'retained-file'));
          assert((await readdir(exampleDirectory)).length > beforeFiles.length);
        } else assert.deepEqual((await readdir(exampleDirectory)).sort(), beforeFiles);
      } finally { await result.close(); }
      for (const record of observed) {
        if (record.evidence) {
          assert.equal(evidenceRuntime.retainedCompletionCanHandoff(record.evidence, record.output), false);
          assert.deepEqual(evidenceRuntime.retainedCompletionDescriptor(record.evidence), record.descriptor);
        }
      }
      assert.equal(result.execution.usage().heldBytes, 0n);
      assert.deepEqual((await readdir(exampleDirectory)).sort(), beforeFiles);
    }
    const residentExample = await runExample({ database: path, environment, environmentCid: args[1],
      program: programFile, parameters, nativeMilliseconds: '20', resident: true });
    try {
      assert.equal(residentExample.report.status, 'host-tasks-completed');
      assert.deepEqual(residentExample.report.completed.map(item => item.realization),
        ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
      assert.equal(residentExample.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
      assert.equal(residentExample.report.cleanup_pending, false);
      assert.equal(residentExample.report.explanation.selection.dispatch_authorized, false);
      assert.equal(residentExample.report.explanation.selection.tasks[0].resident_profile.database_bytes, '134217728');
    } finally { residentExample.close(); }
    // A one-step count has a different final port from filter/select. It must
    // pass the actual DAG, both physical realizations and resident reuse; C
    // consumes A's count result rather than an invented Step(1) output.
    const countProgram = JSON.parse(exampleProgram);
    countProgram.stages[1].steps = [{ group: { by: [], aggregates: { id: { fn: 'count' } } }, as: 'out' }];
    await writeFile(programFile, JSON.stringify(countProgram));
    for (const [estimate, resident, expected] of [
      ['20', false, 'local'], ['1', false, 'duckdb'], ['20', true, 'duckdb-resident'],
    ]) {
      const result = await runExample({ database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate, resident });
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.equal(result.report.completed[0].realization, expected);
        assert.equal(result.report.internal_output_cids[0].cid, hash([{ id: 3 }]));
        assert.equal(result.report.internal_output_cids[2].cid, hash([{ id: 3 }]));
        assert.equal(result.report.cleanup_pending, false);
      } finally { result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    // Statically unsupported native expressions must never win on price.
    const arithmeticProgram = JSON.parse(exampleProgram);
    arithmeticProgram.stages[1].steps[0].filter = 'id + 0 > 2';
    await writeFile(programFile, JSON.stringify(arithmeticProgram));
    for (const estimate of ['1', '20']) {
      const result = await runExample({ database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate });
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.equal(result.report.completed[0].realization, 'local');
        assert.equal(result.report.internal_output_cids[2].cid, hash([{ id: 3 }, { id: 3 }]));
        assert(result.report.explanation.excluded_realizations.some(item =>
          item.task === 1 && item.reason === 'unsupported_predicate'));
      } finally { result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    await writeFile(programFile, exampleProgram);
    const cli = await promisify(execFile)(process.execPath, [
      'adapters/duckdb-node/examples/physical-strategy.mjs', '--database', path,
      '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '5',
    ], { cwd: root, maxBuffer: 1000000 });
    assert.equal(JSON.parse(cli.stdout).status, 'host-tasks-completed');
    const residentCli = await promisify(execFile)(process.execPath, [
      'adapters/duckdb-node/examples/physical-strategy.mjs', '--database', path,
      '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '20', '--resident',
    ], { cwd: root, maxBuffer: 1000000 });
    const residentReport = JSON.parse(residentCli.stdout);
    assert.equal(residentReport.status, 'host-tasks-completed');
    assert.deepEqual(residentReport.completed.map(item => item.realization),
      ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
    const exampleGuide = await readFile(join(root, 'adapters/duckdb-node/examples/README.md'), 'utf8');
    assert.match(exampleGuide, /## Resident candidates/);
    assert.match(exampleGuide, /`--resident` defaults to false/);
    assert.match(exampleGuide, /--native-ms 20 --resident/);
    assert.match(exampleGuide, /does not force every task/);
    assert.match(exampleGuide, /500000 cumulative transfer bytes/);
    assert.doesNotMatch(exampleGuide, /no resident DuckDB\s+sharing/);
    await assert.rejects(runExample({ database: path, environment,
      environmentCid: 'sha256:' + '0'.repeat(64), program: programFile,
      parameters, nativeMilliseconds: '5' }));
    const applicationSource = await readFile(join(root, 'src/physical_strategy_example/moon.pkg'), 'utf8');
    assert.doesNotMatch(applicationSource, /conformance|query_integration/);
    const script = await readFile(join(root, 'adapters/duckdb-node/examples/physical-strategy.mjs'), 'utf8');
    assert.doesNotMatch(script, /duckdb_conformance|query_integration/);
    await writeFile(programFile, await readFile(join(root,
      'adapters/duckdb-node/examples/join-count.json'), 'utf8'));
    for (const [estimate, resident, expected, retained] of [
      ['20', false, ['local', 'local', 'local', 'local']],
      ['1', false, ['duckdb', 'duckdb', 'duckdb', 'duckdb']],
      ['20', true, ['local', 'local', 'duckdb-resident', 'duckdb-resident']],
      ['1', false, ['duckdb', 'duckdb', 'duckdb', 'duckdb'], true],
    ]) {
      const result = await runExample({ database: path, environment,
        environmentCid: args[1], program: programFile, parameters,
        nativeMilliseconds: estimate, resident,
        ...(retained ? {localImportWorkMilliseconds: '0', retainedWorkMilliseconds: '0',
          retainedOutput: {parentDirectory: exampleDirectory, maxFrameBytes: 100000,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000}}} : {}) });
      try {
        assert.equal(result.report.status, 'host-tasks-completed', String(result.execution.failure));
        assert.deepEqual(result.report.completed.map(item => item.realization), expected);
        assert.equal(result.report.internal_output_cids.length, 4);
        assert.equal(result.report.internal_output_cids[3].cid, hash([{ id: 3, n: 4, present: 4 }]));
        if (retained) assert(result.report.completed.every(item => item.outputRepresentation === 'retained-file'));
      } finally { await result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    // Value-sensitive join obligations use verified key-only import scratch.
    // Both retained branches contain duplicate id=3; NULL rejection succeeds,
    // whereas one-to-one must fail before the native join publishes any result.
    for (const [obligation, succeeds] of [
      [{null_key: 'fail'}, true], [{cardinality: 'one_to_one'}, false],
    ]) {
      const joined = JSON.parse(await readFile(join(root,
        'adapters/duckdb-node/examples/join-count.json'), 'utf8'));
      Object.assign(joined.stages[3].steps[0].join, obligation);
      await writeFile(programFile, JSON.stringify(joined));
      const result = await runExample({database: path, environment,
        environmentCid: args[1], program: programFile, parameters,
        nativeMilliseconds: '1', localImportWorkMilliseconds: '0',
        retainedWorkMilliseconds: '0',
        retainedOutput: {parentDirectory: exampleDirectory, maxFrameBytes: 100000,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000}}});
      try {
        assert.equal(result.report.status, succeeds ? 'host-tasks-completed' : 'host-tasks-failed',
          String(result.execution.failure));
        assert.equal(result.report.completed.length, succeeds ? 4 : 2);
        assert(result.report.completed.every(item => item.outputRepresentation === 'retained-file'));
        if (succeeds) {
          assert.equal(result.report.internal_output_cids[3].cid, hash([{id: 3, n: 4, present: 4}]));
        } else {
          assert.equal(result.execution.failure.code, 'MoonBitHostFailure');
          assert(result.execution.failure.cause, 'preserve the typed join validation failure');
          assert.equal(result.execution.cleanupPending(), true,
            'failed import keeps its explicit physical cleanup responsibility');
        }
      } finally { await result.close(); }
      assert.equal(await result.execution.cleanup(), true);
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
  } finally { await rm(exampleDirectory, { recursive: true, force: true }); }
  // Real binary fan-in: a single captured observation feeds two independent
  // branches, an equijoin, then a count consumer. Only physical placement varies.
  for (const selfJoin of [false, true]) {
    const joined = JSON.parse(program);
    joined.stages[3] = { id: 'compute_c', inputs: {
      l: { result: { stage: 'compute_a', result: 'r' } },
      r: { result: { stage: selfJoin ? 'compute_a' : 'compute_b', result: 'r' } },
    }, steps: [{ join: { with: 'r', kind: 'inner',
      on: [{ left: 'id', right: 'id' }], select: { id: 'left.id' } }, from: 'l', as: 'out' }],
    results: { r: { from: 'out', fields: ['id'] } } };
    joined.stages.push({ id: 'count_d', inputs: { x: { result: { stage: 'compute_c', result: 'r' } } },
      steps: [{ group: { by: [], aggregates: { n: { fn: 'count' } } }, as: 'out' }],
      results: { r: { from: 'out', fields: ['n'] } } });
    joined.results = { out: { from: { stage: 'count_d', result: 'r' } } };
    let freshTransfer;
    for (const placement of ['local', 'duckdb', 'resident']) {
      await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      const f = fixture.strategyFixtureJoinCreate(...args, JSON.stringify(joined));
      const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
      let execution;
      try {
        assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
        await replaceRows('INSERT INTO records VALUES (99,99)');
        const dispatch = placement === 'resident'
          ? fixture.strategyFixtureResidentDispatch(f) : fixture.strategyFixtureDispatch(f);
        if (placement !== 'resident') assert.equal(fixture.strategyFixtureReplan(f, placement === 'local' ? 20n : 1n), true);
        execution = await runCapturedStrategy(dispatch, {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 100, maxCells: 1000 }})});
        assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
        assert.deepEqual(execution.completed.map(value => value.realization),
          Array(4).fill(placement === 'resident' ? 'duckdb-resident' : placement));
        assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }, { id: 3 }, { id: 3 }]));
        assert.equal(fixture.strategyFixtureCid(f, 4), hash([{ n: 4 }]));
        if (placement === 'duckdb') freshTransfer = execution.usage().transferredBytes;
        if (placement === 'resident') assert(execution.usage().transferredBytes < freshTransfer,
          'actual shared import and intermediate reuse reduce bytes, not merely estimated cost');
        capture.close();
        fixture.strategyFixtureCloseOutput(f, 1);
        fixture.strategyFixtureCloseOutput(f, 2);
        fixture.strategyFixtureCloseOutput(f, 3);
        assert.equal(fixture.strategyFixtureCid(f, 4), hash([{ n: 4 }]));
      } finally { execution?.close(); capture.close(); }
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
      assert.equal(execution.cleanupPending(), false);
    }
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  // Inspect the product bridge's reservation phases without issuing execution
  // evidence: no native task is run, and its deliberately absent result fails.
  const phaseFixture = fixture.strategyFixtureCreate(...args, program);
  for (const transferCost of [1n, 20n]) {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      assert.equal(fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f))), true);
      assert.equal(fixture.strategyFixtureReplan(f, transferCost), true);
      execution = await runCapturedStrategy(fixture.strategyFixtureDispatch(f), {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 100, maxCells: 1000 }})});
      assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
      // The 300000-byte ledger already contains acquisition traffic. Three
      // 100000-byte native transfer reservations cannot fit; equal-cost mixed
      // strategies follow the fixture's fixed enumeration priority.
      assert.deepEqual(execution.completed.map(item => [item.task, item.realization]),
        [1, 2, 3].map(task => [task, transferCost === 1n && task !== 1 ? 'duckdb' : 'local']));
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      const spent = BigInt(capture.usage.transportBytes) + execution.completed.reduce(
        (sum, item) => sum + BigInt(item.transport?.transportBytes ?? 0), 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      const explanation = execution.explain();
      assert.equal(explanation.program_success, false);
      assert.equal(explanation.assessment_complete, true);
      assert.equal(explanation.selection.reason, 'estimated_fastest');
      assert.equal(explanation.selection.remaining_at_selection.estimated_milliseconds,
        transferCost === 1n ? '14' : '30');
      assert.equal(explanation.selection.ledger_at_selection.transferred_bytes,
        String(capture.usage.transportBytes));
      assert.equal(explanation.ledger.transferred_bytes, String(spent));
      assert.deepEqual(explanation.available_root_statistics, { rows: '3', canonical_wire_bytes: '28' });
      assert(explanation.assessed_strategies.some(item => item.rejection === 'transfer_limit'));
      assert(explanation.selection.tasks.every(item => item.completed));
      assert.deepEqual(explanation.selection.tasks[0].work_estimates,
        [{ slots: [0, 1, 2, 3, 4], milliseconds: '10' }]);
      assert.throws(() => execution.explain(1, 10000));
      assert.throws(() => execution.explain(-1, 10000), { code: 'InvalidExplanationLimit' });
      assert.notEqual(execution.output(3), undefined);
      capture.close();
      assert.equal(execution.explain().available_root_statistics, null);
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      assert.throws(() => execution.output(3), { code: 'ReleasedStrategy' });
    } finally { execution?.close(); capture.close(); }
  }
  // Product dispatch automatically refreshes unstarted choices after actual
  // completion. A's observed two rows replace its three-row forecast for C.
  {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      assert.equal(fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f))), true);
      const setup = fixture.strategyFixtureAdaptiveDispatch(f);
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 0), 'LDD');
      execution = await runCapturedStrategy(setup, {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 100, maxCells: 1000 }})});
      assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
      assert.deepEqual(execution.completed.map(item => item.realization), ['local', 'duckdb', 'local']);
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 1), 'LDL');
      assert.equal(fixture.strategyFixtureHistoryPlacement(f, 2), 'LDL');
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      const spent = BigInt(capture.usage.transportBytes) + execution.completed.reduce(
        (sum, item) => sum + BigInt(item.transport?.transportBytes ?? 0), 0n);
      assert.equal(execution.usage().transferredBytes, spent);
      assert.equal(execution.explain().selection.remaining_at_selection.estimated_milliseconds, '4');
      capture.close();
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().transferredBytes, spent);
    } finally { execution?.close(); capture.close(); }
  }
  const smallFixture = fixture.strategyFixtureCreate(...args, program);
  for (const selected of [false, true]) {
    const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const capture = await runStrategyNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f),
      fixture.strategyFixtureLedger(f), suppliedLimits);
    let execution;
    try {
      fixture.strategyFixtureAttach(f, capture.openDAG(fixture.strategyFixtureGraph(f)));
      if (selected) assert.equal(fixture.strategyFixtureReplan(f, 1n), true);
      execution = await runCapturedStrategy(fixture.strategyFixtureDispatch(f), {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 0, maxCells: 0 }})});
      assert.equal(execution.status, 'host-tasks-failed');
      assert(execution.failure);
      assert.deepEqual(execution.completed.map(item => item.task), selected ? [1] : []);
      assert.equal(fixture.strategyFixtureCid(f, 2), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 3), 'null');
      assert.equal(execution.usage().reservedTransferBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
      capture.close();
      if (selected) assert.equal(fixture.strategyFixtureCid(f, 1), hash([{ id: 3 }, { id: 3 }]));
      execution.close();
      assert.equal(execution.usage().heldBytes, 0n);
    } finally { execution?.close(); capture.close(); }
  }
  await assert.rejects(runStrategyNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(smallFixture),
    fixture.strategyFixtureLedger(smallFixture), suppliedLimits));
  for (const field of [0, 1, 2, 3, 4, 5]) {
    assert.equal(fixture.strategyFixtureUsage(smallFixture, field), 0n);
  }
  for (const mode of ['unauthorized', 'cancelled', 'transfer']) {
    const failed = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const abort = new AbortController();
    if (mode === 'cancelled') abort.abort();
    await assert.rejects(runStrategyNativeHostQuery(mode === 'unauthorized' ? {} : grant,
      fixture.strategyFixtureAcquisition(failed), fixture.strategyFixtureLedger(failed),
      mode === 'transfer' ? { ...suppliedLimits, maxTransportBytes: 0 } : suppliedLimits, abort.signal));
    for (const field of [0, 1, 2, 4, 5]) {
      assert.equal(fixture.strategyFixtureUsage(failed, field), 0n);
    }
    // The chosen attempt was frozen before even a source-open failure, and
    // releasing unused capacity never refunds that bounded attempt record.
    assert.equal(fixture.strategyFixtureUsage(failed, 3), 1n);
  }
  const accountedFixture = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
  const retainedRootDirectory = await mkdtemp(join(root, '_build/duckdb-fixtures/retained-root-'));
  const rootRetention = {parentDirectory: retainedRootDirectory, maxFrameBytes: 4096,
    wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64, max_columns: 10, max_order_work: 10000}};
  try {
    const retainedBridge = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/host_node/host_node.js')));
    const preparedOnly = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
    const setupOnly = fixture.strategyFixtureAcquisition(preparedOnly);
    const ledgerOnly = fixture.strategyFixtureLedger(preparedOnly);
    assert.throws(() => checked(retainedBridge.nativeRetainedStrategyHostOpen(setupOnly, ledgerOnly,
      'invalid-batch', () => true, 100000n, 134217728n, 100000n, 0, () => true)));
    assert.throws(() => checked(retainedBridge.nativeRetainedStrategyHostOpen(setupOnly, ledgerOnly,
      'oversized-batch', () => true, 100000n, 134217728n, 100000n, 100001, () => true)));
    assert.equal(fixture.strategyFixtureUsage(preparedOnly, 3), 0n);
    const fixedStream = checked(retainedBridge.nativeRetainedStrategyHostOpen(setupOnly, ledgerOnly,
      'fixed-stream', () => true, 100000n, 134217728n, 100000n, 4096, () => true));
    // The lower retention reservation never exposes a switchable receiver.
    assert.throws(() => checked(retainedBridge.nativeHostStreamPrepare(fixedStream, 4096)));
    // Even confirmed native stop cannot turn a missing sealed body into a
    // zero-byte holding. Keep the original reservation on this failed path.
    checked(retainedBridge.nativeHostPhysicalSettle(fixedStream, true));
    const pendingRetention = fixture.strategyFixtureUsage(preparedOnly, 5);
    assert(pendingRetention > 0n);
    assert.throws(() => checked(retainedBridge.nativeHostComplete(fixedStream)));
    assert.equal(fixture.strategyFixtureUsage(preparedOnly, 5), pendingRetention);
    assert.equal(fixture.strategyFixtureUsage(preparedOnly, 4), 0n);
    // No transport was started in this boundary probe. Close alone is still
    // not the native-stop acknowledgement required by the physical ledger.
    retainedBridge.nativeHostClose(fixedStream);
    checked(retainedBridge.nativeHostPhysicalSettle(fixedStream, true));
    for (const field of [0, 1, 2, 4, 5]) assert.equal(fixture.strategyFixtureUsage(preparedOnly, field), 0n);
    assert.equal(fixture.strategyFixtureUsage(preparedOnly, 3), 1n);
    for (const adopt of [false, true]) {
      const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
      const captured = await runRetainedStrategyNativeHostQuery(grant,
        fixture.strategyFixtureAcquisition(f), fixture.strategyFixtureLedger(f), suppliedLimits, rootRetention);
      try {
        assert.equal(captured.output, undefined);
        assert.equal(captured.source, undefined);
        // Admission keeps the full file ceiling. Only the exact sealed body
        // becomes a holding; unused capacity is released after completion.
        assert.equal(captured.physicalCapacity.retentionBytes, 134615840n);
        const fileBytes = BigInt(captured.storageUsage().reservedBytes);
        assert(fileBytes > 0n && fileBytes < 100000n);
        const heldBytes = 134515840n + fileBytes;
        assert.equal(fixture.strategyFixtureUsage(f, 4), heldBytes);
        assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
        if (adopt) assert.equal(fixture.strategyFixtureAttach(f,
          captured.openDAG(fixture.strategyFixtureGraph(f))), true);
        captured.close();
        assert.equal(captured.cleanupHandle.status().pending, true);
        assert.equal(fixture.strategyFixtureUsage(f, 4), heldBytes);
        const spent = fixture.strategyFixtureUsage(f, 0);
        await captured.cleanupHandle.retry();
        await captured.cleanupHandle.retry();
        assert.equal(captured.cleanupHandle.status().pending, false);
        assert.equal(fixture.strategyFixtureUsage(f, 4), 0n);
        assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
      } finally { captured.close(); await captured.cleanupHandle.retry(); }
    }
    for (const invalid of ['settings', 'ledger', 'capacity', 'stream']) {
      const f = fixture.strategyFixtureAccounted(fixture.strategyFixtureCreate(...args, program));
      await assert.rejects(runRetainedStrategyNativeHostQuery(grant,
        fixture.strategyFixtureAcquisition(f), invalid === 'ledger' ? undefined : fixture.strategyFixtureLedger(f),
        invalid === 'settings' ? {...suppliedLimits, threads: 0} : suppliedLimits,
        invalid === 'stream' ? {...rootRetention, maxFrameBytes: 1}
          : invalid === 'capacity' ? {...rootRetention, wire: {...rootRetention.wire, max_bytes: 100000000}}
            : rootRetention).catch(async error => {
          await error.cleanupHandle?.retry();
          assert.equal(error.cleanupHandle?.status().pending ?? false, false);
          throw error;
        }));
      for (const field of [1, 2, 4, 5]) assert.equal(fixture.strategyFixtureUsage(f, field), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 3), invalid === 'stream' ? 1n : 0n);
    }
    assert.deepEqual(await readdir(retainedRootDirectory), []);
  } finally { await rm(retainedRootDirectory, {recursive: true, force: true}); }
  const accounted = await runStrategyNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(accountedFixture),
    fixture.strategyFixtureLedger(accountedFixture), suppliedLimits);
  const accountedComputes = [];
  try {
    assert.equal(accounted.output, undefined);
    assert.equal(accounted.source, undefined);
    const graph = fixture.strategyFixtureGraph(accountedFixture);
    const dag = accounted.openDAG(graph);
    assert.equal(fixture.strategyFixtureAttach(accountedFixture, dag), true);
    assert.throws(() => accounted.openDAG(graph));
    const rootBytes = accounted.physicalCapacity.retentionBytes;
    assert.equal(rootBytes, 139926400n);
    assert.equal(accounted.physicalCapacity.receiverScratchBytes, 14475520n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), BigInt(accounted.usage.transportBytes));
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), rootBytes);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 2), 0n);
    for (const task of [1, 2, 3]) {
      accountedComputes.push(await runStrategyHostCompute(
        fixture.strategyFixtureCompute(accountedFixture, task), suppliedLimits,
        { maxRows: 100, maxCells: 1000 }));
    }
    const spent = BigInt(accounted.usage.transportBytes)
      + accountedComputes.reduce((sum, result) => sum + BigInt(result.usage.transportBytes), 0n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), spent);
    accounted.close();
    assert.throws(() => accounted.openDAG(graph), { code: 'IssuerClosed' });
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), rootBytes + 3n * 2771200n);
    assert.equal(fixture.strategyFixtureCid(accountedFixture, 3), hash([{ id: 3 }, { id: 3 }]));
    for (const result of accountedComputes) result.close();
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 4), 0n);
    assert.equal(fixture.strategyFixtureUsage(accountedFixture, 0), spent);
  } finally {
    for (const result of accountedComputes) result.close();
    accounted.close();
  }
  // Retained data uses the ordinary checked DAG's atomic holding boundary.
  // File cleanup is independent of native settlement and keeps its allocation
  // charged even when close cannot reclaim the exact inode.
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const retainedFixture = fixture.strategyFixtureCreate(...args, program);
  const retainedCapture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(retainedFixture), suppliedLimits);
  const fileParent = await mkdtemp(join(dirname(path), 'dag-retained-'));
  const heldFiles = [];
  let completedFileHolding = 0n;
  const retainedWire = { max_columns: 10, max_order_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100 };
  try {
    assert.equal(fixture.strategyFixtureOpen(retainedFixture, retainedCapture.source()), true);
    const unstarted = fixture.strategyFixtureCompute(retainedFixture, 1);
    const attempts = fixture.strategyFixtureUsage(retainedFixture, 3);
    await assert.rejects(runRetainedStrategyHostCompute(unstarted, suppliedLimits,
      {maxRows: 100, maxCells: 1000}, {parentDirectory: fileParent, wire: retainedWire, maxFrameBytes: 100001}),
      {code: 'InvalidRetainedConfiguration'});
    await assert.rejects(runRetainedStrategyHostCompute(unstarted, suppliedLimits,
      {maxRows: 100, maxCells: 1000}, {parentDirectory: fileParent,
        wire: {...retainedWire, max_bytes: 32000001}, maxFrameBytes: 4096}),
      {code: 'MoonBitHostFailure'});
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 3), attempts);
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 5), 0n);
    assert.deepEqual(await readdir(fileParent), []);
    for (const task of [1, 2, 3]) {
      if (task === 3) retainedCapture.close();
      const output = await runRetainedStrategyHostCompute(
        fixture.strategyFixtureCompute(retainedFixture, task), suppliedLimits,
        {maxRows: 100, maxCells: 1000},
        {parentDirectory: fileParent, wire: retainedWire, maxFrameBytes: 4096});
      heldFiles.push(output);
      assert.equal(output.physicalCapacity.retentionBytes, 2765600n);
      const expected = task === 2 ? [{id: 3}, {id: 2}, {id: 3}] : [{id: 3}, {id: 3}];
      completedFileHolding += 2665600n + BigInt(Buffer.byteLength(JSON.stringify(expected)));
      assert.equal(fixture.strategyFixtureUsage(retainedFixture, 4), completedFileHolding);
      assert.equal(fixture.strategyFixtureUsage(retainedFixture, 2), 0n);
      assert.equal(fixture.strategyFixtureUsage(retainedFixture, 5), 0n);
      assert.equal(fixture.strategyFixtureCid(retainedFixture, task),
        hash(task === 2 ? [{id: 3}, {id: 2}, {id: 3}] : [{id: 3}, {id: 3}]));
      assert.equal(output.importedRows, task === 3 ? 2 : 3);
    }
    const transferred = fixture.strategyFixtureUsage(retainedFixture, 0);
    const directories = await readdir(fileParent);
    assert.equal(directories.length, 3);
    // Each task owns a different physical allocation, even if content matches.
    const originals = [];
    for (const name of directories) {
      const path = join(fileParent, name, 'body-0');
      await rename(path, `${path}.saved`);
      await writeFile(path, 'replacement');
      originals.push(path);
    }
    const recoveries = [];
    for (const output of [...heldFiles].reverse()) {
      await assert.rejects(output.close(), error => {
        assert(error.cleanupHandle?.status().pending);
        recoveries.push(error.cleanupHandle);
        return true;
      });
    }
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 4), completedFileHolding);
    assert.equal(fixture.strategyFixtureCid(retainedFixture, 3), 'null');
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 0), transferred);
    for (const path of originals) {
      await rm(path);
      await rename(`${path}.saved`, path);
    }
    for (const recovery of recoveries) assert.equal((await recovery.retry()).pending, false);
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 4), 0n);
    assert.equal(fixture.strategyFixtureUsage(retainedFixture, 0), transferred);
    assert.deepEqual(await readdir(fileParent), []);
  } finally {
    for (const output of heldFiles) {
      await output.close();
      await output.cleanupHandle.retry();
    }
    retainedCapture.close();
  }
  const phaseCapture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(phaseFixture), suppliedLimits);
  const bridge = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/host_node/host_node.js')));
  let phaseRun;
  const accepted = result => { assert.equal(result.$tag, 1); return result._0; };
  try {
    assert.equal(fixture.strategyFixtureOpen(phaseFixture, phaseCapture.source()), true);
    const setup = fixture.strategyFixtureCompute(phaseFixture, 1);
    assert.equal(accepted(bridge.computeStrategyScratchCapacity(setup, false)), 11708160n);
    phaseRun = accepted(bridge.computeStrategyHostOpen(setup, () => false, 100000n, 134217728n));
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 145925888n);
    accepted(bridge.computeHostPhysicalSettle(phaseRun, true));
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 11708160n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 5), 2771200n);
    assert.equal(bridge.computeHostComplete(phaseRun).$tag, 0);
    bridge.computeHostAbort(phaseRun);
    bridge.computeHostClose(phaseRun);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 2), 0n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 5), 0n);
    assert.equal(fixture.strategyFixtureUsage(phaseFixture, 4), 0n);
  } finally {
    if (phaseRun) { bridge.computeHostAbort(phaseRun); bridge.computeHostClose(phaseRun); }
    phaseCapture.close();
  }
  // Managed retained metadata consumes the selected task's existing physical
  // reservation. It is not admitted as a second attempt and unused capacity is
  // returned when the task closes before creating an index allocation.
  const managedProgram = JSON.parse(program);
  managedProgram.stages[1].steps[0].filter = 'id > 0';
  managedProgram.stages[2].steps[0].filter = 'id > 0';
  managedProgram.stages[0].steps[1].select = ['id', 'amount'];
  managedProgram.stages[0].results.r.fields = ['id', 'amount'];
  for (const index of [1, 2, 3]) {
    managedProgram.stages[index].steps[1].select = ['id', 'amount'];
    managedProgram.stages[index].results.r.fields = ['id', 'amount'];
  }
  for (const index of [2, 3]) {
    managedProgram.stages[index].steps[1].select = ['id'];
    managedProgram.stages[index].results.r.fields = ['id'];
  }
  managedProgram.stages[2].steps[1].select = [{kept: 'id'}];
  managedProgram.stages[2].results.r.fields = ['kept'];
  managedProgram.stages[3].steps = [
    {sort: [{kept: 'asc'}]},
    {take: {count: 1, offset: 0}},
    {derive: {id: 'kept'}},
    {select: ['id'], as: 'out'},
  ];
  managedProgram.stages[2].inputs.x.result.stage = 'compute_a';
  managedProgram.stages[3].inputs.x.result.stage = 'compute_b';
  managedProgram.stages.push({
    id: 'group_d',
    inputs: {x: {result: {stage: 'compute_a', result: 'r'}}},
    steps: [{group: {by: [], aggregates: {n: {fn: 'count'}}}, as: 'out'}],
    results: {r: {from: 'out', fields: ['n']}},
  }, {
    id: 'group_e',
    inputs: {x: {result: {stage: 'group_d', result: 'r'}}},
    steps: [{filter: 'n > 0'}, {select: ['n'], as: 'out'}],
    results: {r: {from: 'out', fields: ['n']}},
  }, {
    id: 'group_f',
    inputs: {x: {result: {stage: 'group_d', result: 'r'}}},
    steps: [{filter: 'n > 0'}, {select: ['n'], as: 'out'}],
    results: {r: {from: 'out', fields: ['n']}},
  });
  managedProgram.results.group_e = {from: {stage: 'group_e', result: 'r'}};
  managedProgram.results.group_f = {from: {stage: 'group_f', result: 'r'}};
  // Product black-box path: Program-derived setup plus Host configuration are
  // the only inputs. The standard dispatcher constructs every managed request,
  // compares the installed candidate and owns all task close handles.
  const managedStandardProgram = structuredClone(numericProgram);
  managedStandardProgram.stages[2].inputs.x.result.stage = 'compute_a';
  managedStandardProgram.stages[3].inputs.x.result.stage = 'compute_b';
  const managedStandardFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(managedStandardProgram));
  const managedStandardCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(managedStandardFixture),
    suppliedLimits,
  );
  let managedStandardSetup;
  let managedStandardExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      managedStandardFixture, managedStandardCapture.source()), true);
    managedStandardSetup = fixture.strategyFixtureManagedDispatch(
      managedStandardFixture,
    );
    managedStandardExecution = await runCapturedInternalStrategy(
      managedStandardSetup,
      {duckdb: prepareDuckDBStrategyConfiguration({
        transportLimits: suppliedLimits,
        importLimits: {maxRows: 100, maxCells: 1000},
        managedOutput: {
          parentDirectory: fileParent,
          maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000},
        },
      })},
    );
    assert.equal(managedStandardExecution.status, 'host-tasks-completed',
      `${managedStandardExecution.completed.length} tasks: ` +
      `${managedStandardExecution.failure?.code ?? ''}: ` +
      `${managedStandardExecution.failure?.stack ?? managedStandardExecution.failure}`);
    assert.deepEqual(
      managedStandardExecution.completed.map(item => item.realization),
      Array(3).fill('duckdb-managed'),
    );
    assert(managedStandardExecution.completed.slice(1).every(item =>
      item.phases.logicalContentCidComputations === 0),
    JSON.stringify(managedStandardExecution.completed.slice(1)));
    assert(managedStandardExecution.usage().heldBytes > 0n,
      'the dispatcher retains managed task bodies through graph use');
  } finally {
    await managedStandardExecution?.close();
    if (managedStandardExecution) {
      const cleaned = await managedStandardExecution.cleanup();
      assert.equal(cleaned, true, JSON.stringify({
        pending: managedStandardExecution.cleanupPending(),
        usage: managedStandardExecution.usage(),
      }, (_, value) => typeof value === 'bigint' ? value.toString() : value));
      assert.equal(managedStandardExecution.usage().heldBytes, 0n,
        JSON.stringify(managedStandardExecution.usage(), (_, value) =>
          typeof value === 'bigint' ? value.toString() : value));
      assert.equal(managedStandardExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(managedStandardExecution.usage().reservedExecutionBytes, 0n);
    }
    managedStandardCapture.close();
  }
  // The shared Host selects an implementation/Site pair, then rechecks and
  // reserves an explicit Transfer. DuckDB's first retained generation remains
  // at Site A; Local receives an independently owned bounded-memory generation
  // at Site B and consumes that independent generation.
  const siteA = createInProcessExecutionSite({
    key: 'node-site-a',
    generation: 1,
    runtimeRevision: 'node-test-runtime/1',
    startupMilliseconds: 10n,
  });
  const siteB = createInProcessExecutionSite({
    key: 'node-site-b',
    generation: 1,
    runtimeRevision: 'node-test-runtime/1',
  });
  const twoSiteProgram = structuredClone(managedStandardProgram);
  twoSiteProgram.stages[3].steps = [{select: ['id'], as: 'out'}];
  twoSiteProgram.stages.push({
    id: 'compute_d',
    inputs: {x: {result: {stage: 'compute_b', result: 'r'}}},
    steps: [{select: ['id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}},
  });
  twoSiteProgram.results.d = {
    from: {stage: 'compute_d', result: 'r'},
  };
  const twoSiteFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(twoSiteProgram));
  const twoSiteCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(twoSiteFixture),
    suppliedLimits,
  );
  let twoSiteExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      twoSiteFixture, twoSiteCapture.source()), true);
    const twoSiteSetup = fixture.strategyFixtureManagedDispatch(
      twoSiteFixture,
    );
    const key = registration =>
      hostRuntime.strategyHostRegistrationSelectionKey(registration);
    const twoSitePolicy = prepareExecutionSitePolicy({
      sites: [siteA, siteB],
      placements: new Map([
        [key(hostRuntime.strategyModule_duckdb_Registration(twoSiteSetup)),
          [siteA]],
        [key(hostRuntime.strategyModule_local_Registration(twoSiteSetup)),
          [siteB]],
        [key(hostRuntime.strategyModule_reference_compute_Registration(
          twoSiteSetup,
        )), [siteA]],
      ]),
      transferProvider: createManagedMemoryTransferProvider({
        maxBatchRows: 2,
        maxBatchBytes: 1024 * 1024,
      }),
    });
    twoSiteExecution = await runCapturedInternalStrategy(
      twoSiteSetup,
      {
        executionSitePolicy: twoSitePolicy,
        duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000},
          managedOutput: {
            parentDirectory: fileParent,
            maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000},
          },
        }),
      },
    );
    assert.equal(twoSiteExecution.status, 'host-tasks-completed',
      JSON.stringify({
        stack: twoSiteExecution.failure?.stack,
        completed: twoSiteExecution.completed,
        candidates: twoSiteExecution.candidateComparisons,
        excluded: twoSiteExecution.candidateExclusions,
        usage: twoSiteExecution.usage(),
      }, (_, value) => typeof value === 'bigint' ? value.toString() : value));
    assert.deepEqual(
      twoSiteExecution.completed.map(item => item.realization),
      ['duckdb-managed', 'duckdb-managed', 'local-managed', 'local-managed'],
      JSON.stringify({
        candidates: twoSiteExecution.candidateComparisons,
        excluded: twoSiteExecution.candidateExclusions,
      }, (_, value) => typeof value === 'bigint' ? value.toString() : value),
    );
    assert.deepEqual(
      twoSiteExecution.completed.map(item => item.executionSite.key),
      ['node-site-a', 'node-site-a', 'node-site-b', 'node-site-b'],
    );
    assert.equal(twoSiteExecution.completed[2].siteTransfers, 1);
    const [transfer] = twoSiteExecution.completed[2].siteTransferRecords;
    assert.equal(twoSiteExecution.completed[3].siteTransfers, 1);
    const [sharedTransfer] =
      twoSiteExecution.completed[3].siteTransferRecords;
    assert.equal(transfer.version, 'actql-managed-site-transfer/0.1');
    assert.equal(transfer.sourceTask, 2);
    assert.equal(transfer.sourceSite.key, 'node-site-a');
    assert.equal(transfer.destinationSite.key, 'node-site-b');
    assert.notEqual(
      transfer.sourceMaterialGeneration,
      transfer.destinationMaterialGeneration,
    );
    assert.deepEqual(transfer.sourceLogicalView,
      transfer.destinationLogicalView);
    assert.equal(transfer.codec, 'actql-managed-row-wire-batches/0.1');
    assert.equal(transfer.preservationRule,
      'actql-ordered-row-wire-value-preservation/0.1');
    assert.equal(transfer.trustBoundary,
      'host-adopted-in-process-immutable-generation/0.1');
    assert.equal(transfer.integrityModel,
      'typed-value-order-and-occurrence-preservation');
    assert.equal(transfer.physicalContentDigest, 'not-established');
    assert.equal(transfer.logicalIdentity, 'unestablished');
    assert.equal(transfer.destinationRetention, 'retained');
    assert.deepEqual(transfer.integrity, [
      'source-use-authorized',
      'source-generation-pinned',
      'trusted-typed-values-copied-in-order',
      'destination-generation-retained',
    ]);
    assert.equal(sharedTransfer.transferAttempt, transfer.transferAttempt);
    assert.equal(sharedTransfer.destinationMaterialGeneration,
      transfer.destinationMaterialGeneration,
      'two consumer admissions share one completed destination generation');
    assert(transfer.transferredBytes > 0n);
    assert(transfer.retainedBytes > 0n);
    assert.equal(transfer.batches, 1);
    assert.equal(transfer.maxBatchRows, 2);
    assert.equal(transfer.maxBatchBytes, 1024 * 1024);
    assert.equal(twoSiteExecution.completed[2].outputRows, 2);
    assert.equal(twoSiteExecution.completed[3].outputRows, 2);
    const siteATeardown = beginExecutionSiteTeardown(siteA);
    const siteBTeardown = beginExecutionSiteTeardown(siteB);
    assert.equal(siteATeardown.teardownComplete, false,
      'named Site A results remain retained until the Run result closes');
    assert.equal(siteBTeardown.teardownComplete, false,
      'the terminal retained output must keep Site B alive');
  } finally {
    await twoSiteExecution?.close();
    if (twoSiteExecution) {
      assert.equal(await twoSiteExecution.cleanup(), true);
      assert.equal(twoSiteExecution.usage().heldBytes, 0n);
      assert.equal(twoSiteExecution.usage().reservedTransferBytes, 0n);
      assert.equal(twoSiteExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(twoSiteExecution.usage().reservedExecutionBytes, 0n);
      beginExecutionSiteTeardown(siteA);
      beginExecutionSiteTeardown(siteB);
      const describeSite = site => JSON.stringify(
        executionSiteStatus(site),
        (_key, value) => typeof value === 'bigint' ? value.toString() : value,
      );
      assert.equal(executionSiteStatus(siteA).teardownComplete, true,
        describeSite(siteA));
      assert.equal(executionSiteStatus(siteB).teardownComplete, true,
        describeSite(siteB));
    }
    twoSiteCapture.close();
  }
  // Capacity is re-admitted after selection by the authoritative Run ledger.
  // A selected cross-Site candidate that cannot reserve its destination must
  // fail before representation access and must not rerun at another Site.
  const capacitySourceSite = createInProcessExecutionSite({
    key: 'capacity-site-a',
    generation: 1,
    runtimeRevision: 'node-test-runtime/1',
    startupMilliseconds: 10n,
  });
  const capacityDestinationSite = createInProcessExecutionSite({
    key: 'capacity-site-b',
    generation: 1,
    runtimeRevision: 'node-test-runtime/1',
  });
  const capacityProgram = structuredClone(managedStandardProgram);
  capacityProgram.stages[3].steps = [{select: ['id'], as: 'out'}];
  const capacityFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(capacityProgram));
  const capacityCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(capacityFixture),
    suppliedLimits,
  );
  let capacityExecution;
  let capacityCopyCalls = 0;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      capacityFixture, capacityCapture.source()), true);
    const capacitySetup = fixture.strategyFixtureManagedDispatch(
      capacityFixture,
    );
    const key = registration =>
      hostRuntime.strategyHostRegistrationSelectionKey(registration);
    const memoryTransfer = createManagedMemoryTransferProvider({
      maxBatchRows: 2,
      maxBatchBytes: 1024 * 1024,
    });
    const capacityPolicy = prepareExecutionSitePolicy({
      sites: [capacitySourceSite, capacityDestinationSite],
      placements: new Map([
        [key(hostRuntime.strategyModule_duckdb_Registration(capacitySetup)),
          [capacitySourceSite]],
        [key(hostRuntime.strategyModule_local_Registration(capacitySetup)),
          [capacityDestinationSite]],
        [key(hostRuntime.strategyModule_reference_compute_Registration(
          capacitySetup,
        )), [capacitySourceSite]],
      ]),
      transferProvider: Object.freeze({
        contract: memoryTransfer.contract,
        estimate(material) {
          const admitted = memoryTransfer.estimate(material);
          return admitted && Object.freeze({
            ...admitted,
            retainedBytes: 9223372036854775807n,
          });
        },
        copy(options) {
          capacityCopyCalls++;
          return memoryTransfer.copy(options);
        },
      }),
    });
    capacityExecution = await runCapturedInternalStrategy(
      capacitySetup,
      {
        executionSitePolicy: capacityPolicy,
        duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000},
          managedOutput: {
            parentDirectory: fileParent,
            maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000},
          },
        }),
      },
    );
    assert.equal(capacityExecution.status, 'host-tasks-failed');
    assert.deepEqual(
      capacityExecution.completed.map(item => item.realization),
      ['duckdb-managed', 'duckdb-managed'],
      'the selected failed task must not rerun on Site A',
    );
    assert.equal(capacityCopyCalls, 0,
      'capacity refusal must precede representation access');
  } finally {
    await capacityExecution?.close();
    if (capacityExecution) {
      assert.equal(await capacityExecution.cleanup(), true);
      assert.equal(capacityExecution.usage().heldBytes, 0n);
      assert.equal(capacityExecution.usage().reservedTransferBytes, 0n);
      assert.equal(capacityExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(capacityExecution.usage().reservedExecutionBytes, 0n);
    }
    beginExecutionSiteTeardown(capacitySourceSite);
    beginExecutionSiteTeardown(capacityDestinationSite);
    assert.equal(executionSiteStatus(
      capacitySourceSite).teardownComplete, true);
    assert.equal(executionSiteStatus(
      capacityDestinationSite).teardownComplete, true);
    capacityCapture.close();
  }
  // Cancellation and an explicitly unconfirmed source stop both traverse the
  // same standard dispatcher, real Run ledger and retained DuckDB producer.
  // Neither case may rerun the selected consumer at another Site, and cleanup
  // must close the exact source pin before Site teardown completes.
  for (const transferFailureCase of ['cancellation', 'delayed-stop']) {
    const failureSourceSite = createInProcessExecutionSite({
      key: `${transferFailureCase}-site-a`,
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
      startupMilliseconds: 10n,
    });
    const failureDestinationSite = createInProcessExecutionSite({
      key: `${transferFailureCase}-site-b`,
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
    });
    const failureProgram = structuredClone(managedStandardProgram);
    failureProgram.stages[3].steps = [{select: ['id'], as: 'out'}];
    const failureFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(failureProgram));
    const failureCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(failureFixture),
      suppliedLimits,
    );
    const abort = new AbortController();
    let failureExecution;
    let copyCalls = 0, charges = 0, sourceStopPending = true;
    const delayedStop = Object.freeze({
      status: () => Object.freeze({pending: sourceStopPending}),
      async retry() {
        sourceStopPending = false;
        return this.status();
      },
    });
    try {
      assert.equal(fixture.strategyFixtureOpen(
        failureFixture, failureCapture.source()), true);
      const failureSetup = fixture.strategyFixtureManagedDispatch(
        failureFixture,
      );
      const key = registration =>
        hostRuntime.strategyHostRegistrationSelectionKey(registration);
      const memoryTransfer = createManagedMemoryTransferProvider({
        maxBatchRows: 2,
        maxBatchBytes: 1024 * 1024,
      });
      const failurePolicy = prepareExecutionSitePolicy({
        sites: [failureSourceSite, failureDestinationSite],
        placements: new Map([
          [key(hostRuntime.strategyModule_duckdb_Registration(failureSetup)),
            [failureSourceSite]],
          [key(hostRuntime.strategyModule_local_Registration(failureSetup)),
            [failureDestinationSite]],
          [key(hostRuntime.strategyModule_reference_compute_Registration(
            failureSetup,
          )), [failureSourceSite]],
        ]),
        transferProvider: Object.freeze({
          contract: memoryTransfer.contract,
          estimate: material => memoryTransfer.estimate(material),
          copy(options) {
            copyCalls++;
            return memoryTransfer.copy({
              ...options,
              charge(bytes) {
                options.charge(bytes);
                charges++;
                if (charges !== 1) return;
                if (transferFailureCase === 'cancellation') {
                  abort.abort(new Error('cancel transfer'));
                } else {
                  throw Object.assign(new Error('source stop delayed'), {
                    code: 'ManagedTransferSourceStopDelayed',
                    cleanupPending: true,
                    cleanupHandle: delayedStop,
                  });
                }
              },
            });
          },
        }),
      });
      failureExecution = await runCapturedInternalStrategy(
        failureSetup,
        {
          executionSitePolicy: failurePolicy,
          duckdb: prepareDuckDBStrategyConfiguration({
            transportLimits: suppliedLimits,
            importLimits: {maxRows: 100, maxCells: 1000},
            managedOutput: {
              parentDirectory: fileParent,
              maxFrameBytes: 4096,
              wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
                max_columns: 10, max_order_work: 10000},
            },
          }),
        },
        abort.signal,
      );
      assert.equal(failureExecution.status, 'host-tasks-failed');
      assert.deepEqual(
        failureExecution.completed.map(item => item.realization),
        ['duckdb-managed', 'duckdb-managed'],
        'a selected Transfer failure must not rerun its consumer',
      );
      assert.equal(copyCalls, 1);
      assert.equal(charges, 1);
      if (transferFailureCase === 'delayed-stop') {
        assert.equal(failureExecution.cleanupPending(), true);
        assert.equal(executionSiteStatus(
          failureSourceSite).activeTransfers, 1);
      } else {
        assert.equal(executionSiteStatus(
          failureSourceSite).activeTransfers, 0);
      }
    } finally {
      const closing = failureExecution?.close();
      if (failureExecution) {
        assert.equal(await failureExecution.cleanup(), true);
        await closing;
        assert.equal(failureExecution.usage().reservedTransferBytes, 0n);
        assert.equal(failureExecution.usage().reservedRetentionBytes, 0n);
        assert.equal(failureExecution.usage().reservedExecutionBytes, 0n);
        assert(failureExecution.usage().transferredBytes > 0n,
          'spent Transfer bytes remain cumulative after failure');
      }
      beginExecutionSiteTeardown(failureSourceSite);
      beginExecutionSiteTeardown(failureDestinationSite);
      assert.equal(executionSiteStatus(
        failureSourceSite).teardownComplete, true);
      assert.equal(executionSiteStatus(
        failureDestinationSite).teardownComplete, true);
      failureCapture.close();
    }
  }
  // Binding, source integrity and destination-generation failures must pass
  // through the standard dispatcher and real retained producer. None may
  // manufacture a consumer completion or retry the selected task elsewhere.
  for (const transferBoundaryCase of [
    'stale-binding',
    'source-corruption',
    'destination-generation',
    'source-handle-relabel',
  ]) {
    const sourceSite = createInProcessExecutionSite({
      key: `${transferBoundaryCase}-site-a`,
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
      startupMilliseconds: 10n,
    });
    const destinationSite = createInProcessExecutionSite({
      key: `${transferBoundaryCase}-site-b`,
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
    });
    const failureProgram = structuredClone(managedStandardProgram);
    failureProgram.stages[3].steps = [{select: ['id'], as: 'out'}];
    const failureFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(failureProgram));
    const failureCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(failureFixture),
      suppliedLimits,
    );
    let execution;
    let copyCalls = 0, estimateCalls = 0, corruptedSource;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        failureFixture, failureCapture.source()), true);
      const setup = fixture.strategyFixtureManagedDispatch(failureFixture);
      const key = registration =>
        hostRuntime.strategyHostRegistrationSelectionKey(registration);
      const memoryTransfer = createManagedMemoryTransferProvider({
        maxBatchRows: 2,
        maxBatchBytes: 1024 * 1024,
      });
      const provider = Object.freeze({
        contract: memoryTransfer.contract,
        estimate(material) {
          const estimate = memoryTransfer.estimate(material);
          if (estimate !== undefined) {
            estimateCalls++;
            if (transferBoundaryCase === 'stale-binding' &&
                estimateCalls === 2) {
              revokeExecutionSite(destinationSite);
            }
          }
          return estimate;
        },
        async copy(options) {
          copyCalls++;
          if (transferBoundaryCase === 'destination-generation') {
            throw Object.assign(new Error('destination generation failed'), {
              code: 'DestinationGenerationFailed',
            });
          }
          if (transferBoundaryCase === 'source-handle-relabel') {
            return Object.freeze({
              material: options.sourceMaterial,
              generation: Object.freeze({}),
              rows: 0,
              batches: 0,
              maxBatchRows: 2,
              maxBatchBytes: 1024 * 1024,
              bytes: 0n,
              retainedBytes: 0n,
              close() {},
              status: () => Object.freeze({released: false}),
            });
          }
          if (transferBoundaryCase === 'source-corruption') {
            corruptedSource = managedRepresentation(options.sourceMaterial);
            const borrow = corruptedSource.body.delegateRead(
              'standard-transfer-corruption',
            );
            const bytes = await readFile(borrow.descriptor.path);
            borrow.confirmStopped();
            assert.equal(bytes.at(-1), 10,
              'the managed column fixture must end in a JSON newline');
            bytes[bytes.length - 1] = 32;
            await writeFile(borrow.descriptor.path, bytes);
          }
          return memoryTransfer.copy(options);
        },
      });
      const policy = prepareExecutionSitePolicy({
        sites: [sourceSite, destinationSite],
        placements: new Map([
          [key(hostRuntime.strategyModule_duckdb_Registration(setup)),
            [sourceSite]],
          [key(hostRuntime.strategyModule_local_Registration(setup)),
            [destinationSite]],
          [key(hostRuntime.strategyModule_reference_compute_Registration(
            setup,
          )), [sourceSite]],
        ]),
        transferProvider: provider,
      });
      execution = await runCapturedInternalStrategy(
        setup,
        {
          executionSitePolicy: policy,
          duckdb: prepareDuckDBStrategyConfiguration({
            transportLimits: suppliedLimits,
            importLimits: {maxRows: 100, maxCells: 1000},
            managedOutput: {
              parentDirectory: fileParent,
              maxFrameBytes: 4096,
              wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
                max_columns: 10, max_order_work: 10000},
            },
          }),
        },
      );
      assert.equal(execution.status, 'host-tasks-failed');
      assert.deepEqual(
        execution.completed.map(item => item.realization),
        ['duckdb-managed', 'duckdb-managed'],
        'a failed selected Site binding or Transfer must not rerun its consumer',
      );
      assert.equal(copyCalls, transferBoundaryCase === 'stale-binding' ? 0 : 1);
      if (transferBoundaryCase === 'stale-binding') {
        assert.equal(execution.failure?.code, 'StaleExecutionSiteBinding');
      } else if (transferBoundaryCase === 'source-corruption') {
        assert.equal(execution.failure?.code, 'RetainedBodyChanged');
        assert.equal(corruptedSource.body.available(), false,
          'corruption invalidates the source generation');
      } else if (transferBoundaryCase === 'destination-generation') {
        assert.equal(execution.failure?.code, 'DestinationGenerationFailed');
      } else {
        assert.equal(execution.failure?.code, 'InvalidTransferDestination');
      }
    } finally {
      const closing = execution?.close();
      if (execution) {
        assert.equal(await execution.cleanup(), true);
        await closing;
        assert.equal(execution.usage().reservedTransferBytes, 0n);
        assert.equal(execution.usage().reservedRetentionBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
      beginExecutionSiteTeardown(sourceSite);
      beginExecutionSiteTeardown(destinationSite);
      assert.equal(executionSiteStatus(sourceSite).teardownComplete, true);
      assert.equal(executionSiteStatus(destinationSite).teardownComplete, true);
      failureCapture.close();
    }
  }
  // Destination reclamation can fail after every task has completed. The
  // standard result keeps that Site responsibility live and retries only the
  // explicit cleanup handle; it never retains or reopens the source pin.
  {
    const sourceSite = createInProcessExecutionSite({
      key: 'cleanup-retry-site-a',
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
      startupMilliseconds: 10n,
    });
    const destinationSite = createInProcessExecutionSite({
      key: 'cleanup-retry-site-b',
      generation: 1,
      runtimeRevision: 'node-test-runtime/1',
    });
    const cleanupProgram = structuredClone(managedStandardProgram);
    cleanupProgram.stages[3].steps = [{select: ['id'], as: 'out'}];
    const cleanupFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(cleanupProgram));
    const cleanupCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(cleanupFixture),
      suppliedLimits,
    );
    let execution;
    let pending = true, retries = 0;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        cleanupFixture, cleanupCapture.source()), true);
      const setup = fixture.strategyFixtureManagedDispatch(cleanupFixture);
      const key = registration =>
        hostRuntime.strategyHostRegistrationSelectionKey(registration);
      const memoryTransfer = createManagedMemoryTransferProvider({
        maxBatchRows: 2,
        maxBatchBytes: 1024 * 1024,
      });
      const policy = prepareExecutionSitePolicy({
        sites: [sourceSite, destinationSite],
        placements: new Map([
          [key(hostRuntime.strategyModule_duckdb_Registration(setup)),
            [sourceSite]],
          [key(hostRuntime.strategyModule_local_Registration(setup)),
            [destinationSite]],
          [key(hostRuntime.strategyModule_reference_compute_Registration(
            setup,
          )), [sourceSite]],
        ]),
        transferProvider: Object.freeze({
          contract: memoryTransfer.contract,
          estimate: material => memoryTransfer.estimate(material),
          async copy(options) {
            const destination = await memoryTransfer.copy(options);
            const cleanupHandle = Object.freeze({
              status: () => Object.freeze({pending}),
              async retry() {
                retries++;
                await destination.close();
                pending = false;
                return this.status();
              },
            });
            return Object.freeze({
              ...destination,
              close() {
                throw Object.assign(new Error('destination cleanup pending'), {
                  cleanupPending: true,
                  cleanupHandle,
                });
              },
            });
          },
        }),
      });
      execution = await runCapturedInternalStrategy(
        setup,
        {
          executionSitePolicy: policy,
          duckdb: prepareDuckDBStrategyConfiguration({
            transportLimits: suppliedLimits,
            importLimits: {maxRows: 100, maxCells: 1000},
            managedOutput: {
              parentDirectory: fileParent,
              maxFrameBytes: 4096,
              wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
                max_columns: 10, max_order_work: 10000},
            },
          }),
        },
      );
      assert.equal(execution.status, 'host-tasks-completed');
      beginExecutionSiteTeardown(sourceSite);
      beginExecutionSiteTeardown(destinationSite);
      await assert.rejects(execution.close(), {
        message: 'ManagedSiteTransferCleanupFailed',
      });
      assert.equal(execution.cleanupPending(), true);
      assert.equal(executionSiteStatus(sourceSite).activeTransfers, 0,
        'destination cleanup does not retain a stopped source access');
      assert.equal(executionSiteStatus(destinationSite).teardownComplete, false);
      assert.equal(await execution.cleanup(), true);
      assert.equal(retries, 1);
      assert.equal(execution.cleanupPending(), false);
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().reservedTransferBytes, 0n);
      assert.equal(execution.usage().reservedRetentionBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
      assert.equal(executionSiteStatus(sourceSite).teardownComplete, true);
      assert.equal(executionSiteStatus(destinationSite).teardownComplete, true);
    } finally {
      try { await execution?.close(); } catch {}
      if (execution?.cleanupPending()) await execution.cleanup();
      beginExecutionSiteTeardown(sourceSite);
      beginExecutionSiteTeardown(destinationSite);
      cleanupCapture.close();
    }
  }
  // The public entry executes the checked Program Result contract. Omission
  // and caller false cannot erase that floor; true is only a strengthening.
  for (const callerPublication of [undefined, false, true]) {
    const publicFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(managedStandardProgram));
    const publicCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(publicFixture),
      suppliedLimits,
    );
    let publicExecution;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        publicFixture, publicCapture.source()), true);
      const publicOptions = {
        duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000},
          managedOutput: {
            parentDirectory: fileParent,
            maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000},
          },
        }),
      };
      if (callerPublication !== undefined) {
        publicOptions.managedIdentityPolicy = prepareManagedIdentityPolicy({
          publication: callerPublication,
        });
      }
      publicExecution = await runCapturedStrategy(
        fixture.strategyFixtureManagedDispatch(publicFixture),
        publicOptions,
      );
      assert.equal(publicExecution.status, 'host-tasks-failed');
      assert.equal(publicExecution.failure?.code,
        'NoCompatibleManagedStrategy');
      assert.deepEqual(publicExecution.completed.map(item => item.task), [1]);
    } finally {
      await publicExecution?.close();
      if (publicExecution) assert.equal(await publicExecution.cleanup(), true);
      publicCapture.close();
    }
  }
  // The common Host derives obligations before connector comparison. Either a
  // known logical-identity consumer or a publication contract must exclude the
  // CID-free DuckDB candidate before that task starts.
  const aliasedResultProgram = JSON.parse(JSON.stringify(managedStandardProgram));
  aliasedResultProgram.results = {
    first: {from: {stage: 'compute_a', result: 'r'}},
    second: {from: {stage: 'compute_a', result: 'r'}},
  };
  const aliasedFixture = fixture.strategyFixtureCreate(
    ...args,
    JSON.stringify(aliasedResultProgram),
  );
  const aliasedCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(aliasedFixture),
    suppliedLimits,
  );
  try {
    assert.equal(fixture.strategyFixtureOpen(aliasedFixture, aliasedCapture.source()), true);
    const aliasedSetup = fixture.strategyFixtureManagedDispatch(
      aliasedFixture,
    );
    const aliasedCore = runtimeCore(hostRuntime);
    assert.match(
      aliasedCore.programDefinitionCid(aliasedSetup),
      /^sha256:[0-9a-f]{64}$/u,
    );
    const aliasedInventory = aliasedCore.resultInventory(aliasedSetup);
    assert.deepEqual(
      aliasedInventory.map(({name, task}) => ({name, task})),
      [
        {name: 'first', task: 1},
        {name: 'second', task: 1},
      ],
      'checked aliases remain distinct in the standard Host inventory',
    );
    assert.notEqual(
      aliasedInventory[0].definition.result_definition_cid,
      aliasedInventory[1].definition.result_definition_cid,
      'MoonBit seals each checked Result occurrence independently',
    );
    assert.deepEqual(
      fixture.strategyFixtureManagedObligationLabels(
        aliasedFixture, false, false, false,
      ),
      [
        'ordered-rows:task-output:retained:-',
        'logical-relation:named-result:before-publication:first',
        'logical-relation:named-result:before-publication:second',
      ],
      'checked Result aliases retain distinct publication occurrences',
    );
  } finally {
    aliasedCapture.close();
  }
  const acquisitionResultProgram = JSON.parse(JSON.stringify(managedStandardProgram));
  acquisitionResultProgram.results = {
    acquired: {from: {stage: 'a', result: 'r'}},
  };
  const acquisitionResultFixture = fixture.strategyFixtureCreate(
    ...args,
    JSON.stringify(acquisitionResultProgram),
  );
  const acquisitionResultCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(acquisitionResultFixture),
    suppliedLimits,
  );
  try {
    assert.equal(fixture.strategyFixtureOpen(
      acquisitionResultFixture, acquisitionResultCapture.source()), true);
    const acquisitionSetup = fixture.strategyFixtureManagedDispatch(
      acquisitionResultFixture,
    );
    assert.deepEqual(
      runtimeCore(hostRuntime).resultInventory(acquisitionSetup)
        .map(({name, task}) => ({name, task})),
      [{name: 'acquired', task: 0}],
      'acquisition Results remain exact checked occurrences',
    );
    assert.equal(
      fixture.strategyFixtureManagedPolicyAccepted(
        acquisitionResultFixture, true, false, false,
      ),
      false,
      'acquisition publication is rejected before managed Compute selection',
    );
  } finally {
    acquisitionResultCapture.close();
  }
  for (const identityCase of [
    {name: 'consumer', policy: {consumer: true}, completed: 3, succeeds: true},
    {name: 'publication', policy: {publication: true}, completed: 1,
      succeeds: false},
  ]) {
    const identityFixture = fixture.strategyFixtureCreate(
      ...args,
      JSON.stringify(managedStandardProgram),
    );
    const identityCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(identityFixture),
      suppliedLimits,
    );
    let identityExecution;
    try {
      assert.equal(
        fixture.strategyFixtureOpen(identityFixture, identityCapture.source()),
        true,
      );
      identityExecution = await runCapturedInternalStrategy(
        fixture.strategyFixtureManagedDispatch(identityFixture),
        {
          managedIdentityPolicy: prepareManagedIdentityPolicy(
            identityCase.policy,
          ),
          duckdb: prepareDuckDBStrategyConfiguration({
            transportLimits: suppliedLimits,
            importLimits: {maxRows: 100, maxCells: 1000},
            managedOutput: {
              parentDirectory: fileParent,
              maxFrameBytes: 4096,
              wire: {
                max_bytes: 100000,
                max_nodes: 10000,
                max_depth: 64,
                max_columns: 10,
                max_order_work: 10000,
              },
            },
          }),
        },
      );
      assert.equal(identityExecution.status,
        identityCase.succeeds ? 'host-tasks-completed' : 'host-tasks-failed',
        `${identityCase.name}: ${identityExecution.failure?.stack ?? identityExecution.failure}`);
      assert.equal(
        identityExecution.completed.length,
        identityCase.completed,
        `${identityCase.name} identity requirement started an unsupported task`,
      );
      if (identityCase.succeeds) {
        assert.deepEqual(identityExecution.completed.map(item => item.realization),
          ['duckdb-managed', 'reference-numeric-managed',
            'reference-numeric-managed'],
        'equal-cost managed candidates use the stable registration key');
      } else {
        assert(identityExecution.failure != null);
      }
    } finally {
      await identityExecution?.close();
      if (identityExecution) {
        assert.equal(await identityExecution.cleanup(), true);
      }
      identityCapture.close();
    }
  }
  // The product dispatcher preserves exact input-port order for managed
  // binary fan-in. Join creates and admits new values once; the downstream
  // count then reuses that verified retained result without a logical CID.
  for (const selfJoin of [false, true]) {
    const managedJoinProgram = JSON.parse(program);
    managedJoinProgram.stages[3] = {id: 'compute_c', inputs: {
      l: {result: {stage: 'compute_a', result: 'r'}},
      r: {result: {stage: selfJoin ? 'compute_a' : 'compute_b', result: 'r'}},
    }, steps: [{join: {with: 'r', kind: 'inner',
      on: [{left: 'id', right: 'id'}], select: {id: 'left.id'}},
    from: 'l', as: 'out'}], results: {r: {from: 'out', fields: ['id']}}};
    managedJoinProgram.stages.push({id: 'count_d', inputs: {
      x: {result: {stage: 'compute_c', result: 'r'}},
    }, steps: [{group: {by: [], aggregates: {n: {fn: 'count'}}}, as: 'out'}],
    results: {r: {from: 'out', fields: ['n']}}});
    managedJoinProgram.results = {out: {from: {stage: 'count_d', result: 'r'}}};
    const managedJoinFixture = fixture.strategyFixtureJoinCreate(
      ...args, JSON.stringify(managedJoinProgram));
    const managedJoinCapture = await runNativeHostQuery(
      grant, fixture.strategyFixtureAcquisition(managedJoinFixture), suppliedLimits);
    let managedJoinExecution;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        managedJoinFixture, managedJoinCapture.source()), true);
      managedJoinExecution = await runCapturedInternalStrategy(
        fixture.strategyFixtureManagedDispatch(managedJoinFixture),
        {duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000},
          managedOutput: {
            parentDirectory: fileParent,
            maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000},
          },
        })},
      );
      assert.equal(managedJoinExecution.status, 'host-tasks-completed',
        `${managedJoinExecution.failure?.code ?? ''}: ` +
        `${managedJoinExecution.failure?.stack ?? managedJoinExecution.failure}`);
      assert.deepEqual(
        managedJoinExecution.completed.map(item => item.realization),
        Array(4).fill('duckdb-managed'),
      );
      const joinPhases = managedJoinExecution.completed[2].phases;
      assert.equal(joinPhases.nativeFileImportCommands, 0);
      assert.equal(joinPhases.nativeFileScanCommands, 2);
      assert.equal(joinPhases.inputIntegrityPasses, selfJoin ? 1 : 2);
      assert.equal(joinPhases.inputNativeScanBytes,
        selfJoin ? joinPhases.inputPhysicalBytes * 2 : joinPhases.inputPhysicalBytes);
      assert.equal(joinPhases.logicalContentCidComputations, 0);
      assert.equal(managedJoinExecution.completed[3].phases.nativeFileImportCommands, 0);
      assert.equal(managedJoinExecution.completed[3].phases.nativeFileScanCommands, 1);
      assert.equal(managedJoinExecution.completed[3].phases.logicalContentCidComputations, 0);
    } finally {
      await managedJoinExecution?.close();
      if (managedJoinExecution) {
        assert.equal(await managedJoinExecution.cleanup(), true);
        assert.equal(managedJoinExecution.usage().heldBytes, 0n);
        assert.equal(managedJoinExecution.usage().reservedRetentionBytes, 0n);
        assert.equal(managedJoinExecution.usage().reservedExecutionBytes, 0n);
      }
      managedJoinCapture.close();
    }
  }
  const managedGroupProgram = structuredClone(numericProgram);
  managedGroupProgram.stages = [managedGroupProgram.stages[0],
    managedGroupProgram.stages[1], {
      id: 'group_d',
      inputs: {x: {result: {stage: 'compute_a', result: 'r'}}},
      steps: [{group: {by: [], aggregates: {n: {fn: 'count'}}}, as: 'out'}],
      results: {r: {from: 'out', fields: ['n']}},
    }, {
      id: 'group_e',
      inputs: {x: {result: {stage: 'group_d', result: 'r'}}},
      steps: [{filter: 'n > 0'}, {select: ['n'], as: 'out'}],
      results: {r: {from: 'out', fields: ['n']}},
    }, {
      id: 'group_f',
      inputs: {x: {result: {stage: 'group_d', result: 'r'}}},
      steps: [{filter: 'n > 0'}, {select: ['n'], as: 'out'}],
      results: {r: {from: 'out', fields: ['n']}},
    }];
  managedGroupProgram.results = {
    group_e: {from: {stage: 'group_e', result: 'r'}},
    group_f: {from: {stage: 'group_f', result: 'r'}},
  };
  const managedGroupFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(managedGroupProgram));
  const managedGroupCapture = await runNativeHostQuery(
    grant, fixture.strategyFixtureAcquisition(managedGroupFixture), suppliedLimits,
  );
  let managedGroupExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      managedGroupFixture, managedGroupCapture.source()), true);
    managedGroupExecution = await runCapturedInternalStrategy(
      fixture.strategyFixtureManagedDispatch(managedGroupFixture),
      {duckdb: prepareDuckDBStrategyConfiguration({
        transportLimits: suppliedLimits,
        importLimits: {maxRows: 100, maxCells: 1000},
        managedOutput: {
          parentDirectory: fileParent,
          maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000},
        },
      })},
    );
    assert.equal(managedGroupExecution.status, 'host-tasks-completed',
      `${managedGroupExecution.failure?.code ?? ''}: ${managedGroupExecution.failure?.stack ?? managedGroupExecution.failure}\n${JSON.stringify(managedGroupExecution.explain())}`);
    assert.deepEqual(
      managedGroupExecution.completed.map(item => item.realization),
      Array(4).fill('duckdb-managed'),
    );
    assert.equal(
      managedGroupExecution.completed[1].phases.outputValueAdmissionCells,
      1,
      'the group admits its new value once',
    );
    assert(managedGroupExecution.completed.slice(2).every(item =>
      item.phases.logicalContentCidComputations === 0 &&
      item.phases.reusedMeasurementCells === 1));
  } finally {
    await managedGroupExecution?.close();
    if (managedGroupExecution) {
      assert.equal(await managedGroupExecution.cleanup(), true);
      assert.equal(managedGroupExecution.usage().heldBytes, 0n);
      assert.equal(managedGroupExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(managedGroupExecution.usage().reservedExecutionBytes, 0n);
    }
    managedGroupCapture.close();
  }
  // A downstream Store failure cannot authorize B or C. The independently
  // completed A remains owned until graph close. The failure is injected at
  // the physical Store boundary, not through a replacement execution hook.
  const managedFailureParent = join(fileParent, 'managed-failure');
  await mkdir(managedFailureParent);
  const managedFailureFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(managedStandardProgram));
  const managedFailureCapture = await runNativeHostQuery(
    grant, fixture.strategyFixtureAcquisition(managedFailureFixture), suppliedLimits,
  );
  const managedFailureObserver = installCompletionObserver(async ({task}) => {
    assert.equal(task, 1);
    await chmod(managedFailureParent, 0o500);
  });
  let managedFailureExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      managedFailureFixture, managedFailureCapture.source()), true);
    managedFailureExecution = await runCapturedInternalStrategy(
      fixture.strategyFixtureManagedDispatch(managedFailureFixture),
      {duckdb: prepareDuckDBStrategyConfiguration({
        transportLimits: suppliedLimits,
        importLimits: {maxRows: 100, maxCells: 1000},
        managedOutput: {
          parentDirectory: managedFailureParent,
          maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000},
        },
      })},
      undefined,
      managedFailureObserver,
    );
    assert.equal(managedFailureExecution.status, 'host-tasks-failed');
    assert.deepEqual(
      managedFailureExecution.completed.map(item => item.task), [1],
      `B admission failure cannot authorize B or C: ${managedFailureExecution.failure?.stack ?? managedFailureExecution.failure}`,
    );
    assert(managedFailureExecution.usage().heldBytes > 0n,
      'completed A remains held until graph close');
  } finally {
    await chmod(managedFailureParent, 0o700);
    await managedFailureExecution?.close();
    if (managedFailureExecution) {
      assert.equal(await managedFailureExecution.cleanup(), true);
      assert.equal(managedFailureExecution.usage().heldBytes, 0n,
        JSON.stringify(managedFailureExecution.usage(), (_, value) =>
          typeof value === 'bigint' ? value.toString() : value));
      assert.equal(managedFailureExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(managedFailureExecution.usage().reservedExecutionBytes, 0n);
    }
    managedFailureCapture.close();
  }
  // Cancellation after A's atomic completion stops the dispatcher before B.
  // The observer sees only the exact common completion and cannot publish a
  // substitute output or bypass graph-owned cleanup.
  const managedCancelFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(managedStandardProgram));
  const managedCancelCapture = await runNativeHostQuery(
    grant, fixture.strategyFixtureAcquisition(managedCancelFixture), suppliedLimits,
  );
  const managedCancellation = new AbortController();
  const managedCancelObserver = installCompletionObserver(({task}) => {
    assert.equal(task, 1);
    managedCancellation.abort();
  });
  let managedCancelExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      managedCancelFixture, managedCancelCapture.source()), true);
    managedCancelExecution = await runCapturedInternalStrategy(
      fixture.strategyFixtureManagedDispatch(managedCancelFixture),
      {duckdb: prepareDuckDBStrategyConfiguration({
        transportLimits: suppliedLimits,
        importLimits: {maxRows: 100, maxCells: 1000},
        managedOutput: {
          parentDirectory: fileParent,
          maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000},
        },
      })},
      managedCancellation.signal,
      managedCancelObserver,
    );
    assert.equal(managedCancelExecution.status, 'host-tasks-failed');
    assert.equal(managedCancelExecution.failure?.name, 'AbortError');
    assert.deepEqual(managedCancelExecution.completed.map(item => item.task), [1]);
    assert(managedCancelExecution.usage().heldBytes > 0n,
      'cancel does not silently release a completed output');
  } finally {
    await managedCancelExecution?.close();
    if (managedCancelExecution) {
      assert.equal(await managedCancelExecution.cleanup(), true);
      assert.equal(managedCancelExecution.usage().heldBytes, 0n);
      assert.equal(managedCancelExecution.usage().reservedRetentionBytes, 0n);
      assert.equal(managedCancelExecution.usage().reservedExecutionBytes, 0n);
    }
    managedCancelCapture.close();
  }
  // Q7 lifetime integration: use the ordinary product registry and standard
  // Host selection, then replace only the selected execution contribution
  // with a conformance body that remains unsettled after a real DuckDB
  // command. This proves that the outer cancellation deadline cannot release
  // Store pins before the real session scope ends. It does not claim an
  // arbitrary C++ instruction is interruptible at this exact point.
  const delayedStopProgram = JSON.parse(program);
  delayedStopProgram.stages[3] = {
    id: 'compute_c',
    inputs: {
      l: {result: {stage: 'compute_a', result: 'r'}},
      r: {result: {stage: 'compute_b', result: 'r'}},
    },
    steps: [{
      join: {with: 'r', kind: 'inner',
        on: [{left: 'id', right: 'id'}], select: {id: 'left.id'}},
      from: 'l',
      as: 'out',
    }],
    results: {r: {from: 'out', fields: ['id']}},
  };
  delayedStopProgram.stages.push({
    id: 'count_d',
    inputs: {x: {result: {stage: 'compute_c', result: 'r'}}},
    steps: [{
      group: {by: [], aggregates: {n: {fn: 'count'}}},
      as: 'out',
    }],
    results: {r: {from: 'out', fields: ['n']}},
  });
  delayedStopProgram.results = {
    out: {from: {stage: 'count_d', result: 'r'}},
  };
  for (const delayedStopMode of ['session-scope', 'command-unsettled']) {
    const delayedStopFixture = fixture.strategyFixtureJoinCreate(
      ...args, JSON.stringify(delayedStopProgram));
    const delayedStopCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(delayedStopFixture),
      suppliedLimits,
    );
    const delayedStopCancellation = new AbortController();
    let enterDelayedStop;
    let releaseDelayedStop;
    const delayedStopEntered = new Promise(resolve => {
      enterDelayedStop = resolve;
    });
    const delayedStopWait = new Promise(resolve => {
      releaseDelayedStop = resolve;
    });
    const delayedStopControl = {
      mode: delayedStopMode,
      entered: enterDelayedStop,
      wait: delayedStopWait,
      commandStarted: false,
      commandSettled: false,
      representations: [],
      settlements: [],
    };
    let delayedStopExecution;
    try {
    assert.equal(fixture.strategyFixtureOpen(
      delayedStopFixture, delayedStopCapture.source()), true);
    const delayedStopSetup = fixture.strategyFixtureManagedDispatch(
      delayedStopFixture);
    assert.equal(hostRuntime.strategyHostConfigureManagedIdentity(
      delayedStopSetup, false, false, false, false,
    ), true);
    const delayedStopConfiguration = prepareDuckDBStrategyConfiguration({
      transportLimits: suppliedLimits,
      importLimits: {maxRows: 100, maxCells: 1000},
      managedOutput: {
        parentDirectory: fileParent,
        maxFrameBytes: 4096,
        wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
          max_columns: 10, max_order_work: 10000},
      },
    });
    const productContribution = duckdbStrategyContribution(
      hostRuntime, delayedStopSetup, checked, delayedStopConfiguration,
    );
    const contribution = Object.freeze({
      ...productContribution,
      runPrepared(prepared, signal) {
        return prepared.task === 3
          ? runDelayedManagedStop(
            bridge, prepared, suppliedLimits, signal, delayedStopControl,
          )
          : productContribution.runPrepared(prepared, signal);
      },
    });
    const running = runInstalledStrategy(
      delayedStopSetup,
      runtimeCore(hostRuntime),
      [contribution],
      delayedStopCancellation.signal,
    );
    await delayedStopEntered;
    if (delayedStopMode === 'command-unsettled') {
      assert.equal(delayedStopControl.commandStarted, true);
      assert.equal(delayedStopControl.commandSettled, false);
    }
    delayedStopCancellation.abort();
    delayedStopExecution = await running;
    assert.equal(delayedStopExecution.status, 'host-tasks-failed');
    assert.equal(delayedStopExecution.failure?.code, 'Cancelled');
    assert.deepEqual(
      delayedStopExecution.completed.map(item => item.task), [1, 2],
    );
    assert.equal(delayedStopExecution.cleanupPending(), true);
    if (delayedStopMode === 'command-unsettled') {
      assert.equal(delayedStopControl.commandSettled, false,
        'outer cancellation returns while the real session command is unsettled');
    }
    assert.equal(delayedStopControl.representations.length, 2);
    assert.notEqual(
      delayedStopControl.representations[0].body,
      delayedStopControl.representations[1].body,
      'the join pins two distinct physical generations',
    );
    for (const representation of delayedStopControl.representations) {
      assert(representation?.store);
      assert(representation?.body);
      assert(representation.store.status().activeReaders > 0,
        'an unsettled native session retains every exact input generation');
    }
    await assert.rejects(
      delayedStopExecution.close(),
      {code: 'RetainedCleanupPending'},
      'graph close reports the still-pinned producer as cleanup pending',
    );
    for (const representation of delayedStopControl.representations) {
      assert(representation.store.status().activeReaders > 0,
        'graph close cannot turn an unsettled session into stopped access');
    }
    releaseDelayedStop();
    let delayedStopCleaned = false;
    for (let retry = 0; retry < 4 && !delayedStopCleaned; retry++) {
      delayedStopCleaned = await delayedStopExecution.cleanup();
    }
    assert.equal(delayedStopCleaned, true,
      'bounded cleanup retries converge after native stop and pin release');
    if (delayedStopMode === 'command-unsettled') {
      assert.equal(delayedStopControl.commandSettled, true);
    }
    assert.deepEqual(delayedStopControl.settlements, [false, true],
      'deadline marks cleanup pending before actual native settlement');
    for (const representation of delayedStopControl.representations) {
      assert.equal(representation.store.status().activeReaders, 0);
    }
    delayedStopCapture.close();
    assert.equal(delayedStopExecution.usage().heldBytes, 0n,
      JSON.stringify(delayedStopExecution.usage(), (_, value) =>
        typeof value === 'bigint' ? value.toString() : value));
    assert.equal(delayedStopExecution.usage().reservedRetentionBytes, 0n);
    assert.equal(delayedStopExecution.usage().reservedExecutionBytes, 0n);
    } finally {
      releaseDelayedStop();
      try { await delayedStopExecution?.close(); } catch (error) {
        assert.equal(error?.code, 'RetainedCleanupPending');
      }
      for (let retry = 0;
        retry < 4 && delayedStopExecution?.cleanupPending(); retry++) {
        await delayedStopExecution.cleanup();
      }
      delayedStopCapture.close();
    }
  }
  const managedLedgerFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(managedProgram));
  const managedLedgerCapture = await runNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(managedLedgerFixture), suppliedLimits);
  let managedLedgerRun;
  let managedLedgerResult;
  let managedLedgerOutput;
  let managedLedgerStore;
  let managedLedgerWriter;
  let managedLedgerBody;
  let managedDownstream;
  let managedTerminal;
  let managedGroup;
  let managedGroupFirst;
  let managedGroupSecond;
  try {
    assert.equal(fixture.strategyFixtureOpen(managedLedgerFixture, managedLedgerCapture.source()), true);
    const setup = fixture.strategyFixtureCompute(managedLedgerFixture, 1);
    const baseRetention = accepted(bridge.computeStrategyRetentionCapacity(setup, true));
    const indexBytes = 512n + 6n * 9n;
    const projectedIndexBytes = 512n + 3n * 9n;
    const terminalIndexBytes = 512n + 9n;
    let attempt;
    let port;
    let consume;
    let managedRows = 0;
    let managedStorageOrder, managedFieldsFrame;
    const managedProfile = accepted(fixture.managedFileProfile(await readFile(join(root,
      'spec/contracts/actql-managed-retained-execution.json'), 'utf8')));
    managedLedgerStore = await createLocalRetainedStore({
      parentDirectory: fileParent, capacityBytes: 100000,
      maxFrameBytes: 4096, maxEntries: 1,
    });
    managedLedgerWriter = managedLedgerStore.reserve(100000);
    await managedLedgerWriter.start();
    let managedCompletion;
    managedLedgerRun = accepted(bridge.computeManagedRetainedStrategyHostOpen(
      setup, current => current === attempt && matchesFixedCompute(managedLedgerResult, port, consume),
      100000n, 134217728n, 100000n, () => true, 6));
    attempt = bridge.computeHostAttempt(managedLedgerRun);
    managedCompletion = accepted(
      bridge.computeHostManagedPrepare(managedLedgerRun, managedProfile, () => true));
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5),
      baseRetention + 100000n + indexBytes);
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 3), 1n,
      'metadata capacity must not create another physical attempt');
    port = Object.freeze({
      importCount: () => bridge.computeHostImportCount(managedLedgerRun),
      rowCount: index => Number(accepted(bridge.computeHostCount(managedLedgerRun, index, false))),
      columnCount: index => Number(accepted(bridge.computeHostCount(managedLedgerRun, index, true))),
      createSql: index => accepted(bridge.computeHostSql(managedLedgerRun, 0, index)),
      insertSql: index => accepted(bridge.computeHostSql(managedLedgerRun, 1, index)),
      parameter: (index, row, column) => JSON.parse(accepted(
        bridge.computeHostParameter(managedLedgerRun, row, column, false, index))),
      querySql: () => accepted(bridge.computeHostSql(managedLedgerRun, 2, 0)),
      queryParameters: () => Array.from({length: bridge.computeHostQueryParameterCount(managedLedgerRun)},
        (_, index) => JSON.parse(accepted(
          bridge.computeHostParameter(managedLedgerRun, 0, index, true, 0)))),
    });
    consume = async chunk => {
      if (!managedLedgerOutput) {
        managedFieldsFrame = JSON.stringify(chunk.fields.map(({name, type}) =>
          [name, type.id, type.precision == null ? null : String(type.precision),
            type.scale == null ? null : String(type.scale)]));
        managedLedgerOutput = accepted(
          bridge.computeHostManagedOutputBegin(
            managedLedgerRun, managedFieldsFrame));
        managedStorageOrder = accepted(
          bridge.managedOutputStorageOrder(managedLedgerOutput));
        assert.deepEqual(managedStorageOrder, [1, 0],
          'positional storage follows the logical schema, not DuckDB field order');
        assert.throws(() => accepted(
          bridge.computeHostManagedOutputEnableIndex(managedLedgerOutput, 5)));
        assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), 0n,
          'a mismatched index ceiling must not allocate from the task reservation');
        accepted(bridge.computeHostManagedOutputEnableIndex(managedLedgerOutput, 6));
        assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), indexBytes);
        assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5),
          baseRetention + 100000n);
      }
      accepted(bridge.managedOutputAccept(managedLedgerOutput, chunk.rowCount,
        JSON.stringify(chunk.columns)));
      assert.deepEqual(chunk.fields.map(field => field.type.id),
        ['DOUBLE', 'DOUBLE']);
      const storedFields = managedStorageOrder.map(index => chunk.fields[index]);
      const storedColumns = managedStorageOrder.map(index => chunk.columns[index]);
      await managedLedgerWriter.appendBytes(encodeManagedColumnFrame(
        storedFields, storedColumns, chunk.rowCount, managedRows));
      managedRows += chunk.rowCount;
    };
    managedLedgerResult = await runFixedCompute(port, suppliedLimits,
      {maxRows: 100, maxCells: 1000}, consume);
    accepted(bridge.managedOutputFinish(managedLedgerOutput));
    assert.equal(accepted(bridge.managedOutputMeasurementIndexCells(managedLedgerOutput)), 6);
    assert.throws(() => accepted(
      bridge.managedOutputRetain(managedLedgerOutput, 100001n, () => true)));
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), indexBytes,
      'the stream base cannot enlarge the separately admitted file ceiling');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5),
      baseRetention + 100000n);
    managedLedgerBody = await managedLedgerWriter.sealPhysical();
    const managedBodyBytes = BigInt(managedLedgerBody.bytes);
    accepted(bridge.managedOutputRetain(
      managedLedgerOutput, managedBodyBytes, () => managedLedgerBody.available()));
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), indexBytes + managedBodyBytes,
      'sealed managed body and measurement index own distinct task holdings');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5),
      baseRetention + 100000n - managedBodyBytes,
      'exact body bytes move from the admitted file ceiling into a holding');
    accepted(bridge.computeHostPhysicalSettle(managedLedgerRun, true));
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), indexBytes + managedBodyBytes,
      'native settlement must not release a live managed body or its index');
    accepted(bridge.managedOutputVerifyCompute(managedLedgerOutput));
    const managedCompleted = accepted(
      bridge.managedOutputCompleteStrategyCompute(managedLedgerOutput, managedCompletion));
    assert.equal(bridge.managedCompletedAvailable(managedCompleted), true);
    assert.deepEqual(
      accepted(bridge.managedCompletedTaskOutputIdentityStatus(managedCompleted)),
      ['unestablished', 'retained'],
      'normal managed completion keeps an explicit delayed identity state',
    );
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 1, managedCompleted), true);
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), 2,
      'managed success advances the common DAG without manufacturing a legacy output');
    const managedInput = fixture.strategyFixtureManagedInput(
      managedLedgerFixture, 2, managedCompleted);
    const managedMaterial = bridge.managedOutputMaterial(managedLedgerOutput);
    registerManagedInput(managedMaterial,
      input => bridge.managedInputMatchesMaterial(input, managedMaterial),
      managedLedgerStore, managedLedgerBody, managedColumnCodecContractCid,
      managedPhysicalRepresentation(
        managedLedgerBody,
        managedRows,
        managedColumnCodecContractCid,
        managedFieldsFrame,
        managedStorageOrder,
      ).manifest);
    assert.equal(bridge.managedInputMatchesMaterial(managedInput, managedMaterial), true,
      'the next task binds the exact retained occurrence through its checked graph edge');
    assert.equal(fixture.strategyFixtureManagedRequestAccepts(managedInput, 1), false,
      'managed requests retain the consumer logical row ceiling');
    assert.equal(fixture.strategyFixtureManagedRequestAccepts(managedInput, 2), false);
    assert.equal(fixture.strategyFixtureManagedRequestAccepts(managedInput, 3), true);
    const managedRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 2, managedCompleted);
    assert.equal(fixture.strategyFixtureManagedRequestInputCount(managedRequest), 1);
    assert.equal(fixture.strategyFixtureManagedIdentityCandidateAccepts(
      managedLedgerFixture, 2, managedCompleted), false,
    'a CID-dependent publication cannot select the CID-free candidate');
    const otherManagedRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 2, managedCompleted);
    assert.equal(fixture.strategyFixtureManagedCandidateAccepts(
      managedLedgerFixture, managedRequest, managedRequest), true);
    assert.equal(fixture.strategyFixtureManagedCandidateAccepts(
      managedLedgerFixture, managedRequest, otherManagedRequest), false,
    'a candidate for another use-site request cannot enter comparison');
    const managedQuery = fixture.strategyFixtureManagedRequestQuery(
      managedLedgerFixture, managedRequest);
    const [managedCreateSql, managedQuerySql] =
      fixture.strategyFixtureManagedRequestQuerySql(managedQuery);
    assert.match(managedCreateSql, /CREATE TEMP TABLE "managed_input"/);
    assert.match(managedQuerySql, /FROM "main"\."managed_input"/);
    const managedConfiguration = fixture.strategyFixtureManagedConfiguration(
      managedLedgerFixture, 2, managedRequest, managedProfile, 100000n);
    await assert.rejects(runManagedColumnStrategyHostCompute(
      managedConfiguration, managedMaterial, 'sha256:' + '0'.repeat(64),
      suppliedLimits, {parentDirectory: fileParent, maxFrameBytes: 4096}),
    {code: 'InvalidManagedStorageConfiguration'});
    managedDownstream = await runManagedColumnStrategyHostCompute(
      managedConfiguration, managedMaterial, managedColumnCodecContractCid,
      suppliedLimits, {parentDirectory: fileParent, maxFrameBytes: 4096});
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 2, managedDownstream.completed), true,
    'the product Host publishes task 2 through the common managed DAG');
    assert.deepEqual(managedDownstream.diagnostics, {
      inputPhysicalBytes: Number(managedBodyBytes),
      inputNativeScanBytes: Number(managedBodyBytes), inputIntegrityPasses: 1,
      nativeFileImportCommands: 0, nativeFileScanCommands: 1,
      parameterInsertRows: 0,
      logicalContentCidComputations: 0, outputValueAdmissionCells: 0,
      reusedMeasurementCells: 3, selectionOccurrenceRows: 3,
      outputFrames: 1, outputPhysicalBytes: managedDownstream.diagnostics.outputPhysicalBytes,
      physicalManifestCid: managedDownstream.diagnostics.physicalManifestCid,
      directOutputCopies: 0, outputJsMaterializedCells: 3,
      outputFrameReencodes: 1,
      measuredGuardWork: 6, measuredGuardBytes: 3, measuredGuardNodes: 3,
      reusedGuardWork: 15, reusedGuardBytes: 12, reusedGuardNodes: 9,
      comparisonWork: 13, comparisonBytes: 1, comparisonNodes: 1,
    });
    const managedDownstreamBytes = BigInt(managedDownstream.diagnostics.outputPhysicalBytes);
    assert(managedDownstreamBytes > 0n,
      'the bounded generation has an independently retained body');
    assert.equal(managedDownstream.representation, 'managed-column-file');
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), 3);
    const terminalInput = fixture.strategyFixtureManagedInput(
      managedLedgerFixture, 3, managedDownstream.completed);
    assert.equal(bridge.managedInputMatchesMaterial(
      terminalInput, managedDownstream.material), true,
    'task 3 binds the exact independent body published by task 2');
    const terminalRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 3, managedDownstream.completed);
    const terminalQuery = fixture.strategyFixtureManagedRequestQuery(
      managedLedgerFixture, terminalRequest);
    const [, terminalQuerySql] =
      fixture.strategyFixtureManagedRequestQuerySql(terminalQuery);
    assert.match(terminalQuerySql,
      /ORDER BY "__actql_input"\."kept" ASC NULLS LAST, .* LIMIT 1 OFFSET 0$/);
    assert.equal(fixture.strategyFixtureManagedSelectionMatches(
      terminalQuery, [1]), true);
    assert.equal(fixture.strategyFixtureManagedSelectionMatches(
      terminalQuery, [0]), true,
    'metadata selection alone does not claim that the checked sort executed');
    assert.equal(fixture.strategyFixtureManagedSelectionMatches(
      terminalQuery, [1, 2]), false,
    'extra native occurrences cannot satisfy the checked sorted take');
    assert.equal(fixture.strategyFixtureManagedSelectionMatches(
      terminalQuery, [3]), false,
    'an occurrence outside the retained input cannot satisfy the sorted take');
    const terminalConfiguration = fixture.strategyFixtureManagedConfiguration(
      managedLedgerFixture, 3, terminalRequest, managedProfile, 100000n);
    managedTerminal = await runManagedColumnStrategyHostCompute(
      terminalConfiguration, managedDownstream.material,
      managedInputCodecContractCid(managedDownstream.material), suppliedLimits,
      {parentDirectory: fileParent, maxFrameBytes: 4096});
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 3, managedTerminal.completed), true,
    'a second downstream consumer reuses the managed path without legacy rows');
    assert.deepEqual(managedTerminal.diagnostics, {
      inputPhysicalBytes: Number(managedDownstreamBytes),
      inputNativeScanBytes: Number(managedDownstreamBytes), inputIntegrityPasses: 1,
      nativeFileImportCommands: 0, nativeFileScanCommands: 1,
      parameterInsertRows: 0,
      logicalContentCidComputations: 0, outputValueAdmissionCells: 0,
      reusedMeasurementCells: 1, selectionOccurrenceRows: 1,
      outputFrames: 1, outputPhysicalBytes: managedTerminal.diagnostics.outputPhysicalBytes,
      physicalManifestCid: managedTerminal.diagnostics.physicalManifestCid,
      directOutputCopies: 0, outputJsMaterializedCells: 1,
      outputFrameReencodes: 1,
      measuredGuardWork: 2, measuredGuardBytes: 1, measuredGuardNodes: 1,
      reusedGuardWork: 8, reusedGuardBytes: 4, reusedGuardNodes: 4,
      comparisonWork: 0, comparisonBytes: 0, comparisonNodes: 0,
    });
    const managedTerminalBytes = BigInt(managedTerminal.diagnostics.outputPhysicalBytes);
    assert(managedTerminalBytes > 0n,
      'the checked take writes one bounded retained generation');
    assert.equal(managedTerminal.representation, 'managed-column-file');
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), 4);
    assert.throws(() => accepted(bridge.computeHostComplete(managedLedgerRun)),
      'legacy completion cannot consume an already published managed task');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5), 0n,
      'successful downstream completion returns its unused metadata reservation');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      indexBytes + managedBodyBytes + managedDownstreamBytes + managedTerminalBytes +
      projectedIndexBytes + terminalIndexBytes,
      'both downstream results own independent retained bodies');

    const groupInput = fixture.strategyFixtureManagedInput(
      managedLedgerFixture, 4, managedCompleted);
    assert.equal(bridge.managedInputMatchesMaterial(
      groupInput, managedMaterial), true,
    'the group binds the original retained producer occurrence');
    const groupRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 4, managedCompleted);
    const groupQuery = fixture.strategyFixtureManagedRequestQuery(
      managedLedgerFixture, groupRequest);
    const [, groupQuerySql] =
      fixture.strategyFixtureManagedRequestQuerySql(groupQuery);
    assert.match(groupQuerySql, /count\(\*\)/i);
    const groupConfiguration = fixture.strategyFixtureManagedConfiguration(
      managedLedgerFixture, 4, groupRequest, managedProfile, 100000n);
    managedGroup = await runManagedColumnStrategyHostCompute(
      groupConfiguration, managedMaterial, managedColumnCodecContractCid,
      suppliedLimits, {parentDirectory: fileParent, maxFrameBytes: 4096});
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 4, managedGroup.completed), true,
    'the newly computed group result enters the common managed DAG');
    assert.deepEqual(managedGroup.diagnostics, {
      inputPhysicalBytes: Number(managedBodyBytes),
      inputNativeScanBytes: Number(managedBodyBytes), inputIntegrityPasses: 1,
      nativeFileImportCommands: 0, nativeFileScanCommands: 1,
      parameterInsertRows: 0,
      logicalContentCidComputations: 0, outputValueAdmissionCells: 1,
      reusedMeasurementCells: 0, selectionOccurrenceRows: 0,
      outputFrames: 1, outputPhysicalBytes: managedGroup.diagnostics.outputPhysicalBytes,
      physicalManifestCid: managedGroup.diagnostics.physicalManifestCid,
      directOutputCopies: 0, outputJsMaterializedCells: 1,
      outputFrameReencodes: 1,
      measuredGuardWork: 2, measuredGuardBytes: 1, measuredGuardNodes: 1,
      reusedGuardWork: 11, reusedGuardBytes: 10, reusedGuardNodes: 7,
      comparisonWork: 0, comparisonBytes: 0, comparisonNodes: 0,
    });
    const managedGroupBytes = BigInt(managedGroup.diagnostics.outputPhysicalBytes);
    assert.equal(managedGroupBytes, 19n,
      'the new count value is admitted into one retained column frame');
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), 5);
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      indexBytes + managedBodyBytes + managedDownstreamBytes + managedTerminalBytes +
      projectedIndexBytes + 2n * terminalIndexBytes + managedGroupBytes,
      'the group owns one newly measured body and index');

    bridge.managedOutputCancel(managedLedgerOutput);
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 1, managedCompleted), false,
      'revoked material cannot be rebound through the stored occurrence');
    assert.equal(bridge.managedInputMatchesMaterial(managedInput, managedMaterial), false,
      'a prepared use-site is not permission to read revoked material');
    assert.equal(fixture.strategyFixtureManagedRequestAccepts(managedInput, 2), false,
      'revoked material cannot satisfy another managed request');
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 2, managedDownstream.completed), true,
    'the independent downstream result survives revocation of its consumed input');
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 3, managedTerminal.completed), true,
    'the terminal result survives revocation of its transitive ancestor');
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 4, managedGroup.completed), true,
    'the newly admitted group survives revocation of its consumed input');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      managedBodyBytes + managedDownstreamBytes + managedTerminalBytes +
      projectedIndexBytes + 2n * terminalIndexBytes + managedGroupBytes,
    'revocation releases only the initial measurement index');
    await managedTerminal.close();
    managedTerminal = undefined;
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      managedBodyBytes + managedDownstreamBytes + projectedIndexBytes +
      terminalIndexBytes + managedGroupBytes,
    'closing task 3 releases only its own body');
    await managedDownstream.close();
    managedDownstream = undefined;
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      managedBodyBytes + terminalIndexBytes + managedGroupBytes,
      'the independent group remains after the projection chain closes');

    const groupFirstInput = fixture.strategyFixtureManagedInput(
      managedLedgerFixture, 5, managedGroup.completed);
    assert.equal(bridge.managedInputMatchesMaterial(
      groupFirstInput, managedGroup.material), true);
    const groupFirstRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 5, managedGroup.completed);
    const groupFirstConfiguration = fixture.strategyFixtureManagedConfiguration(
      managedLedgerFixture, 5, groupFirstRequest, managedProfile, 100000n);
    managedGroupFirst = await runManagedColumnStrategyHostCompute(
      groupFirstConfiguration, managedGroup.material,
      managedInputCodecContractCid(managedGroup.material), suppliedLimits,
      {parentDirectory: fileParent, maxFrameBytes: 4096});
    assert.deepEqual(managedGroupFirst.diagnostics, {
      inputPhysicalBytes: Number(managedGroupBytes),
      inputNativeScanBytes: Number(managedGroupBytes), inputIntegrityPasses: 1,
      nativeFileImportCommands: 0, nativeFileScanCommands: 1,
      parameterInsertRows: 0,
      logicalContentCidComputations: 0, outputValueAdmissionCells: 0,
      reusedMeasurementCells: 1, selectionOccurrenceRows: 1,
      outputFrames: 1,
      outputPhysicalBytes: managedGroupFirst.diagnostics.outputPhysicalBytes,
      physicalManifestCid: managedGroupFirst.diagnostics.physicalManifestCid,
      directOutputCopies: 0, outputJsMaterializedCells: 1,
      outputFrameReencodes: 1,
      measuredGuardWork: 2, measuredGuardBytes: 1, measuredGuardNodes: 1,
      reusedGuardWork: 4, reusedGuardBytes: 2, reusedGuardNodes: 2,
      comparisonWork: 3, comparisonBytes: 1, comparisonNodes: 1,
    });
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 5, managedGroupFirst.completed), true);
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), 6);
    const managedGroupFirstBytes = BigInt(
      managedGroupFirst.diagnostics.outputPhysicalBytes);

    const groupSecondInput = fixture.strategyFixtureManagedInput(
      managedLedgerFixture, 6, managedGroup.completed);
    assert.equal(bridge.managedInputMatchesMaterial(
      groupSecondInput, managedGroup.material), true,
    'the second consumer binds the same live group result independently');
    const groupSecondRequest = fixture.strategyFixtureManagedRequest(
      managedLedgerFixture, 6, managedGroup.completed);
    const groupSecondConfiguration = fixture.strategyFixtureManagedConfiguration(
      managedLedgerFixture, 6, groupSecondRequest, managedProfile, 100000n);
    managedGroupSecond = await runManagedColumnStrategyHostCompute(
      groupSecondConfiguration, managedGroup.material,
      managedInputCodecContractCid(managedGroup.material), suppliedLimits,
      {parentDirectory: fileParent, maxFrameBytes: 4096});
    assert.deepEqual(managedGroupSecond.diagnostics, {
      inputPhysicalBytes: Number(managedGroupBytes),
      inputNativeScanBytes: Number(managedGroupBytes), inputIntegrityPasses: 1,
      nativeFileImportCommands: 0, nativeFileScanCommands: 1,
      parameterInsertRows: 0,
      logicalContentCidComputations: 0, outputValueAdmissionCells: 0,
      reusedMeasurementCells: 1, selectionOccurrenceRows: 1,
      outputFrames: 1,
      outputPhysicalBytes: managedGroupSecond.diagnostics.outputPhysicalBytes,
      physicalManifestCid: managedGroupSecond.diagnostics.physicalManifestCid,
      directOutputCopies: 0, outputJsMaterializedCells: 1,
      outputFrameReencodes: 1,
      measuredGuardWork: 2, measuredGuardBytes: 1, measuredGuardNodes: 1,
      reusedGuardWork: 4, reusedGuardBytes: 2, reusedGuardNodes: 2,
      comparisonWork: 3, comparisonBytes: 1, comparisonNodes: 1,
    });
    assert.equal(fixture.strategyFixtureManagedOutputMatches(
      managedLedgerFixture, 6, managedGroupSecond.completed), true);
    assert.equal(fixture.strategyFixtureNext(managedLedgerFixture), -1);
    const managedGroupSecondBytes = BigInt(
      managedGroupSecond.diagnostics.outputPhysicalBytes);
    assert(managedGroupFirstBytes > 0n);
    assert(managedGroupSecondBytes > 0n);
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      managedBodyBytes + managedGroupBytes + managedGroupFirstBytes +
      managedGroupSecondBytes + 3n * terminalIndexBytes,
    'the group and both consumers own independent managed holdings');

    await managedGroupFirst.close();
    managedGroupFirst = undefined;
    await managedGroupSecond.close();
    managedGroupSecond = undefined;
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4),
      managedBodyBytes + managedGroupBytes + terminalIndexBytes,
    'closing both consumers leaves the shared group result live');
    await managedGroup.close();
    managedGroup = undefined;
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), managedBodyBytes,
      'revocation leaves only the graph-owned initial body holding');
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5), 0n,
      'closing the settled downstream task releases its unused managed completion capacity');
    bridge.computeHostClose(managedLedgerRun);
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 5), 0n);
    assert.equal(fixture.strategyFixtureUsage(managedLedgerFixture, 4), 0n);
  } finally {
    await managedGroupSecond?.close();
    await managedGroupFirst?.close();
    await managedGroup?.close();
    await managedTerminal?.close();
    await managedDownstream?.close();
    if (managedLedgerOutput) bridge.managedOutputCancel(managedLedgerOutput);
    if (managedLedgerRun) bridge.computeHostClose(managedLedgerRun);
    if (managedLedgerResult) releaseFixedCompute(managedLedgerResult);
    managedLedgerBody?.close();
    managedLedgerStore?.close();
    await managedLedgerStore?.cleanup();
    managedLedgerCapture.close();
  }
  let freshDuckDBTransfer;
  for (const layout of [[true, true, true], [true, false, true], [false, true, false]]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const held = [];
    let transferred = 0n;
    let retained = 0n;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      // A and B must consume one immutable observation, not read this mutation.
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (let task = 1; task <= 3; task++) {
        if (task === 3) capture.close();
        if (layout[task - 1]) {
          const setup = fixture.strategyFixtureCompute(f, task);
          if (task === 2) {
            // An unstarted oversized reservation cannot erase already spent A
            // transfer or create a DB. Retrying this unstarted configuration is
            // explicit test orchestration, not automatic failed-attempt fallback.
            const attempts = fixture.strategyFixtureUsage(f, 3);
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxTransportBytes: 300001 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            // DB memory alone fits, but the bounded transport containers do not.
            await assert.rejects(runStrategyHostCompute(setup,
              { ...suppliedLimits, maxCells: 2000000 }, { maxRows: 100, maxCells: 1000 }),
            { code: 'MoonBitHostFailure' });
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
            assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          }
          const completed = await runStrategyHostCompute(setup, suppliedLimits, { maxRows: 100, maxCells: 1000 });
          transferred += BigInt(completed.usage.transportBytes);
          assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
          assert.equal(fixture.strategyFixtureUsage(f, 1), 0n);
          assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
          held.push([task, completed]);
          retained += 2771200n;
          assert.equal(completed.physicalCapacity.retentionBytes, 2771200n);
          assert.equal(completed.physicalCapacity.receiverScratchBytes, 11708160n);
          assert.equal(completed.physicalCapacity.executionBytes,
            completed.physicalCapacity.databaseBytes + completed.physicalCapacity.scratchBytes + 11708160n);
          assert.equal(fixture.strategyFixtureUsage(f, 4), retained);
          assert.equal(fixture.strategyFixtureUsage(f, 5), 0n);
          // Each task really imports into a fresh DB, including DuckDB A -> C.
          assert.equal(completed.importedRows, task === 3 ? 2 : 3);
        } else {
          assert.equal(fixture.strategyFixtureLocal(f, task), true);
          retained += 7760000n;
          assert.equal(fixture.strategyFixtureUsage(f, 4), retained);
        }
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      const beforeParentClose = fixture.strategyFixtureUsage(f, 4);
      held.find(([task]) => task === 1)?.[1].close();
      // C's completed input anchors still retain A, even after A's port closes.
      assert.equal(fixture.strategyFixtureUsage(f, 4), beforeParentClose);
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
      const last = held.find(([task]) => task === 3)?.[1];
      if (last) {
        last.close();
        assert.equal(fixture.strategyFixtureCanBind(f, 3), false);
      }
      fixture.strategyFixtureCloseOutput(f, 3); // includes a Local C
      fixture.strategyFixtureCloseOutput(f, 2);
      fixture.strategyFixtureCloseOutput(f, 1);
      assert.equal(fixture.strategyFixtureUsage(f, 4), 0n);
      assert.equal(fixture.strategyFixtureNext(f), -1); // release is not an unexecuted task
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred); // close never refunds transfer
      if (layout.every(Boolean)) freshDuckDBTransfer = transferred;
    } finally {
      capture.close();
      for (const [, result] of held) result.close();
    }
  }
  // Compare retained resident execution with a retained fresh execution, not
  // the row-backed baseline above which has no retained-consumer verification.
  let freshRetainedTransfer;
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const retention = {parentDirectory: dirname(path), maxFrameBytes: 4096,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
        max_columns: 10, max_order_work: 10000}};
    const capture = await runRetainedNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(f), suppliedLimits, retention);
    const outputs = [];
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (const task of [1, 2, 3]) {
        outputs.push(await runRetainedStrategyHostCompute(
          fixture.strategyFixtureCompute(f, task), suppliedLimits,
          {maxRows: 100, maxCells: 1000}, retention));
        assert.equal(outputs.at(-1).usage.retainedInputBytes,
          Buffer.byteLength(JSON.stringify(task === 3
            ? [{id: 3}, {id: 3}] : [{id: 3}, {id: 2}, {id: 3}])));
        assert.equal(outputs.at(-1).usage.residentInputBytes, 0);
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{id: 3}, {id: 2}, {id: 3}] : [{id: 3}, {id: 3}]));
      }
      freshRetainedTransfer = outputs.reduce((sum, output) => sum + BigInt(output.usage.transportBytes), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), freshRetainedTransfer);
    } finally {
      for (const output of outputs) { await output.close(); await output.cleanupHandle.retry(); }
      capture.close(); await capture.cleanupHandle.retry();
    }
  }
  // Two independent count consumers of X can share established value evidence.
  // This passes the actual checked DAG and installed resident Host, not a fake
  // verifier callback. The third filter still executes its own demand scan.
  for (const projected of [false, true]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const counts = JSON.parse(program);
    if (projected) {
      counts.stages[0].steps.at(-1).select = ['id', 'amount'];
      counts.stages[0].results.r.fields = ['id', 'amount'];
      counts.stages[0].results.narrow = {from: 'captured', fields: ['id']};
      counts.stages[2].inputs.x.result.result = 'narrow';
    }
    for (const index of [1, 2]) counts.stages[index].steps = [
      {group: {by: [], aggregates: {id: {fn: 'count'}}}, as: 'out'},
    ];
    const f = fixture.strategyFixtureCreate(...args, JSON.stringify(counts));
    const retention = {parentDirectory: dirname(path), maxFrameBytes: 4096,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
        max_columns: 10, max_order_work: 10000}};
    const capture = await runRetainedNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(f), suppliedLimits, retention);
    let execution;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      execution = await runCapturedStrategy(fixture.strategyFixtureRetainedResidentDispatch(f), {
        duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits,
          importLimits: {maxRows: 100, maxCells: 1000}, retainedOutput: retention}),
      });
      assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
      assert.deepEqual(execution.completed.map(item => item.phases.reusedInputValues), [0, 1, 0]);
      assert.deepEqual(execution.completed.map(item => item.phases.directInputScans), [1, 0, 1]);
      for (const task of [1, 2, 3]) assert.equal(fixture.strategyFixtureCid(f, task), hash([{id: 3}]));
    } finally {
      if (execution) { await execution.close(); assert.equal(await execution.cleanup(), true); }
      capture.close(); await capture.cleanupHandle.retry();
    }
  }
  // Shared X is imported once; both branches read that exact capture, and C
  // consumes A's retained native table without importing A from the Host again.
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  for (const [retainedSource, batchedImport] of [
    [false, false], [true, false], ['installed', false], [false, true], [true, true],
  ]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = retainedSource
      ? await runRetainedNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits, {
        parentDirectory: dirname(path), maxFrameBytes: 4096,
        wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64, max_columns: 10, max_order_work: 10000},
      })
      : await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = retainedSource ? fixture.strategyFixtureRetainedResidentDispatch(f)
        : fixture.strategyFixtureResidentDispatch(f);
      if (retainedSource === 'installed') {
        const execution = await runCapturedStrategy(dispatch, {duckdb: prepareDuckDBStrategyConfiguration({
          transportLimits: suppliedLimits, importLimits: {maxRows: 100, maxCells: 1000},
          retainedOutput: {parentDirectory: dirname(path), maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000}},
        })});
        try {
          assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
          assert.deepEqual(execution.completed.map(item => [item.realization, item.outputRepresentation]),
            Array.from({length: 3}, () => ['duckdb-resident', 'retained-file']));
          assert.deepEqual(execution.completed.map(item => item.preparation.imports.length), [1, 0, 0]);
          for (const item of execution.completed) {
            assert(Object.isFrozen(item.phases));
            assert(Number.isFinite(item.phases.workMilliseconds));
            assert(item.phases.inputVerificationMilliseconds >= 0);
            assert(item.phases.finalizationMilliseconds >= 0);
          }
          assert.equal(fixture.strategyFixtureCid(f, 3), hash([{id: 3}, {id: 3}]));
          assert.equal(fixture.strategyFixtureCanBind(f, 3), true,
            'independent file is usable after the installed finisher closes the DB');
        } finally {
          await execution.close();
          assert.equal(await execution.cleanup(), true);
          assert.equal(execution.cleanupPending(), false);
        }
        continue;
      }
      const firstTask = checked(hostRuntime.strategyHostNext(dispatch));
      const beforeProvision = fixture.strategyFixtureUsage(f, 3);
      for (const invalid of [{ threads: 0 }, { maxRows: -1 }, { cancelWaitMs: -1 },
        { cancelWaitMs: 2147483648 }]) {
        await assert.rejects(openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1,
          { ...suppliedLimits, ...invalid }), error => {
          assert.equal(error.code, 'InvalidLimits');
          assert.equal(error.cleanupPending, undefined);
          return true;
        });
        for (const counter of [0, 1, 2, 4, 5]) assert.equal(fixture.strategyFixtureUsage(f, counter), 0n);
        assert.equal(fixture.strategyFixtureUsage(f, 3), beforeProvision);
        assert.equal(fixture.strategyFixtureNext(f), 1);
      }
      await assert.rejects(openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1,
        { ...suppliedLimits, memoryBytes: suppliedLimits.memoryBytes / 2 }));
      assert.equal(fixture.strategyFixtureUsage(f, 3), beforeProvision);
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1, suppliedLimits);
      const mapping = { maxEntries: 1000, maxNameBytes: 10000 };
      const importAttempts = fixture.strategyFixtureUsage(f, 3);
      // More corrections than the table-name/holding bound must not consume it.
      for (let retry = 0; retry < 40; retry++) {
        await assert.rejects(importResidentStrategyInput(environment, 0, 4000000n,
          { ...suppliedLimits, maxRows: 2 }, mapping), { code: 'InvalidImportLimits' });
        assert.equal(environment.hasTable(0), false);
        assert.equal(fixture.strategyFixtureUsage(f, 3), importAttempts);
        assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes));
      }
      // Valid transport settings, but beyond the selected import reservation.
      await assert.rejects(importResidentStrategyInput(environment, 0, 4000000n,
        { ...suppliedLimits, maxTransportBytes: 100001 }, mapping));
      assert.equal(fixture.strategyFixtureUsage(f, 3), importAttempts);
      const importLimits = batchedImport ? {...suppliedLimits,
        maxColumns: 1, maxChunkRows: 2, maxChunkBytes: 4096} : suppliedLimits;
      const imported = await importResidentStrategyInput(environment, 0, 4000000n, importLimits, mapping);
      assert.equal(imported.importedRows, 3);
      assert.equal(imported.batchRows, batchedImport ? 2 : 1);
      assert.equal(imported.usage.statements, batchedImport ? 3 : 4);
      assert.equal(imported.usage.preparations, batchedImport ? 3 : 2,
        'CREATE and each distinct bounded INSERT shape own their preparation');
      if (retainedSource) {
        assert.equal(imported.usage.storageReadBytes,
          Buffer.byteLength('[{"id":3},{"id":2},{"id":3}]'));
        assert.equal(fixture.strategyFixtureUsage(f, 0), BigInt(imported.usage.transportBytes));
        assert.equal(environment.hasTable(0), true);
        assert.equal(JSON.parse(capture.document()).output.rows_cid,
          hash([{id: 3}, {id: 2}, {id: 3}]));
      }
      assert.equal(fixture.strategyFixtureUsage(f, 3), importAttempts + 1n);
      await assert.rejects(importResidentStrategyInput(environment, 0, 4000000n,
        suppliedLimits, mapping));
      assert.equal(fixture.strategyFixtureUsage(f, 3), importAttempts + 1n);
      await replaceRows('INSERT INTO records VALUES (99,99)');
      for (let task = 1; task <= 3; task++) {
        const table = environment.table(task === 3 ? 1 : 0);
        const selected = task === 1 ? firstTask : checked(hostRuntime.strategyHostNext(dispatch));
        const compute = checked(hostRuntime.strategyModule_duckdb_Dispatch(dispatch, selected));
        if (task === 1) {
          await assert.rejects(runResidentStrategyHostCompute(compute, environment, [table],
            { ...suppliedLimits, threads: 2 }, mapping), { code: 'ResidentProfileMismatch' });
          if (!retainedSource) {
            const attempts = fixture.strategyFixtureUsage(f, 3);
            await assert.rejects(runResidentStrategyHostCompute(compute, environment, [table],
              suppliedLimits, mapping, undefined, {parentDirectory: dirname(path), maxFrameBytes: 4096,
                wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
                  max_columns: 10, max_order_work: 10000}}), {code: 'MoonBitHostFailure'});
            assert.equal(fixture.strategyFixtureUsage(f, 3), attempts,
              'a selected row-only offer cannot be enlarged into file holding');
          }
        }
        const output = await runResidentStrategyHostCompute(compute,
          environment, [table], suppliedLimits, mapping, undefined,
          retainedSource ? {parentDirectory: dirname(path), maxFrameBytes: 4096,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000}} : undefined);
        outputs.push(output);
        assert.equal(output.importedRows, 0);
        assert.equal(output.usage.residentInputBytes, 0,
          'eligible resident inputs read the owned DB copy, not the independently retained file');
        assert.equal(output.diagnostics.directInputScans, retainedSource ? 1 : 0,
          'each retained consumer still executes its typed measurement and guard scan');
        assert.equal(output.diagnostics.reusedInputIdentities, retainedSource ? 1 : 0,
          'only the exact live resident lease reuses the previously admitted identity');
        assert.equal(environment.hasTable(0), task === 1,
          'X remains through A and is removed only after B commits its last use');
        assert.equal(environment.hasTable(1), task < 3,
          'A remains until C commits its read; its Host result stays independent');
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      const residentTransfer = BigInt(imported.usage.transportBytes) +
        outputs.reduce((sum, output) => sum + BigInt(output.usage.transportBytes), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), residentTransfer);
      const comparableFreshTransfer = retainedSource ? freshRetainedTransfer : freshDuckDBTransfer;
      if (!retainedSource) {
        assert(residentTransfer < comparableFreshTransfer,
          `resident ${residentTransfer} must transfer less than matched fresh ${comparableFreshTransfer}`);
      }
      // This three-row fixture measures fixed SQL metadata as well as values.
      // Native verification can transfer more than decoding a tiny file; do not
      // conceal that cost or mistake import elimination for a universal saving.
      console.log('ACTQL_RESIDENT_TRANSFER', JSON.stringify({retainedSource, batchedImport,
        resident: String(residentTransfer), fresh: String(comparableFreshTransfer)}));
      await environment.close();
      if (retainedSource) assert.ok(capture.source(), 'retained source survives DB-copy removal');
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
    } finally {
      if (environment) await environment.close();
      for (const output of outputs) {
        await output.close();
        if (retainedSource) assert.equal(output.cleanupHandle.status().pending, false);
      }
      capture.close();
      if (retainedSource) {
        await capture.cleanupHandle.retry();
        assert.equal(capture.cleanupHandle.status().pending, false);
      }
    }
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const cancelledFixture = fixture.strategyFixtureCreate(...args, program);
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      checked(hostRuntime.strategyHostNext(dispatch));
      environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1, suppliedLimits);
      await assert.rejects(importResidentStrategyInput(environment, 0, 4000000n,
        { ...suppliedLimits, maxTransportBytes: 20 }, { maxEntries: 1000, maxNameBytes: 10000 }));
      assert.equal(fixture.strategyFixtureNext(f), -1, 'failed import stops the common DAG even without its driver');
      assert.equal(environment.hasTable(0), false);
      assert.equal(fixture.strategyFixtureCid(f, 1), 'null');
      assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes));
      await environment.close();
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      assert.equal(fixture.strategyFixtureNext(f), -1, 'cleanup does not authorize fallback');
    } finally { if (environment) await environment.close(); capture.close(); }
  }
  {
    const directory = await mkdtemp(join(dirname(path), 'retained-failed-read-'));
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runRetainedNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits, {
      parentDirectory: directory, maxFrameBytes: 4096,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64, max_columns: 10, max_order_work: 10000},
    });
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const [holding] = await readdir(directory);
      const bodyPath = join(directory, holding, 'body-0');
      const original = await readFile(bodyPath);
      // Same inode and byte length: a consumer actually reading this physical
      // copy must reject corruption. Resident consumers may instead use their
      // separately verified DB copy, so exercise the file path explicitly.
      const changed = Buffer.from(original);
      changed[0] = '!'.charCodeAt(0);
      await writeFile(bodyPath, changed);
      let failure;
      await assert.rejects(runRetainedStrategyHostCompute(
        fixture.strategyFixtureCompute(f, 1), suppliedLimits,
        {maxRows: 100, maxCells: 1000}, {parentDirectory: directory, maxFrameBytes: 4096,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000}}), error => {
        failure = error;
        assert.equal(error.code, 'RetainedInputReadUnconfirmed');
        assert.equal(error.cleanupHandle.status().pending, true);
        return true;
      });
      assert.equal(fixture.strategyFixtureCid(f, 1), 'null');
      assert.equal(fixture.strategyFixtureNext(f), -1);
      assert.equal((await failure.cleanupHandle.retry()).pending, true,
        'native settlement and retry are not a Store read-stop acknowledgement');
    } finally {
      capture.close();
      await capture.cleanupHandle.retry();
      await rm(directory, {recursive: true, force: true});
    }
  }
  {
    const directory = await mkdtemp(join(dirname(path), 'resident-revoked-input-'));
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runRetainedNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits, {
      parentDirectory: directory, maxFrameBytes: 4096,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64, max_columns: 10, max_order_work: 10000},
    });
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const selected = checked(hostRuntime.strategyHostNext(dispatch));
      environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), 1, suppliedLimits);
      const mapping = {maxEntries: 1000, maxNameBytes: 10000};
      await importResidentStrategyInput(environment, 0, 4000000n, suppliedLimits, mapping);
      const table = environment.table(0);
      const body = retainedStorageBody(checked(bridge.residentImportMaterial(table)));
      const [holding] = await readdir(directory);
      const bodyPath = join(directory, holding, 'body-0');
      const changed = await readFile(bodyPath);
      changed[0] = '!'.charCodeAt(0);
      await writeFile(bodyPath, changed);
      // Installed Store verification detects corruption and revokes the exact
      // bound input. A previously imported DB copy must not bypass that now
      // known revocation or fabricate a fresh receiving grant.
      await assert.rejects(body.consume(() => {}), {code: 'RetainedBodyChanged'});
      assert.equal(body.available(), false);
      await assert.rejects(runResidentStrategyHostCompute(
        checked(hostRuntime.strategyModule_duckdb_Dispatch(dispatch, selected)),
        environment, [table], suppliedLimits, mapping));
      assert.equal(fixture.strategyFixtureCid(f, 1), 'null');
      await environment.close();
      assert.equal(environment.status().pending, false);
    } finally {
      if (environment) await environment.close();
      capture.close(); await capture.cleanupHandle.retry();
      await rm(directory, {recursive: true, force: true});
    }
  }
  for (const failure of ['received-row-limit', 'cancelled']) {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    let environment;
    let a;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const graph = fixture.strategyFixtureRun(f);
      const selectedA = checked(hostRuntime.strategyHostNext(dispatch));
      environment = await openResidentStrategyEnvironment(graph, 1, suppliedLimits);
      const mapping = { maxEntries: 1000, maxNameBytes: 10000 };
      await importResidentStrategyInput(environment, 0, 4000000n, suppliedLimits, mapping);
      a = await runResidentStrategyHostCompute(checked(hostRuntime.strategyModule_duckdb_Dispatch(dispatch, selectedA)),
        environment, [environment.table(0)], suppliedLimits, mapping);
      const before = fixture.strategyFixtureUsage(f, 0);
      const selectedB = checked(hostRuntime.strategyHostNext(dispatch));
      const abort = new AbortController();
      if (failure === 'cancelled') abort.abort();
      await assert.rejects(runResidentStrategyHostCompute(checked(hostRuntime.strategyModule_duckdb_Dispatch(dispatch, selectedB)),
        environment, [environment.table(0)],
        { ...suppliedLimits, maxRows: failure === 'received-row-limit' ? 2 : 100 }, mapping, abort.signal));
      assert.equal(fixture.strategyFixtureNext(f), -1, 'failed B cannot authorize unstarted C');
      assert.equal(fixture.strategyFixtureCid(f, 2), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 3), 'null');
      assert.equal(fixture.strategyFixtureCid(f, 1), hash([{ id: 3 }, { id: 3 }]));
      assert.equal(environment.hasTable(1), true, 'B rollback does not remove committed A');
      assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
      assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes),
        'settling B does not settle the shared database');
      assert(fixture.strategyFixtureUsage(f, 0) >= before);
      const spent = fixture.strategyFixtureUsage(f, 0);
      await environment.close();
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
      assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
    } finally {
      if (environment) await environment.close();
      a?.close();
      capture.close();
    }
  }
  {
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    let environment;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const dispatch = fixture.strategyFixtureResidentDispatch(f);
      const graph = fixture.strategyFixtureRun(f);
      for (let index = 1; index <= 3; index++) {
        const task = checked(hostRuntime.strategyHostNext(dispatch));
        assert.equal(hostRuntime.strategyHostTask(task), index);
        if (index === 2) {
          // Two new imports plus both task envelopes exceed the remaining
          // transfer budget. Reselection must choose Local B, not erase A's
          // spent transfer to retain the old all-resident placement.
          assert.equal(hostRuntime.strategyHostRegistration(task), hostRuntime.strategyModule_local_Registration(dispatch));
          checked(hostRuntime.strategyModule_local_Dispatch(dispatch, task));
          capture.close();
          continue;
        }
        assert.equal(hostRuntime.strategyHostResident(task), true, `resident task ${index}`);
        const [[producer, bytes, entries, names]] = checked(hostRuntime.strategyHostResidentInputs(dispatch, index));
        const mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
        environment ??= await openResidentStrategyEnvironment(graph, index, suppliedLimits);
        if (!environment.hasTable(Number(producer))) {
          const imported = await importResidentStrategyInput(environment, Number(producer), bytes,
            suppliedLimits, mapping);
          assert.equal(imported.importedRows, index === 3 ? 2 : 3);
        }
        const result = await runResidentStrategyHostCompute(
          checked(hostRuntime.strategyModule_duckdb_Dispatch(dispatch, task)), environment, [environment.table(Number(producer))],
          suppliedLimits, mapping);
        outputs.push(result);
        if (index === 1) {
          const spent = fixture.strategyFixtureUsage(f, 0);
          await environment.close();
          assert.equal(environment.status().pending, false);
          assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
          assert.equal(fixture.strategyFixtureCanBind(f, 1), true);
          environment = undefined;
        }
        if (index === 2) capture.close();
      }
      assert.equal(outputs.length, 2, 'only A and C execute on DuckDB; completed A is not retried');
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally {
      if (environment) await environment.close();
      for (const output of outputs) output.close();
      capture.close();
    }
  }
  for (const expensiveCleanup of [false, true]) {
    const selectedFixture = fixture.strategyFixtureCreate(...args, program);
    const selectedCapture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(selectedFixture), suppliedLimits);
    let result;
    try {
      assert.equal(fixture.strategyFixtureOpen(selectedFixture, selectedCapture.source()), true);
      const setup = expensiveCleanup
        ? fixture.strategyFixtureResidentCleanupDispatch(selectedFixture)
        : fixture.strategyFixtureResidentDispatch(selectedFixture);
      result = await runCapturedStrategy(setup, {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 100, maxCells: 1000 }})});
      assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
      assert.equal(result.cleanupPending(), false);
      assert.equal(await result.cleanup(), true);
      assert.deepEqual(result.completed.map(task => task.realization), ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
      assert.equal(fixture.strategyFixtureCid(selectedFixture, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally { result?.close(); selectedCapture.close(); }
  }
  // One installed implementation, two distinct resource bindings. A/C reuse one
  // database while B independently imports X into the other database.
  {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureTwoResourcesCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    let result;
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      await replaceRows('INSERT INTO records VALUES (99,99)');
      const setup = fixture.strategyFixtureTwoResourcesDispatch(f);
      result = await runCapturedStrategy(setup, {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: suppliedLimits, importLimits: { maxRows: 100, maxCells: 1000 }})});
      assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
      assert.deepEqual(result.completed.map(task => task.realization), Array(3).fill('duckdb-resident'));
      assert.deepEqual(result.completed.map(task => task.preparation.environmentCreated), [true, true, false]);
      assert.deepEqual(result.completed.map(task => task.preparation.imports.map(value => [value.producer, value.rows])),
        [[[0, 3]], [[0, 3]], []]);
      const transferred = result.completed.reduce((sum, task) => sum + BigInt(task.transport.transportBytes)
        + task.preparation.imports.reduce((bytes, value) => bytes + BigInt(value.transport.transportBytes), 0n), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
      for (const task of [1, 2, 3]) {
        assert.equal(fixture.strategyFixtureCid(f, task), hash(task === 2
          ? [{ id: 3 }, { id: 2 }, { id: 3 }] : [{ id: 3 }, { id: 3 }]));
      }
      assert.equal(result.cleanupPending(), false);
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n, 'both database reservations were settled');
      capture.close();
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
      result.close();
      assert.equal(fixture.strategyFixtureUsage(f, 4), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred, 'close does not refund either import');
    } finally { result?.close(); capture.close(); }
  }
  {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureTwoResourcesCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const environments = [];
    const outputs = [];
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      const setup = fixture.strategyFixtureTwoResourcesDispatch(f);
      const mapping = {maxEntries: 1000, maxNameBytes: 10000};
      const bindings = [];
      for (const index of [1, 2, 3]) {
        const task = checked(hostRuntime.strategyHostNext(setup));
        bindings.push(hostRuntime.strategyHostResourceBinding(task));
        let environment;
        if (index < 3) {
          environment = await openResidentStrategyEnvironment(fixture.strategyFixtureRun(f), index, suppliedLimits);
          environments.push(environment);
          await importResidentStrategyInput(environment, 0, 4000000n, suppliedLimits, mapping);
        } else {
          assert.equal(bindings[2], bindings[0]);
          assert.notEqual(bindings[1], bindings[0]);
          environment = environments[0];
        }
        const compute = checked(hostRuntime.strategyModule_duckdb_Dispatch(setup, task));
        if (index === 2) {
          const attempts = fixture.strategyFixtureUsage(f, 3);
          const transferred = fixture.strategyFixtureUsage(f, 0);
          // Equal captured contents on another binding are not this task's copy.
          await assert.rejects(runResidentStrategyHostCompute(compute, environments[0],
            [environments[0].table(0)], suppliedLimits, mapping));
          await assert.rejects(runResidentStrategyHostCompute(compute, environment,
            [environments[0].table(0)], suppliedLimits, mapping));
          assert.equal(fixture.strategyFixtureUsage(f, 3), attempts);
          assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
        }
        outputs.push(await runResidentStrategyHostCompute(compute, environment,
          [environment.table(index === 3 ? 1 : 0)], suppliedLimits, mapping));
        if (index === 2) {
          assert.equal(fixture.strategyFixtureUsage(f, 2), 2n * BigInt(suppliedLimits.memoryBytes));
          await environment.close();
          assert.equal(fixture.strategyFixtureUsage(f, 2), BigInt(suppliedLimits.memoryBytes));
          assert.equal(environments[0].status().live, true);
          assert.equal(environments[0].hasTable(1), true);
          assert.equal(fixture.strategyFixtureCanBind(f, 2), true);
        }
      }
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
      const transferred = fixture.strategyFixtureUsage(f, 0);
      await environments[0].close();
      assert.equal(fixture.strategyFixtureUsage(f, 2), 0n);
      assert.equal(fixture.strategyFixtureUsage(f, 0), transferred);
      assert.equal(fixture.strategyFixtureCanBind(f, 3), true);
    } finally {
      for (const environment of environments) await environment.close();
      for (const output of outputs) output.close();
      capture.close();
    }
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const captured = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(cancelledFixture), suppliedLimits);
  let first;
  try {
    assert.equal(fixture.strategyFixtureOpen(cancelledFixture, captured.source()), true);
    first = await runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 1), suppliedLimits,
      { maxRows: 100, maxCells: 1000 });
    const cancellation = new AbortController();
    cancellation.abort();
    await assert.rejects(runStrategyHostCompute(fixture.strategyFixtureCompute(cancelledFixture, 2), suppliedLimits,
      { maxRows: 100, maxCells: 1000 }, cancellation.signal));
    assert.equal(fixture.strategyFixtureNext(cancelledFixture), -1);
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 1), hash([{ id: 3 }, { id: 3 }]));
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 2), 'null');
    assert.equal(fixture.strategyFixtureCid(cancelledFixture, 3), 'null');
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 0), BigInt(first.usage.transportBytes));
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 1), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 2), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 5), 0n);
    assert.equal(fixture.strategyFixtureUsage(cancelledFixture, 4), 2771200n);
  } finally { captured.close(); first?.close(); }
  for (const initialTransferCost of [1n, 20n]) {
    await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
    const f = fixture.strategyFixtureCreate(...args, program);
    const capture = await runNativeHostQuery(grant, fixture.strategyFixtureAcquisition(f), suppliedLimits);
    const outputs = [];
    try {
      assert.equal(fixture.strategyFixtureOpen(f, capture.source()), true);
      assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost), true);
      const firstPlacement = initialTransferCost === 1n ? 'duckdb' : 'local';
      assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 6n : 30n);
      for (let task = 1; task <= 3; task++) {
        if (task === 2) {
          const spent = fixture.strategyFixtureUsage(f, 0);
          assert.equal(fixture.strategyFixtureReplan(f, initialTransferCost === 1n ? 20n : 1n), true);
          assert.equal(fixture.strategyFixturePlacement(f, 1), firstPlacement);
          assert.equal(fixture.strategyFixtureUsage(f, 0), spent);
          assert.equal(fixture.strategyFixtureEstimate(f), initialTransferCost === 1n ? 20n : 4n);
        }
        if (task === 3) capture.close();
        const placement = fixture.strategyFixturePlacement(f, task);
        assert.equal(placement, task === 1 ? firstPlacement : firstPlacement === 'local' ? 'duckdb' : 'local');
        if (placement === 'duckdb') outputs.push(await runStrategyHostCompute(
          fixture.strategyFixtureCompute(f, task), suppliedLimits, { maxRows: 100, maxCells: 1000 }));
        else assert.equal(fixture.strategyFixtureLocal(f, task), true);
      }
      assert.equal(fixture.strategyFixtureCid(f, 2), hash([{ id: 3 }, { id: 2 }, { id: 3 }]));
      assert.equal(fixture.strategyFixtureCid(f, 3), hash([{ id: 3 }, { id: 3 }]));
    } finally { capture.close(); for (const output of outputs) output.close(); }
  }
}
