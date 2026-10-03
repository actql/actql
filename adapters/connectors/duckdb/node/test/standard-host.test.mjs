import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { inspect, promisify } from 'node:util';
import { tmpdir } from 'node:os';
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
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';
import {createNodeHostEntry,
  runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from '../../../../host-node/entry.mjs';
import {installStrategyContributions} from
  '../../../../connectors-builtin/strategy.generated.mjs';
import {runInstalledStrategy} from '../../../../host-common/strategy.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {duckdbStrategyContribution} from '../strategy-bundle.mjs';
import {localStrategyContribution} from
  '../../../../local-node/strategy-bundle.mjs';
import {installLocalRetainedStore} from
  '../../../../local-node/retained-store.mjs';
import {
  prepareManagedIdentityPolicy,
} from '../../../../host-node/managed-identity-policy.mjs';
import { prepareDuckDBStrategyConfiguration } from '../configuration.mjs';
import { checked } from '../runtime-result.mjs';
import { exampleAccountConfiguration, runExample } from '../examples/physical-strategy.mjs';
import {installCompletionObserver} from '../../../../host-common/completion-observer.mjs';
import {retainedStorageBody} from '../../../../store-local/representations.mjs';
import {runFixedCompute, matchesFixedCompute, releaseFixedCompute} from '../fixed-compute.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {registerManagedInput,
  managedInputCodecContractCid, withManagedInputFiles} from
  '../../../../store-local/managed-representations.mjs';
import {managedRepresentation} from
  '../../../../store-local/managed-memory-representations.mjs';
import {managedPhysicalRepresentation} from
  '../../../../store-local/managed-physical-representation.mjs';
import {computePhysicalCapacity} from '../physical-capacity.mjs';
import {ownedHostFailure} from '../failure-envelope.mjs';
import {managedParquetCodecContractCid} from '../managed-parquet-codec.mjs';
import {beginExecutionSiteTeardown, createInProcessExecutionSite,
  executionSiteStatus, prepareExecutionSitePolicy, revokeExecutionSite} from
  '../../../../host-common/execution-sites.mjs';
import {createManagedMemoryTransferProvider} from
  '../../../../store-local/managed-memory-transfer.mjs';
import {openLocalPublicationStore} from
  '../../../../store-local/publication-store.mjs';
import {
  deliverAuthorizedResult,
  installNodeResultAccessService,
  installResultAccessAuthority,
} from '../../../../host-node/result-access.mjs';
import {canonical, hash as canonicalHash} from './typed-catalog.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
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

// Read a completed run's Named Result through the existing publication
// export, which reads managed and captured outputs alike, and return its
// rows in order. The temporary Store is removed afterwards.
async function readPublishedResultRows(runtime, execution, result) {
  const directory = await mkdtemp(join(root, '_build/duckdb-fixtures/result-read-'));
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: hash('result-read-store'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: publicationResultExportLimits.maxWireBytes,
    maxObjects: 100,
    maxContractNodes: 10000,
    maxContractDepth: 64,
  }, runtime.publicationControl);
  try {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const seal = (kind, value) =>
      runtime.publicationControl.seal(kind, JSON.stringify(value), limits);
    const policy = hash('result-read-policy');
    const stored = await execution.storePublicationResult(result, store, {
      outputLimits: publicationResultExportLimits,
      contractLimits: limits,
      runDefinition: seal('run_definition', {
        version: 'actql-run-definition/0.1',
        scope_id: 'result-read-scope',
        run_id: 'result-read-run',
        compiled_plan_cid: hash('compiled-plan'),
        invocation_template_cid: hash('invocation-template'),
        authorization_context_cid: hash('authorization-context'),
        input_artifact_set_cid: hash('input-artifact-set'),
        created_at: '2026-09-18T00:00:00.000Z',
        valid_until: '2026-09-18T04:00:00.000Z',
      }),
      invocation: seal('run_invocation', {
        version: 'actql-run-invocation/0.1',
        invocation_template_cid: hash('invocation-template'),
        observation_set_cid: hash('observation-set'),
      }),
      retention: seal('result_retention_policy', {
        version: 'actql-result-retention-policy/0.1',
        retention_contract_cid: hash('retention-contract'),
        effective_data_policy_cid: policy,
        available_until: '2026-09-18T01:00:00.000Z',
        delete_by: '2026-09-18T02:00:00.000Z',
        extension_ceiling_at: '2026-09-18T03:00:00.000Z',
        metadata_retention_policy_cid: hash('metadata-retention'),
        metadata_delete_by: '2026-09-18T04:00:00.000Z',
        clock_contract_cid: hash('clock-contract'),
      }),
      evidenceContext: {
        computationContractCid: hash('checked-computation'),
        inputRelationCids: [],
        scopeCid: hash('result-scope'),
        effectiveDataPolicyCid: policy,
        authorityScopeCid: hash('authority-scope'),
      },
    });
    const payload = [];
    try {
      await store.consumeObject(stored.physical.cid,
        chunk => payload.push(Buffer.from(chunk)));
    } finally {
      assert.equal(await stored.prepared.release(), true);
    }
    return JSON.parse(Buffer.concat(payload).toString('utf8'));
  } finally {
    await store.close();
    await rm(directory, {recursive: true, force: true});
  }
}

function sgaEnvironmentArguments(args) {
  const environment = JSON.parse(args[0]);
  delete environment.evidence_bundle_cid;
  Object.assign(environment.host_policy_profile.capacity, {
    max_graph_construction_edges: 10000,
    max_graph_construction_input_rows: 10000,
    max_graph_construction_nodes: 10000,
  });
  environment.evidence_bundle_cid = canonicalHash(environment);
  return [
    canonical(environment),
    environment.evidence_bundle_cid,
    ...args.slice(2),
  ];
}

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
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
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
      namespaceId: 'namespace-a',
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
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/conformance'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/physical_strategy_example'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/physical_task_manifest_example'], { cwd: root });
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
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
  const contracts = await pinnedEngineContracts(root);
  const [orderedContract] = await pinnedEngineContracts(
    root,
    ['registered_ordered'],
  );
  const args = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'), 'utf8')];
  const analyticEnvironment = JSON.parse(args[0]);
  Object.assign(analyticEnvironment.host_policy_profile.capacity, {
    max_analytic_frame_memberships: 10000,
    max_analytic_input_wire_bytes: 10000,
    max_analytic_output_wire_bytes: 10000,
    max_analytic_partition_wire_bytes: 10000,
  });
  const {
    evidence_bundle_cid: ignoredEnvironmentCid,
    ...analyticEnvironmentBody
  } = analyticEnvironment;
  void ignoredEnvironmentCid;
  analyticEnvironment.evidence_bundle_cid =
    canonicalHash(analyticEnvironmentBody);
  const analyticArgs = [
    canonical(analyticEnvironment),
    analyticEnvironment.evidence_bundle_cid,
    ...args.slice(2),
  ];
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
      const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
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
            assert(error.cause); // Preserve the typed admission failure, not a JS bridge error.
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
          // The private physical ordinal participates in the import wire but
          // is not a caller-visible logical cell.
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
      if (kind === 'valid') await exerciseStrategyGraph(
        fixture,
        args,
        analyticArgs,
        path,
        grant,
        suppliedLimits,
        orderedContract,
      );
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

async function exerciseStrategyGraph(
  fixture,
  args,
  analyticArgs,
  path,
  grant,
  suppliedLimits,
  orderedContract,
) {
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
  const pagedEventsProgram = {
    version: 'actql/0.1',
    id: 'paged-events',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'events',
      inputs: {rows: {result: {stage: 'a', result: 'r'}}},
      steps: [{
        from: 'rows',
        to_events: {id: 'id', time: 'id'},
      }, {
        window_events: {kind: 'fixed', size: 2},
      }, {
        events: true,
        as: 'out',
      }],
      results: {
        r: {
          from: 'out',
          fields: ['id', 'window_start_ms', 'window_end_ms'],
        },
      },
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'events', result: 'r'}}},
      steps: [{
        select: ['id', 'window_start_ms', 'window_end_ms'],
        as: 'out',
      }],
      results: {
        r: {
          from: 'out',
          fields: ['id', 'window_start_ms', 'window_end_ms'],
        },
      },
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'events', result: 'r'}}},
      steps: [{select: ['window_start_ms', 'id'], as: 'out'}],
      results: {
        r: {from: 'out', fields: ['window_start_ms', 'id']},
      },
    }],
    results: {published: {from: {stage: 'consumer_a', result: 'r'}}},
  };
  const runPagedEvents = async maxChunkRows => {
    await replaceRows(
      'INSERT INTO records VALUES (4,40),(1,NULL),(2,20),(3,30)',
    );
    const paged = fixture.strategyFixtureTeaCreate(
      ...args,
      JSON.stringify(pagedEventsProgram),
    );
    const capture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(paged),
      {...suppliedLimits, maxChunkRows, maxChunkBytes: 4096},
    );
    let execution;
    try {
      assert.equal(fixture.strategyFixtureOpen(paged, capture.source()), true);
      const setup = fixture.strategyFixtureTeaSubset(paged);
      assert.deepEqual(hostRuntime.strategyHostManagedProducers(setup), [0]);
      execution = await runCapturedStrategy(
        setup,
        {},
        new AbortController().signal,
      );
      assert.equal(
        execution.status,
        'host-tasks-completed',
        JSON.stringify({
          failure: execution.failure?.stack,
          failureCause: execution.failure?.cause,
          exclusions: execution.candidateExclusions,
          comparisons: execution.candidateComparisons,
          completed: execution.completed,
        }, (_, value) => typeof value === 'bigint' ? value.toString() : value),
      );
      assert.deepEqual(
        execution.completed.map(value => value.realization),
        Array(3).fill('local-managed'),
      );
      return Object.freeze({
        observation: JSON.parse(capture.document()).output,
        first: fixture.strategyFixtureCid(paged, 2),
        second: fixture.strategyFixtureCid(paged, 3),
      });
    } finally {
      await execution?.close();
      if (execution !== undefined) {
        assert.equal(execution.cleanupPending(), false);
        assert.equal(await execution.cleanup(), true);
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
      capture.close();
    }
  };
  const singleRowPages = await runPagedEvents(1);
  const wholeObservation = await runPagedEvents(100);
  assert.deepEqual(singleRowPages, wholeObservation);
  assert.equal(singleRowPages.observation.row_count, 3);
  assert.notEqual(singleRowPages.first, undefined);
  assert.notEqual(singleRowPages.second, undefined);
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
            Array(3).fill(mode === 0 || mode === 2 ? 'local-managed' :
              mode === 3 ? 'duckdb' : 'reference-numeric'),
            `mode=${mode}`);
          // Managed completion is not mirrored into the legacy fixture's
          // output slot. Its value is checked through publication below;
          // legacy and DuckDB placements retain the CID assertion.
          if (mode === 1 || mode === 3) {
            assert.equal(fixture.strategyFixtureCid(f, 3),
              hash([{id:3}, {id:3}]));
          }
          if (mode !== 1) {
            assert.ok(execution.usage().transferredBytes > 0n);
          } else {
            assert.equal(execution.usage().transferredBytes, 0n);
          }
          if (mode !== 1) {
            const runtime = runtimeCore(hostRuntime);
            const publicationDirectory = await mkdtemp(join(
              root, '_build/duckdb-fixtures/publication-payload-',
            ));
            const publicationConfiguration = {
              directory: publicationDirectory,
              storeAuthorityCid: hash('publication-store'),
              capacityBytes: 4 * 1024 * 1024,
              maxObjectBytes: publicationResultExportLimits.maxWireBytes,
              maxObjects: 100,
              maxContractNodes: 10000,
              maxContractDepth: 64,
            };
            const publicationStore = await openLocalPublicationStore(
              publicationConfiguration,
              runtime.publicationControl,
            );
            let restartedPublicationStore;
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
                  metadata_delete_by: '2026-09-18T04:00:00.000Z',
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
                  metadata_delete_by: '2026-09-18T04:00:00.000Z',
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
                  namespaceId: 'namespace-a',
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
                      metadata_delete_by:
                        '2026-09-18T04:00:00.000Z',
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
                  namespaceId: 'namespace-a',
                  authorityScopeCid: hash('authority-scope'),
                  runDefinitionCid: publishedRun.identity,
                }, occurrence.definitionContract.identity,
                  () => true, chunk => received.push(Buffer.from(chunk)));
                assert.ok(received.length > 0);
              }
              const accessAuthority = installResultAccessAuthority({
                authorizeResultReadRequest: () => true,
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
                        namespaceId: 'namespace-a',
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
                      async finish() { return {confirmed: true}; },
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
              await publicationStore.close();
              restartedPublicationStore = await openLocalPublicationStore(
                publicationConfiguration,
                runtime.publicationControl,
              );
              let restartedAdmissions = 0;
              let restartedAuthorizations = 0;
              const restartedAccess = installNodeResultAccessService({
                store: restartedPublicationStore,
                control: runtime.publicationControl,
                authority: installResultAccessAuthority({
                  authorizeResultReadRequest() {
                    return true;
                  },
                  admitResultRead() {
                    restartedAdmissions++;
                    return {
                      authorizationContextCid:
                        hash('restarted-authorization-context'),
                      dataCeilingCid: hash('restarted-data-ceiling'),
                      egressAdmissionCid: hash('restarted-egress-admission'),
                      expiresAt: '2026-09-18T01:00:00.000Z',
                      maxBytes: 100000,
                      maxUses: 1,
                    };
                  },
                  authorizeResultRead() {
                    restartedAuthorizations++;
                    return true;
                  },
                }),
                now: () => '2026-09-18T00:45:00.000Z',
                limits: contractLimits,
                frameLimits: {
                  maxRowBytes: 4096,
                  maxDepth: 32,
                  maxFrameBytes: 4096,
                },
              });
              const restartedOccurrence =
                execution.publicationInventory.occurrences[0];
              const restartedBytes = [];
              await deliverAuthorizedResult(
                restartedAccess,
                {
                  indexKey: {
                    namespaceId: 'namespace-a',
                    authorityScopeCid: hash('authority-scope'),
                    runDefinitionCid: publishedRun.identity,
                  },
                  principalId: 'principal-after-restart',
                  purpose: 'download-after-restart',
                  resultName: restartedOccurrence.name,
                  format: 'json',
                  attemptId: `restarted-${mode}`,
                },
                {
                  async write(bytes) {
                    restartedBytes.push(Buffer.from(bytes));
                    return {confirmedBytes: bytes.byteLength};
                  },
                  async finish() { return {confirmed: true}; },
                },
                controller.signal,
              );
              assert.equal(restartedAdmissions, 1);
              assert.ok(restartedAuthorizations >= 3);
              assert.equal(
                Buffer.concat(restartedBytes).toString('utf8'),
                expectedDelivery[restartedOccurrence.name].json,
              );
            } finally {
              await restartedPublicationStore?.close();
              await publicationStore.close();
              await rm(publicationDirectory, {recursive: true, force: true});
            }
          }
        }
      } finally { await execution?.close(); capture.close(); }
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
        Array(3).fill(mode === 3 ? 'duckdb' : 'local-managed'),
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
          namespaceId: plan.request.namespaceId,
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
  const createCarrierRetainedStore = async (name, options = {}) => {
    const directory = await mkdtemp(join(
      root, `_build/duckdb-fixtures/${name}-retained-entry-`,
    ));
    const store = await createLocalRetainedStore({
      parentDirectory: directory,
      capacityBytes: 8 * 1024 * 1024,
      maxFrameBytes: 1024 * 1024,
    });
    const leases = [];
    let permitCleanup = false;
    let cleanupFailures = 0;
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases.push(key);
      const lease = leases.length;
      let writer, closed = false, cleanupPending = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && (!closed || cleanupPending)
          ? bytes : 0, cleanupPending}),
        reserve: value => (writer = store.reserve(value)),
        close() {
          options.beforeClose?.();
          closed = true;
          if (lease === options.failCleanupLease) cleanupPending = true;
          else writer?.cancel();
        },
        async cleanup() {
          if (cleanupPending && !permitCleanup) {
            cleanupFailures++;
            throw new Error('InjectedCarrierRetainedCleanupPending');
          }
          writer?.cancel();
          await writer?.cleanupHandle?.retry?.();
          cleanupPending = false;
        },
      });
    });
    return Object.freeze({
      configuration, leases,
      permitCleanup() { permitCleanup = true; },
      cleanupFailures: () => cleanupFailures,
      async close() {
        await store.close();
        await rm(directory, {recursive: true, force: true});
      },
    });
  };
  const graphProgramBase = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'values',
      inputs: {},
      steps: [{
        values: {
          schema: {
            id: {type: 'number', nullable: false},
            src: {type: 'number', nullable: false},
            dst: {type: 'number', nullable: false},
            node_name: {type: 'string', nullable: false},
            weight: {type: 'number', nullable: false},
          },
          rows: [
            {id: 1, src: 1, dst: 2, node_name: 'first', weight: 10},
            {id: 2, src: 2, dst: 1, node_name: 'second', weight: 20},
          ],
        },
        as: 'out',
      }],
      results: {
        r: {from: 'out', fields: ['id', 'src', 'dst', 'node_name', 'weight']},
      },
    }, {
      id: 'graph',
      inputs: {rows: {result: {stage: 'values', result: 'r'}}},
      steps: [{
        property_graph: {
          version:'actql-property-graph-constructor/0.1',
          nodes:[{name:'N',from:'rows',key:['id'],
            labels:[{name:'Node',properties:{mode:'all_columns'}}]}],
          edges:[{name:'E',from:'rows',key:['id'],
            source:{definition:'N',key:['src']},
            target:{definition:'N',key:['dst']},
            labels:[{name:'Link',properties:{mode:'all_columns'}}]}],
        },
        as: 'g',
      }, {
        from: 'g',
        match_nodes: {definition:'N',where:'true',fields:['id','node_name']},
        as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'node_name']}},
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'graph', result: 'r'}}},
      steps: [{select: ['id', 'node_name'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'node_name']}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'graph', result: 'r'}}},
      steps: [{select: ['node_name'], as: 'out'}],
      results: {r: {from: 'out', fields: ['node_name']}},
    }, {
      id: 'tail',
      inputs: {x: {result: {stage: 'consumer_a', result: 'r'}}},
      steps: [{select: ['id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}},
    }],
    results: {published: {from: {stage: 'graph', result: 'r'}}},
  };
  // Current Graph execution positives use the sole typed-key constructor.
  // Unsupported algorithm acceptance belongs to the shared public refusal
  // test, not to historical tuple fixtures in this execution/custody matrix.
  const graphPublicationCases = [{
    name: 'node-match',
    step: {from:'g', match_nodes:{definition:'N', where:'true',
      fields:['id','node_name']}, as:'out'},
    fields:['id','node_name'], secondFields:['node_name'],
    expected:[{id:1,node_name:'first'},{id:2,node_name:'second'}],
    // VALUES, fused constructor/MATCH, two consumers, and the tail.
    completedTasks:5,
  }, {
    name:'retained-node-match', retainedOutput:true, selectedStructural:true,
    step:{from:'g', match_nodes:{definition:'N', where:'true',
      fields:['id','node_name']}, as:'out'},
    fields:['id','node_name'], secondFields:['node_name'],
    expected:[{id:1,node_name:'first'},{id:2,node_name:'second'}],
  }, {
    name:'node-match-filter-sort-take',
    steps:[
      {from:'g',match_nodes:{definition:'N',where:'true',
        fields:['id','node_name']},as:'matched'},
      {from:'matched',filter:'id > 1',as:'filtered'},
      {from:'filtered',sort:[{id:'desc'}],as:'ordered'},
      {from:'ordered',take:{count:1,offset:0},as:'out'},
    ],
    fields:['id','node_name'],secondFields:['node_name'],
    expected:[{id:2,node_name:'second'}],completedTasks:9,
  }, {
    name:'retained-trail-relation-filter', retainedOutput:true,
    steps:[
      {from:'g',traverse:{start:{from:'seeds',id:'element'},
        direction:'out',min_hops:1,max_hops:1,path_mode:'trail',
        emit:'paths'},as:'paths'},
      {from:'paths',filter:'hop_count > 0',as:'out'},
    ],
    fields:['hop_count'],secondFields:['hop_count'],
    expected:[{hop_count:1},{hop_count:1}],
  }, {
    name:'edge-match',
    step:{from:'g',match_edges:{definition:'E',where:'true',
      fields:['src','dst','weight']},as:'out'},
    fields:['src','dst','weight'],secondFields:['weight','src'],
    expected:[{src:1,dst:2,weight:10},{src:2,dst:1,weight:20}],
    completedTasks:5,
  }];
  for (const publicationCase of graphPublicationCases) {
    const graphProgram = structuredClone(graphProgramBase);
    const graphStage = graphProgram.stages.find(stage => stage.id === 'graph');
    const consumerA = graphProgram.stages.find(stage => stage.id === 'consumer_a');
    const consumerB = graphProgram.stages.find(stage => stage.id === 'consumer_b');
    const tail = graphProgram.stages.find(stage => stage.id === 'tail');
    if (publicationCase.name === 'retained-trail-relation-filter') {
      const seedSource = {
        id:'seed_source',
        inputs:{rows:{result:{stage:'values',result:'r'}}},
        steps:[structuredClone(graphStage.steps[0]),{
          from:'g',match_nodes:{definition:'N',
            bindings:{identity:'element'},where:'true',fields:['element']},
          as:'seeds',
        }],
        results:{r:{from:'seeds',fields:['element']}},
      };
      graphProgram.stages.splice(graphProgram.stages.indexOf(graphStage),0,seedSource);
      graphStage.inputs.seeds = {result:{stage:'seed_source',result:'r'}};
    }
    graphStage.steps.splice(
      1,
      1,
      ...(publicationCase.steps ?? [publicationCase.step]),
    );
    if (publicationCase.selectedStructural) {
      graphStage.steps.at(-1).as = 'projected';
      graphStage.steps.push({
        from: 'projected', filter: 'true', as: 'out',
      });
    }
    graphStage.results.r.fields = publicationCase.fields;
    consumerA.steps[0].select = publicationCase.fields;
    consumerA.results.r.fields = publicationCase.fields;
    consumerB.steps[0].select = publicationCase.secondFields;
    consumerB.results.r.fields = publicationCase.secondFields;
    if (tail) {
      tail.steps[0].select = [publicationCase.fields[0]];
      tail.results.r.fields = [publicationCase.fields[0]];
    }
    if (publicationCase.name === 'node-match-filter-sort-take' ||
        publicationCase.retainedOutput) {
      graphProgram.results.consumed_a = {
        from: {stage: 'consumer_a', result: 'r'},
      };
      graphProgram.results.consumed_b = {
        from: {stage: 'consumer_b', result: 'r'},
      };
    }
    const createSgaFixture = fixture.strategyFixtureSgaCreate;
    let sgaFixture;
    try {
      sgaFixture = createSgaFixture(
        ...sgaEnvironmentArguments(args),
        JSON.stringify(graphProgram),
        ...(publicationCase.name === 'retained-shortest-filter' ? [2n] : []),
      );
    } catch (error) {
      throw new Error(`SGA fixture ${publicationCase.name} failed to check`,
        {cause: error});
    }
    const sgaCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(sgaFixture),
      suppliedLimits,
    );
    const sgaPublicationDirectory = await mkdtemp(join(
      root,
      '_build/duckdb-fixtures/sga-publication-entry-',
    ));
    const sgaRetained = publicationCase.retainedOutput
      ? await createCarrierRetainedStore('sga', {
        failCleanupLease: publicationCase.name === 'retained-node-match'
          ? 1 : undefined,
      })
      : undefined;
    let sgaPublicationOwner, failedGraphExecution;
    let sgaPublicationStore;
    try {
      assert.equal(
        fixture.strategyFixtureOpen(sgaFixture, sgaCapture.source()),
        true,
      );
      const setup = publicationCase.name === 'retained-node-match'
        ? fixture.strategyFixtureSgaRetainedNodeLimit(sgaFixture, 2)
        : publicationCase.retainedOutput
          ? fixture.strategyFixtureSgaRetainedSubset(sgaFixture)
          : fixture.strategyFixtureSgaSubset(sgaFixture);
      const runtime = runtimeCore(hostRuntime);
      const resultCount = runtime.resultInventory(setup).length;
      assert.equal(
        resultCount,
        publicationCase.name === 'node-match-filter-sort-take' ||
          publicationCase.retainedOutput ? 3 : 1,
      );
      sgaPublicationStore = await openLocalPublicationStore({
        directory: sgaPublicationDirectory,
        storeAuthorityCid: hash('sga-publication-store'),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime,
        runtime.programDefinitionCid(setup),
        resultCount,
        `sga-publication-attempt-${publicationCase.name}`,
      );
      sgaPublicationOwner = await runPublishedCapturedStrategy(
        setup,
        {store: sgaPublicationStore, plan},
        sgaRetained === undefined
          ? {} : {local: sgaRetained.configuration},
        new AbortController().signal,
      );
      assert.equal(sgaPublicationOwner.status, 'published');
      assert.equal(
        sgaPublicationOwner.publication.publication.state,
        'succeeded',
      );
      if (!publicationCase.retainedOutput) {
        assert.deepEqual(
          sgaPublicationOwner.execution.completed.map(value => value.realization),
          Array(publicationCase.completedTasks ?? 7)
            .fill('local-managed'),
          publicationCase.name,
        );
      } else {
        assert(sgaRetained.leases.length > 0);
        assert(sgaPublicationOwner.execution.completed.some(value =>
          value.outputRepresentation === 'retained-file'));
        assert(sgaPublicationOwner.execution.completed.some(value =>
          value.outputRepresentation === 'managed-local-carrier'));
        assert(sgaPublicationOwner.execution.completed.some(value =>
          value.outputRepresentation === 'managed-local-memory'));
      }
      if (publicationCase.name === 'node-match-filter-sort-take') {
        assert.deepEqual(
          sgaPublicationOwner.execution.completed.map(value => value.task),
          [1, 2, 3, 4, 5, 6, 7, 8, 9],
        );
      }
      const expectedResults = {
        published: publicationCase.expected,
        ...(publicationCase.name === 'node-match-filter-sort-take' ||
          publicationCase.retainedOutput ? {
          consumed_a: publicationCase.expected,
          consumed_b: publicationCase.expected.map(row =>
            Object.fromEntries(publicationCase.secondFields.map(field =>
              [field, row[field]]))),
        } : {}),
      };
      for (const occurrence of
        sgaPublicationOwner.execution.publicationInventory.occurrences) {
        const received = [];
        await sgaPublicationStore.consumeCommittedResult({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, occurrence.definitionContract.identity, () => true,
        chunk => received.push(Buffer.from(chunk)));
        const actual = JSON.parse(Buffer.concat(received).toString('utf8'));
        const expected = expectedResults[occurrence.name];
        assert.deepEqual(
          actual,
          expected,
          `${publicationCase.name}/${occurrence.name}`,
        );
        if (publicationCase.name === 'edge-match' &&
            occurrence.name === 'published') {
          assert.throws(
            () => assert.deepEqual([...actual].reverse(), expected),
            {code: 'ERR_ASSERTION'},
            'the published edge-row assertion must reject reversed output',
          );
        }
      }
    } catch (error) {
      failedGraphExecution = error.execution;
      console.error('Current Graph publication failure', publicationCase.name,
        inspect({status:failedGraphExecution?.status,
          failure:failedGraphExecution?.failure,
          completed:failedGraphExecution?.completed}, {depth:8}));
      throw error;
    } finally {
      if (failedGraphExecution !== undefined) {
        await failedGraphExecution.close();
        assert.equal(await failedGraphExecution.cleanup(), true);
        assert.equal(failedGraphExecution.cleanupPending(), false);
        assert.equal(failedGraphExecution.usage().heldBytes, 0n);
        assert.equal(failedGraphExecution.usage().reservedExecutionBytes, 0n);
      }
      if (sgaPublicationOwner !== undefined) {
        if (publicationCase.name === 'retained-node-match') {
          assert.equal(sgaRetained.leases.length, 1);
          await assert.rejects(
            async () => sgaPublicationOwner.close(),
            /InjectedCarrierRetainedCleanupPending/,
          );
          assert.equal(sgaPublicationOwner.cleanupPending(), true);
          assert.equal(sgaRetained.cleanupFailures(), 1);
          assert(sgaPublicationOwner.execution.usage().heldBytes > 0n ||
            sgaPublicationOwner.execution.usage().reservedExecutionBytes > 0n);
          sgaRetained.permitCleanup();
        } else await sgaPublicationOwner.close();
        assert.equal(await sgaPublicationOwner.cleanup(), true);
        assert.equal(sgaPublicationOwner.cleanupPending(), false);
        assert.equal(sgaPublicationOwner.execution.usage().heldBytes, 0n);
        assert.equal(
          sgaPublicationOwner.execution.usage().reservedExecutionBytes,
          0n,
        );
      }
      sgaCapture.close();
      await sgaPublicationStore?.close();
      await rm(sgaPublicationDirectory, {recursive: true, force: true});
      await sgaRetained?.close();
    }
  }
  for (const failureCase of [
    'construction-capacity', 'consumer-filter', 'following-relation-filter',
    'match-predicate',
  ]) {
    const failureProgram = structuredClone(graphProgramBase);
    failureProgram.stages[2].steps.splice(1,1,{
      from:'g', match_nodes:{definition:'N',
        where:failureCase === 'match-predicate' ? '1 / (id - id) > 0' : 'true',
      fields:['id','node_name']}, as:'out',
    });
    failureProgram.stages[2].steps.at(-1).as = 'projected';
    failureProgram.stages[2].steps.push({
      from:'projected',
      filter:failureCase === 'following-relation-filter'
        ? '1 / (id - id) > 0' : 'true',
      as:'out',
    });
    failureProgram.results.consumed_a = {
      from: {stage: 'consumer_a', result: 'r'},
    };
    if (failureCase === 'match-predicate') {
      failureProgram.stages.pop();
    } else {
      failureProgram.results.consumed_b = {
        from: {stage: 'consumer_b', result: 'r'},
      };
    }
    if (failureCase === 'consumer-filter') {
      failureProgram.stages[3].steps = [{
        filter: '1 / (id - id) > 0', as: 'filtered',
      }, {
        from: 'filtered', select: ['id', 'node_name'], as: 'out',
      }];
    }
    const failureFixture = fixture.strategyFixtureSgaCreate(
      ...sgaEnvironmentArguments(args), JSON.stringify(failureProgram),
    );
    const failureCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(failureFixture),
      suppliedLimits,
    );
    const failureDirectory = await mkdtemp(join(
      root, `_build/duckdb-fixtures/sga-${failureCase}-entry-`,
    ));
    const failureRetained = await createCarrierRetainedStore(failureCase);
    let failurePublicationStore, failureExecution;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        failureFixture, failureCapture.source()), true);
      const setup = failureCase === 'construction-capacity'
        ? fixture.strategyFixtureSgaRetainedNodeLimit(failureFixture, 1)
        : fixture.strategyFixtureSgaRetainedSubset(failureFixture);
      const runtime = runtimeCore(hostRuntime);
      failurePublicationStore = await openLocalPublicationStore({
        directory: failureDirectory,
        storeAuthorityCid: hash(`sga-${failureCase}-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime,
        runtime.programDefinitionCid(setup),
        runtime.resultInventory(setup).length,
        `sga-${failureCase}-attempt`,
      );
      await assert.rejects(runPublishedCapturedStrategy(
        setup, {store: failurePublicationStore, plan},
        {local: failureRetained.configuration},
        new AbortController().signal,
      ), error => {
        failureExecution = error.execution;
        return error.code === 'CapturedRunPublicationFailed';
      });
      assert.equal(failureExecution.status, 'host-tasks-failed');
      assert(failureRetained.leases.length > 0);
      assert(failureExecution.completed.some(value =>
        value.outputRepresentation === 'retained-file'));
      assert.equal(failureExecution.completed.some(value =>
        value.outputRepresentation === 'managed-local-carrier'),
      failureCase !== 'construction-capacity');
      assert.equal(failureExecution.failure?.code, 'MoonBitHostFailure');
      assert(failureExecution.failure.cause);
      // The Graph provider preserves its typed InputSet rejection; row
      // kernels preserve their exact scalar error and authored location.
      assert.equal(failureCase === 'construction-capacity' ||
          failureCase === 'match-predicate'
        ? fixture.strategyFixtureSgaConstructionLimitFailure(
          failureExecution.failure.cause)
        : failureCase === 'following-relation-filter'
          ? fixture.strategyFixtureManagedFilterArithmetic(
            failureExecution.failure.cause, 2)
        : fixture.strategyFixtureSgaConsumerFilterArithmetic(
          failureExecution.failure.cause), true,
      `${failureCase}: preserve the selected typed failure; ` +
        JSON.stringify(failureExecution.failure.cause,
          (_, value) => typeof value === 'bigint' ? value.toString() : value));
      await assert.rejects(failurePublicationStore.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
    } finally {
      if (failureExecution !== undefined) {
        await failureExecution.close();
        assert.equal(await failureExecution.cleanup(), true);
        assert.equal(failureExecution.cleanupPending(), false);
        assert.equal(failureExecution.usage().heldBytes, 0n);
        assert.equal(failureExecution.usage().reservedExecutionBytes, 0n);
      }
      failureCapture.close();
      await failurePublicationStore?.close();
      await rm(failureDirectory, {recursive: true, force: true});
      await failureRetained.close();
    }
  }
  const vectorExpressionProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'vector_values',
      inputs: {},
      steps: [{
        values: {
          schema: {
            id: {type: 'number', nullable: false},
            left: {type: 'vector', dimensions: 2, nullable: false},
            right: {type: 'vector', dimensions: 2, nullable: false},
          },
          rows: [
            {id: 1, left: [1, 2], right: [3, 4]},
            {id: 2, left: [2, 1], right: [4, 3]},
          ],
        },
        as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'left', 'right']}},
    }, {
      id: 'vector_score',
      inputs: {
        rows: {result: {stage: 'vector_values', result: 'r'}},
      },
      steps: [{
        derive: {
          score: {
            vector_score: {
              left: {field: 'left'},
              right: {field: 'right'},
              metric: 'dot',
            },
          },
        },
        as: 'out',
      }],
      results: {
        r: {from: 'out', fields: ['id', 'left', 'right', 'score']},
      },
    }, {
      id: 'vectors',
      inputs: {
        rows: {result: {stage: 'vector_score', result: 'r'}},
      },
      steps: [{
        derive: {
          joined: {
            vector_concat: [{field: 'right'}, {field: 'left'}],
          },
        },
        as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'score', 'joined']}},
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
      steps: [{select: ['id', 'score', 'joined'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'score', 'joined']}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
      steps: [{select: ['joined', 'id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['joined', 'id']}},
    }],
    results: {published: {from: {stage: 'vectors', result: 'r'}}},
  };
  const vectorFixture = fixture.strategyFixtureVecaCreate(
    ...args,
    JSON.stringify(vectorExpressionProgram),
    orderedContract,
  );
  const vectorCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(vectorFixture),
    suppliedLimits,
  );
  const vectorPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/vector-publication-entry-',
  ));
  let vectorPublicationOwner;
  let vectorPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(vectorFixture, vectorCapture.source()),
      true,
    );
    const setup = fixture.strategyFixtureModuleSubset(vectorFixture, 0);
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 1);
    vectorPublicationStore = await openLocalPublicationStore({
      directory: vectorPublicationDirectory,
      storeAuthorityCid: hash('vector-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'vector-publication-attempt',
    );
    vectorPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: vectorPublicationStore, plan},
      {},
      new AbortController().signal,
    );
    assert.equal(vectorPublicationOwner.status, 'published');
    assert.equal(
      vectorPublicationOwner.publication.publication.state,
      'succeeded',
    );
    assert.deepEqual(
      vectorPublicationOwner.execution.completed.map(
        value => value.realization,
      ),
      Array(5).fill('local-managed'),
    );
    const occurrence =
      vectorPublicationOwner.execution.publicationInventory.occurrences[0];
    const received = [];
    await vectorPublicationStore.consumeCommittedResult({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, occurrence.definitionContract.identity, () => true,
    chunk => received.push(Buffer.from(chunk)));
    assert.deepEqual(
      JSON.parse(Buffer.concat(received).toString('utf8')),
      [
        {id: 1, score: 11, joined: [3, 4, 1, 2]},
        {id: 2, score: 11, joined: [4, 3, 2, 1]},
      ],
    );
  } finally {
    if (vectorPublicationOwner !== undefined) {
      await vectorPublicationOwner.close();
      assert.equal(vectorPublicationOwner.cleanupPending(), false);
      assert.equal(await vectorPublicationOwner.cleanup(), true);
      assert.equal(vectorPublicationOwner.execution.usage().heldBytes, 0n);
      assert.equal(
        vectorPublicationOwner.execution.usage().reservedExecutionBytes,
        0n,
      );
    }
    vectorCapture.close();
    await vectorPublicationStore?.close();
    await rm(vectorPublicationDirectory, {recursive: true, force: true});
  }
  const eventPublicationProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'values',
      inputs: {},
      steps: [{
        values: {
          schema: {
            event_id: {type: 'number', nullable: false},
            occurred_at: {type: 'number', nullable: false},
            payload: {type: 'string', nullable: false},
          },
          rows: [
            {event_id: 1, occurred_at: 5, payload: 'first'},
            {event_id: 2, occurred_at: 15, payload: 'second'},
          ],
        },
        as: 'out',
      }],
      results: {
        r: {from: 'out', fields: ['event_id', 'occurred_at', 'payload']},
      },
    }, {
      id: 'events',
      inputs: {rows: {result: {stage: 'values', result: 'r'}}},
      steps: [{
        from: 'rows',
        to_events: {id: 'event_id', time: 'occurred_at'},
        as: 'source',
      }, {
        from: 'source',
        watermark_events: {watermark_ms: 10, policy: 'mark'},
        as: 'marked',
      }, {
        from: 'marked', events: true, as: 'out',
      }],
      results: {
        r: {
          from: 'out',
          fields: [
            'event_id',
            'occurred_at',
            'payload',
            'watermark_ms',
            'late',
            'watermark_decision',
          ],
        },
      },
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'events', result: 'r'}}},
      steps: [{select: ['event_id', 'late'], as: 'out'}],
      results: {r: {from: 'out', fields: ['event_id', 'late']}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'events', result: 'r'}}},
      steps: [{select: ['watermark_decision', 'event_id'], as: 'out'}],
      results: {
        r: {from: 'out', fields: ['watermark_decision', 'event_id']},
      },
    }],
    results: {
      published: {from: {stage: 'events', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    },
  };
  const eventPublicationFixture = fixture.strategyFixtureTeaCreate(
    ...args,
    JSON.stringify(eventPublicationProgram),
  );
  const eventCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(eventPublicationFixture),
    suppliedLimits,
  );
  const eventPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/event-publication-entry-',
  ));
  const eventRetained = await createCarrierRetainedStore('event');
  let eventPublicationOwner;
  let eventPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(
        eventPublicationFixture,
        eventCapture.source(),
      ),
      true,
    );
    const setup = fixture.strategyFixtureTeaRetainedSubset(
      eventPublicationFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 3);
    eventPublicationStore = await openLocalPublicationStore({
      directory: eventPublicationDirectory,
      storeAuthorityCid: hash('event-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'event-publication-attempt',
    );
    eventPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: eventPublicationStore, plan},
      {local: eventRetained.configuration},
      new AbortController().signal,
    );
    assert.equal(eventPublicationOwner.status, 'published');
    assert.equal(
      eventPublicationOwner.publication.publication.state,
      'succeeded',
    );
    assert(eventRetained.leases.length > 0);
    assert(eventPublicationOwner.execution.completed.some(value =>
      value.outputRepresentation === 'retained-file'));
    // The Events generation stays private within this task; only its formal
    // Relation Bridge output is handed to the downstream tasks.
    assert.equal(eventPublicationOwner.execution.completed.filter(value =>
      value.outputRepresentation === 'managed-local-carrier').length, 0);
    assert(eventPublicationOwner.execution.completed.some(value =>
      value.outputRepresentation === 'managed-local-memory'));
    const expectedResults = {
      published: [{
        event_id: 1,
        occurred_at: 5,
        payload: 'first',
        watermark_ms: 10,
        late: true,
        watermark_decision: 'mark',
      }, {
        event_id: 2,
        occurred_at: 15,
        payload: 'second',
        watermark_ms: 10,
        late: false,
        watermark_decision: 'keep',
      }],
      consumed_a: [
        {event_id: 1, late: true},
        {event_id: 2, late: false},
      ],
      consumed_b: [
        {watermark_decision: 'mark', event_id: 1},
        {watermark_decision: 'keep', event_id: 2},
      ],
    };
    for (const occurrence of eventPublicationOwner.execution
      .publicationInventory.occurrences) {
      const received = [];
      await eventPublicationStore.consumeCommittedResult({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, occurrence.definitionContract.identity, () => true,
      chunk => received.push(Buffer.from(chunk)));
      assert.deepEqual(
        JSON.parse(Buffer.concat(received).toString('utf8')),
        expectedResults[occurrence.name],
      );
    }
  } finally {
    if (eventPublicationOwner !== undefined) {
      await eventPublicationOwner.close();
      assert.equal(eventPublicationOwner.cleanupPending(), false);
      assert.equal(await eventPublicationOwner.cleanup(), true);
      assert.equal(eventPublicationOwner.execution.usage().heldBytes, 0n);
      assert.equal(
        eventPublicationOwner.execution.usage().reservedExecutionBytes,
        0n,
      );
    }
    eventCapture.close();
    await eventPublicationStore?.close();
    await rm(eventPublicationDirectory, {recursive: true, force: true});
    await eventRetained.close();
  }
  const carrierVectorPublicationProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'values',
      inputs: {},
      steps: [{
        values: {
          schema: {
            id: {type: 'number', nullable: false},
            embedding: {type: 'vector', dimensions: 2, nullable: false},
          },
          rows: [
            {id: 1, embedding: [3, 4]},
            {id: 2, embedding: [0, 2]},
          ],
        },
        as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'embedding']}},
    }, {
      id: 'vectors',
      inputs: {rows: {result: {stage: 'values', result: 'r'}}},
      steps: [{
        from: 'rows',
        to_vectors: {id: 'id', vector: 'embedding'},
        as: 'source',
      }, {
        from: 'source', normalize_vectors: true, as: 'normalized',
      }, {
        from: 'normalized',
        score_vectors: {query: [1, 0], metric: 'dot'},
        as: 'same_carrier',
      }, {
        from: 'normalized', vectors: true, as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'embedding']}},
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
      steps: [{select: ['id', 'embedding'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'embedding']}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
      steps: [{select: ['embedding', 'id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['embedding', 'id']}},
    }],
    results: {
      published: {from: {stage: 'vectors', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    },
  };
  const carrierVectorPublicationFixture = fixture.strategyFixtureVecaCreate(
    ...args,
    JSON.stringify(carrierVectorPublicationProgram),
    orderedContract,
  );
  const carrierVectorCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(carrierVectorPublicationFixture),
    suppliedLimits,
  );
  const carrierVectorPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/carrier-vector-publication-entry-',
  ));
  const carrierVectorRetained = await createCarrierRetainedStore('vector');
  let carrierVectorPublicationOwner;
  let carrierVectorPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(
        carrierVectorPublicationFixture,
        carrierVectorCapture.source(),
      ),
      true,
    );
    const setup = fixture.strategyFixtureVecaRetainedSubset(
      carrierVectorPublicationFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 3);
    carrierVectorPublicationStore = await openLocalPublicationStore({
      directory: carrierVectorPublicationDirectory,
      storeAuthorityCid: hash('carrier-vector-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'carrier-vector-publication-attempt',
    );
    carrierVectorPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: carrierVectorPublicationStore, plan},
      {local: carrierVectorRetained.configuration},
      new AbortController().signal,
    );
    assert.equal(carrierVectorPublicationOwner.status, 'published');
    assert.equal(
      carrierVectorPublicationOwner.publication.publication.state,
      'succeeded',
    );
    assert(carrierVectorRetained.leases.length > 0);
    assert(carrierVectorPublicationOwner.execution.completed.some(value =>
      value.outputRepresentation === 'retained-file'));
    // The Vectors generation remains private to the stage that publishes the
    // formal Relation view; this case checks its mixed retained handoff.
    assert.equal(carrierVectorPublicationOwner.execution.completed.filter(
      value => value.outputRepresentation === 'managed-local-carrier'
    ).length, 0);
    assert(carrierVectorPublicationOwner.execution.completed.some(value =>
      value.outputRepresentation === 'managed-local-memory'));
    const expectedResults = {
      published: [
        {id: 1, embedding: [0.6000000238418579, 0.800000011920929]},
        {id: 2, embedding: [0, 1]},
      ],
      consumed_a: [
        {id: 1, embedding: [0.6000000238418579, 0.800000011920929]},
        {id: 2, embedding: [0, 1]},
      ],
      consumed_b: [
        {embedding: [0.6000000238418579, 0.800000011920929], id: 1},
        {embedding: [0, 1], id: 2},
      ],
    };
    for (const occurrence of carrierVectorPublicationOwner.execution
      .publicationInventory.occurrences) {
      const received = [];
      await carrierVectorPublicationStore.consumeCommittedResult({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, occurrence.definitionContract.identity, () => true,
      chunk => received.push(Buffer.from(chunk)));
      assert.deepEqual(
        JSON.parse(Buffer.concat(received).toString('utf8')),
        expectedResults[occurrence.name],
      );
    }
  } finally {
    if (carrierVectorPublicationOwner !== undefined) {
      await carrierVectorPublicationOwner.close();
      assert.equal(carrierVectorPublicationOwner.cleanupPending(), false);
      assert.equal(await carrierVectorPublicationOwner.cleanup(), true);
      assert.equal(
        carrierVectorPublicationOwner.execution.usage().heldBytes,
        0n,
      );
      assert.equal(
        carrierVectorPublicationOwner.execution.usage()
          .reservedExecutionBytes,
        0n,
      );
    }
    carrierVectorCapture.close();
    await carrierVectorPublicationStore?.close();
    await rm(carrierVectorPublicationDirectory, {
      recursive: true,
      force: true,
    });
    await carrierVectorRetained.close();
  }
  const rankingFields = ['q', 'id', 'score', 'rank'];
  const rankingInputSchema = {
    q: {type: 'number', nullable: false},
    id: {type: 'number', nullable: false},
    rank: {type: 'number', nullable: false},
  };
  const rankingPublicationProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [carrierVectorPublicationProgram.stages[0], ...[
      ['left', [
        {q: 1, id: 1, rank: 1},
        {q: 1, id: 2, rank: 2},
        {q: 2, id: 1, rank: 1},
      ]],
      ['right', [
        {q: 1, id: 3, rank: 1},
        {q: 1, id: 1, rank: 2},
        {q: 2, id: 1, rank: 1},
      ]],
    ].map(([id, rows]) => ({
      id,
      inputs: {},
      steps: [{values: {schema: rankingInputSchema, rows}, as: 'out'}],
      results: {r: {from: 'out', fields: ['q', 'id', 'rank']}},
    })), {
      id: 'fusion',
      inputs: {
        left: {result: {stage: 'left', result: 'r'}},
        right: {result: {stage: 'right', result: 'r'}},
      },
      steps: [{
        from: 'left',
        merge_rankings: {
          with: ['right'], by: ['q'], candidate: 'id', rank: 'rank',
          score_policy: {rrf: {
            rank_constant: 1, weights: [1, 1], rank_window: 2,
          }},
          k: 2,
        },
        as: 'ranked',
      }, {
        from: 'ranked', filter: 'q = 1', as: 'out',
      }],
      results: {r: {from: 'out', fields: rankingFields}},
    }, ...['a', 'b'].map(id => ({
      id: `consumer_${id}`,
      inputs: {x: {result: {stage: 'fusion', result: 'r'}}},
      steps: [{select: rankingFields, as: 'out'}],
      results: {r: {from: 'out', fields: rankingFields}},
    }))],
    results: {
      published: {from: {stage: 'fusion', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    },
  };
  const rankingPublicationFixture = fixture.strategyFixtureVecaCreate(
    ...args, JSON.stringify(rankingPublicationProgram), orderedContract,
  );
  const rankingCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(rankingPublicationFixture),
    suppliedLimits,
  );
  const rankingPublicationDirectory = await mkdtemp(join(
    root, '_build/duckdb-fixtures/ranking-publication-entry-',
  ));
  const rankingRetained = await createCarrierRetainedStore('ranking-filter');
  let rankingPublicationOwner;
  let rankingPublicationStore;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      rankingPublicationFixture, rankingCapture.source()), true);
    const setup = fixture.strategyFixtureVecaRetainedSubset(
      rankingPublicationFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 3);
    rankingPublicationStore = await openLocalPublicationStore({
      directory: rankingPublicationDirectory,
      storeAuthorityCid: hash('ranking-filter-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'ranking-filter-publication-attempt',
    );
    rankingPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: rankingPublicationStore, plan},
      {local: rankingRetained.configuration},
      new AbortController().signal,
    );
    assert.equal(rankingPublicationOwner.status, 'published');
    assert.equal(rankingPublicationOwner.publication.publication.state,
      'succeeded');
    assert(rankingRetained.leases.length > 0);
    assert(rankingPublicationOwner.execution.completed.some(value =>
      value.outputRepresentation === 'retained-file'));
    const expectedRows = [
      {id: 1, q: 1, rank: 1, score: 0.8333333333333333},
      {id: 3, q: 1, rank: 2, score: 0.5},
    ];
    for (const occurrence of rankingPublicationOwner.execution
      .publicationInventory.occurrences) {
      const received = [];
      await rankingPublicationStore.consumeCommittedResult({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, occurrence.definitionContract.identity, () => true,
      chunk => received.push(Buffer.from(chunk)));
      assert.deepEqual(
        JSON.parse(Buffer.concat(received).toString('utf8')),
        expectedRows,
      );
    }
  } finally {
    if (rankingPublicationOwner !== undefined) {
      await rankingPublicationOwner.close();
      assert.equal(rankingPublicationOwner.cleanupPending(), false);
      assert.equal(await rankingPublicationOwner.cleanup(), true);
      assert.equal(rankingPublicationOwner.execution.usage().heldBytes, 0n);
      assert.equal(rankingPublicationOwner.execution.usage()
        .reservedExecutionBytes, 0n);
    }
    rankingCapture.close();
    await rankingPublicationStore?.close();
    await rm(rankingPublicationDirectory, {recursive: true, force: true});
    await rankingRetained.close();
  }
  const scoreContract = {
    domain: 'unit.v1', normalization: 'unit.v1', range: [0, 1],
  };
  const scoreSchema = {
    q: {type: 'number', nullable: false},
    id: {type: 'number', nullable: false},
    score: {type: 'number', nullable: false},
  };
  const scoredEnvironment = JSON.parse(args[0]);
  scoredEnvironment.schema_snapshots = ['right', 'left'].map(input => ({
    output_carrier: 'relation',
    schema: {
      type: 'object', nullable: false, additional_properties: false,
      fields: Object.fromEntries(Object.entries(scoreSchema).map(
        ([name, field]) => [name, {type: field.type, nullable: false}],
      )),
    },
    score_contracts: {score: scoreContract},
    source_ref: `source:local/fusion/${input}`,
    version: 'actql-local-input-schema/0.1',
  })).sort((left, right) => canonicalHash(left).localeCompare(
    canonicalHash(right)));
  const scoredEnvironmentBody = {...scoredEnvironment};
  delete scoredEnvironmentBody.evidence_bundle_cid;
  scoredEnvironment.evidence_bundle_cid = canonicalHash(scoredEnvironmentBody);
  const scoredArgs = [
    canonical(scoredEnvironment),
    scoredEnvironment.evidence_bundle_cid,
    ...args.slice(2),
  ];
  for (const {name, policy, score, failConsumer = false,
    cancelRanking = false} of [
    {name: 'maximum', policy: 'max', score: 0.75},
    {name: 'weighted', policy: {weighted_sum: {left: 0.5, right: 0.5}},
      score: 0.6875},
    {name: 'maximum-consumer-failure', policy: 'max', score: 0.75,
      failConsumer: true},
    {name: 'maximum-in-flight-cancel', policy: 'max', score: 0.75,
      cancelRanking: true},
  ]) {
    const scoredProgram = {
      version: 'actql/0.1', id: 'p',
      params: {minimum: {type: 'number', nullable: false}},
      stages: [carrierVectorPublicationProgram.stages[0], {
        id: 'fusion',
        inputs: {
          left: {carrier: 'relation', schema: scoreSchema},
          right: {carrier: 'relation', schema: scoreSchema},
        },
        steps: [{
          from: 'left',
          merge_rankings: {
            with: 'right', by: ['q'], candidate: 'id', score: 'score',
            score_policy: policy, score_contract: scoreContract, k: 2,
          },
          as: 'ranked',
        }, {
          from: 'ranked', filter: 'id = 2', as: 'out',
        }],
        results: {r: {from: 'out', fields: rankingFields}},
      }, ...['a', 'b'].map(id => ({
        id: `consumer_${id}`,
        inputs: {x: {result: {stage: 'fusion', result: 'r'}}},
        steps: [{select: rankingFields, as: 'out'}],
        results: {r: {from: 'out', fields: rankingFields}},
      }))],
      results: {
        published: {from: {stage: 'fusion', result: 'r'}},
        consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
        consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
      },
    };
    if (failConsumer) {
      scoredProgram.stages.find(stage => stage.id === 'consumer_a').steps = [{
        filter: '1 / (id - id) > 0', as: 'failed',
      }, {from: 'failed', select: rankingFields, as: 'out'}];
    }
    const scoredFixture = fixture.strategyFixtureVecaScoredCreate(
      ...scoredArgs, JSON.stringify(scoredProgram), orderedContract, 2,
    );
    const scoredCapture = await runNativeHostQuery(
      grant, fixture.strategyFixtureAcquisition(scoredFixture), suppliedLimits,
    );
    const scoredDirectory = await mkdtemp(join(
      root, `_build/duckdb-fixtures/ranking-${name}-publication-entry-`,
    ));
    const scoredAbort = new AbortController();
    let rankingDispatched = false, rankingAdvanced = false;
    let cancellationScheduled = false, rankingCancelRequested = false;
    let rankingCompletedBeforeCancel = false, rankingStopped = false;
    const scoredRetained = await createCarrierRetainedStore(`ranking-${name}`,
      {
        failCleanupLease: failConsumer ? 1 : undefined,
        beforeClose() {
          if (cancelRanking && scoredAbort.signal.aborted) {
            assert.equal(rankingStopped, true,
              'supplied ranking output release must follow stop');
          }
        },
      });
    let scoredOwner;
    let scoredFailureExecution;
    let scoredStore;
    let computeEntrances = 0;
    const scoredRuntime = new Proxy(hostRuntime, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_Dispatch' ||
            !cancelRanking) return Reflect.get(target, property, receiver);
        return (setup, task) => {
          const producers = target.strategyHostManagedProducers(setup);
          const ranking = target.strategyHostManagedInputCount(setup) === 2 &&
            Array.isArray(producers) && producers.length === 2 &&
            producers.every(value => value === -1);
          const operations = checked(target[property](setup, task));
          if (!ranking) return {$tag: 1, _0: operations};
          rankingDispatched = true;
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, member, receiver) {
              if (member === 'execute') {
                assert.fail('supplied ranking used synchronous execution');
              }
              if (member === 'execution_stopped') return () => {
                const value = operation.execution_stopped();
                if (scoredAbort.signal.aborted && value) rankingStopped = true;
                return value;
              };
              if (member === 'request_cancel') return () => {
                rankingCancelRequested = true;
                return operation.request_cancel();
              };
              if (member !== 'advance') {
                return Reflect.get(operation, member, receiver);
              }
              return quantum => {
                const value = operation.advance(Math.min(quantum, 1));
                const poll = checked(value);
                if (poll.complete && !scoredAbort.signal.aborted) {
                  rankingCompletedBeforeCancel = true;
                }
                if (!poll.complete && poll.progress > 0n) {
                  rankingAdvanced = true;
                  if (!cancellationScheduled) {
                    cancellationScheduled = true;
                    setTimeout(() => scoredAbort.abort(), 0);
                  }
                }
                return value;
              };
            },
          })};
        };
      },
    });
    const scoredHost = createNodeHostEntry(() => scoredRuntime,
      async (...installationArgs) => {
        const contributions = await installStrategyContributions(
          ...installationArgs);
        return contributions.map(contribution => ({
          ...contribution,
          run(...args) {
            computeEntrances++;
            return contribution.run(...args);
          },
          ...(typeof contribution.runPrepared === 'function' ? {
            runPrepared(...args) {
              computeEntrances++;
              return contribution.runPrepared(...args);
            },
          } : {}),
        }));
      });
    try {
      assert.equal(fixture.strategyFixtureOpen(
        scoredFixture, scoredCapture.source()), true);
      const setup = fixture.strategyFixtureVecaRetainedSubset(scoredFixture);
      const runtime = runtimeCore(scoredRuntime);
      assert.equal(runtime.resultInventory(setup).length, 3);
      scoredStore = await openLocalPublicationStore({
        directory: scoredDirectory,
        storeAuthorityCid: hash(`ranking-${name}-publication-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime, runtime.programDefinitionCid(setup), 3,
        `ranking-${name}-publication-attempt`,
      );
      try {
        scoredOwner = await scoredHost.runPublishedCapturedStrategy(
          setup, {store: scoredStore, plan},
          {local: scoredRetained.configuration}, scoredAbort.signal,
        );
      } catch (error) {
        scoredFailureExecution = error.execution;
        if (!failConsumer && !cancelRanking) throw error;
        assert.equal(error.code, 'CapturedRunPublicationFailed');
      }
      const publicationKey = {
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      };
      if (cancelRanking) {
        assert.equal(scoredOwner, undefined);
        assert.equal(rankingDispatched, true);
        assert.equal(rankingAdvanced, true);
        assert.equal(cancellationScheduled, true);
        assert.equal(rankingCancelRequested, true);
        assert.equal(rankingCompletedBeforeCancel, false);
        assert.equal(rankingStopped, true);
        assert.equal(scoredFailureExecution.status, 'host-tasks-failed');
        assert.equal(scoredFailureExecution.failure?.name, 'AbortError');
        await assert.rejects(scoredStore.lookupCommittedIndex(
          publicationKey, () => true), /PublicationLookupDenied/);
      } else if (failConsumer) {
        assert(scoredRetained.leases.length > 0);
        assert.equal(scoredOwner, undefined);
        assert(computeEntrances > 0);
        assert.equal(scoredFailureExecution.status, 'host-tasks-failed');
        assert(scoredFailureExecution.completed.some(value =>
          value.outputRepresentation === 'retained-file'));
        assert.equal(scoredFailureExecution.failure?.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureRetainedCapturedFilterArithmetic(
          scoredFailureExecution.failure.cause), true);
        await assert.rejects(scoredStore.lookupCommittedIndex(
          publicationKey, () => true), /PublicationLookupDenied/);
      } else {
        assert(scoredRetained.leases.length > 0);
        assert.equal(scoredOwner.status, 'published');
        assert.equal(scoredOwner.publication.publication.state, 'succeeded');
        assert(scoredOwner.execution.completed.some(value =>
          value.outputRepresentation === 'retained-file'));
        const committedIndex = await scoredStore.lookupCommittedIndex(
          publicationKey, () => true);
        const committedManifest = JSON.parse((await scoredStore
          .readPublicationContract(committedIndex.result_manifest_cid,
            'result_manifest')).wire);
        assert.deepEqual(Object.keys(committedManifest.results).sort(),
          ['consumed_a', 'consumed_b', 'published']);
        for (const resultName of ['published', 'consumed_a', 'consumed_b']) {
          const received = [];
          await scoredStore.consumeCommittedResult(
            publicationKey,
            committedManifest.results[resultName].result_definition_cid,
            () => true, chunk => received.push(Buffer.from(chunk)),
          );
          assert.deepEqual(JSON.parse(Buffer.concat(received).toString('utf8')),
            [{q: 1, id: 2, score, rank: 2}]);
        }
      }
    } finally {
      if (scoredOwner !== undefined) {
        await scoredOwner.close();
        assert.equal(scoredOwner.cleanupPending(), false);
        assert.equal(await scoredOwner.cleanup(), true);
        assert.equal(scoredOwner.execution.usage().heldBytes, 0n);
        assert.equal(scoredOwner.execution.usage().reservedExecutionBytes, 0n);
      } else if (scoredFailureExecution !== undefined) {
        const entrancesAtFailure = computeEntrances;
        if (failConsumer) {
          await assert.rejects(async () => scoredFailureExecution.close(),
            /InjectedCarrierRetainedCleanupPending/);
          assert.equal(computeEntrances, entrancesAtFailure);
          assert.equal(scoredRetained.cleanupFailures(), 1);
          assert.equal(scoredFailureExecution.cleanupPending(), true);
          scoredRetained.permitCleanup();
        } else await scoredFailureExecution.close();
        assert.equal(await scoredFailureExecution.cleanup(), true);
        assert.equal(scoredFailureExecution.cleanupPending(), false);
        assert.equal(computeEntrances, entrancesAtFailure);
        assert.equal(scoredFailureExecution.usage().heldBytes, 0n);
        assert.equal(scoredFailureExecution.usage().reservedExecutionBytes,
          0n);
      }
      scoredCapture.close();
      await scoredStore?.close();
      await rm(scoredDirectory, {recursive: true, force: true});
      await scoredRetained.close();
    }
  }
  const nearestFields = ['query_id', 'candidate_id', 'score', 'rank'];
  const nearestSchema = {
    id: {type: 'number', nullable: false},
    embedding: {type: 'vector', dimensions: 2, nullable: false},
  };
  const nearestPublicationProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [carrierVectorPublicationProgram.stages[0], ...[
      ['candidates', [
        {id: 2, embedding: [1, 0]},
        {id: 1, embedding: [1, 0]},
        {id: 3, embedding: [0, 1]},
      ]],
      ['queries', [
        {id: 20, embedding: [1, 0]},
        {id: 10, embedding: [0, 1]},
      ]],
    ].map(([id, rows]) => ({
      id,
      inputs: {},
      steps: [{values: {schema: nearestSchema, rows}, as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'embedding']}},
    })), {
      id: 'nearest',
      // Authored Stage input order differs from the nearest operation ports.
      inputs: {
        queries: {result: {stage: 'queries', result: 'r'}},
        candidates: {result: {stage: 'candidates', result: 'r'}},
      },
      steps: [{
        from: 'candidates',
        nearest: {
          queries: 'queries',
          candidate_id: 'id',
          candidate_vector: 'embedding',
          query_id: 'id',
          query_vector: 'embedding',
          metric: 'dot',
          k: 2,
        },
        as: 'ranked',
      }, {
        from: 'ranked', filter: 'query_id = 20', as: 'out',
      }],
      results: {r: {from: 'out', fields: nearestFields}},
    }, ...['a', 'b'].map(id => ({
      id: `consumer_${id}`,
      inputs: {x: {result: {stage: 'nearest', result: 'r'}}},
      steps: [{select: nearestFields, as: 'out'}],
      results: {r: {from: 'out', fields: nearestFields}},
    }))],
    results: {
      published: {from: {stage: 'nearest', result: 'r'}},
      consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
      consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
    },
  };
  const nearestWithVectors = (candidateVectors, queryVectors) => ({
    ...nearestPublicationProgram,
    stages: nearestPublicationProgram.stages.map(stage =>
      stage.id !== 'nearest' ? stage : {
        ...stage,
        steps: [
          ...(candidateVectors ? [{
            from: 'candidates',
            to_vectors: {id: 'id', vector: 'embedding'},
            as: 'candidate_vectors',
          }] : []),
          ...(queryVectors ? [{
            from: 'queries',
            to_vectors: {id: 'id', vector: 'embedding'},
            as: 'query_vectors',
          }] : []), {
            from: candidateVectors ? 'candidate_vectors' : 'candidates',
            nearest: {
              queries: queryVectors ? 'query_vectors' : 'queries',
              ...(candidateVectors ? {} : {
                candidate_id: 'id', candidate_vector: 'embedding',
              }),
              ...(queryVectors ? {} : {
                query_id: 'id', query_vector: 'embedding',
              }),
              metric: 'dot', k: 2,
            },
            as: 'ranked',
          }, {
            from: 'ranked', filter: 'query_id = 20', as: 'out',
          },
        ],
      }),
  });
  for (const [name, program] of [
    ['nearest-filter', nearestPublicationProgram],
    ['nearest-candidate-vectors-filter', nearestWithVectors(true, false)],
    ['nearest-query-vectors-filter', nearestWithVectors(false, true)],
    ['nearest-both-vectors-filter', nearestWithVectors(true, true)],
  ]) {
    const nearestPublicationFixture = fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract,
    );
    const nearestCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(nearestPublicationFixture),
      suppliedLimits,
    );
    const nearestPublicationDirectory = await mkdtemp(join(
      root, `_build/duckdb-fixtures/${name}-publication-entry-`,
    ));
    const nearestRetained = await createCarrierRetainedStore(name);
    let nearestPublicationOwner;
    let nearestPublicationStore;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        nearestPublicationFixture, nearestCapture.source()), true);
      const setup = fixture.strategyFixtureVecaRetainedSubset(
        nearestPublicationFixture,
      );
      const runtime = runtimeCore(hostRuntime);
      const resultCount = runtime.resultInventory(setup).length;
      assert.equal(resultCount, 3);
      nearestPublicationStore = await openLocalPublicationStore({
        directory: nearestPublicationDirectory,
        storeAuthorityCid: hash(`${name}-publication-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime,
        runtime.programDefinitionCid(setup),
        resultCount,
        `${name}-publication-attempt`,
      );
      nearestPublicationOwner = await runPublishedCapturedStrategy(
        setup,
        {store: nearestPublicationStore, plan},
        {local: nearestRetained.configuration},
        new AbortController().signal,
      );
      assert.equal(nearestPublicationOwner.status, 'published');
      assert.equal(nearestPublicationOwner.publication.publication.state,
        'succeeded');
      assert(nearestRetained.leases.length > 0);
      assert(nearestPublicationOwner.execution.completed.some(value =>
        value.outputRepresentation === 'retained-file'));
      const expectedRows = [
        {candidate_id: 1, query_id: 20, rank: 1, score: 1},
        {candidate_id: 2, query_id: 20, rank: 2, score: 1},
      ];
      const publicationKey = {
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      };
      const committedIndex = await nearestPublicationStore
        .lookupCommittedIndex(publicationKey, () => true);
      const committedManifest = JSON.parse((await nearestPublicationStore
        .readPublicationContract(committedIndex.result_manifest_cid,
          'result_manifest')).wire);
      assert.deepEqual(Object.keys(committedManifest.results).sort(),
        ['consumed_a', 'consumed_b', 'published']);
      for (const resultName of ['published', 'consumed_a', 'consumed_b']) {
        const resultDefinitionCid = committedManifest.results[resultName]
          .result_definition_cid;
        const received = [];
        await nearestPublicationStore.consumeCommittedResult(
          publicationKey, resultDefinitionCid, () => true,
        chunk => received.push(Buffer.from(chunk)));
        assert.deepEqual(
          JSON.parse(Buffer.concat(received).toString('utf8')),
          expectedRows,
        );
      }
    } finally {
      if (nearestPublicationOwner !== undefined) {
        await nearestPublicationOwner.close();
        assert.equal(nearestPublicationOwner.cleanupPending(), false);
        assert.equal(await nearestPublicationOwner.cleanup(), true);
        assert.equal(nearestPublicationOwner.execution.usage().heldBytes, 0n);
        assert.equal(nearestPublicationOwner.execution.usage()
          .reservedExecutionBytes, 0n);
      }
      nearestCapture.close();
      await nearestPublicationStore?.close();
      await rm(nearestPublicationDirectory, {recursive: true, force: true});
      await nearestRetained.close();
    }
  }
  const nearestFailureProgram = nearestWithVectors(true, true);
  nearestFailureProgram.stages.find(stage =>
    stage.id === 'consumer_a').steps = [{
    filter: '1 / (candidate_id - candidate_id) > 0', as: 'filtered',
  }, {
    from: 'filtered', select: nearestFields, as: 'out',
  }];
  const nearestFailureFixture = fixture.strategyFixtureVecaCreate(
    ...args, JSON.stringify(nearestFailureProgram), orderedContract,
  );
  const nearestFailureCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(nearestFailureFixture),
    suppliedLimits,
  );
  const nearestFailureDirectory = await mkdtemp(join(
    root, '_build/duckdb-fixtures/nearest-carrier-failure-entry-',
  ));
  const nearestFailureRetained = await createCarrierRetainedStore(
    'nearest-carrier-failure', {failCleanupLease: 1},
  );
  let computeEntrances = 0;
  const countedHost = createNodeHostEntry(() => hostRuntime,
    async (...installationArgs) => {
      const contributions = await installStrategyContributions(
        ...installationArgs);
      return contributions.map(contribution => ({
        ...contribution,
        run(...args) {
          computeEntrances++;
          return contribution.run(...args);
        },
        ...(typeof contribution.runPrepared === 'function' ? {
          runPrepared(...args) {
            computeEntrances++;
            return contribution.runPrepared(...args);
          },
        } : {}),
      }));
    });
  let nearestFailureExecution, nearestFailurePublicationStore;
  let computeEntrancesAtFailure;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      nearestFailureFixture, nearestFailureCapture.source()), true);
    const setup = fixture.strategyFixtureVecaRetainedSubset(
      nearestFailureFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    nearestFailurePublicationStore = await openLocalPublicationStore({
      directory: nearestFailureDirectory,
      storeAuthorityCid: hash('nearest-carrier-failure-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      runtime.resultInventory(setup).length,
      'nearest-carrier-failure-attempt',
    );
    await assert.rejects(countedHost.runPublishedCapturedStrategy(
      setup,
      {store: nearestFailurePublicationStore, plan},
      {local: nearestFailureRetained.configuration},
      new AbortController().signal,
    ), error => {
      nearestFailureExecution = error.execution;
      return error.code === 'CapturedRunPublicationFailed';
    });
    assert(computeEntrances > 0);
    computeEntrancesAtFailure = computeEntrances;
    assert.equal(nearestFailureExecution.status, 'host-tasks-failed');
    assert(nearestFailureRetained.leases.length > 0);
    assert(nearestFailureExecution.completed.some(value =>
      value.outputRepresentation === 'managed-local-carrier'));
    assert(nearestFailureExecution.completed.some(value =>
      value.outputRepresentation === 'retained-file'));
    assert.equal(nearestFailureExecution.failure?.code, 'MoonBitHostFailure');
    assert.equal(fixture.strategyFixtureVecaConsumerFilterArithmetic(
      nearestFailureExecution.failure.cause,
    ), true);
    await assert.rejects(nearestFailurePublicationStore.lookupCommittedIndex({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, () => true), /PublicationLookupDenied/);
  } finally {
    if (nearestFailureExecution !== undefined) {
      await assert.rejects(async () => nearestFailureExecution.close(),
        /InjectedCarrierRetainedCleanupPending/);
      assert.equal(computeEntrances, computeEntrancesAtFailure);
      assert.equal(nearestFailureExecution.cleanupPending(), true);
      assert.equal(nearestFailureRetained.cleanupFailures(), 1);
      nearestFailureRetained.permitCleanup();
      assert.equal(await nearestFailureExecution.cleanup(), true);
      assert.equal(computeEntrances, computeEntrancesAtFailure);
      assert.equal(nearestFailureExecution.cleanupPending(), false);
      assert.equal(nearestFailureExecution.usage().heldBytes, 0n);
      assert.equal(nearestFailureExecution.usage().reservedExecutionBytes, 0n);
    }
    nearestFailureCapture.close();
    await nearestFailurePublicationStore?.close();
    await rm(nearestFailureDirectory, {recursive: true, force: true});
    await nearestFailureRetained.close();
  }
  // A zero-input row source and its Carrier Bridge share an authored Stage.
  // The physical split must retain the Events/Vectors generation for a later
  // Bridge task, then publish and independently consume its Relation view.
  for (const carrierCase of [{
    name: 'events',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    fields: ['event_id', 'occurred_at', 'payload'],
    secondFields: ['payload', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 5, payload: 'first'},
      {event_id: 2, occurred_at: 15, payload: 'second'},
    ],
  }, {
    name: 'events-watermark',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    transform: {
      from: 'source',
      watermark_events: {watermark_ms: 10, policy: 'mark'},
      as: 'marked',
    },
    fields: [
      'event_id', 'occurred_at', 'payload',
      'watermark_ms', 'late', 'watermark_decision',
    ],
    secondFields: ['watermark_decision', 'late', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 5, payload: 'first'},
      {event_id: 2, occurred_at: 15, payload: 'second'},
    ],
    expectedRows: [
      {event_id: 1, occurred_at: 5, payload: 'first',
        watermark_ms: 10, late: true, watermark_decision: 'mark'},
      {event_id: 2, occurred_at: 15, payload: 'second',
        watermark_ms: 10, late: false, watermark_decision: 'keep'},
    ],
  }, {
    name: 'events-dedupe',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    transform: {
      from: 'source',
      dedupe_events: {
        by: ['payload'],
        order_by: [{field: 'occurred_at', dir: 'asc', nulls: 'last'}],
      },
      as: 'deduped',
    },
    fields: ['event_id', 'occurred_at', 'payload'],
    secondFields: ['payload', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 20, payload: 'a'},
      {event_id: 2, occurred_at: 10, payload: 'a'},
      {event_id: 3, occurred_at: 30, payload: 'b'},
    ],
    expectedRows: [
      {event_id: 2, occurred_at: 10, payload: 'a'},
      {event_id: 3, occurred_at: 30, payload: 'b'},
    ],
  }, {
    name: 'events-session',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    transform: {
      from: 'source', session: {by: ['payload'], gap: 10}, as: 'sessioned',
    },
    fields: [
      'event_id', 'occurred_at', 'payload',
      'session_start_ms', 'session_end_ms',
    ],
    secondFields: ['payload', 'session_start_ms', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 5, payload: 'shared'},
      {event_id: 2, occurred_at: 9, payload: 'shared'},
    ],
    expectedRows: [
      {event_id: 1, occurred_at: 5, payload: 'shared',
        session_start_ms: 5, session_end_ms: 19},
      {event_id: 2, occurred_at: 9, payload: 'shared',
        session_start_ms: 5, session_end_ms: 19},
    ],
  }, {
    name: 'events-fixed-window',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    transform: {
      from: 'source', window_events: {kind: 'fixed', size: 10},
      as: 'windowed',
    },
    fields: [
      'event_id', 'occurred_at', 'payload',
      'window_start_ms', 'window_end_ms',
    ],
    secondFields: ['payload', 'window_start_ms', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 9, payload: 'first'},
      {event_id: 2, occurred_at: 10, payload: 'second'},
    ],
    expectedRows: [
      {event_id: 1, occurred_at: 9, payload: 'first',
        window_start_ms: 0, window_end_ms: 10},
      {event_id: 2, occurred_at: 10, payload: 'second',
        window_start_ms: 10, window_end_ms: 20},
    ],
  }, {
    name: 'events-sliding-window',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    transform: {
      from: 'source', window_events: {kind: 'sliding', size: 10, step: 5},
      as: 'windowed',
    },
    fields: [
      'event_id', 'occurred_at', 'payload',
      'window_start_ms', 'window_end_ms',
    ],
    secondFields: ['payload', 'window_start_ms', 'event_id'],
    rows: [
      {event_id: 1, occurred_at: 9, payload: 'first'},
      {event_id: 2, occurred_at: 10, payload: 'second'},
    ],
    expectedRows: [
      {event_id: 1, occurred_at: 9, payload: 'first',
        window_start_ms: 0, window_end_ms: 10},
      {event_id: 1, occurred_at: 9, payload: 'first',
        window_start_ms: 5, window_end_ms: 15},
      {event_id: 2, occurred_at: 10, payload: 'second',
        window_start_ms: 5, window_end_ms: 15},
      {event_id: 2, occurred_at: 10, payload: 'second',
        window_start_ms: 10, window_end_ms: 20},
    ],
  }, {
    name: 'events-asof-filter',
    source: eventPublicationProgram,
    create: program => fixture.strategyFixtureTeaCreate(
      ...args, JSON.stringify(program)),
    configure: value => fixture.strategyFixtureTeaRetainedSubset(value),
    additionalSteps: [{
      values: {
        schema: {
          event_id: {type: 'number', nullable: false},
          occurred_at: {type: 'number', nullable: false},
          payload: {type: 'string', nullable: false},
        },
        rows: [
          {event_id: 10, occurred_at: 8, payload: 'eight'},
          {event_id: 11, occurred_at: 10, payload: 'ten'},
        ],
      },
      as: 'right',
    }],
    transform: {
      from: 'source', asof_join: {
        with: 'right', kind: 'left', by: [],
        left_time: 'occurred_at', right_time: 'occurred_at',
        direction: 'backward', tolerance: 10,
        right_tie_break: ['event_id'],
        select: {id: 'left.event_id', value: 'right.payload'},
      }, as: 'matched',
    },
    relationOutput: true,
    fields: ['id', 'value'],
    secondFields: ['value', 'id'],
    rows: [
      {event_id: 1, occurred_at: 11, payload: 'first'},
      {event_id: 2, occurred_at: 9, payload: 'second'},
    ],
    // As-of order is left time, then identity, not source row order.
    expectedRows: [{id: 2, value: 'eight'}, {id: 1, value: 'ten'}],
  }, {
    name: 'vectors',
    source: carrierVectorPublicationProgram,
    create: program => fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract),
    configure: value => fixture.strategyFixtureVecaRetainedSubset(value),
    fields: ['id', 'embedding'],
    secondFields: ['embedding', 'id'],
    rows: [
      {id: 1, embedding: [3, 4]},
      {id: 2, embedding: [0, 2]},
    ],
  }, {
    name: 'vectors-normalize',
    source: carrierVectorPublicationProgram,
    create: program => fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract),
    configure: value => fixture.strategyFixtureVecaRetainedSubset(value),
    transform: {
      from: 'source', normalize_vectors: true, as: 'normalized',
    },
    fields: ['id', 'embedding'],
    secondFields: ['embedding', 'id'],
    rows: [
      {id: 1, embedding: [3, 4]},
      {id: 2, embedding: [0, 2]},
    ],
    expectedRows: [
      {id: 1, embedding: [0.6000000238418579, 0.800000011920929]},
      {id: 2, embedding: [0, 1]},
    ],
  }, {
    name: 'vectors-score',
    source: carrierVectorPublicationProgram,
    create: program => fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract),
    configure: value => fixture.strategyFixtureVecaRetainedSubset(value),
    transform: {
      from: 'source', score_vectors: {query: [1, 0], metric: 'dot'},
      as: 'scored',
    },
    fields: ['id', 'embedding', 'score'],
    secondFields: ['score', 'embedding', 'id'],
    rows: [
      {id: 1, embedding: [3, 4]},
      {id: 2, embedding: [0, 2]},
    ],
    expectedRows: [
      {id: 1, embedding: [3, 4], score: 3},
      {id: 2, embedding: [0, 2], score: 0},
    ],
  }, {
    name: 'relation-vectors-pool',
    source: carrierVectorPublicationProgram,
    create: program => fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract),
    configure: value => fixture.strategyFixtureVecaRetainedSubset(value),
    relationSource: true,
    transform: {
      from: 'source',
      pool_vectors: {vector: 'embedding', by: ['group'], method: 'sum'},
      as: 'pooled',
    },
    additionalTransforms: [{
      from: 'pooled', normalize_vectors: true, as: 'same_carrier',
    }],
    fields: ['group', 'embedding', 'member_count'],
    secondFields: ['member_count', 'embedding', 'group'],
    rows: [
      {id: 2, group: 1, embedding: [0, 2]},
      {id: 1, group: 1, embedding: [3, 4]},
    ],
    expectedRows: [{group: 1, embedding: [3, 6], member_count: 2}],
  }, {
    name: 'vectors-pool',
    source: carrierVectorPublicationProgram,
    create: program => fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract),
    configure: value => fixture.strategyFixtureVecaRetainedSubset(value),
    transform: {
      from: 'source',
      pool_vectors: {by: ['group'], method: 'sum'},
      as: 'pooled',
    },
    fields: ['group', 'embedding', 'member_count'],
    secondFields: ['member_count', 'embedding', 'group'],
    rows: [
      {id: 1, group: 1, embedding: [3, 4]},
      {id: 2, group: 1, embedding: [0, 2]},
    ],
    expectedRows: [
      {group: 1, embedding: [3, 6], member_count: 2},
    ],
  }]) {
    const directProgram = structuredClone(carrierCase.source);
    const rowStep = directProgram.stages[1].steps[0];
    rowStep.as = 'rows';
    if (carrierCase.name === 'vectors-pool' || carrierCase.relationSource) {
      rowStep.values.schema.group = {type: 'number', nullable: false};
    }
    rowStep.values.rows = carrierCase.rows;
    const carrierStage = directProgram.stages[2];
    carrierStage.inputs = {};
    carrierStage.steps = [
      rowStep,
      carrierCase.relationSource
        ? {from: 'rows', assert_rows: {unique_by: ['id']}, as: 'source'}
        : carrierStage.steps[0],
      ...(carrierCase.additionalSteps ?? []),
      ...(carrierCase.transform ? [carrierCase.transform] : []),
      ...(carrierCase.additionalTransforms ?? []),
      carrierCase.relationOutput
        ? {filter: 'true', as: 'out'} : carrierStage.steps.at(-1),
    ];
    carrierStage.steps.at(-1).from =
      carrierCase.transform?.as ?? 'source';
    carrierStage.results.r.fields = carrierCase.fields;
    directProgram.stages.splice(1, 1);
    for (const consumer of directProgram.stages.slice(2)) {
      const fields = consumer.id === 'consumer_a'
        ? carrierCase.fields : carrierCase.secondFields;
      consumer.steps = [{select: fields, as: 'out'}];
      consumer.results.r.fields = fields;
    }
    const directFixture = carrierCase.create(directProgram);
    const directCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(directFixture),
      suppliedLimits,
    );
    const directDirectory = await mkdtemp(join(
      root,
      `_build/duckdb-fixtures/${carrierCase.name}-handoff-entry-`,
    ));
    const directRetained = await createCarrierRetainedStore(
      `${carrierCase.name}-handoff`,
    );
    let directOwner;
    let directFailedExecution;
    let directStore;
    try {
      assert.equal(
        fixture.strategyFixtureOpen(directFixture, directCapture.source()),
        true,
      );
      const setup = carrierCase.configure(directFixture);
      const runtime = runtimeCore(hostRuntime);
      const resultCount = runtime.resultInventory(setup).length;
      assert.equal(resultCount, 3);
      directStore = await openLocalPublicationStore({
        directory: directDirectory,
        storeAuthorityCid: hash(`${carrierCase.name}-handoff-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime,
        runtime.programDefinitionCid(setup),
        resultCount,
        `${carrierCase.name}-handoff-attempt`,
      );
      try {
        directOwner = await runPublishedCapturedStrategy(
          setup,
          {store: directStore, plan},
          {local: directRetained.configuration},
          new AbortController().signal,
        );
      } catch (error) {
        directFailedExecution = error.execution;
        throw new Error(`${carrierCase.name}: ${String(error.cause)}; ` +
          `completed=${inspect(directFailedExecution?.completed?.map(item => item.task))}; ` +
          `failure=${inspect(directFailedExecution?.failure, {depth: 7})}`,
        {cause: error});
      }
      assert.equal(directOwner.status, 'published');
      assert.equal(directOwner.publication.publication.state, 'succeeded');
      assert(directRetained.leases.length > 0);
      assert(directOwner.execution.completed.some(value =>
        value.outputRepresentation === 'retained-file'));
      assert.equal(directOwner.execution.completed.filter(value =>
        value.outputRepresentation === 'managed-local-carrier').length,
      carrierCase.transform && !carrierCase.relationOutput ? 2 : 1);
      const rows = carrierCase.expectedRows ?? carrierCase.rows;
      const expected = {
        published: rows,
        consumed_a: rows,
        consumed_b: rows.map(row =>
          Object.fromEntries(carrierCase.secondFields.map(
            field => [field, row[field]]))),
      };
      const occurrences = directOwner.execution.publicationInventory.occurrences;
      assert.deepEqual(occurrences.map(value => value.name).sort(),
        ['consumed_a', 'consumed_b', 'published']);
      for (const name of ['published', 'consumed_a', 'consumed_b']) {
        const occurrence = occurrences.find(value => value.name === name);
        const received = [];
        await directStore.consumeCommittedResult({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, occurrence.definitionContract.identity, () => true,
        chunk => received.push(Buffer.from(chunk)));
        assert.deepEqual(
          JSON.parse(Buffer.concat(received).toString('utf8')),
          expected[occurrence.name],
        );
      }
    } finally {
      if (directOwner !== undefined) {
        await directOwner.close();
        assert.equal(directOwner.cleanupPending(), false);
        assert.equal(await directOwner.cleanup(), true);
        assert.equal(directOwner.execution.usage().heldBytes, 0n);
        assert.equal(
          directOwner.execution.usage().reservedExecutionBytes, 0n);
      } else if (directFailedExecution !== undefined) {
        await directFailedExecution.close();
        assert.equal(await directFailedExecution.cleanup(), true);
        assert.equal(directFailedExecution.usage().heldBytes, 0n);
        assert.equal(directFailedExecution.usage().reservedExecutionBytes, 0n);
      }
      directCapture.close();
      await directStore?.close();
      await rm(directDirectory, {recursive: true, force: true});
      await directRetained.close();
    }
  }
  // Relation pooling retains its source generation until confirmed stop;
  // cleanup retry must not invoke the selected Compute again.
  for (const {name} of [{name: 'relation-pool-in-flight-cancel'},
    {name: 'relation-pool-consumer-failure-cleanup'}]) {
    const cancelling = name === 'relation-pool-in-flight-cancel';
    const fields = ['group', 'candidate_id', 'embedding', 'member_count'];
    const program = structuredClone(carrierVectorPublicationProgram);
    program.stages[2].inputs = {};
    program.stages[2].steps = [{
      values: {schema: {
        id: {type: 'number', nullable: false},
        group: {type: 'number', nullable: false},
        embedding: {type: 'vector', dimensions: 2, nullable: false},
      }, rows: [{id: 2, group: 1, embedding: [0, 2]},
        {id: 1, group: 1, embedding: [3, 4]}]}, as: 'rows',
    }, {
      from: 'rows', assert_rows: {unique_by: ['id']}, as: 'keyed',
    }, {
      from: 'keyed', pool_vectors: {vector: 'embedding', by: ['group'],
        method: 'sum', output_id: 'candidate_id'}, as: 'pooled',
    }, {from: 'pooled', vectors: true, as: 'out'}];
    program.stages[2].results.r.fields = fields;
    program.stages.splice(1, 1);
    for (const consumer of program.stages.slice(2)) {
      consumer.steps = !cancelling && consumer.id === 'consumer_a' ? [{
        filter: '1 / (candidate_id - candidate_id) > 0', as: 'filtered',
      }, {from: 'filtered', select: fields, as: 'out'}]
        : [{select: fields, as: 'out'}];
      consumer.results.r.fields = fields;
    }
    const poolFixture = fixture.strategyFixtureVecaCreate(
      ...args, JSON.stringify(program), orderedContract);
    const capture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(poolFixture), suppliedLimits);
    const directory = await mkdtemp(join(root,
      `_build/duckdb-fixtures/${name}-`));
    const cancellation = new AbortController();
    let entrances = 0, scheduled = false, stopped = false;
    let advanced = false;
    const retained = await createCarrierRetainedStore(name, {
      failCleanupLease: cancelling ? undefined : 1,
      beforeClose() {
        if (cancellation.signal.aborted) {
          assert.equal(stopped, true, 'pool input release must follow stop');
        }
      },
    });
    const observed = new Proxy(hostRuntime, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_Dispatch' &&
            property !== 'strategyModule_local_ManagedStart') {
          return Reflect.get(target, property, receiver);
        }
        return (...args) => {
          const entrance = ++entrances;
          const operations = checked(target[property](...args));
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, member, receiver) {
              if (member === 'execute') assert.fail('pool used synchronous execution');
              if (member === 'execution_stopped') return () => {
                const value = operation.execution_stopped();
                if (entrance === 3 && cancellation.signal.aborted && value) stopped = true;
                return value;
              };
              if (member !== 'advance') return Reflect.get(operation, member, receiver);
              return quantum => {
                const value = operation.advance(Math.min(quantum, 1));
                const poll = checked(value);
                if (entrance === 3 && !poll.complete && poll.progress > 0n) {
                  advanced = true;
                  if (cancelling && !scheduled) {
                    scheduled = true;
                    setTimeout(() => cancellation.abort(), 0);
                  }
                }
                return value;
              };
            },
          })};
        };
      },
    });
    const host = createNodeHostEntry(() => observed, installStrategyContributions);
    let store, execution, closeAttempted = false;
    try {
      assert.equal(fixture.strategyFixtureOpen(poolFixture, capture.source()), true);
      const setup = fixture.strategyFixtureVecaRetainedSubset(poolFixture);
      const runtime = runtimeCore(observed);
      store = await openLocalPublicationStore({
        directory, storeAuthorityCid: hash(`${name}-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(runtime,
        runtime.programDefinitionCid(setup), runtime.resultInventory(setup).length, name);
      await assert.rejects(host.runPublishedCapturedStrategy(setup,
        {store, plan}, {local: retained.configuration}, cancellation.signal), error => {
        execution = error.execution;
        return error.code === 'CapturedRunPublicationFailed';
      });
      assert.equal(execution.status, 'host-tasks-failed');
      assert.equal(advanced, true);
      assert.equal(entrances, cancelling ? 3 : 5);
      assert.deepEqual(execution.completed.map(value => value.task),
        cancelling ? [1, 2] : [1, 2, 3, 4]);
      if (cancelling) {
        assert.equal(stopped, true);
        assert.equal(execution.failure?.name, 'AbortError');
      } else {
        assert.equal(execution.failure?.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureVecaConsumerFilterArithmetic(
          execution.failure.cause), true);
      }
      await assert.rejects(store.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      const atFailure = entrances;
      closeAttempted = true;
      if (!cancelling) {
        await assert.rejects(async () => execution.close(),
          /InjectedCarrierRetainedCleanupPending/);
        assert.equal(execution.cleanupPending(), true);
        assert(execution.usage().heldBytes > 0n ||
          execution.usage().reservedExecutionBytes > 0n);
        assert.equal(entrances, atFailure);
        retained.permitCleanup();
      } else await execution.close();
      assert.equal(await execution.cleanup(), true);
      assert.equal(entrances, atFailure);
      assert.equal(execution.cleanupPending(), false);
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
    } finally {
      retained.permitCleanup();
      if (execution !== undefined && !closeAttempted) await execution.close();
      await execution?.cleanup();
      capture.close();
      await store?.close();
      await retained.close();
      await rm(directory, {recursive: true, force: true});
    }
  }
  // Sequence matching is a Relation-producing Events consumer. Its selected
  // step must remain executable when an authored filter follows in the same
  // Stage; both later consumers read the retained filtered generation.
  const retainedSequenceCase = {name: 'events-sequence-filter'};
  const retainedSequenceProgram = structuredClone(eventPublicationProgram);
  retainedSequenceProgram.stages[2].id = 'matched';
  retainedSequenceProgram.stages[3].inputs.x.result.stage = 'matched';
  retainedSequenceProgram.stages[4].inputs.x.result.stage = 'matched';
  retainedSequenceProgram.results.published.from.stage = 'matched';
  // The capacity fixture proves 40 source rows; only the first pair lies
  // within the authored interval, leaving a hand-written one-match oracle.
  retainedSequenceProgram.stages[1].steps[0].values.rows.push(
    ...Array.from({length: 38}, (_, index) => ({
      event_id: index + 3,
      occurred_at: 1000 + index * 100,
      payload: `far-${index}`,
    })),
  );
  retainedSequenceProgram.stages[2].steps = [{
    from: 'rows', to_events: {id: 'event_id', time: 'occurred_at'},
    as: 'source',
  }, {
    from: 'source',
    sequence: {
      by: [], id: 'event_id', time: 'occurred_at',
      pattern: [
        {as: 'start', where: {literal: true}},
        {as: 'end', where: {literal: true}},
      ],
      within: 10, overlap: 'allow', contiguity: 'subsequence',
    },
    as: 'matched',
  }, {from: 'matched', filter: 'true', as: 'out'}];
  const sequenceFields = [
    'match_start_ms', 'match_end_ms', 'start_id',
    'start_time_ms', 'end_id', 'end_time_ms',
  ];
  retainedSequenceProgram.stages[2].results.r.fields = sequenceFields;
  retainedSequenceProgram.stages[3].steps = [
    {select: sequenceFields, as: 'out'},
  ];
  retainedSequenceProgram.stages[3].results.r.fields = sequenceFields;
  retainedSequenceProgram.stages[4].steps = [
    {select: ['end_id', 'start_id'], as: 'out'},
  ];
  retainedSequenceProgram.stages[4].results.r.fields = [
    'end_id', 'start_id',
  ];
  const retainedSequenceFixture = fixture.strategyFixtureTeaSequenceCreate(
    ...args, JSON.stringify(retainedSequenceProgram));
  const retainedSequenceCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(retainedSequenceFixture),
    suppliedLimits,
  );
  const retainedSequenceRetained = await createCarrierRetainedStore(
    retainedSequenceCase.name);
  const retainedSequenceDirectory = await mkdtemp(join(
    root, '_build/duckdb-fixtures/events-sequence-filter-publication-'));
  let retainedSequenceOwner;
  let retainedSequenceStore;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      retainedSequenceFixture, retainedSequenceCapture.source()), true);
    const setup = fixture.strategyFixtureTeaRetainedSubset(
      retainedSequenceFixture);
    const runtime = runtimeCore(hostRuntime);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      runtime.resultInventory(setup).length,
      'events-sequence-filter-attempt',
    );
    retainedSequenceStore = await openLocalPublicationStore({
      directory: retainedSequenceDirectory,
      storeAuthorityCid: hash('events-sequence-filter-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    retainedSequenceOwner = await runPublishedCapturedStrategy(
      setup,
      {store: retainedSequenceStore, plan},
      {local: retainedSequenceRetained.configuration},
      new AbortController().signal,
    );
    assert.equal(retainedSequenceOwner.status, 'published');
    assert.equal(retainedSequenceOwner.execution.status,
      'host-tasks-completed');
    assert.equal(retainedSequenceOwner.execution.completed.filter(value =>
      value.outputRepresentation === 'managed-local-carrier').length, 1);
    assert(retainedSequenceRetained.leases.length > 0);
    const match = {
      match_start_ms: 5, match_end_ms: 15,
      start_id: 1, start_time_ms: 5, end_id: 2, end_time_ms: 15,
    };
    const expected = {
      published: [match],
      consumed_a: [match],
      consumed_b: [{end_id: 2, start_id: 1}],
    };
    for (const occurrence of retainedSequenceOwner.execution
      .publicationInventory.occurrences) {
      const received = [];
      await retainedSequenceStore.consumeCommittedResult({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, occurrence.definitionContract.identity, () => true,
      chunk => received.push(Buffer.from(chunk)));
      assert.deepEqual(
        JSON.parse(Buffer.concat(received).toString('utf8')),
        expected[occurrence.name],
      );
    }
  } finally {
    if (retainedSequenceOwner !== undefined) {
      await retainedSequenceOwner.close();
      assert.equal(await retainedSequenceOwner.cleanup(), true);
      assert.equal(retainedSequenceOwner.execution.usage().heldBytes, 0n);
      assert.equal(retainedSequenceOwner.execution.usage()
        .reservedExecutionBytes, 0n);
    }
    retainedSequenceCapture.close();
    await retainedSequenceStore?.close();
    await rm(retainedSequenceDirectory, {recursive: true, force: true});
    await retainedSequenceRetained.close();
  }
  const scoredVectorPublicationProgram = structuredClone(
    carrierVectorPublicationProgram,
  );
  scoredVectorPublicationProgram.results = {
    published: {from: {stage: 'vectors', result: 'r'}},
  };
  scoredVectorPublicationProgram.stages[1].steps[0].values.rows = [
    {id: 1, embedding: [3, 4]},
    {id: 2, embedding: [0, 5]},
  ];
  scoredVectorPublicationProgram.stages[2].steps = [{
    from: 'rows',
    to_vectors: {id: 'id', vector: 'embedding'},
    as: 'source',
  }, {
    from: 'source',
    score_vectors: {query: [0, 1], metric: 'dot'},
    as: 'scored',
  }, {
    from: 'scored', normalize_vectors: true, as: 'same_carrier',
  }, {
    from: 'scored', vectors: true, as: 'out',
  }];
  scoredVectorPublicationProgram.stages[2].results.r.fields =
    ['id', 'embedding', 'score'];
  scoredVectorPublicationProgram.stages[3].steps[0].select =
    ['id', 'embedding', 'score'];
  scoredVectorPublicationProgram.stages[3].results.r.fields =
    ['id', 'embedding', 'score'];
  scoredVectorPublicationProgram.stages[4].steps[0].select =
    ['score', 'embedding', 'id'];
  scoredVectorPublicationProgram.stages[4].results.r.fields =
    ['score', 'embedding', 'id'];
  const scoredVectorPublicationFixture = fixture.strategyFixtureVecaCreate(
    ...args,
    JSON.stringify(scoredVectorPublicationProgram),
    orderedContract,
  );
  const scoredVectorCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(scoredVectorPublicationFixture),
    suppliedLimits,
  );
  const scoredVectorPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/scored-vector-publication-entry-',
  ));
  let scoredVectorPublicationOwner;
  let scoredVectorPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(
        scoredVectorPublicationFixture,
        scoredVectorCapture.source(),
      ),
      true,
    );
    const setup = fixture.strategyFixtureVecaSubset(
      scoredVectorPublicationFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 1);
    scoredVectorPublicationStore = await openLocalPublicationStore({
      directory: scoredVectorPublicationDirectory,
      storeAuthorityCid: hash('scored-vector-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'scored-vector-publication-attempt',
    );
    scoredVectorPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: scoredVectorPublicationStore, plan},
      {},
      new AbortController().signal,
    );
    assert.equal(scoredVectorPublicationOwner.status, 'published');
    assert.equal(
      scoredVectorPublicationOwner.publication.publication.state,
      'succeeded',
    );
    assert.deepEqual(
      scoredVectorPublicationOwner.execution.completed.map(
        value => value.realization,
      ),
      Array(4).fill('local-managed'),
    );
    const occurrence = scoredVectorPublicationOwner.execution
      .publicationInventory.occurrences[0];
    const received = [];
    await scoredVectorPublicationStore.consumeCommittedResult({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, occurrence.definitionContract.identity, () => true,
    chunk => received.push(Buffer.from(chunk)));
    assert.deepEqual(
      JSON.parse(Buffer.concat(received).toString('utf8')),
      [
        {id: 2, embedding: [0, 5], score: 5},
        {id: 1, embedding: [3, 4], score: 4},
      ],
    );
  } finally {
    if (scoredVectorPublicationOwner !== undefined) {
      await scoredVectorPublicationOwner.close();
      assert.equal(scoredVectorPublicationOwner.cleanupPending(), false);
      assert.equal(await scoredVectorPublicationOwner.cleanup(), true);
      assert.equal(
        scoredVectorPublicationOwner.execution.usage().heldBytes,
        0n,
      );
      assert.equal(
        scoredVectorPublicationOwner.execution.usage()
          .reservedExecutionBytes,
        0n,
      );
    }
    scoredVectorCapture.close();
    await scoredVectorPublicationStore?.close();
    await rm(scoredVectorPublicationDirectory, {
      recursive: true,
      force: true,
    });
  }
  const pooledVectorPublicationProgram = structuredClone(
    carrierVectorPublicationProgram,
  );
  pooledVectorPublicationProgram.results = {
    published: {from: {stage: 'vectors', result: 'r'}},
  };
  pooledVectorPublicationProgram.stages[1].steps[0].values.schema.group =
    {type: 'number', nullable: false};
  pooledVectorPublicationProgram.stages[1].steps[0].values.rows = [
    {id: 1, group: 1, embedding: [3, 4]},
    {id: 2, group: 1, embedding: [0, 5]},
  ];
  pooledVectorPublicationProgram.stages[1].results.r.fields =
    ['id', 'group', 'embedding'];
  pooledVectorPublicationProgram.stages[2].steps = [{
    from: 'rows',
    to_vectors: {id: 'id', vector: 'embedding'},
    as: 'source',
  }, {
    from: 'source',
    pool_vectors: {by: ['group'], method: 'sum'},
    as: 'pooled',
  }, {
    from: 'pooled', normalize_vectors: true, as: 'same_carrier',
  }, {
    from: 'pooled', vectors: true, as: 'out',
  }];
  const pooledFields = ['group', 'embedding', 'member_count'];
  pooledVectorPublicationProgram.stages[2].results.r.fields = pooledFields;
  pooledVectorPublicationProgram.stages[3].steps[0].select = pooledFields;
  pooledVectorPublicationProgram.stages[3].results.r.fields = pooledFields;
  pooledVectorPublicationProgram.stages[4].steps[0].select =
    ['member_count', 'embedding', 'group'];
  pooledVectorPublicationProgram.stages[4].results.r.fields =
    ['member_count', 'embedding', 'group'];
  const pooledVectorPublicationFixture = fixture.strategyFixtureVecaCreate(
    ...args,
    JSON.stringify(pooledVectorPublicationProgram),
    orderedContract,
  );
  const pooledVectorCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(pooledVectorPublicationFixture),
    suppliedLimits,
  );
  const pooledVectorPublicationDirectory = await mkdtemp(join(
    root,
    '_build/duckdb-fixtures/pooled-vector-publication-entry-',
  ));
  let pooledVectorPublicationOwner;
  let pooledVectorPublicationStore;
  try {
    assert.equal(
      fixture.strategyFixtureOpen(
        pooledVectorPublicationFixture,
        pooledVectorCapture.source(),
      ),
      true,
    );
    const setup = fixture.strategyFixtureVecaSubset(
      pooledVectorPublicationFixture,
    );
    const runtime = runtimeCore(hostRuntime);
    const resultCount = runtime.resultInventory(setup).length;
    assert.equal(resultCount, 1);
    pooledVectorPublicationStore = await openLocalPublicationStore({
      directory: pooledVectorPublicationDirectory,
      storeAuthorityCid: hash('pooled-vector-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      resultCount,
      'pooled-vector-publication-attempt',
    );
    pooledVectorPublicationOwner = await runPublishedCapturedStrategy(
      setup,
      {store: pooledVectorPublicationStore, plan},
      {},
      new AbortController().signal,
    );
    assert.equal(pooledVectorPublicationOwner.status, 'published');
    assert.equal(
      pooledVectorPublicationOwner.publication.publication.state,
      'succeeded',
    );
    assert.deepEqual(
      pooledVectorPublicationOwner.execution.completed.map(
        value => value.realization,
      ),
      Array(4).fill('local-managed'),
    );
    const occurrence = pooledVectorPublicationOwner.execution
      .publicationInventory.occurrences[0];
    const received = [];
    await pooledVectorPublicationStore.consumeCommittedResult({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, occurrence.definitionContract.identity, () => true,
    chunk => received.push(Buffer.from(chunk)));
    assert.deepEqual(
      JSON.parse(Buffer.concat(received).toString('utf8')),
      [{group: 1, embedding: [3, 9], member_count: 2}],
    );
  } finally {
    if (pooledVectorPublicationOwner !== undefined) {
      await pooledVectorPublicationOwner.close();
      assert.equal(pooledVectorPublicationOwner.cleanupPending(), false);
      assert.equal(await pooledVectorPublicationOwner.cleanup(), true);
      assert.equal(
        pooledVectorPublicationOwner.execution.usage().heldBytes,
        0n,
      );
      assert.equal(
        pooledVectorPublicationOwner.execution.usage()
          .reservedExecutionBytes,
        0n,
      );
    }
    pooledVectorCapture.close();
    await pooledVectorPublicationStore?.close();
    await rm(pooledVectorPublicationDirectory, {
      recursive: true,
      force: true,
    });
  }
  const stressSortKeys = Array.from(
    {length: 5}, (_, index) => `sort_key_${index + 1}`,
  );
  const stressSortTextBytes = 660;
  const stressSortText = '𠮷' + 'x'.repeat(stressSortTextBytes - 4);
  assert.equal(Buffer.byteLength(stressSortText, 'utf8'), stressSortTextBytes);
  // Preserve the selected Relation cancellation obligations after the sole
  // current Graph constructor/MATCH prefix; no retired normalize/row adapter.
  const matchedRelationSteps = (step, fields = ['id', 'node_name']) => [{
    from: 'g', match_nodes: {definition: 'N', where: 'true', fields},
    as: 'projected',
  }, {from: 'projected', ...step, as: 'out'}];
  const graphCancellationCases = [{
    name:'property-construction-in-flight',
    selectedStructural:true,
    rows:40,advanceQuantum:1,
    cancelOnManagedStart:2,managedStarts:2,constructionProgress:0,
    completedTasks:[1],
    step:{from:'g',match_nodes:{definition:'N',where:'true',
      fields:['id','node_name']},as:'out'},
    fields:['id','node_name'],
  }, {
    name:'current-match-nodes-predicate-in-flight',
    selectedStructural:true,
    rows:40,advanceQuantum:1,
    constructionProgress:80,constructionStarts:[2],
    cancelOnManagedStart:3,managedStarts:3,cancelTask:3,
    completedTasks:[1,2],
    step:{from:'g',match_nodes:{definition:'N',where:"node_name = 'node-39'",
      fields:['id','node_name']},as:'out'},
    fields:['id','node_name'],
  }, {
    name:'current-match-edges-predicate-in-flight',
    selectedStructural:true,
    retainedOutput:true,rows:40,advanceQuantum:1,
    // Retained VALUES uses the file route, not a ManagedStart. The first
    // observed managed owner constructs Graph; the second executes MATCH.
    constructionProgress:80,constructionStarts:[1],
    cancelOnManagedStart:2,managedStarts:2,cancelTask:3,
    completedTasks:[1,2],
    step:{from:'g',match_edges:{definition:'E',where:'weight > 10',
      fields:['src','dst','weight']},as:'out'},
    fields:['src','dst','weight'],
  }, {
    name: 'property-match-filter',
    rows: 40, advanceQuantum: 1,
    cancelOnManagedStart: 4, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({filter: 'id > 0'}),
    fields: ['id', 'node_name'],
  }, {
    name: 'property-match-select',
    rows: 40, advanceQuantum: 1,
    cancelOnManagedStart: 4, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({select: ['id', 'node_name']}),
    fields: ['id', 'node_name'],
  }, {
    name: 'property-match-take',
    rows: 40, advanceQuantum: 1,
    cancelOnManagedStart: 4, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({take: {count: 1, offset: 0}}),
    fields: ['id', 'node_name'],
  }, {
    name: 'property-match-sort-wide-comparison',
    rows: 2, sortStress: true, cancelAfterSortAdvances: 70,
    advanceQuantum: 1, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({sort: [
      {node_name: 'asc'},
      ...stressSortKeys.map(key => ({[key]: 'asc'})),
      {id: 'asc'},
    ]}, ['id', 'node_name', ...stressSortKeys]),
    fields: ['id', 'node_name', ...stressSortKeys],
  }, {
    name: 'property-match-assert',
    rows: 40, advanceQuantum: 1,
    cancelOnManagedStart: 4, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({assert_rows: {where: 'id > 0'}}),
    fields: ['id', 'node_name'],
  }, {
    name: 'property-match-assert-unique',
    rows: 40, advanceQuantum: 1,
    cancelOnManagedStart: 4, managedStarts: 4, cancelTask: 4,
    completedTasks: [1, 2, 3],
    steps: matchedRelationSteps({assert_rows: {unique_by: ['id']}}),
    fields: ['id', 'node_name'],
  }, {
    name: 'to-events-bridge',
    family: 'tea',
    operation: 'watermark',
    rows: 40,
    advanceQuantum: 1,
    cancelOnManagedStart: 2,
    constructionProgress: 0,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'watermark_ms',
      'late',
      'watermark_decision',
    ],
    secondFields: ['watermark_decision', 'event_id'],
  }, {
    name: 'events-to-rows-bridge',
    family: 'tea',
    operation: 'watermark',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'watermark_ms',
      'late',
      'watermark_decision',
    ],
    secondFields: ['watermark_decision', 'event_id'],
  }, {
    name: 'window-fixed',
    family: 'tea',
    operation: 'window-fixed',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'window_start_ms',
      'window_end_ms',
    ],
    secondFields: ['window_start_ms', 'event_id'],
  }, {
    name: 'window-sliding',
    family: 'tea',
    operation: 'window-sliding',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'window_start_ms',
      'window_end_ms',
    ],
    secondFields: ['window_start_ms', 'event_id'],
  }, {
    name: 'window-fixed-selected-filter',
    family: 'tea',
    operation: 'window-fixed',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: [
      'event_id', 'occurred_at', 'payload',
      'window_start_ms', 'window_end_ms',
    ],
    secondFields: ['window_start_ms', 'event_id'],
  }, {
    name: 'window-sliding-later-filter',
    family: 'tea',
    operation: 'window-sliding',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 5,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: [
      'event_id', 'occurred_at', 'payload',
      'window_start_ms', 'window_end_ms',
    ],
    secondFields: ['window_start_ms', 'event_id'],
  }, {
    name: 'watermark',
    family: 'tea',
    operation: 'watermark',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'watermark_ms',
      'late',
      'watermark_decision',
    ],
    secondFields: ['watermark_decision', 'event_id'],
  }, {
    name: 'dedupe-events',
    family: 'tea',
    operation: 'dedupe',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    fields: ['event_id', 'occurred_at', 'payload'],
    secondFields: ['payload', 'event_id'],
  }, {
    name: 'dedupe-events-later-filter',
    family: 'tea',
    operation: 'dedupe',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 5,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: ['event_id', 'occurred_at', 'payload'],
    secondFields: ['payload', 'event_id'],
  }, {
    name: 'dedupe-events-selected-filter',
    family: 'tea',
    operation: 'dedupe',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['event_id', 'occurred_at', 'payload'],
    secondFields: ['payload', 'event_id'],
  }, {
    name: 'session',
    family: 'tea',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    managedStarts: 2,
    completedTasks: [1],
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'session_start_ms',
      'session_end_ms',
      'session_id',
    ],
  }, {
    name: 'session-view',
    family: 'tea',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'session_start_ms',
      'session_end_ms',
      'session_id',
    ],
  }, {
    name: 'session-relation',
    family: 'tea',
    operation: 'session',
    relationSession: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 2,
    managedStarts: 2,
    fields: [
      'event_id',
      'occurred_at',
      'payload',
      'session_start_ms',
      'session_end_ms',
      'session_id',
    ],
  }, {
    name: 'sequence',
    family: 'sequence',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 2,
    fields: [
      'end_id',
      'end_time_ms',
      'key',
      'match_end_ms',
      'match_start_ms',
      'start_id',
      'start_time_ms',
    ],
  }, {
    name: 'time-series',
    family: 'time-series',
    rows: 100,
    advanceQuantum: 1,
    fields: ['time'],
  }, {
    name: 'interval-join',
    family: 'interval',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: ['left_value', 'right_value'],
  }, {
    name: 'asof-join',
    family: 'asof',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: ['left_value', 'right_value'],
  }, {
    name: 'rows-to-vectors-bridge',
    family: 'veca',
    operation: 'bridge',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 2,
    fields: ['id', 'embedding'],
  }, {
    name: 'vectors-to-rows-bridge',
    family: 'veca',
    operation: 'bridge',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    fields: ['id', 'embedding'],
  }, {
    name: 'vector-normalize',
    family: 'veca',
    operation: 'normalize',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    fields: ['id', 'embedding'],
  }, {
    name: 'vector-normalize-score-selected-filter',
    family: 'veca',
    operation: 'normalize',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 4,
    managedStarts: 4,
    completedTasks: [1, 2, 3],
    fields: ['id', 'embedding'],
  }, {
    name: 'vector-normalize-selected-filter',
    family: 'veca',
    operation: 'normalize',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['id', 'embedding'],
  }, {
    name: 'vector-normalize-later-filter',
    family: 'veca',
    operation: 'normalize',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 5,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: ['id', 'embedding'],
  }, {
    name: 'vector-expression',
    family: 'veca',
    operation: 'expression',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 2,
    minimumCompletedRows: 1,
    fields: ['id', 'score', 'joined'],
  }, {
    name: 'vector-score',
    family: 'veca',
    operation: 'score',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    fields: ['id', 'embedding', 'score'],
  }, {
    name: 'vector-score-selected-filter',
    family: 'veca',
    operation: 'score',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['id', 'embedding', 'score'],
  }, {
    name: 'vector-pool',
    family: 'veca',
    operation: 'pool',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 80,
    fields: ['group', 'embedding', 'member_count'],
  }, {
    name: 'vector-pool-selected-filter',
    family: 'veca',
    operation: 'pool',
    mixedRelationFilter: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 40,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['group', 'embedding', 'member_count'],
  }, {
    name: 'vector-pool-relation',
    family: 'veca',
    operation: 'pool',
    relationPool: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['group', 'embedding', 'member_count'],
  }, {
    name: 'vector-ranking-rrf',
    family: 'veca',
    operation: 'ranking',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['q', 'id', 'score', 'rank'],
  }, {
    name: 'vector-ranking-maximum',
    family: 'veca',
    operation: 'ranking',
    scoredPolicy: 'max',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 1,
    managedStarts: 1,
    completedTasks: [],
    fields: ['q', 'id', 'score', 'rank'],
  }, {
    name: 'vector-ranking-weighted',
    family: 'veca',
    operation: 'ranking',
    scoredPolicy: {weighted_sum: {left: 0.5, right: 0.5}},
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 1,
    managedStarts: 1,
    completedTasks: [],
    fields: ['q', 'id', 'score', 'rank'],
  }, {
    name: 'vector-nearest',
    family: 'veca',
    operation: 'nearest',
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['query_id', 'candidate_id', 'score', 'rank'],
  }, {
    name: 'vector-nearest-fused',
    family: 'veca',
    operation: 'nearest',
    fusedNearest: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 3,
    managedStarts: 3,
    completedTasks: [1, 2],
    fields: ['query_id', 'candidate_id', 'score', 'rank'],
  }, {
    name: 'vector-nearest-carrier-inputs',
    family: 'veca',
    operation: 'nearest',
    selectedCarrierNearest: true,
    rows: 40,
    advanceQuantum: 1,
    constructionProgress: 0,
    cancelOnManagedStart: 5,
    managedStarts: 5,
    completedTasks: [1, 2, 3, 4],
    fields: ['query_id', 'candidate_id', 'score', 'rank'],
  }];
  for (const cancellationCase of graphCancellationCases) {
    const teaFamily = cancellationCase.family === 'tea' ||
      cancellationCase.family === 'time-series' ||
      cancellationCase.family === 'interval' ||
      cancellationCase.family === 'asof' ||
      cancellationCase.family === 'sequence';
    const vecaFamily = cancellationCase.family === 'veca';
    const graphFamily = !teaFamily && !vecaFamily;
    const teaTransform = cancellationCase.operation === 'window-fixed'
      ? {window_events: {kind: 'fixed', size: 10}}
      : cancellationCase.operation === 'window-sliding'
        ? {window_events: {kind: 'sliding', size: 10, step: 5}}
        : cancellationCase.operation === 'watermark'
          ? {watermark_events: {watermark_ms: 10, policy: 'mark'}}
          : cancellationCase.operation === 'dedupe'
            ? {
              dedupe_events: {
                by: ['payload'],
                order_by: [{
                  field: 'occurred_at', dir: 'asc', nulls: 'last',
                }],
              },
            }
            : {session: {by: ['payload'], gap: 10}};
    const graphCancellationProgram = cancellationCase.family === 'interval' ||
      cancellationCase.family === 'asof'
      ? {
        version: 'actql/0.1',
        id: 'p',
        params: {minimum: {type: 'number', nullable: false}},
        stages: [{
          id: 'a',
          inputs: {remote: {connector: 'crm/main', resource: 'r'}},
          steps: [
            {filter: 'id > $minimum', as: 'filtered'},
            {select: ['id'], as: 'captured'},
          ],
          results: {r: {from: 'captured', fields: ['id']}},
        }, ...['left', 'right'].map(side => ({
          id: side,
          inputs: {},
          steps: [{
            values: {
              schema: side === 'left'
                ? {
                  id: {type: 'number', nullable: false},
                  key: {type: 'number', nullable: false},
                  time: {type: 'number', nullable: false},
                  value: {type: 'number', nullable: false},
                }
                : {
                  id: {type: 'number', nullable: false},
                  key: {type: 'number', nullable: false},
                  ...(cancellationCase.family === 'interval'
                    ? {
                      start: {type: 'number', nullable: false},
                      end: {type: 'number', nullable: false},
                    }
                    : {time: {type: 'number', nullable: false}}),
                  value: {type: 'number', nullable: false},
                },
              rows: Array.from(
                {length: cancellationCase.rows},
                (_, index) => side === 'left'
                  ? {id: index, key: index, time: index, value: index}
                  : cancellationCase.family === 'interval'
                    ? {
                      id: index,
                      key: index,
                      start: index,
                      end: index + 1,
                      value: index,
                    }
                    : {id: index, key: index, time: index, value: index},
              ),
            },
            as: 'out',
          }],
          results: {
            r: {
              from: 'out',
              fields: side === 'left'
                ? ['id', 'key', 'time', 'value']
                : cancellationCase.family === 'interval'
                  ? ['id', 'key', 'start', 'end', 'value']
                  : ['id', 'key', 'time', 'value'],
            },
          },
        })), {
          id: 'joined',
          inputs: {
            l: {result: {stage: 'left', result: 'r'}},
            r: {result: {stage: 'right', result: 'r'}},
          },
          steps: [{
            from: 'l',
            ...(cancellationCase.family === 'interval'
              ? {
                interval_join: {
                  with: 'r',
                  kind: 'inner',
                  mode: 'point_in_interval',
                  on: [{left: 'key', right: 'key'}],
                  left: {time: 'time'},
                  right: {start: 'start', end: 'end'},
                  select: {
                    left_value: 'left.value',
                    right_value: 'right.value',
                  },
                  max_output_rows: cancellationCase.rows,
                },
              }
              : {
                asof_join: {
                  with: 'r',
                  kind: 'inner',
                  by: [{left: 'key', right: 'key'}],
                  left_id: 'id',
                  left_time: 'time',
                  right_time: 'time',
                  direction: 'backward',
                  tolerance: cancellationCase.rows,
                  right_tie_break: ['id'],
                  select: {
                    left_value: 'left.value',
                    right_value: 'right.value',
                  },
                },
              }),
            as: 'out',
          }],
          results: {r: {from: 'out', fields: cancellationCase.fields}},
        }, ...['a', 'b'].map(id => ({
          id: `consumer_${id}`,
          inputs: {x: {result: {stage: 'joined', result: 'r'}}},
          steps: [{select: cancellationCase.fields, as: 'out'}],
          results: {r: {from: 'out', fields: cancellationCase.fields}},
        }))],
        results: {published: {from: {stage: 'joined', result: 'r'}}},
      }
      : cancellationCase.family === 'sequence'
        ? {
          version: 'actql/0.1',
          id: 'p',
          params: {minimum: {type: 'number', nullable: false}},
          stages: [{
            id: 'a',
            inputs: {remote: {connector: 'crm/main', resource: 'r'}},
            steps: [
              {filter: 'id > $minimum', as: 'filtered'},
              {select: ['id'], as: 'captured'},
            ],
            results: {r: {from: 'captured', fields: ['id']}},
          }, {
            id: 'events',
            inputs: {},
            steps: [{
              values: {
                schema: {
                  id: {type: 'number', nullable: false},
                  key: {type: 'number', nullable: false},
                  clock: {type: 'number', nullable: false},
                  value: {type: 'number', nullable: false},
                },
                rows: Array.from(
                  {length: cancellationCase.rows},
                  (_, index) => ({
                    id: index + 1,
                    key: index % 2,
                    clock: index + 1,
                    value: index % 2 + 1,
                  }),
                ),
              },
              as: 'out',
            }],
            results: {
              r: {from: 'out', fields: ['id', 'key', 'clock', 'value']},
            },
          }, {
            id: 'matched',
            inputs: {x: {result: {stage: 'events', result: 'r'}}},
            steps: [{
              from: 'x',
              sequence: {
                by: ['key'],
                id: 'id',
                time: 'clock',
                pattern: [{as: 'start', where: 'value = 1'}, {
                  as: 'end', where: 'value = 2',
                }],
                within: cancellationCase.rows,
                overlap: 'allow',
                contiguity: 'subsequence',
              },
              as: 'out',
            }],
            results: {r: {from: 'out', fields: cancellationCase.fields}},
          }, ...['a', 'b'].map(id => ({
            id: `consumer_${id}`,
            inputs: {x: {result: {stage: 'matched', result: 'r'}}},
            steps: [{select: cancellationCase.fields, as: 'out'}],
            results: {r: {from: 'out', fields: cancellationCase.fields}},
          }))],
          results: {published: {from: {stage: 'matched', result: 'r'}}},
        }
      : cancellationCase.family === 'tea'
      ? {
        version: 'actql/0.1',
        id: 'p',
        params: {minimum: {type: 'number', nullable: false}},
        stages: [{
          id: 'a',
          inputs: {remote: {connector: 'crm/main', resource: 'r'}},
          steps: [
            {filter: 'id > $minimum', as: 'filtered'},
            {select: ['id'], as: 'captured'},
          ],
          results: {r: {from: 'captured', fields: ['id']}},
        }, {
          id: 'values',
          inputs: {},
          steps: [{
            values: {
              schema: {
                event_id: {type: 'number', nullable: false},
                occurred_at: {type: 'number', nullable: false},
                payload: {type: 'string', nullable: false},
              },
              rows: Array.from(
                {length: cancellationCase.rows},
                (_, index) => ({
                  event_id: index + 1,
                  occurred_at: index + 1,
                  payload: `partition-${index % 2}`,
                }),
              ),
            },
            as: 'out',
          }],
          results: {
            r: {
              from: 'out',
              fields: ['event_id', 'occurred_at', 'payload'],
            },
          },
        }, {
          id: 'events',
          inputs: {rows: {result: {stage: 'values', result: 'r'}}},
          steps: cancellationCase.relationSession
            ? [{
              from: 'rows',
              session: {
                id: 'event_id',
                time: 'occurred_at',
                by: ['payload'],
                gap: 10,
              },
              as: 'out',
            }]
            : [{
              from: 'rows',
              to_events: {id: 'event_id', time: 'occurred_at'},
            }, teaTransform, {
              events: true,
              as: 'out',
            }],
          results: {
            r: {from: 'out', fields: cancellationCase.fields},
          },
        }, {
          id: 'consumer_a',
          inputs: {x: {result: {stage: 'events', result: 'r'}}},
          steps: [{select: cancellationCase.fields, as: 'out'}],
          results: {
            r: {from: 'out', fields: cancellationCase.fields},
          },
        }, {
          id: 'consumer_b',
          inputs: {x: {result: {stage: 'events', result: 'r'}}},
          steps: [{
            select: cancellationCase.secondFields ??
              ['session_id', 'event_id'],
            as: 'out',
          }],
          results: {
            r: {
              from: 'out',
              fields: cancellationCase.secondFields ??
                ['session_id', 'event_id'],
            },
          },
        }],
        results: {published: {from: {stage: 'events', result: 'r'}}},
      }
      : cancellationCase.family === 'time-series'
        ? {
          version: 'actql/0.1',
          id: 'p',
          params: {minimum: {type: 'number', nullable: false}},
          stages: [{
            id: 'a',
            inputs: {remote: {connector: 'crm/main', resource: 'r'}},
            steps: [
              {filter: 'id > $minimum', as: 'filtered'},
              {select: ['id'], as: 'captured'},
            ],
            results: {r: {from: 'captured', fields: ['id']}},
          }, {
            id: 'series',
            inputs: {},
            steps: [{
              time_series: {
                start: '1970-01-01T00:00:00.000Z',
                end: '1970-01-01T00:00:00.100Z',
                step: 1,
              },
              as: 'out',
            }],
            results: {r: {from: 'out', fields: ['time']}},
          }, {
            id: 'consumer_a',
            inputs: {x: {result: {stage: 'series', result: 'r'}}},
            steps: [{select: ['time'], as: 'out'}],
            results: {r: {from: 'out', fields: ['time']}},
          }, {
            id: 'consumer_b',
            inputs: {x: {result: {stage: 'series', result: 'r'}}},
            steps: [{select: ['time'], as: 'out'}],
            results: {r: {from: 'out', fields: ['time']}},
          }],
          results: {published: {from: {stage: 'series', result: 'r'}}},
        }
        : vecaFamily && cancellationCase.operation === 'expression'
          ? {
            version: 'actql/0.1',
            id: 'p',
            params: {minimum: {type: 'number', nullable: false}},
            stages: [{
              id: 'a',
              inputs: {remote: {connector: 'crm/main', resource: 'r'}},
              steps: [
                {filter: 'id > $minimum', as: 'filtered'},
                {select: ['id'], as: 'captured'},
              ],
              results: {r: {from: 'captured', fields: ['id']}},
            }, {
              id: 'values',
              inputs: {},
              steps: [{
                values: {
                  schema: {
                    id: {type: 'number', nullable: false},
                    left: {
                      type: 'vector', dimensions: 2, nullable: false,
                    },
                    right: {
                      type: 'vector', dimensions: 2, nullable: false,
                    },
                  },
                  rows: Array.from(
                    {length: cancellationCase.rows},
                    (_, index) => ({
                      id: index + 1,
                      left: [index + 1, index + 2],
                      right: [index + 2, index + 1],
                    }),
                  ),
                },
                as: 'out',
              }],
              results: {
                r: {from: 'out', fields: ['id', 'left', 'right']},
              },
            }, {
              id: 'expression',
              inputs: {rows: {result: {stage: 'values', result: 'r'}}},
              steps: [{
                derive: {
                  score: {
                    vector_score: {
                      left: {field: 'left'},
                      right: {field: 'right'},
                      metric: 'dot',
                    },
                  },
                  joined: {
                    vector_concat: [
                      {field: 'right'},
                      {field: 'left'},
                    ],
                  },
                },
                as: 'out',
              }],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }, ...['a', 'b'].map(id => ({
              id: `consumer_${id}`,
              inputs: {x: {result: {stage: 'expression', result: 'r'}}},
              steps: [{select: cancellationCase.fields, as: 'out'}],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }))],
            results: {published: {from: {stage: 'expression', result: 'r'}}},
          }
        : vecaFamily && cancellationCase.operation === 'ranking' &&
            cancellationCase.scoredPolicy !== undefined
          ? {
            version: 'actql/0.1',
            id: 'p',
            params: {minimum: {type: 'number', nullable: false}},
            stages: [{
              id: 'a',
              inputs: {remote: {connector: 'crm/main', resource: 'r'}},
              steps: [
                {filter: 'id > $minimum', as: 'filtered'},
                {select: ['id'], as: 'captured'},
              ],
              results: {r: {from: 'captured', fields: ['id']}},
            }, {
              id: 'ranked',
              inputs: Object.fromEntries(['left', 'right'].map(id => [id, {
                carrier: 'relation',
                schema: {
                  q: {type: 'number', nullable: false},
                  id: {type: 'number', nullable: false},
                  score: {type: 'number', nullable: false},
                },
              }])),
              from: 'left',
              steps: [{
                merge_rankings: {
                  with: 'right',
                  by: ['q'],
                  candidate: 'id',
                  score: 'score',
                  score_policy: cancellationCase.scoredPolicy,
                  score_contract: {
                    domain: 'unit.v1',
                    normalization: 'unit.v1',
                    range: [0, 1],
                  },
                  k: cancellationCase.rows,
                },
                as: 'out',
              }],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }, ...['a', 'b'].map(id => ({
              id: `consumer_${id}`,
              inputs: {x: {result: {stage: 'ranked', result: 'r'}}},
              steps: [{select: cancellationCase.fields, as: 'out'}],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }))],
            results: {published: {from: {stage: 'ranked', result: 'r'}}},
          }
        : vecaFamily && cancellationCase.operation === 'ranking'
          ? {
            version: 'actql/0.1',
            id: 'p',
            params: {minimum: {type: 'number', nullable: false}},
            stages: [{
              id: 'a',
              inputs: {remote: {connector: 'crm/main', resource: 'r'}},
              steps: [
                {filter: 'id > $minimum', as: 'filtered'},
                {select: ['id'], as: 'captured'},
              ],
              results: {r: {from: 'captured', fields: ['id']}},
            }, ...['left', 'right'].map(id => ({
              id,
              inputs: {},
              steps: [{
                values: {
                  schema: {
                    q: {type: 'number', nullable: false},
                    id: {type: 'number', nullable: false},
                    rank: {type: 'number', nullable: false},
                  },
                  rows: Array.from(
                    {length: cancellationCase.rows},
                    (_, index) => ({q: 1, id: index + 1, rank: index + 1}),
                  ),
                },
                as: 'out',
              }],
              results: {r: {from: 'out', fields: ['q', 'id', 'rank']}},
            })), {
              id: 'fusion',
              inputs: {
                left: {result: {stage: 'left', result: 'r'}},
                right: {result: {stage: 'right', result: 'r'}},
              },
              steps: [{
                from: 'left',
                merge_rankings: {
                  with: ['right'],
                  by: ['q'],
                  candidate: 'id',
                  rank: 'rank',
                  score_policy: {
                    rrf: {
                      rank_constant: 1,
                      weights: [1, 1],
                      rank_window: cancellationCase.rows,
                    },
                  },
                  k: cancellationCase.rows,
                },
                as: 'out',
              }],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }, ...['a', 'b'].map(id => ({
              id: `consumer_${id}`,
              inputs: {x: {result: {stage: 'fusion', result: 'r'}}},
              steps: [{select: cancellationCase.fields, as: 'out'}],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }))],
            results: {published: {from: {stage: 'fusion', result: 'r'}}},
          }
          : vecaFamily && cancellationCase.operation === 'nearest'
            ? {
              version: 'actql/0.1',
              id: 'p',
              params: {minimum: {type: 'number', nullable: false}},
              stages: [{
                id: 'a',
                inputs: {remote: {connector: 'crm/main', resource: 'r'}},
                steps: [
                  {filter: 'id > $minimum', as: 'filtered'},
                  {select: ['id'], as: 'captured'},
                ],
                results: {r: {from: 'captured', fields: ['id']}},
              }, ...(cancellationCase.selectedCarrierNearest
                ? [] : ['candidates', 'queries'].map(id => ({
                id,
                inputs: {},
                steps: [{
                  values: {
                    schema: {
                      id: {type: 'number', nullable: false},
                      embedding: {
                        type: 'vector', dimensions: 2, nullable: false,
                      },
                    },
                    rows: Array.from(
                      {
                        length: id === 'queries'
                          ? 1
                          : cancellationCase.rows,
                      },
                      (_, index) => ({
                        id: index + 1,
                        embedding: [index + 1, index + 2],
                      }),
                    ),
                  },
                  as: 'out',
                }],
                results: {r: {from: 'out', fields: ['id', 'embedding']}},
              }))), {
                id: 'nearest',
                inputs: cancellationCase.selectedCarrierNearest ? {} : {
                  candidates: {result: {stage: 'candidates', result: 'r'}},
                  queries: {result: {stage: 'queries', result: 'r'}},
                },
                steps: [
                  ...(cancellationCase.selectedCarrierNearest
                    ? ['candidates', 'queries'].map(id => ({
                      values: {
                        schema: {
                          id: {type: 'number', nullable: false},
                          embedding: {
                            type: 'vector', dimensions: 2, nullable: false,
                          },
                        },
                        rows: Array.from(
                          {length: id === 'queries' ? 1 : cancellationCase.rows},
                          (_, index) => ({
                            id: index + 1,
                            embedding: [index + 1, index + 2],
                          }),
                        ),
                      },
                      as: id,
                    })) : []),
                  ...(cancellationCase.fusedNearest ||
                      cancellationCase.selectedCarrierNearest ? [{
                    from: 'candidates',
                    to_vectors: {id: 'id', vector: 'embedding'},
                    as: 'candidate_vectors',
                  }, {
                    from: 'queries',
                    to_vectors: {id: 'id', vector: 'embedding'},
                    as: 'query_vectors',
                  }] : []), {
                  from: cancellationCase.fusedNearest ||
                    cancellationCase.selectedCarrierNearest
                    ? 'candidate_vectors' : 'candidates',
                  nearest: {
                    queries: cancellationCase.fusedNearest ||
                      cancellationCase.selectedCarrierNearest
                      ? 'query_vectors' : 'queries',
                    ...(cancellationCase.fusedNearest ||
                        cancellationCase.selectedCarrierNearest ? {} : {
                      candidate_id: 'id',
                      candidate_vector: 'embedding',
                      query_id: 'id',
                      query_vector: 'embedding',
                    }),
                    metric: 'dot',
                    k: cancellationCase.rows,
                  },
                  as: 'out',
                }],
                results: {r: {from: 'out', fields: cancellationCase.fields}},
              }, ...['a', 'b'].map(id => ({
                id: `consumer_${id}`,
                inputs: {x: {result: {stage: 'nearest', result: 'r'}}},
                steps: [{select: cancellationCase.fields, as: 'out'}],
                results: {r: {from: 'out', fields: cancellationCase.fields}},
              }))],
              results: {published: {from: {stage: 'nearest', result: 'r'}}},
            }
          : vecaFamily
          ? {
            version: 'actql/0.1',
            id: 'p',
            params: {minimum: {type: 'number', nullable: false}},
            stages: [{
              id: 'a',
              inputs: {remote: {connector: 'crm/main', resource: 'r'}},
              steps: [
                {filter: 'id > $minimum', as: 'filtered'},
                {select: ['id'], as: 'captured'},
              ],
              results: {r: {from: 'captured', fields: ['id']}},
            }, {
              id: 'values',
              inputs: {},
              steps: [{
                values: {
                  schema: {
                    id: {type: 'number', nullable: false},
                    group: {type: 'number', nullable: false},
                    embedding: {
                      type: 'vector', dimensions: 2, nullable: false,
                    },
                  },
                  rows: Array.from(
                    {length: cancellationCase.rows},
                    (_, index) => ({
                      id: index + 1,
                      group: index % 2,
                      embedding: [index + 1, index + 2],
                    }),
                  ),
                },
                as: 'out',
              }, ...(cancellationCase.relationPool ? [{
                from: 'out',
                assert_rows: {unique_by: ['id']},
                as: 'keyed',
              }] : [])],
              results: {
                r: {
                  from: cancellationCase.relationPool ? 'keyed' : 'out',
                  fields: cancellationCase.operation === 'pool'
                    ? ['id', 'group', 'embedding']
                    : ['id', 'embedding'],
                },
              },
            }, {
              id: 'vectors',
              inputs: {rows: {result: {stage: 'values', result: 'r'}}},
              steps: cancellationCase.operation === 'bridge'
                ? [{
                  from: 'rows',
                  to_vectors: {id: 'id', vector: 'embedding'},
                  as: 'source',
                }, {
                  from: 'source', vectors: true, as: 'out',
                }]
                : cancellationCase.operation === 'score'
                ? [{
                  from: 'rows',
                  to_vectors: {id: 'id', vector: 'embedding'},
                  as: 'source',
                }, {
                  from: 'source',
                  score_vectors: {query: [0, 1], metric: 'dot'},
                  as: 'scored',
                }, {
                  from: 'scored',
                  normalize_vectors: true,
                  as: 'same_carrier',
                }, {
                  from: 'scored', vectors: true, as: 'out',
                }]
                : cancellationCase.operation === 'pool'
                  ? cancellationCase.relationPool ? [{
                    from: 'rows',
                    pool_vectors: {
                      vector: 'embedding', by: ['group'], method: 'sum',
                    },
                    as: 'pooled',
                  }, {
                    from: 'pooled', vectors: true, as: 'out',
                  }] : [{
                    from: 'rows',
                    to_vectors: {id: 'id', vector: 'embedding'},
                    as: 'source',
                  }, {
                    from: 'source',
                    pool_vectors: {by: ['group'], method: 'sum'},
                    as: 'pooled',
                  }, {
                    from: 'pooled',
                    normalize_vectors: true,
                    as: 'same_carrier',
                  }, {
                    from: 'pooled', vectors: true, as: 'out',
                  }]
                : [{
                  from: 'rows',
                  to_vectors: {id: 'id', vector: 'embedding'},
                  as: 'source',
                }, {
                  from: 'source', normalize_vectors: true, as: 'normalized',
                }, {
                  from: 'normalized',
                  score_vectors: {query: [1, 0], metric: 'dot'},
                  as: 'same_carrier',
                }, {
                  from: 'normalized', vectors: true, as: 'out',
                }],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }, {
              id: 'consumer_a',
              inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
              steps: [{select: cancellationCase.fields, as: 'out'}],
              results: {r: {from: 'out', fields: cancellationCase.fields}},
            }, {
              id: 'consumer_b',
              inputs: {x: {result: {stage: 'vectors', result: 'r'}}},
              steps: [{
                select: cancellationCase.fields.toReversed(), as: 'out',
              }],
              results: {
                r: {
                  from: 'out',
                  fields: cancellationCase.fields.toReversed(),
                },
              },
            }],
            results: {published: {from: {stage: 'vectors', result: 'r'}}},
          }
          : structuredClone(graphProgramBase);
    if (cancellationCase.mixedRelationFilter) {
      const carrierStage = graphCancellationProgram.stages.find(stage =>
        stage.id === (teaFamily ? 'events' : 'vectors'));
      const projection = carrierStage.steps.at(-1);
      projection.as = 'projected';
      carrierStage.steps.push({
        from: 'projected',
        filter: 'true',
        as: 'out',
      });
    }
    const graphStageIndex = 2;
    if (graphFamily) {
      graphCancellationProgram.stages[1].steps[0].values.rows =
        Array.from({length: cancellationCase.rows}, (_, index) => ({
          id: index + 1,
          src: index + 1,
          dst: (index + 1) % cancellationCase.rows + 1,
          node_name: `node-${index + 1}`,
          weight: index + 1,
        }));
    }
    if (graphFamily && cancellationCase.sortStress) {
      const valueStep = graphCancellationProgram.stages[1].steps[0].values;
      for (const key of stressSortKeys) {
        valueStep.schema[key] = {type: 'string', nullable: false};
      }
      for (const row of valueStep.rows) {
        row.node_name = stressSortText;
        for (const key of stressSortKeys) row[key] = stressSortText;
      }
      graphCancellationProgram.stages[1].results.r.fields.push(...stressSortKeys);
      // Both definition labels already expose all_columns from this exact
      // input; no tuple-only Graph field list needs extending.
    }
    if (graphFamily) {
      graphCancellationProgram.stages[graphStageIndex].steps.splice(
        1,
        1,
        ...(cancellationCase.steps ?? [cancellationCase.step]),
      );
      if (cancellationCase.selectedStructural) {
        const graphStage = graphCancellationProgram.stages[graphStageIndex];
        graphStage.steps.at(-1).as = 'projected';
        graphStage.steps.push({
          from: 'projected', filter: 'true', as: 'out',
        });
      }
    }
    const graphFields = cancellationCase.fields;
    if (graphFamily) {
      graphCancellationProgram.stages[graphStageIndex].results.r.fields =
        graphFields;
      graphCancellationProgram.stages[graphStageIndex + 1].steps[0].select =
        graphFields;
      graphCancellationProgram.stages[graphStageIndex + 1].results.r.fields =
        graphFields;
      const graphSecondFields = graphFields.slice(1);
      graphCancellationProgram.stages[graphStageIndex + 2].steps[0].select =
        graphSecondFields;
      graphCancellationProgram.stages[graphStageIndex + 2].results.r.fields =
        graphSecondFields;
      graphCancellationProgram.stages[graphStageIndex + 3].steps[0].select =
        [graphFields[0]];
      graphCancellationProgram.stages[graphStageIndex + 3].results.r.fields =
        [graphFields[0]];
    }
    let cancellationArguments = args;
    if (cancellationCase.scoredPolicy !== undefined) {
      const environment = JSON.parse(args[0]);
      const scoreSchema = {
        additional_properties: false,
        fields: {
          id: {nullable: false, type: 'number'},
          q: {nullable: false, type: 'number'},
          score: {nullable: false, type: 'number'},
        },
        nullable: false,
        type: 'object',
      };
      environment.schema_snapshots = ['right', 'left'].map(input => ({
        output_carrier: 'relation',
        schema: scoreSchema,
        score_contracts: {
          score: {
            domain: 'unit.v1',
            normalization: 'unit.v1',
            range: [0, 1],
          },
        },
        source_ref: `source:local/ranked/${input}`,
        version: 'actql-local-input-schema/0.1',
      }));
      const body = {...environment};
      delete body.evidence_bundle_cid;
      environment.evidence_bundle_cid = canonicalHash(body);
      cancellationArguments = [
        JSON.stringify(environment),
        environment.evidence_bundle_cid,
        ...args.slice(2),
      ];
    }
    const createCancellationFixture = cancellationCase.scoredPolicy !==
        undefined
      ? fixture.strategyFixtureVecaScoredCreate
      : cancellationCase.family === 'sequence'
        ? fixture.strategyFixtureTeaSequenceCreate
      : teaFamily
      ? fixture.strategyFixtureTeaCreate
      : vecaFamily
        ? fixture.strategyFixtureVecaCreate
      : fixture.strategyFixtureSgaCreate;
    let cancellationFixture;
    try {
      cancellationFixture = createCancellationFixture(
        ...(teaFamily || vecaFamily
          ? cancellationArguments
          : sgaEnvironmentArguments(cancellationArguments)),
        JSON.stringify(graphCancellationProgram),
        ...(teaFamily || graphFamily
          ? []
          : vecaFamily
            ? cancellationCase.scoredPolicy !== undefined
              ? [orderedContract, cancellationCase.rows]
              : [orderedContract]
          : []),
      );
    } catch (error) {
      throw new Error(`Graph cancellation fixture ${cancellationCase.name} failed to check`,
        {cause: error});
    }
    const cancellationCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(cancellationFixture),
      suppliedLimits,
    );
    const graphCancellation = new AbortController();
    let cancellationExecution;
    let constructionProgress = 0n;
    let constructionComplete = cancellationCase.family === 'time-series';
    let sawOperationWork = false;
    let cancellationScheduled = false;
    let cancellationDeliveredAt;
    let stopObservedAt;
    let managedStarts = 0;
    const managedTaskByStart = [];
    let fusedNearestBridgeRows = 0n;
    const completedRowsByStart = new Map();
    const boundedValuesInputs = cancellationCase.family === 'interval' ||
      cancellationCase.family === 'asof';
    const constructionStarts = cancellationCase.constructionStarts ??
      (boundedValuesInputs ? [3, 4] : [2]);
    const expectedManagedStarts = cancellationCase.managedStarts ??
      (cancellationCase.family === 'time-series' ? 1 : 2);
    let maxSortResumeMs = 0;
    let selectedSortAdvances = 0;
    let selectedSortReportedWork = 0n;
    const advanceObservations = [];
    const finalizationObservations = [];
    const lifecycleObservations = [];
    const cancellationRetained = cancellationCase.retainedOutput
      ? await createCarrierRetainedStore('cancel-graph')
      : undefined;
    graphCancellation.signal.addEventListener('abort', () => {
      cancellationDeliveredAt = performance.now();
    }, {once: true});
    try {
      assert.equal(
        fixture.strategyFixtureOpen(
          cancellationFixture,
          cancellationCapture.source(),
        ),
        true,
      );
      const setup = teaFamily
        ? fixture.strategyFixtureTeaSubset(cancellationFixture)
        : vecaFamily
          ? fixture.strategyFixtureVecaSubset(cancellationFixture)
          : cancellationCase.retainedOutput
            ? fixture.strategyFixtureSgaRetainedSubset(cancellationFixture)
            : fixture.strategyFixtureSgaSubset(cancellationFixture);
      assert.equal(
        hostRuntime.strategyHostConfigureManagedIdentity(
          setup,
          cancellationCase.cancelDuringFinalization === true,
          false,
          false,
          false,
        ),
        true,
      );
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return configuration => {
            const start = ++managedStarts;
            managedTaskByStart[start] = target.strategyHostNextTask(setup);
            const started = target.strategyModule_local_ManagedStart(
              configuration,
            );
            const execution = checked(started);
            const observed = new Proxy(execution, {
              get(operation, name, operationReceiver) {
                if (name !== 'advance' &&
                    name !== 'advance_finalization' &&
                    name !== 'request_cancel' &&
                    name !== 'execution_stopped' && name !== 'cleanup_refresh') {
                  return Reflect.get(operation, name, operationReceiver);
                }
                if (name === 'advance_finalization') {
                  return quantum => {
                    const result = operation.advance_finalization(quantum);
                    const observation = checked(result);
                    finalizationObservations.push({start, observation});
                    if (cancellationCase.cancelDuringFinalization &&
                        start === 2 &&
                        observation?.complete === false &&
                        observation.work > 0n &&
                        (!cancellationCase.cancelAfterFirstIdentity ||
                          observation.progress >
                            BigInt(cancellationCase.rows)) &&
                        !cancellationScheduled) {
                      sawOperationWork = true;
                      cancellationScheduled = true;
                      setTimeout(() => graphCancellation.abort(), 0);
                    }
                    return result;
                  };
                }
                if (name !== 'advance') {
                  return (...arguments_) => {
                    const result = operation[name](...arguments_);
                    if (name === 'execution_stopped' && result === true &&
                        graphCancellation.signal.aborted &&
                        stopObservedAt === undefined) {
                      stopObservedAt = performance.now();
                    }
                    lifecycleObservations.push({start, name, result});
                    return result;
                  };
                }
                return quantum => {
                  const selectedQuantum = cancellationCase.advanceQuantum ??
                    quantum;
                  const resumeStartedAt = cancellationCase.sortStress &&
                    start === expectedManagedStarts
                    ? performance.now() : 0;
                  const result = operation.advance(selectedQuantum);
                  const observation = checked(result);
                  advanceObservations.push({start, observation});
                  const completedRows =
                    (completedRowsByStart.get(start) ?? 0n) +
                    (observation?.progress ?? 0n);
                  completedRowsByStart.set(start, completedRows);
                  const nearestBridgesFinished =
                    !cancellationCase.fusedNearest ||
                    fusedNearestBridgeRows >= BigInt(cancellationCase.rows + 1);
                  if (cancellationCase.fusedNearest && start === 3) {
                    fusedNearestBridgeRows += observation?.progress ?? 0n;
                  }
                  if (cancellationCase.sortStress && start === expectedManagedStarts) {
                    maxSortResumeMs = Math.max(
                      maxSortResumeMs,
                      performance.now() - resumeStartedAt,
                    );
                    selectedSortAdvances++;
                    selectedSortReportedWork += observation?.work ?? 0n;
                  }
                  if (cancellationCase.cancelAfterSortAdvances !== undefined &&
                      start === expectedManagedStarts && observation?.complete === false &&
                      selectedSortAdvances >=
                        cancellationCase.cancelAfterSortAdvances &&
                      !cancellationScheduled) {
                    sawOperationWork = true;
                    cancellationScheduled = true;
                    setTimeout(() => graphCancellation.abort(), 0);
                  } else if (!cancellationCase.cancelDuringFinalization &&
                      cancellationCase.cancelOnManagedStart === start &&
                      nearestBridgesFinished && observation?.complete === false &&
                      observation.work > 0n && !cancellationScheduled &&
                      completedRows >= BigInt(
                        cancellationCase.minimumCompletedRows ?? 0)) {
                    sawOperationWork = true;
                    cancellationScheduled = true;
                    setTimeout(() => graphCancellation.abort(), 0);
                  } else if (constructionStarts.includes(start) &&
                      observation !== undefined &&
                      !constructionComplete) {
                    constructionProgress += observation.progress;
                    constructionComplete = constructionProgress >=
                      BigInt(cancellationCase.constructionProgress ??
                        cancellationCase.rows * 2);
                  } else if (!cancellationCase.cancelDuringFinalization &&
                      cancellationCase.cancelAfterSortAdvances === undefined &&
                      cancellationCase.cancelOnManagedStart === undefined &&
                      constructionComplete &&
                      start === expectedManagedStarts &&
                      observation?.complete === false &&
                      observation.work > 0n && !cancellationScheduled) {
                    sawOperationWork = true;
                    cancellationScheduled = true;
                    setTimeout(() => graphCancellation.abort(), 0);
                  }
                  return result;
                };
              },
            });
            return {$tag: 1, _0: observed};
          };
        },
      });
      const contribution = localStrategyContribution(
        observedRuntime,
        setup,
        checked,
        cancellationRetained?.configuration,
      );
      cancellationExecution = await runInstalledStrategy(
        setup,
        runtimeCore(hostRuntime),
        [contribution],
        graphCancellation.signal,
      );
      assert.equal(
        managedStarts,
        expectedManagedStarts,
        `${cancellationCase.name}: ${JSON.stringify({
          managedTaskByStart, advanceObservations, lifecycleObservations,
        }, (_, value) => typeof value === 'bigint' ? value.toString() : value)}`,
      );
      if (cancellationCase.cancelTask !== undefined) {
        const cancelledStart = cancellationCase.cancelOnManagedStart ??
          expectedManagedStarts;
        assert.equal(
          managedTaskByStart[cancelledStart],
          cancellationCase.cancelTask,
          `${cancellationCase.name}: ${JSON.stringify({
            managedTaskByStart,
            completed:cancellationExecution.completed.map(value => ({
              task:value.task,realization:value.realization,
              representation:value.outputRepresentation,
            })),
            firstPoll:advanceObservations.find(value =>
              value.start === cancelledStart),
          }, (_, value) => typeof value === 'bigint' ? value.toString() : value)}`,
        );
      }
      if (cancellationCase.fusedNearest) {
        assert(fusedNearestBridgeRows >=
          BigInt(cancellationCase.rows + 1));
      }
      assert(
        constructionProgress >= BigInt(cancellationCase.family === 'time-series'
          ? 0
          : cancellationCase.constructionProgress ??
            cancellationCase.rows * 2),
        `${cancellationCase.name}: construction progress ` +
          `${constructionProgress}, starts ${constructionStarts.join(',')}, ` +
          `managed starts ${managedStarts}`,
      );
      assert.equal(
        sawOperationWork,
        true,
        JSON.stringify({
          advanceObservations,
          status: cancellationExecution.status,
          failure: cancellationExecution.failure?.message,
        }, (_, value) => typeof value === 'bigint' ? value.toString() : value),
      );
      if (cancellationCase.minimumCompletedRows !== undefined) {
        assert(
          (completedRowsByStart.get(cancellationCase.cancelOnManagedStart) ??
            0n) >= BigInt(cancellationCase.minimumCompletedRows),
          cancellationCase.name,
        );
      }
      if (cancellationCase.sortStress) {
        assert(selectedSortAdvances >=
          cancellationCase.cancelAfterSortAdvances);
        assert(Number.isFinite(maxSortResumeMs));
        assert(selectedSortReportedWork > 0n);
      }
      assert.equal(graphCancellation.signal.aborted, true);
      if (cancellationRetained !== undefined) {
        assert(cancellationRetained.leases.length > 0);
      }
      assert.equal(Number.isFinite(cancellationDeliveredAt), true);
      assert.equal(Number.isFinite(stopObservedAt), true);
      assert(stopObservedAt >= cancellationDeliveredAt);
      if (cancellationCase.sortStress) {
        console.log('ACTQL_SORT_CANCEL_PROFILE', JSON.stringify({
          maxResumeMs: maxSortResumeMs,
          stopAfterDeliveryMs: stopObservedAt - cancellationDeliveredAt,
          selectedSortAdvances,
          reportedStepWork: selectedSortReportedWork.toString(),
          keys: stressSortKeys.length + 2,
          textBytesPerKey: stressSortTextBytes,
        }));
      }
      if (cancellationCase.cancelDuringFinalization) {
        assert.equal(
          finalizationObservations.some(value =>
            value.observation?.complete === false &&
            value.observation.work > 0n),
          true,
        );
        if (cancellationCase.cancelAfterFirstIdentity) {
          assert.equal(
            finalizationObservations.some(value =>
              value.start === 2 &&
              value.observation?.complete === false &&
              value.observation.progress > BigInt(cancellationCase.rows)),
            true,
          );
        }
      }
      assert.equal(cancellationExecution.status, 'host-tasks-failed');
      assert.equal(cancellationExecution.failure?.name, 'AbortError');
      assert.deepEqual(
        cancellationExecution.completed.map(value => value.task),
        cancellationCase.completedTasks ??
          (cancellationCase.family === 'time-series' ? [] : [1]),
        `${cancellationCase.name}: ${JSON.stringify({
          managedTaskByStart,
          advanceObservations: advanceObservations.filter(value =>
            value.start >= (cancellationCase.cancelOnManagedStart ?? 1)),
          lifecycleObservations: lifecycleObservations.filter(value =>
            value.start >= (cancellationCase.cancelOnManagedStart ?? 1)),
          completed: cancellationExecution.completed.map(value => ({
            task: value.task,
            outputRepresentation: value.outputRepresentation,
          })),
        }, (_, value) => typeof value === 'bigint' ? value.toString() : value)}`,
      );
    } finally {
      cancellationCapture.close();
      await cancellationExecution?.close();
      if (cancellationExecution) {
        let cleaned = false;
        for (let attempt = 0; attempt < 3 && !cleaned; attempt++) {
          cleaned = await cancellationExecution.cleanup();
          if (cleaned) break;
          assert.equal(cancellationExecution.cleanupPending(), true);
        }
        assert.equal(
          cleaned,
          true,
          JSON.stringify({
            usage: cancellationExecution.usage(),
            failurePending: cancellationExecution.failure?.cleanupPending,
            failureStatus:
              cancellationExecution.failure?.cleanupHandle?.status?.(),
            lifecycleObservations,
          }, (_, value) =>
            typeof value === 'bigint' ? value.toString() : value),
        );
        assert.equal(
          lifecycleObservations.some(value =>
            value.name === 'execution_stopped' && value.result === true),
          true,
          `${cancellationCase.name}: ${JSON.stringify(
            {
              status: cancellationExecution.status,
              failure: cancellationExecution.failure?.name,
              failureMessage: cancellationExecution.failure?.message,
              failureCause: cancellationExecution.failure?.cause,
              aborted: graphCancellation.signal.aborted,
              managedStarts,
              constructionProgress,
              lifecycleObservations,
              finalizationObservations,
            },
            (_, value) => typeof value === 'bigint' ? value.toString() : value,
          )}`,
        );
        assert.equal(
          lifecycleObservations.some(value =>
            value.name === 'cleanup_refresh' && value.result === true),
          true,
        );
        assert.equal(cancellationExecution.cleanupPending(), false);
        assert.equal(cancellationExecution.usage().heldBytes, 0n);
        assert.equal(
          cancellationExecution.usage().reservedExecutionBytes,
          0n,
        );
      }
      await cancellationRetained?.close();
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
  const zeroInputProgram = {
    version: 'actql/0.1',
    id: 'p',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a',
      inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [
        {filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'},
      ],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'values_a',
      inputs: {},
      steps: [{
        values: {
          schema: {
            id: {type: 'number', nullable: true},
            label: {type: 'string', nullable: false},
          },
          rows: [{id: null, label: 'none'}, {id: 1, label: 'one'}],
        },
        as: 'out',
      }],
      results: {r: {from: 'out', fields: ['id', 'label']}},
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
      steps: [{select: ['id', 'label'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'label']}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
      steps: [{select: ['label', 'id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['label', 'id']}},
    }],
    results: {source: {from: {stage: 'a', result: 'r'}}},
  };
  const splitValuesProgram = structuredClone(zeroInputProgram);
  const capturedRelationChainProgram = structuredClone(zeroInputProgram);
  const capturedChainStage = capturedRelationChainProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  capturedChainStage.inputs = {
    x: {result: {stage: 'a', result: 'r'}},
  };
  capturedChainStage.steps = [
    {from: 'x', filter: 'id > 2', as: 'filtered'},
    {from: 'filtered', select: ['id'], as: 'out'},
  ];
  capturedChainStage.results.r.fields = ['id'];
  for (const consumer of capturedRelationChainProgram.stages.filter(
    stage => stage.id.startsWith('consumer_'))) {
    consumer.steps[0].select = ['id'];
    consumer.results.r.fields = ['id'];
  }
  const capturedCountChainProgram = structuredClone(capturedRelationChainProgram);
  const capturedCountStage = capturedCountChainProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  capturedCountStage.steps = [
    {from: 'x', group: {by: [], aggregates: {n: {fn: 'count'}}}, as: 'counted'},
    {from: 'counted', filter: 'n > 0', as: 'filtered'},
    {from: 'filtered', select: ['n'], as: 'out'},
  ];
  capturedCountStage.results.r.fields = ['n'];
  for (const consumer of capturedCountChainProgram.stages.filter(
    stage => stage.id.startsWith('consumer_'))) {
    consumer.steps[0].select = ['n'];
    consumer.results.r.fields = ['n'];
  }
  const capturedKeyedCountChainProgram = structuredClone(capturedRelationChainProgram);
  const capturedKeyedCountStage = capturedKeyedCountChainProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  capturedKeyedCountStage.steps = [
    {from: 'x', group: {by: ['id'], aggregates: {n: {fn: 'count'}}}, as: 'counted'},
    {from: 'counted', filter: 'n > 0', as: 'filtered'},
    {from: 'filtered', select: ['id'], as: 'out'},
  ];
  const capturedUnpivotChainProgram = structuredClone(capturedRelationChainProgram);
  const capturedUnpivotStage = capturedUnpivotChainProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  capturedUnpivotStage.steps = [
    {from: 'x', unpivot: {
      columns: ['id'], keep: [], name_column: 'metric',
      value_column: 'value',
    }, as: 'expanded'},
    {from: 'expanded', filter: 'value > 2', as: 'filtered'},
    {from: 'filtered', select: ['value'], as: 'out'},
  ];
  capturedUnpivotStage.results.r.fields = ['value'];
  for (const consumer of capturedUnpivotChainProgram.stages.filter(
    stage => stage.id.startsWith('consumer_'))) {
    consumer.steps[0].select = ['value'];
    consumer.results.r.fields = ['value'];
  }
  const capturedWindowChainProgram = structuredClone(capturedRelationChainProgram);
  const capturedWindowStage = capturedWindowChainProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  capturedWindowStage.steps = [
    {from: 'x', row_window: {kind: 'fixed', time: 'id', size: 10},
      as: 'windowed'},
    {from: 'windowed', filter: 'id > 0', as: 'filtered'},
    {from: 'filtered', select: ['id'], as: 'out'},
  ];
  const splitValuesStage = splitValuesProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesStage.steps[0].as = 'values_rows';
  splitValuesStage.steps.push({
    from: 'values_rows', filter: 'id > 0', as: 'out',
  });
  const splitValuesSelectProgram = structuredClone(zeroInputProgram);
  const splitValuesSelectStage = splitValuesSelectProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesSelectStage.steps[0].as = 'values_rows';
  splitValuesSelectStage.steps.push({
    from: 'values_rows', select: ['id', 'label'], as: 'out',
  });
  const splitValuesDeriveProgram = structuredClone(zeroInputProgram);
  const splitValuesDeriveStage = splitValuesDeriveProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesDeriveStage.steps[0].as = 'values_rows';
  splitValuesDeriveStage.steps.push({
    from: 'values_rows', derive: {copy: 'label'}, as: 'out',
  });
  splitValuesDeriveStage.results.r.fields = ['id', 'label', 'copy'];
  const splitValuesTakeProgram = structuredClone(zeroInputProgram);
  const splitValuesTakeStage = splitValuesTakeProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesTakeStage.steps[0].as = 'values_rows';
  splitValuesTakeStage.steps.push({
    from: 'values_rows', take: 1, as: 'out',
  });
  const splitValuesAssertProgram = structuredClone(zeroInputProgram);
  const splitValuesAssertStage = splitValuesAssertProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesAssertStage.steps[0].as = 'values_rows';
  splitValuesAssertStage.steps.push({
    from: 'values_rows', assert_rows: {where: '1 > 0'}, as: 'out',
  });
  const splitValuesUniqueProgram = structuredClone(zeroInputProgram);
  const splitValuesUniqueStage = splitValuesUniqueProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesUniqueStage.steps[0].as = 'values_rows';
  splitValuesUniqueStage.steps.push({
    from: 'values_rows', assert_rows: {unique_by: ['label']}, as: 'out',
  });
  const splitValuesSortTakeProgram = structuredClone(zeroInputProgram);
  const splitValuesSortTakeStage = splitValuesSortTakeProgram.stages.find(
    stage => stage.id === 'values_a',
  );
  splitValuesSortTakeStage.steps[0].as = 'values_rows';
  splitValuesSortTakeStage.steps.push(
    {from: 'values_rows', sort: [
      {field: 'id', dir: 'desc', nulls: 'last'},
    ], as: 'ordered'},
    {from: 'ordered', take: 1, as: 'out'},
  );
  const separateSortTakeProgram = structuredClone(zeroInputProgram);
  separateSortTakeProgram.stages.splice(2, 0, {
    id: 'ordered',
    inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
    steps: [
      {from: 'x', sort: [
        {field: 'id', dir: 'desc', nulls: 'last'},
      ], as: 'ordered_rows'},
      {from: 'ordered_rows', take: 1, as: 'out'},
    ],
    results: {r: {from: 'out', fields: ['id', 'label']}},
  });
  for (const consumer of separateSortTakeProgram.stages.filter(
    stage => stage.id === 'consumer_a' || stage.id === 'consumer_b')) {
    consumer.inputs.x.result.stage = 'ordered';
  }
  const longSelectedSortTakeProgram = structuredClone(separateSortTakeProgram);
  longSelectedSortTakeProgram.stages.find(stage =>
    stage.id === 'values_a').steps[0].values.rows[1].label = 'a'.repeat(512);
  const separateFilterSortTakeProgram = structuredClone(
    separateSortTakeProgram,
  );
  const filteredOrderedStage = separateFilterSortTakeProgram.stages.find(
    stage => stage.id === 'ordered',
  );
  filteredOrderedStage.steps.unshift({from: 'x', filter: 'true', as: 'filtered'});
  filteredOrderedStage.steps[1].from = 'filtered';
  const chainedFilterSortTakeProgram = structuredClone(
    separateSortTakeProgram,
  );
  const chainedOrderedIndex = chainedFilterSortTakeProgram.stages.findIndex(
    stage => stage.id === 'ordered',
  );
  chainedFilterSortTakeProgram.stages.splice(chainedOrderedIndex, 0, {
    id: 'filtered',
    inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
    steps: [{from: 'x', filter: 'true', as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'label']}},
  });
  chainedFilterSortTakeProgram.stages.find(
    stage => stage.id === 'ordered',
  ).inputs.x.result.stage = 'filtered';
  const appendProgram = structuredClone(zeroInputProgram);
  appendProgram.stages.splice(1, 3, {
    id: 'append_a',
    inputs: {},
    steps: [
      {values: {
        schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 1}],
      }, as: 'left_rows'},
      {values: {
        schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 2}],
      }, as: 'right_rows'},
      {from: 'left_rows', append: {with: 'right_rows'}, as: 'out'},
    ],
    results: {r: {from: 'out', fields: ['id']}},
  }, ...['a', 'b'].map(id => ({
    id: `append_consumer_${id}`,
    inputs: {x: {result: {stage: 'append_a', result: 'r'}}},
    steps: [{select: ['id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}},
  })));
  const appendFilterProgram = structuredClone(appendProgram);
  const appendFilterStage = appendFilterProgram.stages.find(
    stage => stage.id === 'append_a');
  const appendSources = appendFilterStage.steps.slice(0, 2).map((step, index) => ({
    id: `append_source_${index}`,
    inputs: {},
    steps: [{...structuredClone(step), as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}},
  }));
  appendFilterStage.inputs = {
    l: {result: {stage: 'append_source_0', result: 'r'}},
    r: {result: {stage: 'append_source_1', result: 'r'}},
  };
  appendFilterStage.steps = [
    {from: 'l', append: {with: 'r'}, as: 'appended'},
    {from: 'appended', filter: 'id > 1', as: 'out'},
  ];
  appendFilterProgram.stages.splice(1, 0, ...appendSources);
  const filterThenAppendProgram = structuredClone(appendFilterProgram);
  filterThenAppendProgram.stages = filterThenAppendProgram.stages.filter(
    stage => stage.id !== 'append_source_0');
  const filterThenAppendStage = filterThenAppendProgram.stages.find(
    stage => stage.id === 'append_a');
  filterThenAppendStage.inputs.l.result.stage = 'a';
  filterThenAppendStage.steps = [
    {from: 'l', filter: 'id > 1', as: 'filtered'},
    {from: 'filtered', append: {with: 'r'}, as: 'out'},
  ];
  const nestProgram = structuredClone(zeroInputProgram);
  nestProgram.stages.splice(1, 3, {
    id: 'nest_parents',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        key: {type: 'number', nullable: true},
      },
      rows: [
        {id: 1, key: 1},
        {id: 2, key: 1},
        {id: 3, key: null},
        {id: 4, key: 2},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'key']}},
  }, {
    id: 'nest_children',
    inputs: {},
    steps: [{values: {
      schema: {
        child_id: {type: 'number', nullable: false},
        key: {type: 'number', nullable: true},
        value: {type: 'number', nullable: true},
      },
      rows: [
        {child_id: 2, key: 1, value: null},
        {child_id: 1, key: 1, value: 10},
        {child_id: 3, key: null, value: 30},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['child_id', 'key', 'value']}},
  }, {
    id: 'nested',
    inputs: {
      parents: {result: {stage: 'nest_parents', result: 'r'}},
      children: {result: {stage: 'nest_children', result: 'r'}},
    },
    from: 'parents',
    steps: [{nest: {
      with: 'children',
      on: [{left: 'key', right: 'key'}],
      into: 'items',
      fields: [{amount: 'value'}],
      max_items: 2,
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'items', 'key']}},
  }, ...['a', 'b'].map(id => ({
    id: `nest_consumer_${id}`,
    inputs: {x: {result: {stage: 'nested', result: 'r'}}},
    steps: [{select: id === 'a'
      ? ['id', 'key', 'items']
      : ['items', 'id', 'key'], as: 'out'}],
    results: {r: {from: 'out', fields: id === 'a'
      ? ['id', 'key', 'items']
      : ['items', 'id', 'key']}},
  })));
  const nestUnwrapProgram = structuredClone(nestProgram);
  const nestConsumerIndex = nestUnwrapProgram.stages.findIndex(stage =>
    stage.id === 'nest_consumer_a');
  nestUnwrapProgram.stages.splice(nestConsumerIndex, 0, {
    id: 'unnested',
    inputs: {x: {result: {stage: 'nested', result: 'r'}}},
    steps: [
      {from: 'x', unnest: {column: 'items', as: 'item', outer: false},
        as: 'expanded'},
      {from: 'expanded', filter: 'id > 1', as: 'filtered'},
      {from: 'filtered', select: ['id', 'item'], as: 'out'},
    ],
    results: {r: {from: 'out', fields: ['id', 'item']}},
  });
  for (const consumer of nestUnwrapProgram.stages.filter(stage =>
    stage.id.startsWith('nest_consumer_'))) {
    consumer.inputs.x.result.stage = 'unnested';
    consumer.steps[0].select = consumer.id.endsWith('_a')
      ? ['id', 'item'] : ['item', 'id'];
    consumer.results.r.fields = consumer.steps[0].select;
  }
  const valuesVariantProgram = (schema, rows, fields, reversed) => {
    const variant = structuredClone(zeroInputProgram);
    variant.stages.splice(1, 3, {
      id: 'values_a',
      inputs: {},
      steps: [{values: {schema, rows}, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, {
      id: 'consumer_a',
      inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
      steps: [{select: fields, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, {
      id: 'consumer_b',
      inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
      steps: [{select: reversed, as: 'out'}],
      results: {r: {from: 'out', fields: reversed}},
    });
    return variant;
  };
  const emptyValuesProgram = valuesVariantProgram(
    {id: {type: 'number', nullable: false}},
    [],
    ['id'],
    ['id'],
  );
  const nestedValuesProgram = valuesVariantProgram({
    items: {
      type: 'array',
      nullable: false,
      items: {
        type: 'object',
        nullable: false,
        fields: {
          name: {type: 'string', nullable: false},
          score: {type: 'number', nullable: false},
        },
      },
    },
    meta: {
      type: 'object',
      nullable: false,
      fields: {active: {type: 'boolean', nullable: false}},
    },
  }, [{
    items: {literal: [{name: 'a', score: 1}, {name: 'b', score: 2}]},
    meta: {literal: {active: true}},
  }], ['items', 'meta'], ['meta', 'items']);
  const selectProgram = structuredClone(zeroInputProgram);
  selectProgram.stages.splice(1, 3, {
    id: 'select_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: true},
      },
      rows: [{id: 1, amount: 10}, {id: 2, amount: null}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount']}},
  }, {
    id: 'selected',
    inputs: {x: {result: {stage: 'select_values', result: 'r'}}},
    steps: [{select: [{total: 'amount'}, 'id'], as: 'out'}],
    results: {r: {from: 'out', fields: ['total', 'id']}},
  }, ...['a', 'b'].map(id => ({
    id: `select_consumer_${id}`,
    inputs: {x: {result: {stage: 'selected', result: 'r'}}},
    steps: [{select: id === 'a' ? ['total', 'id'] : ['id', 'total'],
      as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a' ? ['total', 'id'] : ['id', 'total'],
    }},
  })));
  const snapshotDeriveProgram = structuredClone(zeroInputProgram);
  const deriveFields = ['id', 'amount', 'saved', 'next'];
  snapshotDeriveProgram.stages.splice(1, 3, {
    id: 'derive_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: true},
      },
      rows: [{id: 1, amount: 10}, {id: 2, amount: null}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount']}},
  }, {
    id: 'derived',
    inputs: {x: {result: {stage: 'derive_values', result: 'r'}}},
    steps: [{derive: {
      saved: 'id',
      next: 'id + $minimum',
    }, as: 'out'}],
    results: {r: {from: 'out', fields: deriveFields}},
  }, ...['a', 'b'].map(id => ({
    id: `derive_consumer_${id}`,
    inputs: {x: {result: {stage: 'derived', result: 'r'}}},
    steps: [{select: id === 'a'
      ? deriveFields
      : [...deriveFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a'
        ? deriveFields
        : [...deriveFields].reverse(),
    }},
  })));
  const sortProgram = structuredClone(zeroInputProgram);
  sortProgram.stages.splice(1, 3, {
    id: 'sort_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: true},
      },
      rows: [
        {id: 2, amount: 20},
        {id: 1, amount: null},
        {id: 1, amount: 30},
        {id: 2, amount: null},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount']}},
  }, {
    id: 'sorted',
    inputs: {x: {result: {stage: 'sort_values', result: 'r'}}},
    steps: [{sort: [
      {field: 'amount', dir: 'desc', nulls: 'first'},
      {id: 'asc'},
    ], as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount']}},
  }, ...['a', 'b'].map(id => ({
    id: `sort_consumer_${id}`,
    inputs: {x: {result: {stage: 'sorted', result: 'r'}}},
    steps: [{select: id === 'a' ? ['id', 'amount'] : ['amount', 'id'],
      as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a' ? ['id', 'amount'] : ['amount', 'id'],
    }},
  })));
  const dedupeProgram = structuredClone(zeroInputProgram);
  dedupeProgram.stages.splice(1, 3, {
    id: 'dedupe_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
        group: {type: 'string', nullable: true},
        bucket: {type: 'number', nullable: false},
      },
      rows: [
        {id: 1, amount: 10, group: null, bucket: 1},
        {id: 2, amount: 30, group: null, bucket: 1},
        {id: 3, amount: 20, group: 'a', bucket: 2},
        {id: 4, amount: 40, group: 'a', bucket: 2},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount', 'group', 'bucket']}},
  }, {
    id: 'deduped',
    inputs: {x: {result: {stage: 'dedupe_values', result: 'r'}}},
    steps: [{dedupe_rows: {
      by: ['group', 'bucket'],
      order_by: [{amount: 'desc'}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'amount', 'group', 'bucket']}},
  }, ...['a', 'b'].map(id => ({
    id: `dedupe_consumer_${id}`,
    inputs: {x: {result: {stage: 'deduped', result: 'r'}}},
    steps: [{select: id === 'a'
      ? ['id', 'amount', 'group', 'bucket']
      : ['bucket', 'group', 'amount', 'id'], as: 'out'}],
    results: {r: {
      from: 'out',
      fields: id === 'a'
        ? ['id', 'amount', 'group', 'bucket']
        : ['bucket', 'group', 'amount', 'id'],
    }},
  })));
  const dedupeFilterProgram = structuredClone(dedupeProgram);
  const dedupeFilterStage = dedupeFilterProgram.stages.find(
    stage => stage.id === 'deduped',
  );
  dedupeFilterStage.steps = [
    {...dedupeFilterStage.steps[0], as: 'deduped_rows'},
    {from: 'deduped_rows', filter: 'amount > 30', as: 'filtered'},
    {from: 'filtered', select: ['id', 'amount', 'group', 'bucket'], as: 'out'},
  ];
  const topKProgram = partitioned => {
    const variant = structuredClone(zeroInputProgram);
    const fields = ['id', 'amount', 'group'];
    variant.stages.splice(1, 3, {
      id: 'top_k_values',
      inputs: {},
      steps: [{values: {
        schema: {
          id: {type: 'number', nullable: false},
          amount: {type: 'number', nullable: true},
          group: {type: 'string', nullable: true},
        },
        rows: [
          {id: 1, amount: 10, group: null},
          {id: 2, amount: null, group: null},
          {id: 3, amount: 30, group: 'a'},
          {id: 4, amount: 20, group: 'a'},
        ],
      }, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, {
      id: 'ranked',
      inputs: {x: {result: {stage: 'top_k_values', result: 'r'}}},
      steps: [
        {assert_rows: {unique_by: ['id']}, as: 'unique'},
        {from: 'unique', ...(partitioned ? {
          top_k_by: {
            partition_by: ['group'],
            k: 1,
            by: [{field: 'amount', dir: 'desc', nulls: 'first'}],
          },
        } : {
          top_k: {
            k: 2,
            by: [
              {field: 'amount', dir: 'desc', nulls: 'first'},
              {id: 'asc'},
            ],
          },
        }), as: 'out'},
      ],
      results: {r: {from: 'out', fields}},
    }, ...['a', 'b'].map(id => ({
      id: `top_k_consumer_${id}`,
      inputs: {x: {result: {stage: 'ranked', result: 'r'}}},
      steps: [{select: id === 'a' ? fields : [...fields].reverse(), as: 'out'}],
      results: {r: {
        from: 'out', fields: id === 'a' ? fields : [...fields].reverse(),
      }},
    })));
    return variant;
  };
  const globalTopKProgram = topKProgram(false);
  const partitionedTopKProgram = topKProgram(true);
  const groupProgram = structuredClone(zeroInputProgram);
  groupProgram.stages.splice(1, 3, {
    id: 'group_values',
    inputs: {},
    steps: [{values: {
      schema: {id: {type: 'number', nullable: true}},
      rows: [{id: null}, {id: 1}, {id: 1}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}},
  }, {
    id: 'group_a',
    inputs: {x: {result: {stage: 'group_values', result: 'r'}}},
    steps: [{group: {by: ['id'], aggregates: {n: {fn: 'count'}}}, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'n']}},
  }, ...['a', 'b'].map(id => ({
    id: `group_consumer_${id}`,
    inputs: {x: {result: {stage: 'group_a', result: 'r'}}},
    steps: [{select: id === 'a' ? ['id', 'n'] : ['n', 'id'], as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a' ? ['id', 'n'] : ['n', 'id'],
    }},
  })));
  // A general group: the extra max aggregate leaves the count kernel.
  const directGroupProgram = structuredClone(groupProgram);
  directGroupProgram.stages.find(stage => stage.id === 'group_a').steps = [
    {group: {by: ['id'], aggregates: {
      n: {fn: 'count'}, highest: {fn: 'max', field: 'id'},
    }}, as: 'out'},
  ];
  const globalCountProgram = structuredClone(groupProgram);
  const globalCountStage = globalCountProgram.stages.find(
    stage => stage.id === 'group_a',
  );
  globalCountStage.steps[0].group = {
    by: [],
    aggregates: {n: {fn: 'count'}, present: {fn: 'count', field: 'id'}},
  };
  globalCountStage.results.r.fields = ['n', 'present'];
  for (const stage of globalCountProgram.stages.filter(
    stage => stage.id.startsWith('group_consumer_'),
  )) {
    const fields = stage.id.endsWith('_a')
      ? ['n', 'present'] : ['present', 'n'];
    stage.steps[0].select = fields;
    stage.results.r.fields = fields;
  }
  const nestedGlobalCountProgram = structuredClone(globalCountProgram);
  const nestedCountValues = nestedGlobalCountProgram.stages.find(
    stage => stage.id === 'group_values',
  );
  nestedCountValues.steps[0].values.schema.payload = {
    type: 'array', nullable: false,
    items: {type: 'number', nullable: false},
  };
  nestedCountValues.results.r.fields = ['id', 'payload'];
  const sameStageGlobalCountProgram = structuredClone(globalCountProgram);
  const countValuesStage = sameStageGlobalCountProgram.stages.find(
    stage => stage.id === 'group_values',
  );
  const sameStageCount = sameStageGlobalCountProgram.stages.find(
    stage => stage.id === 'group_a',
  );
  sameStageCount.inputs = {};
  sameStageCount.steps = [
    {...countValuesStage.steps[0], as: 'source'},
    {from: 'source', group: sameStageCount.steps[0].group, as: 'counted'},
    {from: 'counted', take: 1, as: 'out'},
  ];
  sameStageGlobalCountProgram.stages = sameStageGlobalCountProgram.stages
    .filter(stage => stage.id !== 'group_values');
  const sameStageCountIfProgram = structuredClone(sameStageGlobalCountProgram);
  const sameStageCountIf = sameStageCountIfProgram.stages.find(
    stage => stage.id === 'group_a');
  sameStageCountIf.steps[0].values.schema = {
    flag: {type: 'boolean', nullable: true},
  };
  sameStageCountIf.steps[0].values.rows = [
    {flag: true}, {flag: false}, {flag: null}, {flag: true},
  ];
  sameStageCountIf.steps[1].group.aggregates = {
    hits: {fn: 'count_if', field: 'flag'}, n: {fn: 'count'},
  };
  sameStageCountIf.results.r.fields = ['hits', 'n'];
  for (const stage of sameStageCountIfProgram.stages.filter(
    stage => stage.id.startsWith('group_consumer_'))) {
    const fields = stage.id.endsWith('_a') ? ['hits', 'n'] : ['n', 'hits'];
    stage.steps[0].select = fields;
    stage.results.r.fields = fields;
  }
  const sameStageKeyedCountProgram = structuredClone(sameStageGlobalCountProgram);
  const sameStageKeyedCount = sameStageKeyedCountProgram.stages.find(
    stage => stage.id === 'group_a');
  sameStageKeyedCount.steps[1].group.by = ['id'];
  sameStageKeyedCount.results.r.fields = ['id', 'n', 'present'];
  for (const stage of sameStageKeyedCountProgram.stages.filter(
    stage => stage.id.startsWith('group_consumer_'),
  )) {
    const fields = stage.id.endsWith('_a')
      ? ['id', 'n', 'present'] : ['present', 'n', 'id'];
    stage.steps[0].select = fields;
    stage.results.r.fields = fields;
  }
  const watermarkProgram = (threshold, latePolicy) => {
    const variant = structuredClone(zeroInputProgram);
    const fields = [
      'id',
      'time',
      'watermark_ms',
      'watermark_late',
      'watermark_decision',
    ];
    variant.stages.splice(1, 3, {
      id: 'watermark_values',
      inputs: {},
      steps: [{values: {
        schema: {
          id: {type: 'number', nullable: false},
          time: {type: 'number', nullable: false},
        },
        rows: [{id: 1, time: 100}, {id: 2, time: 80}, {id: 3, time: 95}],
      }, as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'time']}},
    }, {
      id: 'watermarked',
      inputs: {x: {result: {stage: 'watermark_values', result: 'r'}}},
      steps: [{watermark_rows: {
        time: 'time',
        late_policy: latePolicy,
        ...threshold,
      }, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, ...['a', 'b'].map(id => ({
      id: `watermark_consumer_${id}`,
      inputs: {x: {result: {stage: 'watermarked', result: 'r'}}},
      steps: [{select: id === 'a' ? fields : [...fields].reverse(), as: 'out'}],
      results: {r: {
        from: 'out',
        fields: id === 'a' ? fields : [...fields].reverse(),
      }},
    })));
    return variant;
  };
  const fixedWatermarkProgram = watermarkProgram(
    {watermark_ms: {$param: 'minimum'}},
    'mark',
  );
  const prefixWatermarkProgram = watermarkProgram(
    {max_skew: {$param: 'minimum'}},
    'drop',
  );
  const rowWindowProgram = kind => {
    const variant = structuredClone(zeroInputProgram);
    const fields = ['at', 'id', 'window_start', 'window_end'];
    const window = {
      kind,
      time: 'at',
      size: {$param: 'minimum'},
    };
    if (kind === 'sliding') window.step = {$param: 'minimum'};
    variant.stages.splice(1, 3, {
      id: 'window_values',
      inputs: {},
      steps: [{values: {
        schema: {
          at: {type: 'number', nullable: false},
          id: {type: 'number', nullable: false},
        },
        rows: [{at: -1, id: 1}, {at: 2, id: 2}, {at: 12, id: 3}],
      }, as: 'out'}],
      results: {r: {from: 'out', fields: ['at', 'id']}},
    }, {
      id: 'windowed',
      inputs: {x: {result: {stage: 'window_values', result: 'r'}}},
      steps: [{row_window: window, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, ...['a', 'b'].map(id => ({
      id: `row_window_consumer_${id}`,
      inputs: {x: {result: {stage: 'windowed', result: 'r'}}},
      steps: [{select: id === 'a' ? fields : [...fields].reverse(), as: 'out'}],
      results: {r: {
        from: 'out',
        fields: id === 'a' ? fields : [...fields].reverse(),
      }},
    })));
    return variant;
  };
  const fixedRowWindowProgram = rowWindowProgram('fixed');
  const slidingRowWindowProgram = rowWindowProgram('sliding');
  const windowGroupProgram = structuredClone(zeroInputProgram);
  const windowGroupFields = ['lowest', 'window_end', 'window_start'];
  windowGroupProgram.stages.splice(1, 3, {
    id: 'window_grouped',
    inputs: {},
    steps: [{values: {
      schema: {
        amount: {type: 'number', nullable: false},
        at: {type: 'number', nullable: false},
      },
      rows: [
        {amount: 0, at: 1},
        {amount: 10, at: 2},
        {amount: 20, at: 11},
      ],
    }, as: 'seed'}, {
      from: 'seed',
      row_window: {kind: 'fixed', time: 'at', size: 10},
      as: 'windowed',
    }, {
      from: 'windowed',
      window_group: {by: [], aggregates: {
        lowest: {
          fn: 'min',
          expr: '100 / amount',
          filter: 'amount > 0',
        },
      }},
      as: 'out',
    }],
    results: {r: {from: 'out', fields: windowGroupFields}},
  }, ...['a', 'b'].map(id => ({
    id: `window_group_consumer_${id}`,
    inputs: {x: {result: {stage: 'window_grouped', result: 'r'}}},
    steps: [{select: id === 'a'
      ? windowGroupFields
      : [...windowGroupFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out',
      fields: id === 'a'
        ? windowGroupFields
        : [...windowGroupFields].reverse(),
    }},
  })));
  const lagProgram = structuredClone(zeroInputProgram);
  const lagFields = ['amount', 'group', 'id', 'previous'];
  lagProgram.stages.splice(1, 3, {
    id: 'lagged',
    inputs: {},
    steps: [{values: {
      schema: {
        amount: {type: 'number', nullable: true},
        group: {type: 'string', nullable: true},
        id: {type: 'number', nullable: false},
      },
      rows: [
        {amount: 30, group: 'a', id: 3},
        {amount: 20, group: null, id: 2},
        {amount: 10, group: 'a', id: 1},
        {amount: null, group: null, id: 4},
        {amount: 30, group: 'a', id: 5},
      ],
    }, as: 'seed'},
    {from: 'seed', assert_rows: {unique_by: ['id']}, as: 'unique'},
    {from: 'unique', lag: {
      partition_by: ['group', 'group'],
      order_by: [{amount: 'desc'}],
      field: 'amount',
      output: 'previous',
      offset: {$param: 'minimum'},
    }, as: 'out'}],
    results: {r: {from: 'out', fields: lagFields}},
  }, ...['a', 'b'].map(id => ({
    id: `lag_consumer_${id}`,
    inputs: {x: {result: {stage: 'lagged', result: 'r'}}},
    steps: [{select: id === 'a' ? lagFields : [...lagFields].reverse(),
      as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a' ? lagFields : [...lagFields].reverse(),
    }},
  })));
  const analyticProgram = structuredClone(zeroInputProgram);
  const analyticFields = ['amount', 'group', 'id', 'lowest'];
  analyticProgram.stages.splice(1, 3, {
    id: 'analytic_rows',
    inputs: {},
    steps: [{values: {
      schema: {
        amount: {type: 'number', nullable: true},
        group: {type: 'string', nullable: true},
        id: {type: 'number', nullable: false},
      },
      rows: [
        {amount: 30, group: 'a', id: 3},
        {amount: 20, group: null, id: 2},
        {amount: 10, group: 'a', id: 1},
        {amount: 0, group: null, id: 4},
        {amount: 30, group: 'a', id: 5},
      ],
    }, as: 'seed'}, {
      from: 'seed',
      analytic: {
        partition_by: ['group'],
        order_by: [{id: 'asc'}],
        frame: {start: 'unbounded_preceding', end: 'current_row'},
        functions: {lowest: {
          fn: 'min',
          expr: 'amount + 1',
          filter: 'amount > 0',
        }},
      },
      as: 'out',
    }],
    results: {r: {from: 'out', fields: analyticFields}},
  }, ...['a', 'b'].map(id => ({
    id: `analytic_consumer_${id}`,
    inputs: {x: {result: {stage: 'analytic_rows', result: 'r'}}},
    steps: [{select: id === 'a'
      ? analyticFields
      : [...analyticFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out',
      fields: id === 'a'
        ? analyticFields
        : [...analyticFields].reverse(),
    }},
  })));
  const unpivotProgram = structuredClone(zeroInputProgram);
  const unpivotFields = ['id', 'metric', 'value'];
  unpivotProgram.stages.splice(1, 3, {
    id: 'unpivot_values',
    inputs: {},
    steps: [{values: {
      schema: {
        a: {type: 'number', nullable: true},
        b: {type: 'number', nullable: true},
        id: {type: 'number', nullable: false},
      },
      rows: [{a: 10, b: null, id: 1}, {a: null, b: 20, id: 2}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['a', 'b', 'id']}},
  }, {
    id: 'unpivoted',
    inputs: {x: {result: {stage: 'unpivot_values', result: 'r'}}},
    steps: [{unpivot: {
      columns: ['a', 'b', 'a'],
      keep: ['id'],
      name_column: 'metric',
      value_column: 'value',
    }, as: 'out'}],
    results: {r: {from: 'out', fields: unpivotFields}},
  }, ...['a', 'b'].map(id => ({
    id: `unpivot_consumer_${id}`,
    inputs: {x: {result: {stage: 'unpivoted', result: 'r'}}},
    steps: [{select: id === 'a'
      ? unpivotFields
      : [...unpivotFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a'
        ? unpivotFields
        : [...unpivotFields].reverse(),
    }},
  })));
  const sameStageUnpivotProgram = structuredClone(unpivotProgram);
  const sameStageUnpivotValues = sameStageUnpivotProgram.stages.find(stage =>
    stage.id === 'unpivot_values');
  const sameStageUnpivotIndex = sameStageUnpivotProgram.stages.findIndex(
    stage => stage.id === 'unpivoted');
  const sameStageUnpivotStep = structuredClone(
    sameStageUnpivotProgram.stages[sameStageUnpivotIndex].steps[0]);
  sameStageUnpivotValues.steps.push({
    from: 'out', ...sameStageUnpivotStep, as: 'expanded',
  });
  sameStageUnpivotValues.results.r = {
    from: 'expanded', fields: unpivotFields,
  };
  sameStageUnpivotProgram.stages.splice(sameStageUnpivotIndex, 1);
  for (const stage of sameStageUnpivotProgram.stages.filter(stage =>
    stage.id.startsWith('unpivot_consumer_'))) {
    stage.inputs.x.result.stage = 'unpivot_values';
  }
  const unpivotFilterProgram = structuredClone(unpivotProgram);
  const unpivotFilterStage = unpivotFilterProgram.stages.find(stage =>
    stage.id === 'unpivoted');
  unpivotFilterStage.steps[0].as = 'expanded';
  unpivotFilterStage.steps.push({from: 'expanded', filter: 'id > 1',
    as: 'out'});
  const pivotProgram = structuredClone(zeroInputProgram);
  const pivotFields = ['id', 'open', 'won'];
  pivotProgram.stages.splice(1, 3, {
    id: 'pivot_values',
    inputs: {},
    steps: [{values: {
      schema: {
        amount: {type: 'number', nullable: true},
        id: {type: 'number', nullable: false},
        status: {type: 'string', nullable: true},
      },
      rows: [
        {amount: 20, id: 2, status: 'open'},
        {amount: 10, id: 1, status: 'won'},
        {amount: 30, id: 2, status: 'open'},
        {amount: null, id: 1, status: 'open'},
        {amount: 99, id: 1, status: 'other'},
        {amount: 5, id: 1, status: null},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['amount', 'id', 'status']}},
  }, {
    id: 'pivoted',
    inputs: {x: {result: {stage: 'pivot_values', result: 'r'}}},
    steps: [{pivot: {
      index: ['id', 'id'],
      column: 'status',
      values: ['won', 'open'],
      value: 'amount',
      aggregate: 'count',
    }, as: 'out'}],
    results: {r: {from: 'out', fields: pivotFields}},
  }, ...['a', 'b'].map(id => ({
    id: `pivot_consumer_${id}`,
    inputs: {x: {result: {stage: 'pivoted', result: 'r'}}},
    steps: [{select: id === 'a'
      ? pivotFields
      : [...pivotFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a'
        ? pivotFields
        : [...pivotFields].reverse(),
    }},
  })));
  const unnestProgram = structuredClone(zeroInputProgram);
  const unnestFields = ['id', 'item', 'items', 'position'];
  unnestProgram.stages.splice(1, 3, {
    id: 'unnest_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        items: {
          type: 'array',
          nullable: true,
          items: {type: 'number', nullable: true},
          max_items: 2,
        },
      },
      rows: [
        {id: 1, items: [2, null]},
        {id: 2, items: []},
        {id: 3, items: null},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'items']}},
  }, {
    id: 'unnested',
    inputs: {x: {result: {stage: 'unnest_values', result: 'r'}}},
    steps: [{unnest: {
      column: 'items',
      as: 'item',
      with_index: 'position',
      outer: true,
    }, as: 'out'}],
    results: {r: {from: 'out', fields: unnestFields}},
  }, ...['a', 'b'].map(id => ({
    id: `unnest_consumer_${id}`,
    inputs: {x: {result: {stage: 'unnested', result: 'r'}}},
    steps: [{select: id === 'a'
      ? unnestFields
      : [...unnestFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a'
        ? unnestFields
        : [...unnestFields].reverse(),
    }},
  })));
  const sameStageUnnestProgram = structuredClone(unnestProgram);
  const sameStageUnnestValues = sameStageUnnestProgram.stages.find(stage =>
    stage.id === 'unnest_values');
  const sameStageUnnestIndex = sameStageUnnestProgram.stages.findIndex(
    stage => stage.id === 'unnested');
  const sameStageUnnestStep = structuredClone(
    sameStageUnnestProgram.stages[sameStageUnnestIndex].steps[0]);
  sameStageUnnestValues.steps.push({
    from: 'out', ...sameStageUnnestStep, as: 'expanded',
  });
  sameStageUnnestValues.results.r = {
    from: 'expanded', fields: unnestFields,
  };
  sameStageUnnestProgram.stages.splice(sameStageUnnestIndex, 1);
  for (const stage of sameStageUnnestProgram.stages.filter(stage =>
    stage.id.startsWith('unnest_consumer_'))) {
    stage.inputs.x.result.stage = 'unnest_values';
  }
  const unnestFilterProgram = structuredClone(unnestProgram);
  const unnestFilterStage = unnestFilterProgram.stages.find(stage =>
    stage.id === 'unnested');
  unnestFilterStage.steps[0].as = 'expanded';
  unnestFilterStage.steps.push({from: 'expanded', filter: 'id > 1',
    as: 'out'});
  const jsonPickProgram = structuredClone(zeroInputProgram);
  const jsonPickFields = ['id', 'payload', 'picked'];
  jsonPickProgram.stages.splice(1, 3, {
    id: 'json_pick_values',
    inputs: {},
    steps: [{values: {
      schema: {
        id: {type: 'number', nullable: false},
        payload: {
          type: 'object',
          nullable: true,
          fields: {
            inner: {
              type: 'object',
              nullable: false,
              fields: {leaf: {type: 'number', nullable: false}},
            },
          },
        },
      },
      rows: [
        {id: 1, payload: {inner: {leaf: 3}}},
        {id: 2, payload: null},
      ],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id', 'payload']}},
  }, {
    id: 'json_picked',
    inputs: {x: {result: {stage: 'json_pick_values', result: 'r'}}},
    steps: [{json_pick: {
      column: 'payload',
      path: ['inner', 'leaf'],
      output: 'picked',
    }, as: 'out'}],
    results: {r: {from: 'out', fields: jsonPickFields}},
  }, ...['a', 'b'].map(id => ({
    id: `json_pick_consumer_${id}`,
    inputs: {x: {result: {stage: 'json_picked', result: 'r'}}},
    steps: [{select: id === 'a'
      ? jsonPickFields
      : [...jsonPickFields].reverse(), as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a'
        ? jsonPickFields
        : [...jsonPickFields].reverse(),
    }},
  })));
  const sameStageJsonPickProgram = structuredClone(jsonPickProgram);
  const sameStageJsonValues = sameStageJsonPickProgram.stages.find(
    stage => stage.id === 'json_pick_values');
  const sameStageJsonIndex = sameStageJsonPickProgram.stages.findIndex(
    stage => stage.id === 'json_picked');
  const sameStageJsonStep = structuredClone(
    sameStageJsonPickProgram.stages[sameStageJsonIndex].steps[0]);
  sameStageJsonValues.steps.push({
    from: 'out', ...sameStageJsonStep, as: 'picked_rows',
  });
  sameStageJsonValues.results.r = {
    from: 'picked_rows', fields: jsonPickFields,
  };
  sameStageJsonPickProgram.stages.splice(sameStageJsonIndex, 1);
  for (const stage of sameStageJsonPickProgram.stages.filter(stage =>
    stage.id.startsWith('json_pick_consumer_'))) {
    stage.inputs.x.result.stage = 'json_pick_values';
  }
  const sameStageJsonFilterProgram = structuredClone(sameStageJsonPickProgram);
  const sameStageJsonFilterValues = sameStageJsonFilterProgram.stages.find(
    stage => stage.id === 'json_pick_values');
  sameStageJsonFilterValues.steps.push({
    from: 'picked_rows', filter: 'picked > 1', as: 'filtered',
  });
  sameStageJsonFilterValues.results.r.from = 'filtered';
  const joinProgram = structuredClone(zeroInputProgram);
  const joinFields = ['id', 'l', 'r'];
  joinProgram.stages.splice(1, 3, {
    id: 'joined',
    inputs: {},
    steps: [
      {values: {
        schema: {
          id: {type: 'number', nullable: false},
          l: {type: 'string', nullable: false},
        },
        rows: [{id: 1, l: 'l1'}, {id: 1, l: 'l2'}, {id: 2, l: 'l3'}],
      }, as: 'left_raw'},
      {from: 'left_raw', distinct: ['id', 'l'], as: 'left_rows'},
      {values: {
        schema: {
          id: {type: 'number', nullable: false},
          r: {type: 'string', nullable: false},
        },
        rows: [
          {id: 1, r: 'r1'},
          {id: 1, r: 'r2'},
          {id: 3, r: 'r3'},
          {id: 4, r: 'r4'},
        ],
      }, as: 'right_raw'},
      {from: 'right_raw', distinct: ['id', 'r'], as: 'right_rows'},
      {from: 'left_rows', join: {
        with: 'right_rows',
        kind: 'full',
        on: [{left: 'id', right: 'id'}],
        select: {id: 'left.id', l: 'left.l', r: 'right.r'},
      }, as: 'joined_raw'},
      {from: 'joined_raw', distinct: true, as: 'unique'},
      {from: 'unique', sort: [
        {id: 'asc'}, {l: 'asc'}, {r: 'asc'},
      ], as: 'out'},
    ],
    results: {r: {from: 'out', fields: joinFields}},
  }, ...['a', 'b'].map(id => ({
    id: `join_consumer_${id}`,
    inputs: {x: {result: {stage: 'joined', result: 'r'}}},
    steps: [{select: id === 'a' ? joinFields : [...joinFields].reverse(),
      as: 'out'}],
    results: {r: {
      from: 'out', fields: id === 'a' ? joinFields : [...joinFields].reverse(),
    }},
  })));
  const crossJoinProgram = singleton => {
    const variant = structuredClone(zeroInputProgram);
    const fields = ['id', 'tag'];
    variant.stages.splice(1, 3, {
      id: 'crossed',
      inputs: {},
      steps: [
        {values: {
          schema: {id: {type: 'number', nullable: false}},
          rows: [{id: 1}, {id: 2}],
        }, as: 'left_raw'},
        {from: 'left_raw', distinct: ['id'], as: 'left_rows'},
        {values: {
          schema: {tag: {type: 'string', nullable: false}},
          rows: singleton ? [{tag: 'a'}] : [{tag: 'a'}, {tag: 'b'}],
        }, as: 'right_raw'},
        {from: 'right_raw', distinct: ['tag'], as: 'right_rows'},
        {from: 'left_rows', cross_join: {
          with: 'right_rows',
          ...(singleton ? {right_rows: 'one'} : {}),
          select: {id: 'left.id', tag: 'right.tag'},
        }, as: 'out'},
      ],
      results: {r: {from: 'out', fields}},
    }, ...['a', 'b'].map(id => ({
      id: `cross_join_consumer_${id}`,
      inputs: {x: {result: {stage: 'crossed', result: 'r'}}},
      steps: [{select: id === 'a' ? fields : [...fields].reverse(), as: 'out'}],
      results: {r: {
        from: 'out',
        fields: id === 'a' ? fields : [...fields].reverse(),
      }},
    })));
    return variant;
  };
  const unrestrictedCrossJoinProgram = crossJoinProgram(false);
  const singletonCrossJoinProgram = crossJoinProgram(true);
  const directCrossJoinProgram = structuredClone(unrestrictedCrossJoinProgram);
  const directCrossedStage = directCrossJoinProgram.stages.find(
    stage => stage.id === 'crossed',
  );
  const directCrossSteps = directCrossedStage.steps;
  directCrossSteps[0].as = 'left_rows';
  directCrossSteps[2].as = 'right_rows';
  directCrossedStage.steps = [directCrossSteps[0], directCrossSteps[2],
    directCrossSteps[4]];
  const externalCrossJoinProgram = structuredClone(zeroInputProgram);
  const externalCrossFields = ['id', 'tag'];
  externalCrossJoinProgram.stages.splice(1, 3, {
    id: 'cross_left',
    inputs: {},
    steps: [{values: {
      schema: {id: {type: 'number', nullable: false}},
      rows: [{id: 1}, {id: 2}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['id']}},
  }, {
    id: 'cross_right',
    inputs: {},
    steps: [{values: {
      schema: {tag: {type: 'string', nullable: false}},
      rows: [{tag: 'a'}, {tag: 'b'}, {tag: 'c'}],
    }, as: 'out'}],
    results: {r: {from: 'out', fields: ['tag']}},
  }, {
    id: 'crossed',
    inputs: {
      l: {result: {stage: 'cross_left', result: 'r'}},
      r: {result: {stage: 'cross_right', result: 'r'}},
    },
    steps: [{from: 'l', cross_join: {
      with: 'r', select: {id: 'left.id', tag: 'right.tag'},
    }, as: 'out'}],
    results: {r: {from: 'out', fields: externalCrossFields}},
  }, ...['a', 'b'].map(id => ({
    id: `external_cross_consumer_${id}`,
    inputs: {x: {result: {stage: 'crossed', result: 'r'}}},
    steps: [{select: id === 'a'
      ? externalCrossFields : [...externalCrossFields].reverse(), as: 'out'}],
    results: {r: {from: 'out', fields: id === 'a'
      ? externalCrossFields : [...externalCrossFields].reverse()}},
  })));
  const splitCrossJoinProgram = structuredClone(externalCrossJoinProgram);
  const boundedEqualityJoinProgram = structuredClone(externalCrossJoinProgram);
  const equalityRight = boundedEqualityJoinProgram.stages.find(
    stage => stage.id === 'cross_right');
  equalityRight.steps[0].values = {
    schema: {
      id: {type: 'number', nullable: false},
      tag: {type: 'string', nullable: false},
    },
    rows: [{id: 1, tag: 'a'}, {id: 1, tag: 'b'}, {id: 2, tag: 'c'}],
  };
  equalityRight.results.r.fields = ['id', 'tag'];
  const equalityStage = boundedEqualityJoinProgram.stages.find(
    stage => stage.id === 'crossed');
  equalityStage.steps = [{
    from: 'l',
    join: {
      with: 'r', kind: 'inner',
      on: [{left: 'id', right: 'id'}],
      select: {id: 'left.id', tag: 'right.tag'},
      max_output_rows: 6,
    },
    as: 'joined_rows',
  }, {
    from: 'joined_rows', select: ['id', 'tag'], as: 'out',
  }];
  const splitCrossedStage = splitCrossJoinProgram.stages.find(
    stage => stage.id === 'crossed',
  );
  splitCrossedStage.steps[0].as = 'crossed_rows';
  splitCrossedStage.steps.push({
    from: 'crossed_rows', filter: 'id > 0', as: 'out',
  });
  const externalAppendProgram = structuredClone(externalCrossJoinProgram);
  const appendRight = externalAppendProgram.stages.find(
    stage => stage.id === 'cross_right',
  );
  appendRight.steps[0].values = {
    schema: {id: {type: 'number', nullable: false}},
    rows: [{id: 3}, {id: 4}],
  };
  appendRight.results.r.fields = ['id'];
  const appendStage = externalAppendProgram.stages.find(
    stage => stage.id === 'crossed',
  );
  appendStage.steps = [{from: 'l', append: {with: 'r'}, as: 'out'}];
  appendStage.results.r.fields = ['id'];
  for (const consumer of externalAppendProgram.stages.filter(
    stage => stage.id.startsWith('external_cross_consumer_'))) {
    consumer.steps[0].select = ['id'];
    consumer.results.r.fields = ['id'];
  }
  for (const [name, program, tasks] of [
    ['values', zeroInputProgram, [1, 2, 3]],
    ['captured Relation filter/select chain', capturedRelationChainProgram,
      [1, 2, 3]],
    ['captured Relation count/filter chain', capturedCountChainProgram,
      [1, 2, 3]],
    ['captured Relation keyed count/filter chain', capturedKeyedCountChainProgram,
      [1, 2, 3]],
    ['captured Relation unpivot/filter chain', capturedUnpivotChainProgram,
      [1, 2, 3]],
    ['captured Relation window/filter chain', capturedWindowChainProgram,
      [1, 2, 3]],
    ['split values', splitValuesProgram, [1, 2, 3, 4]],
    ['split values select', splitValuesSelectProgram, [1, 2, 3, 4]],
    ['split values derive', splitValuesDeriveProgram, [1, 2, 3, 4]],
    ['split values take', splitValuesTakeProgram, [1, 2, 3, 4]],
    ['split values sort/take', splitValuesSortTakeProgram, [1, 2, 3, 4, 5]],
    ['separate sort/take Stage', separateSortTakeProgram, [1, 2, 3, 4, 5]],
    ['long selected sort/take Stage', longSelectedSortTakeProgram,
      [1, 2, 3, 4, 5]],
    ['separate filter/sort/take Stage', separateFilterSortTakeProgram,
      [1, 2, 3, 4, 5, 6]],
    ['chained filter then sort/take Stages', chainedFilterSortTakeProgram,
      [1, 2, 3, 4, 5, 6]],
    ['empty values', emptyValuesProgram, [1, 2, 3]],
    ['nested values', nestedValuesProgram, [1, 2, 3]],
    ['select', selectProgram, [1, 2, 3, 4]],
    ['snapshot derive', snapshotDeriveProgram, [1, 2, 3, 4]],
    ['sort', sortProgram, [1, 2, 3, 4]],
    ['dedupe rows', dedupeProgram, [1, 2, 3, 4]],
    ['dedupe/filter chain', dedupeFilterProgram, [1, 2, 3, 4, 5, 6]],
    ['global top k', globalTopKProgram, [1, 2, 3, 4, 5]],
    ['partitioned top k', partitionedTopKProgram, [1, 2, 3, 4, 5]],
    ['append', appendProgram, [1, 2, 3, 4, 5]],
    ['append filter chain', appendFilterProgram, [1, 2, 3, 4, 5]],
    ['filter then append captured input', filterThenAppendProgram,
      [1, 2, 3, 4]],
    ['direct cross join', directCrossJoinProgram, [1, 2, 3, 4, 5]],
    ['nest', nestProgram, [1, 2, 3, 4, 5]],
    ['nest then unnest/filter', nestUnwrapProgram, [1, 2, 3, 4, 5, 6]],
    ['group count', groupProgram, [1, 2, 3, 4]],
    ['direct general group', directGroupProgram, [1, 2, 3, 4]],
    ['global count', globalCountProgram, [1, 2, 3, 4]],
    ['same-stage global count/take', sameStageGlobalCountProgram,
      [1, 2, 3, 4, 5]],
    ['same-stage keyed count/take', sameStageKeyedCountProgram,
      [1, 2, 3, 4, 5]],
    ['fixed parameter watermark', fixedWatermarkProgram, [1, 2, 3, 4]],
    ['prefix watermark', prefixWatermarkProgram, [1, 2, 3, 4]],
    ['fixed parameter row window', fixedRowWindowProgram, [1, 2, 3, 4]],
    ['sliding parameter row window', slidingRowWindowProgram, [1, 2, 3, 4]],
    ['window group', windowGroupProgram, [1, 2, 3]],
    ['parameter lag', lagProgram, [1, 2, 3, 4, 5]],
    ['analytic', analyticProgram, [1, 2, 3]],
    ['unpivot', unpivotProgram, [1, 2, 3, 4]],
    ['unpivot/filter chain', unpivotFilterProgram, [1, 2, 3, 4, 5]],
    ['same-stage unpivot', sameStageUnpivotProgram, [1, 2, 3, 4]],
    ['pivot', pivotProgram, [1, 2, 3, 4]],
    ['unnest', unnestProgram, [1, 2, 3, 4]],
    ['unnest/filter chain', unnestFilterProgram, [1, 2, 3, 4, 5]],
    ['same-stage unnest', sameStageUnnestProgram, [1, 2, 3, 4]],
    ['json pick', jsonPickProgram, [1, 2, 3, 4]],
    ['same-stage json pick', sameStageJsonPickProgram, [1, 2, 3, 4]],
    ['same-stage json pick/filter', sameStageJsonFilterProgram,
      [1, 2, 3, 4, 5]],
    ['full join', joinProgram, [1, 2, 3, 4, 5, 6, 7, 8, 9]],
    ['unrestricted cross join', unrestrictedCrossJoinProgram,
      [1, 2, 3, 4, 5, 6, 7]],
    ['singleton cross join', singletonCrossJoinProgram,
      [1, 2, 3, 4, 5, 6, 7]],
    ['external cross join', externalCrossJoinProgram, [1, 2, 3, 4, 5]],
    ['bounded equality join/select', boundedEqualityJoinProgram,
      [1, 2, 3, 4, 5]],
    ['same-task external cross join', splitCrossJoinProgram, [1, 2, 3, 4, 5]],
    ['external append', externalAppendProgram, [1, 2, 3, 4, 5]],
  ]) {
    const fixtureArgs = name === 'analytic' ? analyticArgs : args;
    let zeroInputFixture;
    try {
      zeroInputFixture = fixture.strategyFixtureCreate(
        ...fixtureArgs, JSON.stringify(program));
    } catch (error) {
      throw new Error(
        `${name}: fixture preparation failed: ${String(error)}`,
        {cause: error},
      );
    }
    const zeroInputCapture = await runNativeHostQuery(
      grant, fixture.strategyFixtureAcquisition(zeroInputFixture), suppliedLimits);
    let zeroInputExecution;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        zeroInputFixture, zeroInputCapture.source()), true);
      let setup;
      try {
        setup = fixture.strategyFixtureModuleSubset(zeroInputFixture, 0);
      } catch (error) {
        throw new Error(`${name}: strategy setup failed`, {cause: error});
      }
      zeroInputExecution = await runCapturedInternalStrategy(
        setup,
        {duckdb: new Proxy({}, {
          get() { assert.fail('unused DuckDB settings accessed'); },
        })},
      );
      assert.equal(zeroInputExecution.status, 'host-tasks-completed',
        `${name}: ${JSON.stringify(zeroInputExecution.completed)}; ` +
        `${zeroInputExecution.failure?.code ?? ''}: ` +
        `${zeroInputExecution.failure?.stack ?? zeroInputExecution.failure}`);
      assert.deepEqual(
        zeroInputExecution.completed.map(item => item.realization),
        Array(tasks.length).fill('local-managed'),
        `${name} and both actual consumers use the real managed Local bridge`,
      );
      assert.deepEqual(
        zeroInputExecution.completed.map(item => item.task),
        tasks,
        `${name} downstream computations complete instead of only opening handles`,
      );
      if (name === 'sort') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 4, 4, 4],
          'sort and both consumers publish complete retained outputs',
        );
      }
      if (name === 'bounded equality join/select') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 3, 3, 3, 3],
          'the unsplit equality join feeds two real downstream Computes',
        );
      }
      if (name === 'same-stage keyed count/take') {
        assert.deepEqual(zeroInputExecution.completed.map(item => item.outputRows),
          [3, 2, 1, 1, 1]);
      }
      if (name === 'append filter chain') {
        assert.deepEqual(zeroInputExecution.completed.map(item => item.outputRows),
          [1, 1, 1, 1, 1]);
      }
      if (name === 'captured Relation filter/select chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2],
          'an unsegmented captured input feeds two actual computations',
        );
      }
      if (name === 'captured Relation window/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 3, 3],
          'a bounded row window feeds two actual computations',
        );
      }
      if (name === 'captured Relation count/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [1, 1, 1],
          'an intermediate count feeds two actual bounded computations',
        );
      }
      if (name === 'captured Relation keyed count/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2],
          'a keyed intermediate count feeds two bounded computations',
        );
      }
      if (name === 'captured Relation unpivot/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2],
          'the bounded reshape and filter feed two actual computations',
        );
      }
      if (name === 'split values') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 1, 1, 1],
        );
      }
      if (name === 'split values select' || name === 'split values take') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          name === 'split values select' ? [2, 2, 2, 2] : [2, 1, 1, 1],
        );
      }
      if (name === 'split values sort/take' ||
          name === 'separate sort/take Stage' ||
          name === 'long selected sort/take Stage') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 1, 1, 1],
        );
      }
      if (name === 'same-stage global count/take') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 1, 1, 1, 1],
        );
      }
      if (name === 'separate filter/sort/take Stage' ||
          name === 'chained filter then sort/take Stages') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2, 1, 1, 1],
        );
      }
      if (name === 'unrestricted cross join' ||
          name === 'singleton cross join') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          name === 'unrestricted cross join'
            ? [2, 2, 2, 2, 4, 4, 4] : [2, 2, 1, 1, 2, 2, 2],
        );
      }
      if (name === 'external cross join' ||
          name === 'same-task external cross join') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          name === 'external cross join'
            ? [2, 3, 6, 6, 6] : [2, 3, 6, 6, 6],
        );
      }
      if (name === 'external append') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 4, 4, 4],
          'append and both consumers retain the full ordered output',
        );
      }
      if (name === 'append' || name === 'direct cross join') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          name === 'append' ? [1, 1, 2, 2, 2] : [2, 2, 4, 4, 4],
          `${name}: bounded producers and binary consumer retain output`,
        );
      }
      if (name === 'snapshot derive' || name === 'split values derive') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2, 2],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'parameter lag') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [5, 5, 5, 5, 5],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'window group') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'global count') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 1, 1, 1],
          'global count and both consumers retain one aggregate row',
        );
      }
      if (name === 'analytic') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [5, 5, 5],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'unpivot' || name === 'same-stage unpivot') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 6, 6, 6],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'unpivot/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 6, 3, 3, 3],
          'bounded unpivot and filter feed two actual computations',
        );
      }
      if (name === 'pivot') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [6, 2, 2, 2],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'unnest' || name === 'same-stage unnest') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 4, 4, 4],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'unnest/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 4, 2, 2, 2],
          'bounded unnest and filter feed two actual computations',
        );
      }
      if (name === 'nest then unnest/filter') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 3, 4, 2, 2, 2],
          'the unsplit bounded unnest chain feeds two real computations',
        );
      }
      if (name === 'nest') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 3, 4, 4, 4],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'json pick' || name === 'same-stage json pick') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 2, 2],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'same-stage json pick/filter') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [2, 2, 1, 1, 1],
          `${name} filters picked rows before both consumers run`,
        );
      }
      if (name === 'full join') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [3, 3, 4, 4, 7, 7, 7, 7, 7],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
      if (name === 'dedupe rows') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 2, 2, 2],
          'dedupe and both consumers publish complete retained outputs',
        );
      }
      if (name === 'dedupe/filter chain') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 2, 1, 1, 1, 1],
          'bounded dedupe and filter feed two actual computations',
        );
      }
      if (name === 'global top k' || name === 'partitioned top k') {
        assert.deepEqual(
          zeroInputExecution.completed.map(item => item.outputRows),
          [4, 4, 2, 2, 2],
          `${name} and both consumers publish complete retained outputs`,
        );
      }
    } finally {
      await zeroInputExecution?.close();
      zeroInputCapture.close();
    }
    assert.equal(zeroInputExecution.cleanupPending(), false);
    assert.equal(await zeroInputExecution.cleanup(), true);
    assert.equal(zeroInputExecution.usage().heldBytes, 0n);
    assert.equal(zeroInputExecution.usage().reservedExecutionBytes, 0n);
  }
  // The same bounded binary chain reaches formal publication and retrieval,
  // not just a private completion or a row-count assertion.
  for (const equalityPublicationCase of [{
    name: 'bounded-join-publication',
    program: structuredClone(boundedEqualityJoinProgram),
    stage: 'crossed',
    tasks: 5,
    expected: [{id: 1, tag: 'a'}, {id: 1, tag: 'b'}, {id: 2, tag: 'c'}],
  }, {
    name: 'same-stage-keyed-count-publication',
    program: structuredClone(sameStageKeyedCountProgram),
    stage: 'group_a',
    tasks: 5,
    expected: [{id: null, n: 1, present: 0}],
  }, {
    name: 'append-filter-publication',
    program: structuredClone(appendFilterProgram),
    stage: 'append_a',
    tasks: 5,
    expected: [{id: 2}],
  }, {
    name: 'same-stage-full-join-publication',
    program: structuredClone(joinProgram),
    stage: 'joined',
    tasks: 9,
    expected: [
      {id: 1, l: 'l1', r: 'r1'}, {id: 1, l: 'l1', r: 'r2'},
      {id: 1, l: 'l2', r: 'r1'}, {id: 1, l: 'l2', r: 'r2'},
      {id: 2, l: 'l3', r: null},
      {id: null, l: null, r: 'r3'}, {id: null, l: null, r: 'r4'},
    ],
  }]) {
    const equalityPublicationProgram = equalityPublicationCase.program;
    equalityPublicationProgram.results = {
      joined: {from: {stage: equalityPublicationCase.stage, result: 'r'}},
    };
    const equalityPublicationFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(equalityPublicationProgram));
    const equalityPublicationCapture = await runNativeHostQuery(
      grant, fixture.strategyFixtureAcquisition(equalityPublicationFixture),
      suppliedLimits);
    const equalityPublicationDirectory = await mkdtemp(join(
      root, '_build/duckdb-fixtures/bounded-join-publication-'));
    let equalityPublicationOwner;
    let equalityPublicationStore;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        equalityPublicationFixture, equalityPublicationCapture.source()), true);
      const setup = fixture.strategyFixtureModuleSubset(
        equalityPublicationFixture, 0);
      const runtime = runtimeCore(hostRuntime);
      equalityPublicationStore = await openLocalPublicationStore({
        directory: equalityPublicationDirectory,
        storeAuthorityCid: hash('bounded-join-publication-store'),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime, runtime.programDefinitionCid(setup),
        runtime.resultInventory(setup).length, equalityPublicationCase.name);
      equalityPublicationOwner = await runPublishedCapturedStrategy(
        setup, {store: equalityPublicationStore, plan}, {},
        new AbortController().signal);
      assert.equal(equalityPublicationOwner.status, 'published');
      assert.deepEqual(equalityPublicationOwner.execution.completed.map(
        value => value.realization),
      Array(equalityPublicationCase.tasks).fill('local-managed'));
      const occurrence =
        equalityPublicationOwner.execution.publicationInventory.occurrences[0];
      const received = [];
      await equalityPublicationStore.consumeCommittedResult({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, occurrence.definitionContract.identity, () => true,
      chunk => received.push(Buffer.from(chunk)));
      assert.deepEqual(JSON.parse(Buffer.concat(received).toString('utf8')),
        equalityPublicationCase.expected);
    } finally {
      if (equalityPublicationOwner !== undefined) {
        await equalityPublicationOwner.close();
        assert.equal(await equalityPublicationOwner.cleanup(), true);
        assert.equal(equalityPublicationOwner.cleanupPending(), false);
        assert.equal(equalityPublicationOwner.execution.usage().heldBytes, 0n);
        assert.equal(equalityPublicationOwner.execution.usage()
          .reservedExecutionBytes, 0n);
      }
      equalityPublicationCapture.close();
      await equalityPublicationStore?.close();
      await rm(equalityPublicationDirectory, {recursive: true, force: true});
    }
  }
  const retainedManagedRoot = await mkdtemp(join(
    root, '_build/duckdb-fixtures/local-retained-managed-',
  ));
  const retainedManagedConfig = {
    parentDirectory: retainedManagedRoot,
    maxFrameBytes: 4096,
    wire: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 64,
      max_columns: 10,
      max_order_work: 10000,
    },
  };
  try {
    for (const [name, program, expectedRows] of [
      ['filter/select', capturedRelationChainProgram, [2, 2, 2]],
      ['dedupe/filter', dedupeFilterProgram, [4, 2, 1, 1, 1, 1]],
      ['count/filter', capturedCountChainProgram, [1, 1, 1]],
      ['unpivot/filter', capturedUnpivotChainProgram, [2, 2, 2]],
      ['nest', nestProgram, [4, 3, 4, 4, 4]],
    ]) {
      const f = fixture.strategyFixtureAccounted(
        fixture.strategyFixtureCreate(...args, JSON.stringify(program)),
      );
      const capture = await runRetainedStrategyNativeHostQuery(
        grant,
        fixture.strategyFixtureAcquisition(f),
        fixture.strategyFixtureLedger(f),
        suppliedLimits,
        retainedManagedConfig,
      );
      let execution;
      try {
        assert.equal(fixture.strategyFixtureAttach(
          f, capture.openDAG(fixture.strategyFixtureGraph(f)),
        ), true);
        execution = await runCapturedInternalStrategy(
          fixture.strategyFixtureModuleSubset(f, 0),
          {duckdb: new Proxy({}, {
            get() { assert.fail('unused DuckDB settings accessed'); },
          })},
        );
        assert.equal(execution.status, 'host-tasks-completed',
          `${name}: ${String(execution.failure)}`);
        assert.deepEqual(
          execution.completed.map(item => item.realization),
          Array(expectedRows.length).fill('local-managed'),
          `${name}: retained capture and both consumers use bounded Local`,
        );
        assert.deepEqual(
          execution.completed.map(item => item.outputRows),
          expectedRows,
        );
      } finally {
        await execution?.close();
        capture.close();
        await capture.cleanupHandle.retry();
      }
      assert.equal(execution.cleanupPending(), false);
      assert.equal(await execution.cleanup(), true);
      assert.equal(execution.usage().heldBytes, 0n);
      assert.equal(execution.usage().reservedExecutionBytes, 0n);
      assert.equal(capture.cleanupHandle.status().pending, false);
    }
    assert.deepEqual(await readdir(retainedManagedRoot), []);
  } finally {
    await rm(retainedManagedRoot, {recursive: true, force: true});
  }
  for (const {name: cancellationName, program: cancellationProgram} of [
    {name: 'external-cross-join-in-flight', program: externalCrossJoinProgram},
    {name: 'external-cross-join-empty-right-admission',
      program: externalCrossJoinProgram},
    {name: 'split-external-cross-join-in-flight', program: splitCrossJoinProgram},
    {name: 'external-append-in-flight', program: externalAppendProgram},
    {name: 'direct-cross-join-in-flight', program: directCrossJoinProgram},
    {name: 'direct-append-in-flight', program: appendProgram},
  ]) {
    const externalCrossJoinCancellationCase = {name: cancellationName};
    const cancellableCrossJoinProgram = structuredClone(cancellationProgram);
    const appendCancellation = cancellationName.includes('append');
    const directCancellation = cancellationName.startsWith('direct-');
    const emptyRightAdmission = cancellationName ===
      'external-cross-join-empty-right-admission';
    const sourceRows = emptyRightAdmission ? 100 :
      appendCancellation && !directCancellation ? 49 : 10;
    const directStage = appendCancellation ? 'append_a' : 'crossed';
    const leftValues = directCancellation
      ? cancellableCrossJoinProgram.stages.find(
        stage => stage.id === directStage).steps[0].values
      : cancellableCrossJoinProgram.stages.find(
        stage => stage.id === 'cross_left').steps[0].values;
    const rightValues = directCancellation
      ? cancellableCrossJoinProgram.stages.find(
        stage => stage.id === directStage).steps[1].values
      : cancellableCrossJoinProgram.stages.find(
        stage => stage.id === 'cross_right').steps[0].values;
    leftValues.rows = Array.from(
      {length: sourceRows},
      (_, index) => ({id: index}),
    );
    rightValues.rows = Array.from(
      {length: emptyRightAdmission ? 0 : sourceRows},
      (_, index) => appendCancellation
        ? {id: index + 10} : {tag: `tag${index}`},
    );
    const crossJoinCancellationFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(cancellableCrossJoinProgram),
    );
    const crossJoinCancellationCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(crossJoinCancellationFixture),
      suppliedLimits,
    );
    const crossJoinCancellation = new AbortController();
    let crossJoinCancellationExecution;
    let crossJoinManagedStarts = 0;
    let crossJoinPairProgress = 0n;
    let crossJoinAdmissionWork = 0n;
    let crossJoinCancellationScheduled = false;
    let crossJoinCancellationDeliveredAt;
    let crossJoinStopObservedAt;
    crossJoinCancellation.signal.addEventListener('abort', () => {
      crossJoinCancellationDeliveredAt = performance.now();
    }, {once: true});
    try {
      assert.equal(fixture.strategyFixtureOpen(
        crossJoinCancellationFixture,
        crossJoinCancellationCapture.source(),
      ), true);
      const setup = fixture.strategyFixtureModuleSubset(
        crossJoinCancellationFixture, 0,
      );
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return configuration => {
            const start = ++crossJoinManagedStarts;
            const execution = checked(
              target.strategyModule_local_ManagedStart(configuration),
            );
            const observed = new Proxy(execution, {
              get(operation, name, operationReceiver) {
                if (name === 'execution_stopped') {
                  return () => {
                    const stopped = operation.execution_stopped();
                    if (stopped && crossJoinCancellation.signal.aborted &&
                        crossJoinStopObservedAt === undefined) {
                      crossJoinStopObservedAt = performance.now();
                    }
                    return stopped;
                  };
                }
                if (name !== 'advance') {
                  return Reflect.get(operation, name, operationReceiver);
                }
                return quantum => {
                  const actualQuantum = appendCancellation &&
                    directCancellation ? Math.min(quantum, 7) : quantum;
                  const result = operation.advance(actualQuantum);
                  const observation = checked(result);
                  if (start === 3) {
                    assert(observation.work <= BigInt(actualQuantum));
                  }
                  if (start === 3 && observation?.complete === false &&
                      observation.work > 0n &&
                      (emptyRightAdmission || observation.progress > 0n)) {
                    if (emptyRightAdmission) {
                      crossJoinAdmissionWork += observation.work;
                    } else {
                      crossJoinPairProgress += observation.progress;
                    }
                    if (!crossJoinCancellationScheduled) {
                      crossJoinCancellationScheduled = true;
                      setTimeout(() => crossJoinCancellation.abort(), 0);
                    }
                  }
                  return result;
                };
              },
            });
            return {$tag: 1, _0: observed};
          };
        },
      });
      crossJoinCancellationExecution = await runInstalledStrategy(
        setup,
        runtimeCore(hostRuntime),
        [localStrategyContribution(observedRuntime, setup, checked, undefined)],
        crossJoinCancellation.signal,
      );
      assert.equal(crossJoinManagedStarts, 3);
      assert.equal(
        emptyRightAdmission
          ? crossJoinAdmissionWork > 0n && crossJoinPairProgress === 0n
          : crossJoinPairProgress > 0n,
        true,
        `${externalCrossJoinCancellationCase.name}: ` +
          'kernel work must precede abort',
      );
      assert.equal(crossJoinCancellation.signal.aborted, true);
      assert.equal(Number.isFinite(crossJoinCancellationDeliveredAt), true);
      assert.equal(Number.isFinite(crossJoinStopObservedAt), true);
      assert(crossJoinStopObservedAt >= crossJoinCancellationDeliveredAt);
      assert.equal(crossJoinCancellationExecution.status, 'host-tasks-failed');
      assert.equal(crossJoinCancellationExecution.failure?.name, 'AbortError');
      assert.deepEqual(
        crossJoinCancellationExecution.completed.map(item => item.task),
        [1, 2],
        `${externalCrossJoinCancellationCase.name}: no partial cross output`,
      );
    } finally {
      crossJoinCancellationCapture.close();
      await crossJoinCancellationExecution?.close();
      if (crossJoinCancellationExecution) {
        let cleaned = false;
        for (let attempt = 0; attempt < 3 && !cleaned; attempt++) {
          cleaned = await crossJoinCancellationExecution.cleanup();
        }
        assert.equal(cleaned, true);
        assert.equal(crossJoinCancellationExecution.cleanupPending(), false);
        assert.equal(crossJoinCancellationExecution.usage().heldBytes, 0n);
        assert.equal(
          crossJoinCancellationExecution.usage().reservedExecutionBytes,
          0n,
        );
      }
    }
  }
  // Retained Store Local: every task runs through the retained-output driver,
  // whose computation is the bounded provider advanced in quanta. A completed
  // run publishes retained files read by two consumers; an abort during the
  // sort is observed between advances, stops the provider and never reaches
  // the Store for that task.
  for (const cancel of [false, true]) {
    // The retained lane serves Local tasks that read captured inputs and carry
    // only its admitted obligations (no zero-input Values, no cross product).
    const retainedProgram = JSON.parse(program);
    retainedProgram.stages.splice(1, 3, stage('retained_rows', 'a', 'id > 0'), {
      id: 'retained_sorted',
      inputs: {x: {result: {stage: 'retained_rows', result: 'r'}}},
      steps: [{sort: [{id: 'desc'}], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}},
    }, ...['a', 'b'].map(id => ({
      id: `retained_consumer_${id}`,
      inputs: {x: {result: {stage: 'retained_sorted', result: 'r'}}},
      steps: [{select: ['id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}},
    })));
    retainedProgram.results = {
      a: {from: {stage: 'retained_consumer_a', result: 'r'}},
      b: {from: {stage: 'retained_consumer_b', result: 'r'}},
    };
    await replaceRows(`INSERT INTO records VALUES ${Array.from({length: 9},
      (_, index) => `(${index + 2},${index})`).join(',')}`);
    const retainedFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(retainedProgram));
    const retainedCapture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(retainedFixture), suppliedLimits);
    const retainedDirectory = await mkdtemp(join(tmpdir(), 'actql-retained-local-'));
    const store = await createLocalRetainedStore({parentDirectory: retainedDirectory,
      capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024});
    const leased = [];
    const configuration = installLocalRetainedStore((key, bytes) => {
      leased.push(key);
      let writer, closed = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && !closed ? bytes : 0,
          cleanupPending: false}),
        reserve: value => (writer = store.reserve(value)),
        close() { closed = true; writer?.cancel(); },
        async cleanup() { await writer?.cleanupHandle?.retry?.(); },
      });
    });
    const controller = new AbortController();
    const advances = new Map();
    let starts = 0, scheduled = false, stoppedAfterAbort = false;
    const observedRuntime = new Proxy(hostRuntime, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_Dispatch') {
          return Reflect.get(target, property, receiver);
        }
        return (setup, task) => {
          const start = ++starts;
          const operations = checked(target.strategyModule_local_Dispatch(setup, task));
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, name, operationReceiver) {
              if (name === 'execute') assert.fail('retained Local ran synchronously');
              if (name === 'execution_stopped') {
                return () => {
                  const stopped = operation.execution_stopped();
                  if (stopped && controller.signal.aborted) stoppedAfterAbort = true;
                  return stopped;
                };
              }
              if (name !== 'advance') return Reflect.get(operation, name, operationReceiver);
              // A small quantum makes the fixture-sized sort span advances.
              return quantum => {
                const result = operation.advance(Math.min(quantum, 4));
                const observation = checked(result);
                advances.set(start, (advances.get(start) ?? 0) + 1);
                if (cancel && start === 2 && observation.complete === false &&
                    observation.progress > 0n && !scheduled) {
                  scheduled = true;
                  setTimeout(() => controller.abort(), 0);
                }
                return result;
              };
            },
          })};
        };
      },
    });
    let execution;
    try {
      assert.equal(fixture.strategyFixtureOpen(retainedFixture, retainedCapture.source()), true);
      const setup = fixture.strategyFixtureRetainedLocalSubset(retainedFixture);
      execution = await runInstalledStrategy(setup, runtimeCore(hostRuntime),
        [localStrategyContribution(observedRuntime, setup, checked, configuration)],
        controller.signal);
      if (cancel) {
        assert.equal(execution.status, 'host-tasks-failed');
        assert.equal(execution.failure?.name, 'AbortError');
        assert.equal(stoppedAfterAbort, true);
        assert.deepEqual(execution.completed.map(item => item.task), [1]);
        assert.deepEqual(leased, ['task-1']);
      } else {
        assert.equal(execution.status, 'host-tasks-completed', String(execution.failure));
        assert.deepEqual(execution.completed.map(item => item.realization),
          Array(4).fill('local'));
        assert(execution.completed.every(item =>
          item.outputRepresentation === 'retained-file'));
        assert.deepEqual(execution.completed.map(item => item.exportedRows),
          [9, 9, 9, 9]);
        assert.equal(leased.length, 4);
        // Both consumers publish the sorted rows: exact content, order and
        // no duplicates against an independently built expectation.
        const sorted = hash(Array.from({length: 9}, (_, index) => ({id: 10 - index})));
        for (const task of [2, 3, 4]) {
          assert.equal(fixture.strategyFixtureCid(retainedFixture, task), sorted,
            `retained task ${task}`);
        }
      }
      // The sort ran over several bounded advances.
      assert((advances.get(2) ?? 0) > 1, JSON.stringify([...advances]));
    } finally {
      retainedCapture.close();
      await execution?.close();
    }
    let cleaned = false;
    for (let attempt = 0; attempt < 3 && !cleaned; attempt++) {
      cleaned = await execution.cleanup();
    }
    assert.equal(cleaned, true);
    assert.equal(execution.cleanupPending(), false);
    assert.equal(execution.usage().heldBytes, 0n);
    assert.equal(execution.usage().reservedExecutionBytes, 0n);
    store.close();
    await store.cleanup();
    await rm(retainedDirectory, {recursive: true, force: true});
  }
  const retainedValuesProgram = structuredClone(zeroInputProgram);
  retainedValuesProgram.results = {
    values: {from: {stage: 'values_a', result: 'r'}},
    first: {from: {stage: 'consumer_a', result: 'r'}},
    second: {from: {stage: 'consumer_b', result: 'r'}},
  };
  const retainedValuesFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(retainedValuesProgram));
  const retainedValuesCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(retainedValuesFixture),
    suppliedLimits,
  );
  const retainedValuesDirectory = await mkdtemp(join(
    tmpdir(), 'actql-retained-values-'));
  const retainedPublicationDirectory = await mkdtemp(join(
    tmpdir(), 'actql-retained-values-publication-'));
  const retainedValuesStore = await createLocalRetainedStore({
    parentDirectory: retainedValuesDirectory,
    capacityBytes: 8 * 1024 * 1024,
    maxFrameBytes: 1024 * 1024,
  });
  const retainedValuesLeases = [];
  const retainedValuesConfiguration = installLocalRetainedStore((key, bytes) => {
    retainedValuesLeases.push(key);
    let writer, closed = false;
    return Object.freeze({
      status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: false}),
      reserve: value => (writer = retainedValuesStore.reserve(value)),
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); },
    });
  });
  let retainedValuesOwner, retainedPublicationStore;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      retainedValuesFixture, retainedValuesCapture.source()), true);
    const setup = fixture.strategyFixtureRetainedLocalSubset(
      retainedValuesFixture);
    const runtime = runtimeCore(hostRuntime);
    retainedPublicationStore = await openLocalPublicationStore({
      directory: retainedPublicationDirectory,
      storeAuthorityCid: hash('retained-values-publication-store'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100,
      maxContractNodes: 10000,
      maxContractDepth: 64,
    }, runtime.publicationControl);
    const plan = standardPublicationPlan(
      runtime,
      runtime.programDefinitionCid(setup),
      runtime.resultInventory(setup).length,
      'retained-values-publication-attempt',
    );
    retainedValuesOwner = await runPublishedCapturedStrategy(
      setup,
      {store: retainedPublicationStore, plan},
      {local: retainedValuesConfiguration},
      new AbortController().signal,
    );
    assert.equal(retainedValuesOwner.status, 'published');
    assert.equal(retainedValuesOwner.execution.status, 'host-tasks-completed');
    assert.deepEqual(
      retainedValuesOwner.execution.completed.map(item => item.realization),
      Array(3).fill('local'),
    );
    assert(retainedValuesOwner.execution.completed.every(item =>
      item.outputRepresentation === 'retained-file'));
    assert.equal(retainedValuesLeases.length, 3);
    const rows = [{id: null, label: 'none'}, {id: 1, label: 'one'}];
    assert.equal(fixture.strategyFixtureCid(retainedValuesFixture, 1),
      hash(rows));
    assert.equal(fixture.strategyFixtureCid(retainedValuesFixture, 2),
      hash(rows));
    assert.equal(fixture.strategyFixtureCid(retainedValuesFixture, 3),
      hash(rows));
    const authority = installResultAccessAuthority({
      authorizeResultReadRequest: () => true,
      admitResultRead: () => ({
        authorizationContextCid: hash('retained-values-context'),
        dataCeilingCid: hash('retained-values-ceiling'),
        egressAdmissionCid: hash('retained-values-egress'),
        expiresAt: '2026-09-18T01:00:00.000Z',
        maxBytes: 100000,
        maxUses: 1,
      }),
      authorizeResultRead: () => true,
    });
    const accessService = installNodeResultAccessService({
      store: retainedPublicationStore,
      control: runtime.publicationControl,
      authority,
      now: () => '2026-09-18T00:30:00.000Z',
      limits: {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64},
      frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096},
    });
    for (const [name, expected] of Object.entries({
      values: rows,
      first: rows,
      second: rows.map(({id, label}) => ({label, id})),
    })) {
      const delivered = [];
      await deliverAuthorizedResult(accessService, {
        indexKey: {
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        },
        principalId: 'principal-a',
        purpose: 'download',
        resultName: name,
        format: 'json',
        attemptId: `retained-values-${name}`,
      }, {
        async write(bytes) {
          delivered.push(Buffer.from(bytes));
          return {confirmedBytes: bytes.byteLength};
        },
        async finish() { return {confirmed: true}; },
      }, new AbortController().signal);
      assert.deepEqual(JSON.parse(Buffer.concat(delivered).toString('utf8')),
        expected);
    }
  } finally {
    retainedValuesCapture.close();
    if (retainedValuesOwner) {
      await retainedValuesOwner.close();
      assert.equal(await retainedValuesOwner.cleanup(), true);
      assert.equal(retainedValuesOwner.execution.usage().heldBytes, 0n);
      assert.equal(
        retainedValuesOwner.execution.usage().reservedExecutionBytes, 0n);
    }
    await retainedPublicationStore?.close();
    retainedValuesStore.close();
    await retainedValuesStore.cleanup();
    await rm(retainedValuesDirectory, {recursive: true, force: true});
    await rm(retainedPublicationDirectory, {recursive: true, force: true});
  }
  // These checked binary obligations are discharged by their exact bounded
  // providers, including when every output is retained and published.
  const retainedSetProgram = (kind, duplicates = 'all') => {
    const program = structuredClone(externalAppendProgram);
    program.stages.find(stage => stage.id === 'cross_left').steps[0]
      .values.rows = [1, 1, 2, 2, 2].map(id => ({id}));
    const right = program.stages.find(stage => stage.id === 'cross_right');
    right.steps[0].values.rows = [2, 2, 3].map(id => ({id}));
    program.stages.find(stage => stage.id === 'crossed').steps[0] = {
      from: 'l', [kind]: {with: 'r', duplicates}, as: 'out',
    };
    return program;
  };
  const retainedSingletonCross = structuredClone(externalCrossJoinProgram);
  retainedSingletonCross.stages.find(stage => stage.id === 'cross_right')
    .steps[0].values.rows = [{tag: 'a'}];
  retainedSingletonCross.stages.find(stage => stage.id === 'crossed')
    .steps[0].cross_join.right_rows = 'one';
  const retainedBinaryChain = (source, suffix, fields) => {
    const program = structuredClone(source);
    const producer = program.stages.find(stage => stage.id === 'crossed');
    producer.steps[0].as = 'binary';
    let from = 'binary';
    for (const [index, step] of suffix.entries()) {
      const as = index === suffix.length - 1 ? 'out' : `chain_${index}`;
      producer.steps.push({from, ...step, as});
      from = as;
    }
    producer.results.r.fields = fields;
    for (const stage of program.stages.filter(stage =>
      stage.id.startsWith('external_cross_consumer_'))) {
      stage.steps[0].select = fields;
      stage.results.r.fields = fields;
    }
    return program;
  };
  const retainedUnaryChain = (sourceSteps, suffix, fields, rows, schema) => {
    const program = structuredClone(externalAppendProgram);
    const left = program.stages.find(stage => stage.id === 'cross_left');
    if (rows) left.steps[0].values.rows = rows;
    if (schema) {
      left.steps[0].values.schema = schema;
      const right = program.stages.find(stage => stage.id === 'cross_right');
      right.steps[0].values.schema = schema;
      right.steps[0].values.rows = [];
      right.results.r.fields = Object.keys(schema);
    }
    left.results.r.fields = Object.keys(left.steps[0].values.schema);
    const producer = program.stages.find(stage => stage.id === 'crossed');
    const steps = [{append: {with: 'r'}}, ...sourceSteps, ...suffix];
    producer.steps = steps.map((step, index) => ({
      from: index === 0 ? 'l' : `chain_${index - 1}`,
      ...step,
      as: index === steps.length - 1 ? 'out' : `chain_${index}`,
    }));
    producer.results.r.fields = fields;
    for (const stage of program.stages.filter(stage =>
      stage.id.startsWith('external_cross_consumer_'))) {
      stage.steps[0].select = fields;
      stage.results.r.fields = fields;
    }
    return program;
  };
  const retainedTimeSeriesProgram = structuredClone(zeroInputProgram);
  retainedTimeSeriesProgram.stages.find(stage => stage.id === 'values_a')
    .steps = [{time_series: {
      start: '1969-12-31T23:59:59.999Z',
      end: '1970-01-01T00:00:00.004Z', step: 2,
    }, as: 'out'}];
  for (const stage of retainedTimeSeriesProgram.stages.slice(1)) {
    stage.results.r.fields = ['time'];
    if (stage.id !== 'values_a') stage.steps[0].select = ['time'];
  }
  const retainedTemporalJoinProgram = kind => {
    const program = structuredClone(externalCrossJoinProgram);
    const left = program.stages.find(stage => stage.id === 'cross_left');
    const right = program.stages.find(stage => stage.id === 'cross_right');
    const joined = program.stages.find(stage => stage.id === 'crossed');
    let fields;
    if (kind === 'interval') {
      left.steps[0].values = {
        schema: {
          key: {type: 'number', nullable: true},
          time: {type: 'number', nullable: false},
          value: {type: 'number', nullable: false},
        },
        rows: [
          {key: 1, time: 2, value: 10}, {key: 2, time: 7, value: 11},
          {key: null, time: 1, value: 12},
        ],
      };
      right.steps[0].values = {
        schema: {
          key: {type: 'number', nullable: true},
          start: {type: 'number', nullable: false},
          end: {type: 'number', nullable: false},
          value: {type: 'number', nullable: false},
        },
        rows: [
          {key: 1, start: 0, end: 3, value: 20},
          {key: 1, start: 2, end: 4, value: 21},
          {key: 2, start: 8, end: 9, value: 22},
          {key: null, start: 0, end: 3, value: 23},
        ],
      };
      fields = ['left_value', 'right_value'];
      joined.steps = [{from: 'l', interval_join: {
        with: 'r', kind: 'inner', mode: 'point_in_interval',
        on: [{left: 'key', right: 'key'}],
        left: {time: 'time'}, right: {start: 'start', end: 'end'},
        select: {left_value: 'left.value', right_value: 'right.value'},
        max_output_rows: 12,
      }, as: 'out'}];
    } else {
      left.steps[0].values = {
        schema: Object.fromEntries(['id', 'key', 'clock'].map(field =>
          [field, {type: 'number', nullable: false}])),
        rows: [{id: 1, key: 1, clock: 100}],
      };
      right.steps[0].values = {
        schema: {
          ...Object.fromEntries(['id', 'key', 'clock', 'value'].map(field =>
            [field, {type: 'number', nullable: false}])),
          priority: {type: 'number', nullable: true},
        },
        rows: [
          {id: 11, key: 1, clock: 90, priority: 5, value: 100},
          {id: 11, key: 1, clock: 90, priority: 5, value: 200},
          {id: 11, key: 1, clock: 100, priority: 0, value: 300},
        ],
      };
      fields = ['id', 'value'];
      joined.steps = [{from: 'l', asof_join: {
        with: 'r', kind: 'inner', by: [{left: 'key', right: 'key'}],
        left_id: 'id', left_time: 'clock', right_time: 'clock',
        direction: 'backward', tolerance: 10, right_tie_break: ['priority'],
        select: {id: 'left.id', value: 'right.value'},
      }, as: 'out'}];
    }
    left.results.r.fields = Object.keys(left.steps[0].values.schema);
    right.results.r.fields = Object.keys(right.steps[0].values.schema);
    joined.results.r.fields = fields;
    for (const consumer of program.stages.filter(stage =>
      stage.id.startsWith('external_cross_consumer_'))) {
      const selected = consumer.id.endsWith('_a') ? fields : [...fields].reverse();
      consumer.steps[0].select = selected;
      consumer.results.r.fields = selected;
    }
    return program;
  };
  const relationSequenceFields = [
    'end_id', 'end_time_ms', 'key', 'match_end_ms', 'match_start_ms',
    'start_id', 'start_time_ms',
  ];
  const retainedRelationSequenceProgram = structuredClone(zeroInputProgram);
  const sequenceInput = retainedRelationSequenceProgram.stages.find(stage =>
    stage.id === 'values_a');
  sequenceInput.steps[0].values = {
    schema: Object.fromEntries(['id', 'key', 'clock', 'value'].map(field =>
      [field, {type: 'number', nullable: false}])),
    rows: [
      {id: 3, key: 1, clock: 3, value: 2},
      {id: 1, key: 1, clock: 1, value: 1},
      {id: 4, key: 2, clock: 4, value: 2},
      {id: 2, key: 1, clock: 2, value: 2},
      {id: 5, key: 2, clock: 3, value: 1},
    ],
  };
  sequenceInput.results.r.fields = ['id', 'key', 'clock', 'value'];
  retainedRelationSequenceProgram.stages.splice(2, 0, {
    id: 'matched', inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
    steps: [{from: 'x', sequence: {
      by: ['key'], id: 'id', time: 'clock',
      pattern: [{as: 'start', where: 'value = 1'},
        {as: 'end', where: 'value = 2'}],
      within: 10, overlap: 'allow', contiguity: 'subsequence',
    }, as: 'out'}],
    results: {r: {from: 'out', fields: relationSequenceFields}},
  });
  for (const consumer of retainedRelationSequenceProgram.stages.filter(stage =>
    stage.id.startsWith('consumer_'))) {
    consumer.inputs.x.result.stage = 'matched';
    consumer.steps[0].select = relationSequenceFields;
    consumer.results.r.fields = relationSequenceFields;
  }
  const sequenceExpected = [
    {end_id: 2, end_time_ms: 2, key: 1, match_end_ms: 2,
      match_start_ms: 1, start_id: 1, start_time_ms: 1},
    {end_id: 3, end_time_ms: 3, key: 1, match_end_ms: 3,
      match_start_ms: 1, start_id: 1, start_time_ms: 1},
    {end_id: 4, end_time_ms: 4, key: 2, match_end_ms: 4,
      match_start_ms: 3, start_id: 5, start_time_ms: 3},
  ];
  const sequencePolicyArgs = (matches, output) => {
    const environment = JSON.parse(args[0]);
    Object.assign(environment.host_policy_profile.capacity, {
      max_temporal_matches_per_key: matches,
      max_temporal_output_rows: output,
    });
    const {evidence_bundle_cid: ignored, ...body} = environment;
    void ignored;
    environment.evidence_bundle_cid = canonicalHash(body);
    return [canonical(environment), environment.evidence_bundle_cid,
      ...args.slice(2)];
  };
  const retainedFamilyChain = (source, producerId, suffix, fields) => {
    const program = structuredClone(source);
    const producer = program.stages.find(stage => stage.id === producerId);
    producer.steps[0].as = 'family';
    let from = 'family';
    for (const [index, step] of suffix.entries()) {
      const as = index === suffix.length - 1 ? 'out' : `family_${index}`;
      producer.steps.push({from, ...step, as});
      from = as;
    }
    producer.results.r.fields = fields;
    for (const consumer of program.stages.filter(stage =>
      stage.inputs?.x?.result?.stage === producerId)) {
      consumer.steps[0].select = fields;
      consumer.results.r.fields = fields;
    }
    return program;
  };
  const relationSessionFields = ['id', 'session_start_ms', 'session_end_ms'];
  const retainedRelationSessionProgram = structuredClone(zeroInputProgram);
  const sessionInput = retainedRelationSessionProgram.stages.find(stage =>
    stage.id === 'values_a');
  sessionInput.steps[0].values = {
    schema: {
      id: {type: 'number', nullable: false},
      clock: {type: 'number', nullable: false},
      payload: {type: 'string', nullable: false},
    },
    rows: [
      {id: 1, clock: 3, payload: 'x'},
      {id: 2, clock: 1, payload: 'x'},
      {id: 3, clock: 13, payload: 'x'},
    ],
  };
  sessionInput.results.r.fields = ['id', 'clock', 'payload'];
  retainedRelationSessionProgram.stages.splice(2, 0, {
    id: 'sessionized', inputs: {x: {result: {stage: 'values_a', result: 'r'}}},
    steps: [{from: 'x', session: {
      by: ['payload'], id: 'id', time: 'clock', gap: 10,
    }, as: 'out'}],
    results: {r: {from: 'out', fields: [
      'id', 'clock', 'payload', 'session_id', 'session_start_ms', 'session_end_ms',
    ]}},
  });
  for (const consumer of retainedRelationSessionProgram.stages.filter(stage =>
    stage.id.startsWith('consumer_'))) {
    consumer.inputs.x.result.stage = 'sessionized';
    consumer.steps[0].select = relationSessionFields;
    consumer.results.r.fields = relationSessionFields;
  }
  const sessionExpected = [
    {id: 2, session_start_ms: 1, session_end_ms: 13},
    {id: 1, session_start_ms: 1, session_end_ms: 13},
    {id: 3, session_start_ms: 13, session_end_ms: 23},
  ];
  const retainedRelationSessionChain = retainedFamilyChain(
    retainedRelationSessionProgram, 'sessionized',
    [{filter: 'true'}, {select: relationSessionFields}], relationSessionFields);
  for (const {
    name, source, expected, producerCidRows, fields,
    temporal = false, sequence = false, fixtureArgs = args,
    producerStage = 'crossed', producerTask = 3, totalTasks = 5,
    firstStage = 'external_cross_consumer_a',
    secondStage = 'external_cross_consumer_b',
  } of [
    {name: 'session-filter-select-chain', source: retainedRelationSessionChain,
      temporal: true, producerStage: 'sessionized', producerTask: 2, totalTasks: 4,
      firstStage: 'consumer_a', secondStage: 'consumer_b',
      expected: sessionExpected, fields: relationSessionFields,
      producerCidRows: sessionExpected.map(row => ({
        id: row.id, session_end_ms: row.session_end_ms,
        session_start_ms: row.session_start_ms,
      }))},
    {name: 'session-empty-filter-select-chain', source: (() => {
      const program = structuredClone(retainedRelationSessionChain);
      program.stages.find(stage => stage.id === 'values_a').steps[0].values.rows = [];
      return program;
    })(), temporal: true,
      producerStage: 'sessionized', producerTask: 2, totalTasks: 4,
      firstStage: 'consumer_a', secondStage: 'consumer_b',
      expected: [], fields: relationSessionFields},
    {name: 'sequence-filter-sort-chain', source: retainedFamilyChain(
      retainedRelationSequenceProgram, 'matched',
      [{filter: 'key = 1'}, {sort: [{end_id: 'desc'}]},
        {select: relationSequenceFields}], relationSequenceFields),
    temporal: true, sequence: true,
    producerStage: 'matched', producerTask: 2, totalTasks: 4,
    firstStage: 'consumer_a', secondStage: 'consumer_b',
    expected: [sequenceExpected[1], sequenceExpected[0]],
    fields: relationSequenceFields, fixtureArgs: sequencePolicyArgs(2, 3)},
    {name: 'time-series-filter-select-chain', source: retainedFamilyChain(
      retainedTimeSeriesProgram, 'values_a',
      [{filter: 'true'}, {select: ['time']}], ['time']),
    temporal: true, producerStage: 'values_a', producerTask: 1, totalTasks: 3,
    firstStage: 'consumer_a', secondStage: 'consumer_b',
    expected: [
      {time: '1969-12-31T23:59:59.999Z'},
      {time: '1970-01-01T00:00:00.001Z'},
      {time: '1970-01-01T00:00:00.003Z'},
    ], fields: ['time']},
    {name: 'interval-filter-derive-chain', source: retainedFamilyChain(
      retainedTemporalJoinProgram('interval'), 'crossed',
      [{filter: 'right_value > 20'}, {derive: {total: 'left_value + right_value'}},
        {select: ['left_value', 'right_value', 'total']}],
      ['left_value', 'right_value', 'total']), temporal: true,
    expected: [{left_value: 10, right_value: 21, total: 31}],
    fields: ['left_value', 'right_value', 'total']},
    {name: 'asof-filter-select-chain', source: retainedFamilyChain(
      retainedTemporalJoinProgram('asof'), 'crossed',
      [{filter: 'value > 200'}, {select: ['id', 'value']}], ['id', 'value']),
    temporal: true, expected: [{id: 1, value: 300}], fields: ['id', 'value']},
    {name: 'asof-arithmetic-control-chain', source: retainedFamilyChain(
      retainedTemporalJoinProgram('asof'), 'crossed',
      [{filter: 'id >= 1'}], ['id', 'value']),
    temporal: true, expected: [{id: 1, value: 300}], fields: ['id', 'value']},
    {name: 'nest-filter-derive-chain', source: retainedFamilyChain(
      nestProgram, 'nested', [{filter: 'id > 1'}, {derive: {copy: 'id'}},
        {select: ['copy', 'id', 'items', 'key']}], ['copy', 'id', 'items', 'key']),
    producerStage: 'nested', firstStage: 'nest_consumer_a',
    secondStage: 'nest_consumer_b', expected: [
      {copy: 2, id: 2, items: [{amount: null}, {amount: 10}], key: 1},
      {copy: 3, id: 3, items: [], key: null},
      {copy: 4, id: 4, items: [], key: 2},
    ], fields: ['copy', 'id', 'items', 'key']},
    {name: 'nest-unnest-filter-chain', source: retainedFamilyChain(
      nestProgram, 'nested', [{unnest: {column: 'items', as: 'item', outer: false}},
        {filter: 'id > 1'}, {select: ['id', 'item']}], ['id', 'item']),
    producerStage: 'nested', firstStage: 'nest_consumer_a',
    secondStage: 'nest_consumer_b', expected: [
      {id: 2, item: {amount: null}}, {id: 2, item: {amount: 10}},
    ], fields: ['id', 'item']},
    {name: 'sequence', source: retainedRelationSequenceProgram, temporal: true,
      sequence: true, producerStage: 'matched', producerTask: 2, totalTasks: 4,
      firstStage: 'consumer_a', secondStage: 'consumer_b',
      expected: sequenceExpected, fields: relationSequenceFields,
      fixtureArgs: sequencePolicyArgs(2, 3)},
    {name: 'sequence-empty', source: (() => {
      const program = structuredClone(retainedRelationSequenceProgram);
      program.stages.find(stage => stage.id === 'values_a')
        .steps[0].values.rows = [];
      return program;
    })(), temporal: true, sequence: true,
    producerStage: 'matched', producerTask: 2, totalTasks: 4,
    firstStage: 'consumer_a', secondStage: 'consumer_b',
    expected: [], fields: relationSequenceFields},
    {name: 'sequence-adjacent-disallow', source: (() => {
      const program = structuredClone(retainedRelationSequenceProgram);
      const matcher = program.stages.find(stage => stage.id === 'matched')
        .steps[0].sequence;
      matcher.contiguity = 'adjacent';
      matcher.overlap = 'disallow';
      return program;
    })(), temporal: true, sequence: true,
    producerStage: 'matched', producerTask: 2, totalTasks: 4,
    firstStage: 'consumer_a', secondStage: 'consumer_b',
    expected: [sequenceExpected[0], sequenceExpected[2]], fields: relationSequenceFields},
    {name: 'time-series', source: retainedTimeSeriesProgram, temporal: true,
      producerStage: 'values_a', producerTask: 1, totalTasks: 3,
      firstStage: 'consumer_a', secondStage: 'consumer_b',
      expected: [
        {time: '1969-12-31T23:59:59.999Z'},
        {time: '1970-01-01T00:00:00.001Z'},
        {time: '1970-01-01T00:00:00.003Z'},
      ], fields: ['time']},
    {name: 'interval-join', source: retainedTemporalJoinProgram('interval'),
      temporal: true,
      expected: [
        {left_value: 10, right_value: 20}, {left_value: 10, right_value: 21},
      ], fields: ['left_value', 'right_value']},
    {name: 'asof-join', source: retainedTemporalJoinProgram('asof'),
      temporal: true,
      expected: [{id: 1, value: 300}], fields: ['id', 'value']},
    {name: 'time-series-empty', source: (() => {
      const program = structuredClone(retainedTimeSeriesProgram);
      const series = program.stages.find(stage => stage.id === 'values_a')
        .steps[0].time_series;
      series.end = series.start;
      return program;
    })(), temporal: true,
    producerStage: 'values_a', producerTask: 1, totalTasks: 3,
    firstStage: 'consumer_a', secondStage: 'consumer_b',
    expected: [], fields: ['time']},
    {name: 'interval-empty-right', source: (() => {
      const program = retainedTemporalJoinProgram('interval');
      program.stages.find(stage => stage.id === 'cross_right')
        .steps[0].values.rows = [];
      program.stages.find(stage => stage.id === 'crossed')
        .steps[0].interval_join.kind = 'left';
      return program;
    })(), temporal: true,
    expected: [10, 11, 12].map(left_value => ({left_value, right_value: null})),
    fields: ['left_value', 'right_value']},
    {name: 'asof-empty-right', source: (() => {
      const program = retainedTemporalJoinProgram('asof');
      program.stages.find(stage => stage.id === 'cross_right')
        .steps[0].values.rows = [];
      program.stages.find(stage => stage.id === 'crossed')
        .steps[0].asof_join.kind = 'left';
      return program;
    })(), temporal: true,
    expected: [{id: 1, value: null}], fields: ['id', 'value']},
    {name: 'append', source: externalAppendProgram,
      expected: [{id: 1}, {id: 2}, {id: 3}, {id: 4}], fields: ['id']},
    {name: 'except-all', source: retainedSetProgram('except'),
      expected: [{id: 1}, {id: 1}, {id: 2}], fields: ['id']},
    {name: 'except-distinct', source: retainedSetProgram('except', 'distinct'),
      expected: [{id: 1}], fields: ['id']},
    {name: 'intersect-all', source: retainedSetProgram('intersect'),
      expected: [{id: 2}, {id: 2}], fields: ['id']},
    {name: 'intersect-distinct', source: retainedSetProgram('intersect', 'distinct'),
      expected: [{id: 2}], fields: ['id']},
    {name: 'cross-join', source: externalCrossJoinProgram,
      expected: [
        {id: 1, tag: 'a'}, {id: 1, tag: 'b'}, {id: 1, tag: 'c'},
        {id: 2, tag: 'a'}, {id: 2, tag: 'b'}, {id: 2, tag: 'c'},
      ], fields: ['id', 'tag']},
    {name: 'nest', source: nestProgram,
      producerStage: 'nested',
      firstStage: 'nest_consumer_a',
      secondStage: 'nest_consumer_b',
      expected: [
        {id: 1, items: [{amount: null}, {amount: 10}], key: 1},
        {id: 2, items: [{amount: null}, {amount: 10}], key: 1},
        {id: 3, items: [], key: null},
        {id: 4, items: [], key: 2},
      ], fields: ['id', 'items', 'key']},
    {name: 'singleton-cross-join', source: retainedSingletonCross,
      expected: [{id: 1, tag: 'a'}, {id: 2, tag: 'a'}], fields: ['id', 'tag']},
    {name: 'append-filter-select', source: retainedBinaryChain(
      externalAppendProgram, [{filter: 'id > 1'}, {select: ['id']}], ['id']),
    expected: [{id: 2}, {id: 3}, {id: 4}], fields: ['id']},
    {name: 'append-filter-arithmetic-control', source: retainedBinaryChain(
      externalAppendProgram, [{filter: 'id >= 1'}], ['id']),
    expected: [1, 2, 3, 4].map(id => ({id})), fields: ['id']},
    {name: 'append-derive-select', source: retainedBinaryChain(
      externalAppendProgram,
      [{derive: {copy: 'id'}}, {select: ['id', 'copy']}],
      ['id', 'copy']),
    expected: [1, 2, 3, 4].map(id => ({id, copy: id})),
    fields: ['id', 'copy']},
    {name: 'append-reuse-input', source: retainedBinaryChain(
      externalAppendProgram,
      [{append: {with: 'r'}}, {filter: 'id > 1'}], ['id']),
    expected: [2, 3, 4, 3, 4].map(id => ({id})), fields: ['id']},
    {name: 'except-all-filter', source: retainedBinaryChain(
      retainedSetProgram('except'), [{filter: 'id > 1'}], ['id']),
    expected: [{id: 2}], fields: ['id']},
    {name: 'except-distinct-empty', source: retainedBinaryChain(
      retainedSetProgram('except', 'distinct'),
      [{filter: 'id > 1'}], ['id']), expected: [], fields: ['id']},
    {name: 'except-empty-input', source: (() => {
      const program = retainedSetProgram('except');
      program.stages.find(stage => stage.id === 'cross_left')
        .steps[0].values.rows = [];
      return retainedBinaryChain(program, [{filter: 'id > 0'}], ['id']);
    })(), expected: [], fields: ['id']},
    {name: 'intersect-all-filter', source: retainedBinaryChain(
      retainedSetProgram('intersect'), [{filter: 'id >= 2'}], ['id']),
    expected: [{id: 2}, {id: 2}], fields: ['id']},
    {name: 'intersect-distinct-empty', source: retainedBinaryChain(
      retainedSetProgram('intersect', 'distinct'),
      [{filter: 'id > 2'}], ['id']), expected: [], fields: ['id']},
    {name: 'intersect-empty-input', source: (() => {
      const program = retainedSetProgram('intersect');
      program.stages.find(stage => stage.id === 'cross_right')
        .steps[0].values.rows = [];
      return retainedBinaryChain(program, [{filter: 'id > 0'}], ['id']);
    })(), expected: [], fields: ['id']},
    {name: 'cross-join-filter', source: retainedBinaryChain(
      externalCrossJoinProgram, [{filter: 'id > 1'}], ['id', 'tag']),
    expected: [{id: 2, tag: 'a'}, {id: 2, tag: 'b'},
      {id: 2, tag: 'c'}], fields: ['id', 'tag']},
    {name: 'singleton-cross-join-filter', source: retainedBinaryChain(
      retainedSingletonCross, [{filter: 'id > 1'}], ['id', 'tag']),
    expected: [{id: 2, tag: 'a'}], fields: ['id', 'tag']},
    {name: 'cross-join-derive-select', source: retainedBinaryChain(
      externalCrossJoinProgram,
      [{derive: {copy: 'tag'}}, {select: ['id', 'tag', 'copy']}],
      ['id', 'tag', 'copy']),
    expected: [1, 2].flatMap(id => ['a', 'b', 'c'].map(tag =>
      ({id, tag, copy: tag}))), fields: ['id', 'tag', 'copy']},
    {name: 'sort-filter-select', source: retainedUnaryChain(
      [{sort: [{id: 'desc'}]}],
      [{filter: 'id > 0'}, {select: ['id']}], ['id']),
    expected: [4, 3, 2, 1].map(id => ({id})), fields: ['id']},
    {name: 'distinct-filter-select', source: retainedUnaryChain(
      [{distinct: true}], [{filter: 'id > 0'}, {select: ['id']}],
      ['id'], [{id: 1}, {id: 1}, {id: 2}]),
    expected: [1, 2, 3, 4].map(id => ({id})), fields: ['id']},
    {name: 'top-k-filter-select', source: retainedUnaryChain(
      [{assert_rows: {unique_by: ['id']}},
        {top_k: {k: 2, by: [{id: 'desc'}]}}],
      [{filter: 'id > 0'}, {select: ['id']}], ['id']),
    expected: [{id: 4}, {id: 3}], fields: ['id']},
    {name: 'partitioned-top-k-filter-select', source: retainedUnaryChain(
      [{assert_rows: {unique_by: ['id']}},
        {top_k_by: {
          partition_by: ['group'], k: 1, by: [{id: 'desc'}],
        }}],
      [{filter: 'id > 0'}, {select: ['id', 'group']}],
      ['id', 'group'], [
        {id: 1, group: 'a'}, {id: 2, group: 'a'},
        {id: 3, group: 'b'}, {id: 4, group: 'b'},
      ], {
        id: {type: 'number', nullable: false},
        group: {type: 'string', nullable: false},
      }),
    expected: [{id: 2, group: 'a'}, {id: 4, group: 'b'}],
    producerCidRows: [{group: 'a', id: 2}, {group: 'b', id: 4}],
    fields: ['id', 'group']},
    {name: 'dedupe-filter-select', source: retainedUnaryChain(
      [{dedupe_rows: {by: ['id'], order_by: [{amount: 'desc'}]}}],
      [{filter: 'amount > 0'}, {select: ['id', 'amount']}],
      ['id', 'amount'], [
        {id: 1, amount: 10}, {id: 1, amount: 20},
        {id: 1, amount: 15},
      ], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{id: 1, amount: 20}],
    producerCidRows: [{amount: 20, id: 1}], fields: ['id', 'amount']},
    {name: 'assert-filter-select', source: retainedUnaryChain(
      [{assert_rows: {where: 'id > 0'}}],
      [{filter: 'id > 0'}, {select: ['id']}], ['id']),
    expected: [1, 2, 3, 4].map(id => ({id})), fields: ['id']},
    {name: 'unpivot-filter-select', source: retainedUnaryChain(
      [{unpivot: {
        columns: ['jan', 'feb'], keep: ['id'],
        name_column: 'metric', value_column: 'value',
      }}],
      [{filter: 'id > 1'}, {select: ['id', 'metric', 'value']}],
      ['id', 'metric', 'value'], [
        {id: 1, jan: 10, feb: 20},
        {id: 2, jan: null, feb: 30},
      ], {
        id: {type: 'number', nullable: false},
        jan: {type: 'number', nullable: true},
        feb: {type: 'number', nullable: true},
      }),
    expected: [
      {id: 2, metric: 'jan', value: null},
      {id: 2, metric: 'feb', value: 30},
    ], fields: ['id', 'metric', 'value']},
    {name: 'unnest-filter-select', source: retainedUnaryChain(
      [{unnest: {
        column: 'items', as: 'item', with_index: 'position', outer: true,
      }}],
      [{filter: 'id > 1'}, {select: ['id', 'item', 'position']}],
      ['id', 'item', 'position'], [
        {id: 1, items: [2, null]},
        {id: 2, items: []},
        {id: 3, items: null},
      ], {
        id: {type: 'number', nullable: false},
        items: {type: 'array', nullable: true, max_items: 2,
          items: {type: 'number', nullable: true}},
      }),
    expected: [
      {id: 2, item: null, position: null},
      {id: 3, item: null, position: null},
    ], fields: ['id', 'item', 'position']},
    {name: 'lag-filter-select', source: retainedUnaryChain(
      [{assert_rows: {unique_by: ['id']}},
        {lag: {
          partition_by: [], order_by: [{id: 'asc'}],
          field: 'id', output: 'previous', offset: 1,
        }}],
      [{filter: 'id > 0'}, {select: ['id', 'previous']}],
      ['id', 'previous']),
    expected: [
      {id: 1, previous: null}, {id: 2, previous: 1},
      {id: 3, previous: 2}, {id: 4, previous: 3},
    ], fields: ['id', 'previous']},
    {name: 'json-pick-filter-select', source: retainedUnaryChain(
      [{json_pick: {
        column: 'payload', path: ['inner', 'leaf'], output: 'picked',
      }}],
      [{filter: 'id > 0'}, {select: ['id', 'picked']}],
      ['id', 'picked'], [
        {id: 1, payload: {inner: {leaf: 3}}},
        {id: 2, payload: null},
      ], {
        id: {type: 'number', nullable: false},
        payload: {type: 'object', nullable: true, fields: {
          inner: {type: 'object', nullable: false, fields: {
            leaf: {type: 'number', nullable: false},
          }},
        }},
      }),
    expected: [{id: 1, picked: 3}, {id: 2, picked: null}],
    fields: ['id', 'picked']},
    {name: 'watermark-filter-select', source: retainedUnaryChain(
      [{watermark_rows: {
        time: 'time', late_policy: 'mark', watermark_ms: 90,
      }}],
      [{filter: 'id > 0'}, {select: [
        'id', 'time', 'watermark_decision', 'watermark_late', 'watermark_ms',
      ]}],
      ['id', 'time', 'watermark_decision', 'watermark_late', 'watermark_ms'],
      [{id: 1, time: 100}, {id: 2, time: 80}, {id: 3, time: 95}], {
        id: {type: 'number', nullable: false},
        time: {type: 'number', nullable: false},
      }),
    expected: [
      {id: 1, time: 100, watermark_decision: 'keep',
        watermark_late: false, watermark_ms: 90},
      {id: 2, time: 80, watermark_decision: 'mark',
        watermark_late: true, watermark_ms: 90},
      {id: 3, time: 95, watermark_decision: 'keep',
        watermark_late: false, watermark_ms: 90},
    ], fields: [
      'id', 'time', 'watermark_decision', 'watermark_late', 'watermark_ms',
    ]},
    {name: 'group-filter-select', source: retainedUnaryChain(
      [{group: {by: ['id'], aggregates: {n: {fn: 'count'}}}}],
      [{filter: 'n > 0'}, {select: ['id', 'n']}],
      ['id', 'n'], [{id: 1}, {id: 1}, {id: 2}]),
    expected: [{id: 1, n: 2}, ...[2, 3, 4].map(id => ({id, n: 1}))],
    fields: ['id', 'n']},
    {name: 'group-sum-filter-select', source: retainedUnaryChain(
      [{group: {by: ['id'], aggregates: {
        total: {fn: 'sum', field: 'amount'},
      }}}], [{filter: 'total > 0'}, {select: ['id', 'total']}],
      ['id', 'total'], [
        {id: 1, amount: 2}, {id: 1, amount: 3},
        {id: 2, amount: 4},
      ], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{id: 1, total: 5}, {id: 2, total: 4}],
    fields: ['id', 'total']},
    {name: 'group-sum-avg-filter-select', source: retainedUnaryChain(
      [{group: {by: ['id'], aggregates: {
        mean: {fn: 'avg', field: 'amount'},
        total: {fn: 'sum', field: 'amount'},
      }}}], [{filter: 'total > 0'},
        {select: ['id', 'mean', 'total']}],
      ['id', 'mean', 'total'], [
        {id: 1, amount: 2}, {id: 1, amount: 4},
        {id: 2, amount: 8},
      ], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [
      {id: 1, mean: 3, total: 6}, {id: 2, mean: 8, total: 8},
    ], fields: ['id', 'mean', 'total']},
    {name: 'group-sum-avg-empty-global', source: retainedUnaryChain(
      [{filter: 'id < 0'}, {group: {by: [], aggregates: {
        mean: {fn: 'avg', field: 'amount'},
        total: {fn: 'sum', field: 'amount'},
      }}}], [{select: ['mean', 'total']}],
      ['mean', 'total'], [{id: 1, amount: 2}], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{mean: null, total: null}], fields: ['mean', 'total']},
    {name: 'group-sum-global-sum', source: retainedUnaryChain(
      [{group: {by: ['id'], aggregates: {
        total: {fn: 'sum', field: 'amount'},
      }}}], [
        {filter: 'total > 0'},
        {group: {by: [], aggregates: {
          grand: {fn: 'sum', field: 'total'},
        }}},
        {select: ['grand']},
      ], ['grand'], [
        {id: 1, amount: 2}, {id: 1, amount: 3},
        {id: 2, amount: 4},
      ], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{grand: 9}], fields: ['grand']},
    {name: 'row-window-filter-select', source: retainedUnaryChain(
      [{row_window: {kind: 'fixed', time: 'id', size: 10}}],
      [{filter: 'id > 0'},
        {select: ['id', 'window_start', 'window_end']}],
      ['id', 'window_start', 'window_end']),
    expected: [1, 2, 3, 4].map(id =>
      ({id, window_start: 0, window_end: 10})),
    fields: ['id', 'window_start', 'window_end']},
    {name: 'analytic-filter-select', source: retainedUnaryChain(
      [{analytic: {
        partition_by: [], order_by: [{id: 'asc'}],
        frame: {start: 'unbounded_preceding', end: 'current_row'},
        functions: {n: {fn: 'count', field: 'id'}},
      }}], [{filter: 'n > 0'}, {select: ['id', 'n']}], ['id', 'n']),
    expected: [1, 2, 3, 4].map(id => ({id, n: id})), fields: ['id', 'n']},
    {name: 'analytic-sum-filter-select', source: retainedUnaryChain(
      [{analytic: {
        partition_by: [], order_by: [{id: 'asc'}],
        frame: {start: 'unbounded_preceding', end: 'current_row'},
        functions: {total: {fn: 'sum', field: 'amount'}},
      }}], [{filter: 'total > 0'}, {select: ['id', 'total']}],
      ['id', 'total'], [
        {id: 1, amount: 2}, {id: 2, amount: 3},
        {id: 3, amount: 4},
      ], {
        id: {type: 'number', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [
      {id: 1, total: 2}, {id: 2, total: 5}, {id: 3, total: 9},
    ], fields: ['id', 'total']},
    {name: 'pivot-filter-select', source: retainedUnaryChain(
      [{pivot: {
        index: ['id'], column: 'status', values: ['a', 'b'],
        value: 'amount', aggregate: 'max',
      }}], [{filter: 'id > 0'}, {select: ['a', 'b', 'id']}],
      ['a', 'b', 'id'], [
        {id: 1, status: 'a', amount: 3},
        {id: 1, status: 'b', amount: 4},
        {id: 2, status: 'a', amount: 5},
      ], {
        id: {type: 'number', nullable: false},
        status: {type: 'string', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{a: 3, b: 4, id: 1}, {a: 5, b: null, id: 2}],
    fields: ['a', 'b', 'id']},
    {name: 'pivot-sum-filter-select', source: retainedUnaryChain(
      [{pivot: {
        index: ['id'], column: 'status', values: ['a', 'b'],
        value: 'amount', aggregate: 'sum',
      }}], [{filter: 'id > 0'}, {select: ['a', 'b', 'id']}],
      ['a', 'b', 'id'], [
        {id: 1, status: 'a', amount: 2},
        {id: 1, status: 'a', amount: 3},
        {id: 1, status: 'b', amount: 4},
        {id: 2, status: 'a', amount: 5},
      ], {
        id: {type: 'number', nullable: false},
        status: {type: 'string', nullable: false},
        amount: {type: 'number', nullable: false},
      }),
    expected: [{a: 5, b: 4, id: 1}, {a: 5, b: null, id: 2}],
    fields: ['a', 'b', 'id']},
    {name: 'window-group-filter-select', source: retainedUnaryChain(
      [{row_window: {kind: 'fixed', time: 'id', size: 10}},
        {window_group: {by: [], aggregates: {n: {fn: 'count'}}}}],
      [{filter: 'n > 0'},
        {select: ['n', 'window_start', 'window_end']}],
      ['n', 'window_start', 'window_end']),
    expected: [{n: 4, window_start: 0, window_end: 10}],
    fields: ['n', 'window_start', 'window_end']},
  ]) {
    const program = structuredClone(source);
    program.results = {
      producer: {from: {stage: producerStage, result: 'r'}},
      first: {from: {stage: firstStage, result: 'r'}},
      second: {from: {stage: secondStage, result: 'r'}},
    };
    let binaryFixture;
    try {
      binaryFixture = sequence
        ? fixture.strategyFixtureTeaSequenceCreate(...fixtureArgs, JSON.stringify(program))
        : temporal
        ? fixture.strategyFixtureTeaCreate(...args, JSON.stringify(program))
        : name.includes('-sum-')
        ? fixture.strategyFixtureNumericCreate(
          ...(name.startsWith('analytic-') ? analyticArgs : args),
          JSON.stringify(program)) : fixture.strategyFixtureCreate(
        ...(name.startsWith('analytic-') ? analyticArgs : args),
        JSON.stringify(program));
    } catch (error) {
      throw new Error(`${name}: fixture preparation failed: ${String(error)}`,
        {cause: error});
    }
    assert.equal(fixture.strategyFixtureTaskStepCount(binaryFixture, producerTask),
      program.stages.find(stage => stage.id === producerStage).steps.length,
      `${name}: the producer must remain one physical task`);
    const binaryCapture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(binaryFixture), suppliedLimits);
    const binaryDirectory = await mkdtemp(join(
      tmpdir(), `actql-retained-${name}-`));
    const publicationDirectory = await mkdtemp(join(
      tmpdir(), `actql-retained-${name}-publication-`));
    const binaryStore = await createLocalRetainedStore({
      parentDirectory: binaryDirectory,
      capacityBytes: 8 * 1024 * 1024,
      maxFrameBytes: 1024 * 1024,
    });
    const leases = [];
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases.push(key);
      let writer, closed = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && !closed ? bytes : 0,
          cleanupPending: false}),
        reserve: value => (writer = binaryStore.reserve(value)),
        close() { closed = true; writer?.cancel(); },
        async cleanup() { await writer?.cleanupHandle?.retry?.(); },
      });
    });
    let owner, failedExecution, publicationStore;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        binaryFixture, binaryCapture.source()), true);
      const setup = temporal
        ? fixture.strategyFixtureTeaRetainedSubset(binaryFixture)
        : fixture.strategyFixtureRetainedLocalSubset(binaryFixture);
      const runtime = runtimeCore(hostRuntime);
      publicationStore = await openLocalPublicationStore({
        directory: publicationDirectory,
        storeAuthorityCid: hash(`retained-${name}-publication-store`),
        capacityBytes: 4 * 1024 * 1024,
        maxObjectBytes: publicationResultExportLimits.maxWireBytes,
        maxObjects: 100,
        maxContractNodes: 10000,
        maxContractDepth: 64,
      }, runtime.publicationControl);
      const plan = standardPublicationPlan(
        runtime, runtime.programDefinitionCid(setup),
        runtime.resultInventory(setup).length,
        `retained-${name}-publication-attempt`);
      try {
        owner = await runPublishedCapturedStrategy(
          setup, {store: publicationStore, plan},
          {local: configuration}, new AbortController().signal);
      } catch (error) {
        failedExecution = error.execution;
        throw new Error(`${name}: ${String(error.cause)}; ` +
          `execution=${failedExecution?.status}; ` +
          `completed=${inspect(failedExecution?.completed?.map(item => item.task))}; ` +
          `failure=${failedExecution?.failure?.code}: ` +
          inspect(failedExecution?.failure?.cause, {depth: 7}),
        {cause: error});
      }
      assert.equal(owner.status, 'published', name);
      assert.equal(owner.execution.status, 'host-tasks-completed', name);
      assert.deepEqual(owner.execution.completed.map(item => item.realization),
        Array(totalTasks).fill('local'), name);
      assert(owner.execution.completed.every(item =>
        item.outputRepresentation === 'retained-file'), name);
      assert.equal(leases.length, totalTasks, name);
      // Task output identity precedes the Named Result field projection;
      // producerCidRows fixes the canonical task-field order when it differs
      // from the authored Result projection. Publication checks both views.
      const authority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: () => ({
          authorizationContextCid: hash(`retained-${name}-context`),
          dataCeilingCid: hash(`retained-${name}-ceiling`),
          egressAdmissionCid: hash(`retained-${name}-egress`),
          expiresAt: '2026-09-18T01:00:00.000Z',
          maxBytes: 100000,
          maxUses: 1,
        }),
        authorizeResultRead: () => true,
      });
      const accessService = installNodeResultAccessService({
        store: publicationStore,
        control: runtime.publicationControl,
        authority,
        now: () => '2026-09-18T00:30:00.000Z',
        limits: {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64},
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      for (const [resultName, rows] of Object.entries({
        producer: expected,
        first: expected,
        second: expected.map(row => Object.fromEntries(
          [...fields].reverse().map(field => [field, row[field]]))),
      })) {
        const delivered = [];
        await deliverAuthorizedResult(accessService, {
          indexKey: {
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          },
          principalId: 'principal-a',
          purpose: 'download',
          resultName,
          format: 'json',
          attemptId: `retained-${name}-${resultName}`,
        }, {
          async write(bytes) {
            delivered.push(Buffer.from(bytes));
            return {confirmedBytes: bytes.byteLength};
          },
          async finish() { return {confirmed: true}; },
        }, new AbortController().signal);
        assert.deepEqual(JSON.parse(Buffer.concat(delivered).toString('utf8')),
          rows, `${name}: ${resultName}`);
      }
      assert.equal(fixture.strategyFixtureCid(binaryFixture, producerTask),
        fixture.strategyFixtureCid(binaryFixture, producerTask + 1),
        `${name}: retained producer and first consumer must agree`);
      // The JSON expectation is not a typed CID preimage for window boundary
      // values. Their published values and independent consumer are checked
      // above; the producer and first consumer still share the exact CID.
      if (!name.includes('derive') && !name.includes('window')) {
        assert.equal(fixture.strategyFixtureCid(binaryFixture, producerTask),
          hash(producerCidRows ?? expected),
          `${name}: producer task`);
      }
    } finally {
      binaryCapture.close();
      if (owner) {
        await owner.close();
        assert.equal(await owner.cleanup(), true);
        assert.equal(owner.execution.usage().heldBytes, 0n);
        assert.equal(owner.execution.usage().reservedExecutionBytes, 0n);
      } else if (failedExecution) {
        await failedExecution.close();
        assert.equal(await failedExecution.cleanup(), true);
        assert.equal(failedExecution.usage().heldBytes, 0n);
        assert.equal(failedExecution.usage().reservedExecutionBytes, 0n);
      }
      await publicationStore?.close();
      binaryStore.close();
      await binaryStore.cleanup();
      await rm(binaryDirectory, {recursive: true, force: true});
      await rm(publicationDirectory, {recursive: true, force: true});
    }
  }
  for (const {name, mode: fixtureMode, temporal, chain = false,
    eventsAsOf = false} of [
    {name: 'cancel'}, {name: 'cancel-after-filter'},
    {name: 'nest-cancel'},
    {name: 'cancel-after-group'},
    {name: 'cancel-after-numeric-group'},
    {name: 'compute-failure'},
    {name: 'store-failure'}, {name: 'finalize-failure'},
    {name: 'cancel', temporal: 'series'},
    {name: 'cancel', temporal: 'interval'},
    {name: 'cancel', temporal: 'asof'},
    {name: 'store-failure', temporal: 'interval'},
    {name: 'finalize-failure', temporal: 'asof'},
    {name: 'cancel', temporal: 'sequence'},
    {name: 'store-failure', temporal: 'sequence'},
    {name: 'finalize-failure', temporal: 'sequence'},
    {name: 'cancel-after-filter', temporal: 'series', chain: true},
    {name: 'compute-failure', temporal: 'asof', chain: true},
    {name: 'store-failure', temporal: 'interval', chain: true},
    {name: 'finalize-failure', temporal: 'sequence', chain: true},
    {name: 'session-in-flight-filter-cancel', mode: 'cancel-after-filter',
      temporal: 'session', chain: true},
    {name: 'session-later-arithmetic', mode: 'compute-failure',
      temporal: 'session', chain: true},
    {name: 'session-store-append-failure', mode: 'store-failure',
      temporal: 'session', chain: true},
    {name: 'session-store-finalize-failure', mode: 'finalize-failure',
      temporal: 'session', chain: true},
    {name: 'session-cleanup-retry', mode: 'compute-cleanup-failure',
      temporal: 'session', chain: true},
    {name: 'events-asof-in-flight-cancel', mode: 'cancel',
      temporal: 'asof', eventsAsOf: true},
    {name: 'events-asof-later-arithmetic', mode: 'compute-failure',
      temporal: 'asof', eventsAsOf: true},
    {name: 'events-asof-cleanup-retry', mode: 'compute-cleanup-failure',
      temporal: 'asof', eventsAsOf: true},
  ]) {
    const mode = fixtureMode ?? name;
    const caseName = fixtureMode === undefined
      ? (temporal ? `${temporal}-${mode}` : mode) + (chain ? '-chain' : '')
      : name;
    const series = temporal === 'series';
    const sequence = temporal === 'sequence';
    const session = temporal === 'session';
    const computeFailure = mode === 'compute-failure' ||
      mode === 'compute-cleanup-failure';
    // Events construction is task 3; as-of and the later row filter own
    // separate checked generations. Neither is disguised as a row file.
    const producerTask = eventsAsOf ? (computeFailure ? 5 : 4)
      : series ? 1 : sequence || session ? 2 : 3;
    const priorTasks = eventsAsOf ? (computeFailure ? [1, 2, 3, 4] : [1, 2, 3])
      : series ? [] : sequence || session ? [1] : [1, 2];
    const numericGroup = mode === 'cancel-after-numeric-group';
    const grouped = mode === 'cancel-after-group' || numericGroup;
    const nestCancel = mode === 'nest-cancel';
    const cancelling = mode === 'cancel' ||
      mode === 'cancel-after-filter' || grouped || nestCancel;
    let program = temporal ? structuredClone(series
      ? retainedTimeSeriesProgram : sequence
      ? retainedRelationSequenceProgram : session
      ? retainedRelationSessionProgram : retainedTemporalJoinProgram(temporal))
      : nestCancel ? structuredClone(nestProgram)
      : retainedBinaryChain(externalAppendProgram,
      grouped
        ? [{group: {by: ['id'], aggregates: {
          n: numericGroup ? {fn: 'sum', field: 'id'} : {fn: 'count'},
        }}},
          {filter: 'n > 0'}]
        : [{filter: mode === 'compute-failure'
          ? '1 / (id - id) > 0' : 'id >= 10'}],
      grouped ? ['id', 'n'] : ['id']);
    if (chain) {
      const producerId = series ? 'values_a' : sequence ? 'matched'
        : session ? 'sessionized' : 'crossed';
      const fields = program.stages.find(stage => stage.id === producerId)
        .results.r.fields;
      program = retainedFamilyChain(program, producerId,
        [{filter: computeFailure
          ? '1 / (id - id) > 0' : 'true'}], fields);
    }
    if (session) {
      // One record costs 44 session work units, 13 projection units, and
      // one chain handoff. Work above 58 reaches the following filter.
      program.stages.find(stage => stage.id === 'values_a').steps[0].values.rows =
        [{id: 1, clock: 0, payload: 'a'}];
    }
    if (eventsAsOf) {
      const joined = program.stages.find(stage => stage.id === 'crossed');
      joined.steps = [{
        from: 'l', to_events: {id: 'id', time: 'clock'}, as: 'source',
      }, {...joined.steps[0], from: 'source', as: 'matched'}, {
        from: 'matched', filter: computeFailure
          ? '1 / (id - id) > 0' : 'true', as: 'out',
      }];
    }
    program.results = nestCancel ? {
      producer: {from: {stage: 'nested', result: 'r'}},
      first: {from: {stage: 'nest_consumer_a', result: 'r'}},
      second: {from: {stage: 'nest_consumer_b', result: 'r'}},
    } : {
      producer: {from: {stage: series ? 'values_a' : sequence ? 'matched'
        : session ? 'sessionized' : 'crossed', result: 'r'}},
      first: {from: {stage: series || sequence || session ? 'consumer_a' : 'external_cross_consumer_a', result: 'r'}},
      second: {from: {stage: series || sequence || session ? 'consumer_b' : 'external_cross_consumer_b', result: 'r'}},
    };
    if (!temporal && (mode === 'cancel-after-filter' || grouped)) {
      // Three rows give the Append child exactly 28 work units. Its bounded
      // handoff costs one more; work above 29 proves the filter has advanced.
      program.stages.find(stage => stage.id === 'cross_left')
        .steps[0].values.rows = [{id: 1}];
      program.stages.find(stage => stage.id === 'cross_right')
        .steps[0].values.rows = [{id: 2}, {id: 3}];
    } else if (!temporal && mode !== 'compute-failure' && !nestCancel) {
      program.stages.find(stage => stage.id === 'cross_left').steps[0]
        .values.rows = Array.from({length: 30}, (_, id) => ({id}));
      program.stages.find(stage => stage.id === 'cross_right').steps[0]
        .values.rows = Array.from({length: 30}, (_, index) => ({id: index + 30}));
    }
    const binaryFixture = sequence
      ? fixture.strategyFixtureTeaSequenceCreate(...args, JSON.stringify(program))
      : temporal
      ? fixture.strategyFixtureTeaCreate(...args, JSON.stringify(program))
      : numericGroup
      ? fixture.strategyFixtureNumericCreate(...args, JSON.stringify(program))
      : fixture.strategyFixtureCreate(...args, JSON.stringify(program));
    const binaryCapture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(binaryFixture), suppliedLimits);
    const directory = await mkdtemp(join(tmpdir(),
      `actql-retained-${caseName}-`));
    const store = await createLocalRetainedStore({
      parentDirectory: directory,
      capacityBytes: 8 * 1024 * 1024,
      maxFrameBytes: 1024 * 1024,
    });
    let leases = 0, failedAppends = 0, failedFinalizations = 0;
    let failurePublicationStore;
    let permitCleanup = mode !== 'finalize-failure' &&
      mode !== 'compute-cleanup-failure';
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases++;
      const failWrite =
        (mode === 'store-failure' || mode === 'finalize-failure') &&
        leases === producerTask;
      const failThisOutput = failWrite ||
        (mode === 'compute-cleanup-failure' && leases === 1);
      let writer, closed = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && (!closed ||
          (failThisOutput && !permitCleanup)) ? bytes : 0,
          cleanupPending: (failThisOutput && !permitCleanup) ||
            (writer?.cleanupHandle?.status?.().pending ?? false)}),
        reserve(value) {
          writer = store.reserve(value);
          if (!failWrite) return writer;
          return Object.freeze({
            start: () => writer.start(),
            append: async part => {
              if (mode !== 'store-failure') return writer.append(part);
              failedAppends++;
              throw new Error('InjectedRetainedAppendFailure');
            },
            seal: async identity => {
              failedFinalizations++;
              // Finalize the actual file before losing its acknowledgement.
              // The lease must still retain and reclaim the resulting body.
              await writer.seal(identity);
              throw new Error('InjectedRetainedFinalizeFailure');
            },
          });
        },
        close() {
          if (cancelling &&
              cancellation.signal.aborted) {
            assert.equal(sawStop, true, 'input release must follow confirmed stop');
          }
          closed = true;
          writer?.cancel();
        },
        async cleanup() {
          if (failThisOutput && !permitCleanup) {
            throw new Error('InjectedRetainedCleanupPending');
          }
          await writer?.cleanupHandle?.retry?.();
        },
      });
    });
    const cancellation = new AbortController();
    let sawWork = false, sawStop = false, scheduled = false;
    let producerWork = 0n, sawLaterWork = false;
    let dispatches = 0;
    const observedRuntime = new Proxy(hostRuntime, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_Dispatch' &&
            property !== 'strategyModule_local_ManagedStart') {
          return Reflect.get(target, property, receiver);
        }
        return (...callArguments) => {
          const dispatch = ++dispatches;
          const operations = checked(target[property](...callArguments));
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, name, operationReceiver) {
              if (name === 'execute') {
                assert.fail(`${caseName}: retained task ran synchronously`);
              }
              if (name === 'execution_stopped') {
                return () => {
                  const stopped = operation.execution_stopped();
                  if (dispatch === producerTask && cancellation.signal.aborted && stopped) {
                    sawStop = true;
                  }
                  return stopped;
                };
              }
              if (name !== 'advance') {
                return Reflect.get(operation, name, operationReceiver);
              }
              return quantum => {
                const result = operation.advance(cancelling
                  ? Math.min(quantum, 1) : quantum);
                if (dispatch === producerTask && !cancellation.signal.aborted) {
                  const poll = checked(result);
                  producerWork += poll.work;
                  if ((mode === 'cancel-after-filter' || grouped) &&
                      producerWork > (chain && series ? 5n
                        : chain && session ? 58n : 29n) &&
                      !poll.complete) {
                    sawLaterWork = true;
                  }
                  if (!poll.complete && poll.progress > 0n) {
                    sawWork = true;
                  }
                  if (cancelling && !scheduled && (mode === 'cancel' || nestCancel
                    ? sawWork : sawLaterWork)) {
                    scheduled = true;
                    setTimeout(() => cancellation.abort(), 0);
                  }
                }
                return result;
              };
            },
          })};
        };
      },
    });
    const observedHost = createNodeHostEntry(
      () => observedRuntime, installStrategyContributions);
    let execution;
    let failedCloseObserved = false;
    try {
      assert.equal(fixture.strategyFixtureOpen(
        binaryFixture, binaryCapture.source()), true);
      const setup = temporal
        ? fixture.strategyFixtureTeaRetainedSubset(binaryFixture)
        : fixture.strategyFixtureRetainedLocalSubset(binaryFixture);
      assert.equal(fixture.strategyFixtureTaskStepCount(binaryFixture, producerTask),
        eventsAsOf ? 1 : program.stages.find(stage => stage.id ===
          (series ? 'values_a' : sequence ? 'matched' : session ? 'sessionized' : nestCancel
            ? 'nested' : 'crossed')).steps.length,
        `${caseName}: cancellation and failures preserve the selected task shape`);
      if (mode === 'finalize-failure') {
        const runtime = runtimeCore(observedRuntime);
        failurePublicationStore = await openLocalPublicationStore({
          directory: join(directory, 'publication'),
          storeAuthorityCid: hash('binary-finalize-failure-store'),
          capacityBytes: 4 * 1024 * 1024,
          maxObjectBytes: publicationResultExportLimits.maxWireBytes,
          maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
        }, runtime.publicationControl);
        const plan = standardPublicationPlan(runtime,
          runtime.programDefinitionCid(setup),
          runtime.resultInventory(setup).length, 'binary-finalize-failure');
        await assert.rejects(observedHost.runPublishedCapturedStrategy(setup,
          {store: failurePublicationStore, plan}, {local: configuration},
          cancellation.signal), error => {
          execution = error.execution;
          return error.code === 'CapturedRunPublicationFailed';
        });
        await assert.rejects(failurePublicationStore.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      } else execution = await runInstalledStrategy(
        setup,
        runtimeCore(observedRuntime),
        [localStrategyContribution(observedRuntime, setup, checked,
          configuration)],
        cancellation.signal,
      );
      assert.equal(execution.status, 'host-tasks-failed', caseName);
      assert.deepEqual(execution.completed.map(item => item.task), priorTasks, caseName);
      const dispatchesAtFailure = dispatches;
      assert.equal(dispatchesAtFailure, producerTask, caseName);
      if (cancelling) {
        assert.equal(sawWork, true);
        if (mode === 'cancel-after-filter' || grouped) {
          assert.equal(sawLaterWork, true);
        }
        assert.equal(sawStop, true);
        assert.equal(execution.failure?.name, 'AbortError');
        assert.equal(leases, eventsAsOf ? 2 : priorTasks.length);
      } else if (computeFailure) {
        assert.equal(leases, session ? 1 : 2);
        assert.equal(execution.failure?.code, 'MoonBitHostFailure');
        const arithmeticFailure = eventsAsOf
          ? fixture.strategyFixtureRetainedEventsAsOfArithmetic
          : fixture.strategyFixtureRetainedChainFilterArithmetic;
        assert.equal(arithmeticFailure(execution.failure.cause), true);
        if (mode === 'compute-cleanup-failure') {
          await assert.rejects(async () => execution.close(),
            /InjectedRetainedCleanupPending/);
          failedCloseObserved = true;
          assert.equal(execution.cleanupPending(), true,
            'failed close must retain the mixed input cleanup owner');
          await assert.rejects(execution.cleanup(), error =>
            error instanceof AggregateError &&
            error.errors.some(cause =>
              cause.message === 'InjectedRetainedCleanupPending'));
          assert.equal(execution.cleanupPending(), true);
          assert(execution.usage().reservedExecutionBytes > 0n ||
            execution.usage().heldBytes > 0n);
          assert.equal(dispatches, dispatchesAtFailure,
            `${caseName}: failed cleanup must not rerun Compute`);
          permitCleanup = true;
        }
      } else {
        assert.equal(leases, producerTask);
        assert.equal(failedAppends, mode === 'store-failure' ? 1 : 0);
        assert.equal(failedFinalizations, mode === 'finalize-failure' ? 1 : 0);
        if (mode === 'finalize-failure') {
          assert.equal(execution.cleanupPending(), true);
          assert.equal(await execution.cleanup(), false);
          assert(execution.usage().reservedExecutionBytes > 0n ||
            execution.usage().heldBytes > 0n);
          assert.equal(dispatches, dispatchesAtFailure,
            `${caseName}: failed cleanup must not rerun Compute`);
          permitCleanup = true;
        }
      }
    } catch (error) {
      throw new Error(`${caseName}: ${String(error)}; ` +
        `completed=${inspect(execution?.completed?.map(item => item.task))}; ` +
        `failure=${inspect(execution?.failure, {depth: 7})}`, {cause: error});
    } finally {
      const dispatchesBeforeCleanup = dispatches;
      permitCleanup = true;
      binaryCapture.close();
      if (!failedCloseObserved) await execution?.close();
      if (execution) {
        assert.equal(await execution.cleanup(), true);
        assert.equal(dispatches, dispatchesBeforeCleanup,
          `${caseName}: cleanup must not redispatch Compute`);
        assert.equal(execution.cleanupPending(), false);
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
      store.close();
      await store.cleanup();
      await failurePublicationStore?.close();
      await rm(directory, {recursive: true, force: true});
    }
  }
  // The same provider budgets used by the independent kernel proofs must
  // reach the retained driver unchanged. No measured successful run supplies
  // these expectations. Source Values and downstream consumers use separate
  // task budgets; only the producer is requested in these boundary Programs.
  const retainedBoundaryProgram = (operation, left, right) => {
    const program = structuredClone(operation === 'cross_join'
      ? externalCrossJoinProgram : externalAppendProgram);
    program.stages = program.stages.filter(stage =>
      !stage.id.startsWith('external_cross_consumer_'));
    program.stages.find(stage => stage.id === 'cross_left')
      .steps[0].values.rows = left;
    program.stages.find(stage => stage.id === 'cross_right')
      .steps[0].values.rows = right;
    if (operation === 'except') {
      program.stages.find(stage => stage.id === 'crossed').steps[0] = {
        from: 'l', except: {with: 'r', duplicates: 'all'}, as: 'out',
      };
    }
    program.results = {producer: {from: {stage: 'crossed', result: 'r'}}};
    return program;
  };
  const appendBoundary = retainedBoundaryProgram('append',
    [{id: 1}, {id: 2}], [{id: 3}]);
  const appendChainBoundary = retainedBinaryChain(
    retainedBoundaryProgram('append', [{id: 1}], [{id: 2}, {id: 3}]),
    [{filter: 'id > 1'}], ['id']);
  const setWorkBoundary = retainedBoundaryProgram('except', [{id: 1}], []);
  const setSpaceBoundary = retainedBoundaryProgram('except',
    [{id: 1}, {id: 2}], [{id: 3}]);
  const crossBoundary = retainedBoundaryProgram('cross_join',
    [{id: 1}, {id: 2}], [{tag: 'a'}, {tag: 'b'}]);
  const rejectedChain = structuredClone(appendBoundary);
  rejectedChain.stages.find(stage => stage.id === 'crossed').steps = [
    {from: 'l', append: {with: 'r'}, as: 'appended'},
    {from: 'l', filter: 'true', as: 'out'},
  ];
  for (const {name, program, work, space, expected} of [
    {name: 'append-exact', program: appendBoundary, work: 26, space: 10,
      expected: [{id: 1}, {id: 2}, {id: 3}]},
    {name: 'append-work-short', program: appendBoundary, work: 25, space: 10},
    {name: 'append-space-short', program: appendBoundary, work: 26, space: 9},
    {name: 'append-chain-exact', program: appendChainBoundary,
      work: 72, space: 10, expected: [{id: 2}, {id: 3}]},
    {name: 'append-chain-work-short', program: appendChainBoundary,
      work: 71, space: 10},
    {name: 'append-chain-space-short', program: appendChainBoundary,
      work: 72, space: 9},
    {name: 'set-work-exact', program: setWorkBoundary, work: 19, space: 100,
      expected: [{id: 1}]},
    {name: 'set-work-short', program: setWorkBoundary, work: 18, space: 100},
    {name: 'set-space-exact', program: setSpaceBoundary, work: 1000, space: 15,
      expected: [{id: 1}, {id: 2}]},
    {name: 'set-space-short', program: setSpaceBoundary, work: 1000, space: 14},
    {name: 'cross-exact', program: crossBoundary, work: 52, space: 12,
      expected: [{id: 1, tag: 'a'}, {id: 1, tag: 'b'},
        {id: 2, tag: 'a'}, {id: 2, tag: 'b'}]},
    {name: 'cross-work-short', program: crossBoundary, work: 51, space: 12},
    {name: 'cross-space-short', program: crossBoundary, work: 52, space: 11},
    {name: 'unsupported-chain', program: rejectedChain, work: 100000, space: 10000},
  ]) {
    const binaryFixture = fixture.strategyFixtureCreate(...args,
      JSON.stringify(program));
    const capture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(binaryFixture), suppliedLimits);
    const directory = await mkdtemp(join(tmpdir(), `actql-retained-${name}-`));
    const store = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024});
    let leases = 0, dispatches = 0;
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases++;
      let writer, closed = false;
      return {status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
      reserve: value => (writer = store.reserve(value)),
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); }};
    });
    const observed = new Proxy(hostRuntime, {get(target, property, receiver) {
      if (property !== 'strategyModule_local_Dispatch') {
        return Reflect.get(target, property, receiver);
      }
      return (setup, task) => {
        dispatches++;
        const operations = checked(target.strategyModule_local_Dispatch(setup, task));
        return {$tag: 1, _0: new Proxy(operations, {get(operation, key, owner) {
          if (key === 'execute') assert.fail(`${name}: synchronous fallback`);
          return Reflect.get(operation, key, owner);
        }})};
      };
    }});
    let execution;
    try {
      assert.equal(fixture.strategyFixtureOpen(binaryFixture, capture.source()), true);
      const setup = fixture.strategyFixtureRetainedLocalLimits(binaryFixture, work, space);
      execution = await runInstalledStrategy(setup, runtimeCore(observed),
        [localStrategyContribution(observed, setup, checked, configuration)],
        new AbortController().signal);
      assert.equal(execution.status, expected
        ? 'host-tasks-completed' : 'host-tasks-failed', name);
      if (expected) {
        assert.equal(fixture.strategyFixtureCid(binaryFixture, 3), hash(expected), name);
        assert.equal(leases, 3, name);
      } else if (name === 'unsupported-chain') {
        assert.equal(dispatches, 0, 'unsupported Program must fail before any Compute');
        assert.equal(leases, 0, name);
        assert.equal(execution.completed.length, 0, name);
      } else {
        assert.deepEqual(execution.completed.map(item => item.task), [1, 2], name);
        assert.equal(leases, 2, name);
        assert.equal(execution.failure?.code, 'MoonBitHostFailure', name);
        assert(execution.failure.cause, `${name}: preserve the typed failure`);
        const resourceCause = fixture.strategyFixtureRetainedRowLimit(
          execution.failure.cause) ||
          (name === 'append-chain-work-short' &&
            fixture.strategyFixtureRetainedInputLimit(
              execution.failure.cause));
        assert.equal(resourceCause, true,
          `${name}: the producer must fail with a typed resource limit`);
      }
    } finally {
      capture.close();
      await execution?.close();
      if (execution) {
        assert.equal(await execution.cleanup(), true, name);
        assert.equal(execution.usage().heldBytes, 0n, name);
        assert.equal(execution.usage().reservedExecutionBytes, 0n, name);
      }
      store.close();
      await store.cleanup();
      await rm(directory, {recursive: true, force: true});
    }
  }
  // Checked match-per-key and output-row ceilings are separate from the
  // generous provider work/workspace envelope, and each can reject this input.
  for (const {name, matches, output, chain = false} of [
    {name: 'matches-per-key', matches: 1, output: 3},
    {name: 'output-rows', matches: 2, output: 2},
    {name: 'sequence-chain-intermediate-limit', matches: 2, output: 2, chain: true},
  ]) {
    // The suffix would leave only two rows, but its predecessor still needs
    // three output rows. A final-output-only ceiling would incorrectly pass.
    const program = chain ? retainedFamilyChain(retainedRelationSequenceProgram,
      'matched', [{filter: 'key = 1'}], relationSequenceFields)
      : structuredClone(retainedRelationSequenceProgram);
    program.results = {producer: {from: {stage: 'matched', result: 'r'}}};
    const selectedFixture = fixture.strategyFixtureTeaSequenceCreate(
      ...sequencePolicyArgs(matches, output), JSON.stringify(program));
    const capture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(selectedFixture), suppliedLimits);
    const directory = await mkdtemp(join(tmpdir(),
      `actql-retained-sequence-${name}-`));
    const store = await createLocalRetainedStore({
      parentDirectory: directory, capacityBytes: 8 * 1024 * 1024,
      maxFrameBytes: 1024 * 1024,
    });
    const runtime = runtimeCore(hostRuntime);
    const publication = await openLocalPublicationStore({
      directory: join(directory, 'publication'),
      storeAuthorityCid: hash(`retained-sequence-${name}-store`),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: publicationResultExportLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
    }, runtime.publicationControl);
    const configuration = installLocalRetainedStore((key, bytes) => {
      let writer, closed = false;
      return {
        status: () => ({reservedBytes: writer && !closed ? bytes : 0,
          cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
        reserve: value => (writer = store.reserve(value)),
        close() { closed = true; writer?.cancel(); },
        async cleanup() { await writer?.cleanupHandle?.retry?.(); },
      };
    });
    let failure;
    try {
      assert.equal(fixture.strategyFixtureOpen(selectedFixture,
        capture.source()), true);
      const setup = fixture.strategyFixtureTeaRetainedSubset(selectedFixture);
      const plan = standardPublicationPlan(runtime,
        runtime.programDefinitionCid(setup), runtime.resultInventory(setup).length,
        `retained-sequence-${name}-attempt`);
      await assert.rejects(runPublishedCapturedStrategy(setup,
        {store: publication, plan}, {local: configuration},
        new AbortController().signal), error => {
        failure = error.execution;
        return error.code === 'CapturedRunPublicationFailed';
      });
      assert.equal(failure.status, 'host-tasks-failed', name);
      assert.deepEqual(failure.completed.map(item => item.task), [1], name);
      assert.equal(failure.failure?.code, 'MoonBitHostFailure', name);
      assert.equal(fixture.strategyFixtureRetainedRowLimit(
        failure.failure.cause), true, name);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
    } finally {
      capture.close();
      await failure?.close();
      if (failure) {
        assert.equal(await failure.cleanup(), true, name);
        assert.equal(failure.usage().heldBytes, 0n, name);
        assert.equal(failure.usage().reservedExecutionBytes, 0n, name);
      }
      await publication.close();
      store.close();
      await store.cleanup();
      await rm(directory, {recursive: true, force: true});
    }
  }
  // The output-policy ceiling is independent of the generous provider budget.
  // Two admitted rows expand to four unpivot occurrences, exceeding only the
  // selected three-row policy limit before any Named Result can be committed.
  const expansionPolicyEnvironment = JSON.parse(args[0]);
  expansionPolicyEnvironment.host_policy_profile.capacity
    .max_relation_output_rows = 3;
  const {evidence_bundle_cid: ignoredExpansionCid, ...expansionBody} =
    expansionPolicyEnvironment;
  void ignoredExpansionCid;
  expansionPolicyEnvironment.evidence_bundle_cid = canonicalHash(expansionBody);
  const expansionPolicyArgs = [canonical(expansionPolicyEnvironment),
    expansionPolicyEnvironment.evidence_bundle_cid, ...args.slice(2)];
  const expansionPolicyProgram = retainedUnaryChain(
    [{unpivot: {columns: ['jan', 'feb'], keep: ['id'],
      name_column: 'metric', value_column: 'value'}}], [],
    ['id', 'metric', 'value'],
    [{id: 1, jan: 10, feb: 20}, {id: 2, jan: 30, feb: 40}], {
      id: {type: 'number', nullable: false},
      jan: {type: 'number', nullable: false},
      feb: {type: 'number', nullable: false},
    });
  expansionPolicyProgram.results = {
    producer: {from: {stage: 'crossed', result: 'r'}},
  };
  const expansionPolicyFixture = fixture.strategyFixtureCreate(
    ...expansionPolicyArgs, JSON.stringify(expansionPolicyProgram));
  const expansionPolicyCapture = await runNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(expansionPolicyFixture), suppliedLimits);
  const expansionPolicyDirectory = await mkdtemp(join(
    tmpdir(), 'actql-retained-expansion-policy-'));
  const expansionPolicyStore = await createLocalRetainedStore({
    parentDirectory: expansionPolicyDirectory,
    capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024,
  });
  const expansionPublicationStore = await openLocalPublicationStore({
    directory: join(expansionPolicyDirectory, 'publication'),
    storeAuthorityCid: hash('retained-expansion-policy-store'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: publicationResultExportLimits.maxWireBytes,
    maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
  }, runtimeCore(hostRuntime).publicationControl);
  const expansionPolicyConfiguration = installLocalRetainedStore((key, bytes) => {
    let writer, closed = false;
    return {
      status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
      reserve: value => (writer = expansionPolicyStore.reserve(value)),
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); },
    };
  });
  let expansionFailure;
  try {
    assert.equal(fixture.strategyFixtureOpen(expansionPolicyFixture,
      expansionPolicyCapture.source()), true);
    const setup = fixture.strategyFixtureRetainedLocalLimits(
      expansionPolicyFixture, 100000, 10000);
    const runtime = runtimeCore(hostRuntime);
    const plan = standardPublicationPlan(runtime,
      runtime.programDefinitionCid(setup), runtime.resultInventory(setup).length,
      'retained-expansion-policy-attempt');
    await assert.rejects(runPublishedCapturedStrategy(
      setup, {store: expansionPublicationStore, plan},
      {local: expansionPolicyConfiguration}, new AbortController().signal),
    error => {
      expansionFailure = error.execution;
      return error.code === 'CapturedRunPublicationFailed';
    });
    assert.equal(expansionFailure.status, 'host-tasks-failed');
    assert.deepEqual(expansionFailure.completed.map(item => item.task), [1, 2]);
    assert.equal(expansionFailure.failure?.code, 'MoonBitHostFailure');
    assert.equal(fixture.strategyFixtureRetainedRowLimit(
      expansionFailure.failure.cause), true);
    await assert.rejects(expansionPublicationStore.lookupCommittedIndex({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, () => true), /PublicationLookupDenied/);
  } finally {
    expansionPolicyCapture.close();
    await expansionFailure?.close();
    if (expansionFailure) {
      assert.equal(await expansionFailure.cleanup(), true);
      assert.equal(expansionFailure.usage().heldBytes, 0n);
      assert.equal(expansionFailure.usage().reservedExecutionBytes, 0n);
    }
    await expansionPublicationStore.close();
    expansionPolicyStore.close();
    await expansionPolicyStore.cleanup();
    await rm(expansionPolicyDirectory, {recursive: true, force: true});
  }
  const nestPolicyProgram = structuredClone(nestProgram);
  nestPolicyProgram.stages = nestPolicyProgram.stages.filter(stage =>
    !stage.id.startsWith('nest_consumer_'));
  nestPolicyProgram.stages.find(stage => stage.id === 'nested')
    .steps[0].nest.max_items = 1;
  nestPolicyProgram.results = {
    producer: {from: {stage: 'nested', result: 'r'}},
  };
  const nestPolicyFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(nestPolicyProgram));
  const nestPolicyCapture = await runNativeHostQuery(grant,
    fixture.strategyFixtureAcquisition(nestPolicyFixture), suppliedLimits);
  const nestPolicyDirectory = await mkdtemp(join(
    tmpdir(), 'actql-retained-nest-policy-'));
  const nestPolicyStore = await createLocalRetainedStore({
    parentDirectory: nestPolicyDirectory,
    capacityBytes: 8 * 1024 * 1024,
    maxFrameBytes: 1024 * 1024,
  });
  const nestPublicationStore = await openLocalPublicationStore({
    directory: join(nestPolicyDirectory, 'publication'),
    storeAuthorityCid: hash('retained-nest-policy-store'),
    capacityBytes: 4 * 1024 * 1024,
    maxObjectBytes: publicationResultExportLimits.maxWireBytes,
    maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
  }, runtimeCore(hostRuntime).publicationControl);
  let nestPolicyLeases = 0, nestPolicyFailure;
  const nestPolicyConfiguration = installLocalRetainedStore((key, bytes) => {
    nestPolicyLeases++;
    let writer, closed = false;
    return {
      status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
      reserve: value => (writer = nestPolicyStore.reserve(value)),
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); },
    };
  });
  try {
    assert.equal(fixture.strategyFixtureOpen(nestPolicyFixture,
      nestPolicyCapture.source()), true);
    const setup = fixture.strategyFixtureRetainedLocalSubset(nestPolicyFixture);
    const runtime = runtimeCore(hostRuntime);
    const plan = standardPublicationPlan(runtime,
      runtime.programDefinitionCid(setup), runtime.resultInventory(setup).length,
      'retained-nest-policy-attempt');
    await assert.rejects(runPublishedCapturedStrategy(
      setup, {store: nestPublicationStore, plan},
      {local: nestPolicyConfiguration}, new AbortController().signal),
    error => {
      nestPolicyFailure = error.execution;
      return error.code === 'CapturedRunPublicationFailed';
    });
    assert.equal(nestPolicyFailure.status, 'host-tasks-failed');
    assert.deepEqual(nestPolicyFailure.completed.map(item => item.task), [1, 2]);
    assert.equal(nestPolicyLeases, 2, 'no partial nest output is retained');
    assert.equal(nestPolicyFailure.failure?.code, 'MoonBitHostFailure');
    assert.equal(fixture.strategyFixtureRetainedNestItemLimit(
      nestPolicyFailure.failure.cause), true);
    await assert.rejects(nestPublicationStore.lookupCommittedIndex({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, () => true), /PublicationLookupDenied/);
  } finally {
    nestPolicyCapture.close();
    await nestPolicyFailure?.close();
    if (nestPolicyFailure) {
      assert.equal(await nestPolicyFailure.cleanup(), true);
      assert.equal(nestPolicyFailure.usage().heldBytes, 0n);
      assert.equal(nestPolicyFailure.usage().reservedExecutionBytes, 0n);
    }
    await nestPublicationStore.close();
    nestPolicyStore.close();
    await nestPolicyStore.cleanup();
    await rm(nestPolicyDirectory, {recursive: true, force: true});
  }
  const cancelledValuesFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(retainedValuesProgram));
  const cancelledValuesCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(cancelledValuesFixture),
    suppliedLimits,
  );
  const cancelledValuesDirectory = await mkdtemp(join(
    tmpdir(), 'actql-cancelled-values-'));
  const cancelledValuesStore = await createLocalRetainedStore({
    parentDirectory: cancelledValuesDirectory,
    capacityBytes: 8 * 1024 * 1024,
    maxFrameBytes: 1024 * 1024,
  });
  const cancelledValuesLeases = [];
  const cancelledValuesConfiguration = installLocalRetainedStore((key, bytes) => {
    cancelledValuesLeases.push(key);
    let writer, closed = false;
    return Object.freeze({
      status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: false}),
      reserve: value => (writer = cancelledValuesStore.reserve(value)),
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); },
    });
  });
  const valuesCancel = new AbortController();
  let valuesWorkObserved = false, valuesStopped = false;
  const cancelRuntime = new Proxy(hostRuntime, {
    get(target, property, receiver) {
      if (property !== 'strategyModule_local_Dispatch') {
        return Reflect.get(target, property, receiver);
      }
      return (setup, task) => {
        const operations = checked(target.strategyModule_local_Dispatch(setup, task));
        return {$tag: 1, _0: new Proxy(operations, {
          get(operation, name, operationReceiver) {
            if (name === 'execute') assert.fail('Values ran synchronously');
            if (name === 'execution_stopped') {
              return () => {
                const stopped = operation.execution_stopped();
                if (stopped && valuesCancel.signal.aborted) valuesStopped = true;
                return stopped;
              };
            }
            if (name !== 'advance') {
              return Reflect.get(operation, name, operationReceiver);
            }
            return quantum => {
              const result = operation.advance(Math.min(quantum, 1));
              if (!valuesCancel.signal.aborted) {
                const observation = checked(result);
                if (!valuesWorkObserved && !observation.complete &&
                    observation.progress > 0n) {
                  valuesWorkObserved = true;
                  setTimeout(() => valuesCancel.abort(), 0);
                }
              }
              return result;
            };
          },
        })};
      };
    },
  });
  let cancelledValuesExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      cancelledValuesFixture, cancelledValuesCapture.source()), true);
    const setup = fixture.strategyFixtureRetainedLocalSubset(cancelledValuesFixture);
    cancelledValuesExecution = await runInstalledStrategy(
      setup,
      runtimeCore(cancelRuntime),
      [localStrategyContribution(cancelRuntime, setup, checked,
        cancelledValuesConfiguration)],
      valuesCancel.signal,
    );
    assert.equal(valuesWorkObserved, true);
    assert.equal(valuesStopped, true);
    assert.equal(cancelledValuesExecution.status, 'host-tasks-failed');
    assert.equal(cancelledValuesExecution.failure?.name, 'AbortError');
    assert.equal(cancelledValuesExecution.completed.length, 0);
    assert.equal(cancelledValuesLeases.length, 0);
  } finally {
    cancelledValuesCapture.close();
    await cancelledValuesExecution?.close();
    if (cancelledValuesExecution) {
      assert.equal(await cancelledValuesExecution.cleanup(), true);
      assert.equal(cancelledValuesExecution.cleanupPending(), false);
      assert.equal(cancelledValuesExecution.usage().heldBytes, 0n);
      assert.equal(cancelledValuesExecution.usage().reservedExecutionBytes, 0n);
    }
    cancelledValuesStore.close();
    await cancelledValuesStore.cleanup();
    await rm(cancelledValuesDirectory, {recursive: true, force: true});
  }
  const failedValuesFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(retainedValuesProgram));
  const failedValuesCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(failedValuesFixture),
    suppliedLimits,
  );
  const failedValuesDirectory = await mkdtemp(join(
    tmpdir(), 'actql-failed-values-'));
  const failedValuesStore = await createLocalRetainedStore({
    parentDirectory: failedValuesDirectory,
    capacityBytes: 8 * 1024 * 1024,
    maxFrameBytes: 1024 * 1024,
  });
  let failedStoreAppends = 0, failedStoreLeases = 0;
  const failedValuesConfiguration = installLocalRetainedStore((key, bytes) => {
    failedStoreLeases++;
    let writer, closed = false;
    return Object.freeze({
      status: () => ({reservedBytes: writer && !closed ? bytes : 0,
        cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
      reserve(value) {
        writer = failedValuesStore.reserve(value);
        return Object.freeze({
          start: () => writer.start(),
          append: async () => {
            failedStoreAppends++;
            throw new Error('InjectedLocalStoreAppend');
          },
          seal: identity => writer.seal(identity),
        });
      },
      close() { closed = true; writer?.cancel(); },
      async cleanup() { await writer?.cleanupHandle?.retry?.(); },
    });
  });
  let failedValuesExecution;
  try {
    assert.equal(fixture.strategyFixtureOpen(
      failedValuesFixture, failedValuesCapture.source()), true);
    const setup = fixture.strategyFixtureRetainedLocalSubset(failedValuesFixture);
    failedValuesExecution = await runInstalledStrategy(
      setup,
      runtimeCore(hostRuntime),
      [localStrategyContribution(hostRuntime, setup, checked,
        failedValuesConfiguration)],
      new AbortController().signal,
    );
    assert.equal(failedStoreLeases, 1);
    assert.equal(failedStoreAppends, 1);
    assert.equal(failedValuesExecution.status, 'host-tasks-failed');
    assert.equal(failedValuesExecution.completed.length, 0);
  } finally {
    failedValuesCapture.close();
    await failedValuesExecution?.close();
    if (failedValuesExecution) {
      assert.equal(await failedValuesExecution.cleanup(), true);
      assert.equal(failedValuesExecution.cleanupPending(), false);
      assert.equal(failedValuesExecution.usage().heldBytes, 0n);
      assert.equal(failedValuesExecution.usage().reservedExecutionBytes, 0n);
    }
    failedValuesStore.close();
    await failedValuesStore.cleanup();
    await rm(failedValuesDirectory, {recursive: true, force: true});
  }
  await replaceRows('INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
  const copyCancellationCase = {
    name: 'same-stage-distinct-in-flight',
  };
  const copyCancellationProgram = structuredClone(unrestrictedCrossJoinProgram);
  copyCancellationProgram.stages.find(stage =>
    stage.id === 'crossed').steps[2].values.rows = Array.from(
    {length: 40}, (_, index) => ({tag: `tag${index}`}),
  );
  const copyCancellationFixture = fixture.strategyFixtureCreate(
    ...args, JSON.stringify(copyCancellationProgram),
  );
  const copyCancellationCapture = await runNativeHostQuery(
    grant,
    fixture.strategyFixtureAcquisition(copyCancellationFixture),
    suppliedLimits,
  );
  const copyCancellation = new AbortController();
  let copyCancellationExecution;
  let copyManagedStarts = 0;
  let copyProgress = 0n;
  let copyCancelScheduled = false;
  let copyCancelDeliveredAt;
  let copyStopObservedAt;
  copyCancellation.signal.addEventListener('abort', () => {
    copyCancelDeliveredAt = performance.now();
  }, {once: true});
  try {
    assert.equal(fixture.strategyFixtureOpen(
      copyCancellationFixture, copyCancellationCapture.source(),
    ), true);
    const setup = fixture.strategyFixtureModuleSubset(
      copyCancellationFixture, 0,
    );
    const observedRuntime = new Proxy(hostRuntime, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_ManagedStart') {
          return Reflect.get(target, property, receiver);
        }
        return configuration => {
          const start = ++copyManagedStarts;
          const operation = checked(
            target.strategyModule_local_ManagedStart(configuration),
          );
          const observed = new Proxy(operation, {
            get(active, name, operationReceiver) {
              if (name === 'execution_stopped') {
                return () => {
                  const stopped = active.execution_stopped();
                  if (stopped && copyCancellation.signal.aborted &&
                      copyStopObservedAt === undefined) {
                    copyStopObservedAt = performance.now();
                  }
                  return stopped;
                };
              }
              if (name !== 'advance') {
                return Reflect.get(active, name, operationReceiver);
              }
              return quantum => {
                const result = active.advance(quantum);
                const poll = checked(result);
                if (start === 4) {
                  assert(poll.work <= BigInt(quantum));
                  if (poll.complete === false && poll.work > 0n) {
                    copyProgress += poll.work;
                    if (!copyCancelScheduled) {
                      copyCancelScheduled = true;
                      setTimeout(() => copyCancellation.abort(), 0);
                    }
                  }
                }
                return result;
              };
            },
          });
          return {$tag: 1, _0: observed};
        };
      },
    });
    copyCancellationExecution = await runInstalledStrategy(
      setup,
      runtimeCore(hostRuntime),
      [localStrategyContribution(observedRuntime, setup, checked, undefined)],
      copyCancellation.signal,
    );
    assert(copyProgress > 0n,
      `${copyCancellationCase.name}: distinct work must start before cancel`);
    assert.equal(copyCancellation.signal.aborted, true);
    assert.equal(Number.isFinite(copyCancelDeliveredAt), true);
    assert.equal(Number.isFinite(copyStopObservedAt), true);
    assert(copyStopObservedAt >= copyCancelDeliveredAt);
    assert.equal(copyCancellationExecution.status, 'host-tasks-failed');
    assert.equal(copyCancellationExecution.failure?.name, 'AbortError');
    assert.deepEqual(
      copyCancellationExecution.completed.map(item => item.task),
      [1, 2, 3], 'partial distinct output must not publish',
    );
  } finally {
    copyCancellationCapture.close();
    await copyCancellationExecution?.close();
    if (copyCancellationExecution) {
      assert.equal(await copyCancellationExecution.cleanup(), true);
      assert.equal(copyCancellationExecution.cleanupPending(), false);
      assert.equal(copyCancellationExecution.usage().heldBytes, 0n);
      assert.equal(copyCancellationExecution.usage().reservedExecutionBytes, 0n);
    }
  }
  for (const ordinaryUnaryCase of [
    {name: 'ordinary-select-in-flight', kind: 'select'},
    {name: 'ordinary-rename-in-flight', kind: 'rename'},
    {name: 'ordinary-drop-in-flight', kind: 'drop'},
    {name: 'ordinary-filter-in-flight', kind: 'filter'},
    {name: 'ordinary-derive-in-flight', kind: 'derive'},
    {name: 'ordinary-assert-where-in-flight', kind: 'assert-where'},
    {name: 'ordinary-assert-unique-in-flight', kind: 'assert-unique'},
    {name: 'ordinary-sort-in-flight', kind: 'sort'},
    {name: 'ordinary-distinct-in-flight', kind: 'distinct'},
    {name: 'ordinary-dedupe-in-flight', kind: 'dedupe'},
    {name: 'ordinary-global-top-k-in-flight', kind: 'top-k'},
    {name: 'ordinary-partitioned-top-k-in-flight', kind: 'top-k-by'},
    {name: 'ordinary-take-in-flight', kind: 'take'},
    {name: 'ordinary-pivot-in-flight', kind: 'pivot'},
    {name: 'ordinary-analytic-in-flight', kind: 'analytic'},
    {name: 'ordinary-window-group-in-flight', kind: 'window-group'},
    {name: 'ordinary-row-window-in-flight', kind: 'row-window'},
    {name: 'ordinary-unpivot-in-flight', kind: 'unpivot'},
    {name: 'ordinary-json-pick-in-flight', kind: 'json-pick'},
    {name: 'ordinary-unnest-in-flight', kind: 'unnest'},
  ]) {
    const ordinaryUnaryProgram = structuredClone(selectProgram);
    const hasPreliminary = ordinaryUnaryCase.kind === 'top-k' ||
      ordinaryUnaryCase.kind === 'top-k-by';
    const source = ordinaryUnaryProgram.stages.find(stage =>
      stage.id === 'select_values');
    source.steps[0].values.rows = Array.from(
      {length: 80}, (_, index) => ({
        id: index + 1,
        amount: index,
        ...(ordinaryUnaryCase.kind === 'top-k-by' ||
          ordinaryUnaryCase.kind === 'pivot'
          ? {group: index % 2 === 0 ? 'a' : 'b'} : {}),
        ...(ordinaryUnaryCase.kind === 'json-pick'
          ? {payload: {inner: {leaf: index}}} : {}),
        ...(ordinaryUnaryCase.kind === 'unnest'
          ? {items: [index, index + 1]} : {}),
      }),
    );
    if (ordinaryUnaryCase.kind === 'json-pick') {
      source.steps[0].values.schema.payload = {type: 'object', nullable: false,
        fields: {inner: {type: 'object', nullable: false,
          fields: {leaf: {type: 'number', nullable: false}}}}};
      source.results.r.fields = ['id', 'amount', 'payload'];
    }
    if (ordinaryUnaryCase.kind === 'unnest') {
      source.steps[0].values.schema.items = {type: 'array', nullable: false,
        items: {type: 'number', nullable: false}, max_items: 2};
      source.results.r.fields = ['id', 'amount', 'items'];
    }
    if (ordinaryUnaryCase.kind === 'top-k-by' ||
        ordinaryUnaryCase.kind === 'pivot') {
      source.steps[0].values.schema.group = {type: 'string', nullable: false};
      source.results.r.fields = ['id', 'amount', 'group'];
    }
    if (ordinaryUnaryCase.kind !== 'select') {
      const unary = ordinaryUnaryProgram.stages.find(stage =>
        stage.id === 'selected');
      const unaryStep = {
        filter: {filter: 'id > 0', as: 'out'},
        rename: {rename: {amount: 'total'}, as: 'out'},
        drop: {drop: ['amount'], as: 'out'},
        derive: {derive: {next: 'id + 1'}, as: 'out'},
        'assert-where': {assert_rows: {where: 'id > 0'}, as: 'out'},
        'assert-unique': {assert_rows: {unique_by: ['id']}, as: 'out'},
        sort: {sort: [{id: 'desc'}], as: 'out'},
        distinct: {distinct: true, as: 'out'},
        dedupe: {dedupe_rows: {
          by: ['id'], order_by: [{amount: 'desc'}],
        }, as: 'out'},
        'top-k': {top_k: {k: 60, by: [{id: 'desc'}]}, as: 'out'},
        'top-k-by': {top_k_by: {
          partition_by: ['group'], k: 30, by: [{id: 'desc'}],
        }, as: 'out'},
        take: {take: 60, as: 'out'},
        pivot: {pivot: {
          index: ['id'], column: 'group', values: ['a', 'b'],
          value: 'amount', aggregate: 'max',
        }, as: 'out'},
        analytic: {analytic: {
          partition_by: [], order_by: [{id: 'asc'}],
          frame: {start: 'unbounded_preceding', end: 'current_row'},
          functions: {n: {fn: 'count', field: 'amount'}},
        }, as: 'out'},
        'row-window': {row_window: {kind: 'fixed', time: 'id', size: 10}, as: 'out'},
        unpivot: {unpivot: {
          columns: ['amount'], keep: ['id'],
          name_column: 'metric', value_column: 'value',
        }, as: 'out'},
        'json-pick': {json_pick: {
          column: 'payload', path: ['inner', 'leaf'], output: 'picked',
        }, as: 'out'},
        unnest: {unnest: {column: 'items', as: 'item', outer: false}, as: 'out'},
        'window-group': [
          {row_window: {kind: 'fixed', time: 'id', size: 10}, as: 'windowed'},
          {from: 'windowed', window_group: {by: [], aggregates: {
            lowest: {fn: 'min', field: 'amount'},
          }}, as: 'out'},
        ],
      }[ordinaryUnaryCase.kind];
      unary.steps = hasPreliminary
        ? [
          {assert_rows: {unique_by: ['id']}, as: 'unique'},
          {from: 'unique', ...unaryStep},
        ]
        : Array.isArray(unaryStep) ? unaryStep : [unaryStep];
      const fields = ordinaryUnaryCase.kind === 'derive'
        ? ['id', 'amount', 'next']
        : ordinaryUnaryCase.kind === 'rename' ? ['id', 'total']
          : ordinaryUnaryCase.kind === 'drop' ? ['id']
            : ordinaryUnaryCase.kind === 'top-k-by'
              ? ['id', 'amount', 'group']
            : ordinaryUnaryCase.kind === 'pivot' ? ['a', 'b', 'id']
            : ordinaryUnaryCase.kind === 'analytic'
              ? ['amount', 'id', 'n']
            : ordinaryUnaryCase.kind === 'window-group'
              ? ['lowest', 'window_end', 'window_start']
            : ordinaryUnaryCase.kind === 'row-window'
              ? ['amount', 'id', 'window_end', 'window_start']
            : ordinaryUnaryCase.kind === 'unpivot' ? ['id', 'metric', 'value']
            : ordinaryUnaryCase.kind === 'json-pick'
              ? ['amount', 'id', 'payload', 'picked']
            : ordinaryUnaryCase.kind === 'unnest'
              ? ['amount', 'id', 'item', 'items']
            : ['id', 'amount'];
      unary.results.r.fields = fields;
      for (const consumer of ordinaryUnaryProgram.stages.filter(stage =>
        stage.id.startsWith('select_consumer_'))) {
        consumer.steps[0].select = fields;
        consumer.results.r.fields = fields;
      }
    }
    let ordinaryUnaryFixture;
    try {
      ordinaryUnaryFixture = fixture.strategyFixtureCreate(
        ...(ordinaryUnaryCase.kind === 'analytic' ? analyticArgs : args),
        JSON.stringify(ordinaryUnaryProgram),
      );
    } catch (error) {
      throw new Error(`${ordinaryUnaryCase.name}: fixture rejected`, {cause: error});
    }
    const ordinaryUnaryCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(ordinaryUnaryFixture),
      suppliedLimits,
    );
    const cancellation = new AbortController();
    let execution;
    let managedStarts = 0;
    let progressAfterStart = 0n;
    let deliveredAt;
    let stoppedAt;
    let scheduled = false;
    cancellation.signal.addEventListener('abort', () => {
      deliveredAt = performance.now();
    }, {once: true});
    try {
      assert.equal(fixture.strategyFixtureOpen(
        ordinaryUnaryFixture, ordinaryUnaryCapture.source(),
      ), true);
      const setup = fixture.strategyFixtureModuleSubset(
        ordinaryUnaryFixture, 0,
      );
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return configuration => {
            const start = ++managedStarts;
            const operation = checked(
              target.strategyModule_local_ManagedStart(configuration),
            );
            const observed = new Proxy(operation, {
              get(active, name, operationReceiver) {
                if (name === 'execution_stopped') {
                  return () => {
                    const stopped = active.execution_stopped();
                    if (stopped && cancellation.signal.aborted &&
                        stoppedAt === undefined) {
                      stoppedAt = performance.now();
                    }
                    return stopped;
                  };
                }
                if (name !== 'advance') {
                  return Reflect.get(active, name, operationReceiver);
                }
                return quantum => {
                  const result = active.advance(quantum);
                  const poll = checked(result);
                  if (start === (hasPreliminary
                    ? 3 : 2)) {
                    assert(poll.work <= BigInt(quantum));
                    if (poll.complete === false && poll.progress > 0n &&
                        poll.work > 0n) {
                      progressAfterStart += poll.progress;
                      if (!scheduled) {
                        scheduled = true;
                        setTimeout(() => cancellation.abort(), 0);
                      }
                    }
                  }
                  return result;
                };
              },
            });
            return {$tag: 1, _0: observed};
          };
        },
      });
      execution = await runInstalledStrategy(
        setup,
        runtimeCore(hostRuntime),
        [localStrategyContribution(observedRuntime, setup, checked, undefined)],
        cancellation.signal,
      );
      assert.equal(managedStarts,
        hasPreliminary ? 3 : 2);
      assert(progressAfterStart > 0n,
        `${ordinaryUnaryCase.name}: row work must precede abort`);
      assert.equal(cancellation.signal.aborted, true);
      assert.equal(Number.isFinite(deliveredAt), true);
      assert.equal(Number.isFinite(stoppedAt), true);
      assert(stoppedAt >= deliveredAt);
      assert.equal(execution.status, 'host-tasks-failed');
      assert.equal(execution.failure?.name, 'AbortError');
      assert.deepEqual(execution.completed.map(item => item.task),
        hasPreliminary ? [1, 2] : [1]);
    } finally {
      ordinaryUnaryCapture.close();
      await execution?.close();
      if (execution) {
        assert.equal(await execution.cleanup(), true);
        assert.equal(execution.cleanupPending(), false);
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
    }
  }
  // Binary bounded operations: two external value inputs feed the operation
  // stage, which is aborted after positive work at quantum one.
  for (const binaryCase of [
    {name: 'ordinary-except-in-flight', kind: 'except'},
    {name: 'ordinary-intersect-in-flight', kind: 'intersect'},
    {name: 'ordinary-nest-in-flight', kind: 'nest'},
    {name: 'ordinary-equality-join-in-flight', kind: 'join'},
  ]) {
    const nest = binaryCase.kind === 'nest';
    const join = binaryCase.kind === 'join';
    const leftSchema = nest
      ? {id: {type: 'number', nullable: false}, key: {type: 'number', nullable: false}}
      : {id: {type: 'number', nullable: false}};
    const rightSchema = nest
      ? {key: {type: 'number', nullable: false}, value: {type: 'number', nullable: false}}
      : {id: {type: 'number', nullable: false}};
    const fields = nest ? ['id', 'items', 'key']
      : join ? ['id', 'other'] : ['id'];
    const binaryProgram = structuredClone(zeroInputProgram);
    binaryProgram.stages.splice(1, 3, {
      id: 'binary_left', inputs: {},
      steps: [{values: {schema: leftSchema, rows: Array.from({length: 20},
        (_, index) => nest ? {id: index, key: index % 5} : {id: index % 12})}, as: 'out'}],
      results: {r: {from: 'out', fields: Object.keys(leftSchema)}},
    }, {
      id: 'binary_right', inputs: {},
      steps: [{values: {schema: rightSchema, rows: Array.from({length: 20},
        (_, index) => nest ? {key: index % 5, value: index} : {id: index % 8})}, as: 'out'}],
      results: {r: {from: 'out', fields: Object.keys(rightSchema)}},
    }, {
      id: 'binary_op',
      inputs: {l: {result: {stage: 'binary_left', result: 'r'}},
        r: {result: {stage: 'binary_right', result: 'r'}}},
      steps: [nest
        ? {from: 'l', nest: {with: 'r', on: [{left: 'key', right: 'key'}],
          into: 'items', fields: [{amount: 'value'}], max_items: 4}, as: 'out'}
        : join
          ? {from: 'l', join: {with: 'r', kind: 'inner',
            on: [{left: 'id', right: 'id'}],
            select: {id: 'left.id', other: 'right.id'}}, as: 'out'}
          : {from: 'l', [binaryCase.kind]: {with: 'r', duplicates: 'all'}, as: 'out'}],
      results: {r: {from: 'out', fields}},
    }, ...['a', 'b'].map(id => ({
      id: `binary_consumer_${id}`,
      inputs: {x: {result: {stage: 'binary_op', result: 'r'}}},
      steps: [{select: id === 'a' ? fields : [...fields].reverse(), as: 'out'}],
      results: {r: {from: 'out', fields: id === 'a' ? fields : [...fields].reverse()}},
    })));
    binaryProgram.results = {
      a: {from: {stage: 'binary_consumer_a', result: 'r'}},
      b: {from: {stage: 'binary_consumer_b', result: 'r'}},
    };
    const binaryFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(binaryProgram));
    const binaryCapture = await runNativeHostQuery(grant,
      fixture.strategyFixtureAcquisition(binaryFixture), suppliedLimits);
    const cancellation = new AbortController();
    let execution, starts = 0, scheduled = false, workBeforeAbort = 0n;
    let deliveredAt, stoppedAt;
    cancellation.signal.addEventListener('abort', () => {
      deliveredAt = performance.now();
    }, {once: true});
    try {
      assert.equal(fixture.strategyFixtureOpen(
        binaryFixture, binaryCapture.source()), true);
      const setup = fixture.strategyFixtureModuleSubset(binaryFixture, 0);
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return configuration => {
            const start = ++starts;
            const operation = checked(
              target.strategyModule_local_ManagedStart(configuration));
            return {$tag: 1, _0: new Proxy(operation, {
              get(active, name, operationReceiver) {
                if (name === 'execution_stopped') {
                  return () => {
                    const stopped = active.execution_stopped();
                    if (stopped && cancellation.signal.aborted &&
                        stoppedAt === undefined) stoppedAt = performance.now();
                    return stopped;
                  };
                }
                if (name !== 'advance') {
                  return Reflect.get(active, name, operationReceiver);
                }
                return quantum => {
                  const step = start === 3 ? 1 : quantum;
                  const result = active.advance(step);
                  const poll = checked(result);
                  if (start === 3) {
                    assert(poll.work <= BigInt(step));
                    if (poll.complete === false && poll.work > 0n) {
                      workBeforeAbort += poll.work;
                      if (!scheduled && workBeforeAbort >= 5n) {
                        scheduled = true;
                        setTimeout(() => cancellation.abort(), 0);
                      }
                    }
                  }
                  return result;
                };
              },
            })};
          };
        },
      });
      execution = await runInstalledStrategy(setup, runtimeCore(hostRuntime),
        [localStrategyContribution(observedRuntime, setup, checked, undefined)],
        cancellation.signal);
      assert.equal(starts, 3, binaryCase.name);
      assert(workBeforeAbort >= 5n, `${binaryCase.name}: work precedes abort`);
      assert.equal(cancellation.signal.aborted, true);
      assert.equal(Number.isFinite(deliveredAt), true);
      assert.equal(Number.isFinite(stoppedAt), true);
      assert(stoppedAt >= deliveredAt);
      assert.equal(execution.status, 'host-tasks-failed');
      assert.equal(execution.failure?.name, 'AbortError');
      assert.deepEqual(execution.completed.map(item => item.task), [1, 2],
        `${binaryCase.name}: no partial output`);
    } finally {
      binaryCapture.close();
      await execution?.close();
      if (execution) {
        let cleaned = false;
        for (let attempt = 0; attempt < 3 && !cleaned; attempt++) {
          cleaned = await execution.cleanup();
        }
        assert.equal(cleaned, true);
        assert.equal(execution.cleanupPending(), false);
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
    }
  }
  for (const {
    name: cancellationName,
    program: cancellationProgram,
    cancelAtStart,
  } of [
    {name: 'captured-relation-chain-in-flight',
      program: capturedRelationChainProgram, cancelAtStart: 1},
    {name: 'equality-join-chain-in-flight',
      program: boundedEqualityJoinProgram, cancelAtStart: 3},
    {name: 'same-stage-full-join-in-flight',
      program: joinProgram, cancelAtStart: 5},
    {name: 'dedupe-filter-chain-in-flight',
      program: dedupeFilterProgram, cancelAtStart: 2},
    {name: 'captured-count-chain-in-flight',
      program: capturedCountChainProgram, cancelAtStart: 1},
    {name: 'captured-keyed-count-chain-in-flight',
      program: capturedKeyedCountChainProgram, cancelAtStart: 1},
    {name: 'captured-window-chain-in-flight',
      program: capturedWindowChainProgram, cancelAtStart: 1},
    {name: 'captured-unpivot-chain-in-flight',
      program: capturedUnpivotChainProgram, cancelAtStart: 1},
    {name: 'nest-output-unnest-chain-in-flight',
      program: nestUnwrapProgram, cancelAtStart: 4},
    {name: 'zero-input-values-in-flight', program: zeroInputProgram,
      cancelAtStart: 2},
    {name: 'split-values-in-flight', program: splitValuesProgram,
      cancelAtStart: 2},
    {name: 'split-values-select-in-flight',
      program: splitValuesSelectProgram, cancelAtStart: 3},
    {name: 'split-values-derive-in-flight',
      program: splitValuesDeriveProgram, cancelAtStart: 3},
    {name: 'split-values-take-in-flight',
      program: splitValuesTakeProgram, cancelAtStart: 3},
    {name: 'split-values-row-window-in-flight',
      program: fixedRowWindowProgram, cancelAtStart: 2},
    {name: 'global-count-in-flight',
      program: globalCountProgram, cancelAtStart: 2},
    {name: 'nested-global-count-in-flight',
      program: nestedGlobalCountProgram, cancelAtStart: 2},
    {name: 'group-count-in-flight',
      program: groupProgram, cancelAtStart: 2},
    {name: 'direct-group-in-flight',
      program: directGroupProgram, cancelAtStart: 2},
    {name: 'same-stage-global-count-in-flight',
      program: sameStageGlobalCountProgram, cancelAtStart: 2},
    {name: 'same-stage-count-if-in-flight',
      program: sameStageCountIfProgram, cancelAtStart: 2},
    {name: 'same-stage-keyed-count-in-flight',
      program: sameStageKeyedCountProgram, cancelAtStart: 2},
    {name: 'append-filter-in-flight',
      program: appendFilterProgram, cancelAtStart: 3},
    {name: 'filter-append-in-flight',
      program: filterThenAppendProgram, cancelAtStart: 3},
    {name: 'split-values-fixed-watermark-in-flight',
      program: fixedWatermarkProgram, cancelAtStart: 2},
    {name: 'split-values-prefix-watermark-in-flight',
      program: prefixWatermarkProgram, cancelAtStart: 2},
    {name: 'split-values-unpivot-in-flight',
      program: unpivotProgram, cancelAtStart: 2},
    {name: 'unpivot-filter-chain-in-flight',
      program: unpivotFilterProgram, cancelAtStart: 3},
    {name: 'split-values-unnest-in-flight',
      program: unnestProgram, cancelAtStart: 2},
    {name: 'unnest-filter-chain-in-flight',
      program: unnestFilterProgram, cancelAtStart: 3},
    {name: 'split-values-json-pick-in-flight',
      program: jsonPickProgram, cancelAtStart: 2},
    {name: 'same-stage-json-pick-filter-in-flight',
      program: sameStageJsonFilterProgram, cancelAtStart: 3},
    {name: 'split-values-assert-in-flight',
      program: splitValuesAssertProgram, cancelAtStart: 3},
    {name: 'split-values-unique-in-flight',
      program: splitValuesUniqueProgram, cancelAtStart: 3},
    {name: 'same-stage-lag-in-flight',
      program: lagProgram, cancelAtStart: 3},
    {name: 'split-values-sort-in-flight',
      program: splitValuesSortTakeProgram, cancelAtStart: 3},
    {name: 'separate-sort-in-flight',
      program: separateSortTakeProgram, cancelAtStart: 3},
    {name: 'long-selected-take-in-flight',
      program: longSelectedSortTakeProgram, cancelAtStart: 3},
    {name: 'separate-filter-sort-in-flight',
      program: separateFilterSortTakeProgram, cancelAtStart: 4},
    {name: 'chained-filter-sort-in-flight',
      program: chainedFilterSortTakeProgram, cancelAtStart: 4},
  ]) {
    const valuesCancellationCase = {name: cancellationName};
    const equalityJoinCancellation = cancellationName ===
      'equality-join-chain-in-flight' || cancellationName ===
      'same-stage-full-join-in-flight';
    const cancellableValuesProgram = structuredClone(cancellationProgram);
    const capturedRelationChainCancellation = cancellationName ===
      'captured-relation-chain-in-flight' || cancellationName ===
      'captured-count-chain-in-flight' || cancellationName ===
      'captured-keyed-count-chain-in-flight' || cancellationName ===
      'captured-window-chain-in-flight' || cancellationName ===
      'captured-unpivot-chain-in-flight';
    const nestUnwrapCancellation = cancellationName ===
      'nest-output-unnest-chain-in-flight';
    const dedupeFilterCancellation = cancellationName ===
      'dedupe-filter-chain-in-flight';
    const nestedCountCancellation = cancellationName ===
      'nested-global-count-in-flight';
    const longSelectedTakeCancellation = cancellationName ===
      'long-selected-take-in-flight';
    const rowWindowCancellation = cancellationName ===
      'split-values-row-window-in-flight';
    const sameStageGlobalCountCancellation = cancellationName ===
      'same-stage-global-count-in-flight' || cancellationName ===
      'same-stage-count-if-in-flight' || cancellationName ===
      'same-stage-keyed-count-in-flight';
    const globalCountCancellation = cancellationName ===
      'global-count-in-flight' ||
      nestedCountCancellation ||
      cancellationName === 'group-count-in-flight' ||
      cancellationName === 'direct-group-in-flight' ||
      sameStageGlobalCountCancellation;
    const watermarkCancellation = cancellationName ===
      'split-values-fixed-watermark-in-flight' ||
      cancellationName === 'split-values-prefix-watermark-in-flight';
    const lagCancellation = cancellationName === 'same-stage-lag-in-flight';
    const unpivotCancellation = cancellationName ===
      'split-values-unpivot-in-flight' ||
      cancellationName === 'unpivot-filter-chain-in-flight';
    const unnestCancellation = cancellationName ===
      'split-values-unnest-in-flight' ||
      cancellationName === 'unnest-filter-chain-in-flight';
    const jsonPickCancellation = cancellationName ===
      'split-values-json-pick-in-flight';
    const sameStageJsonFilterCancellation = cancellationName ===
      'same-stage-json-pick-filter-in-flight';
    const valuesStage = cancellableValuesProgram.stages.find(
      stage => stage.id === (cancellationName === 'append-filter-in-flight'
        ? 'append_source_0' : cancellationName === 'filter-append-in-flight'
        ? 'append_source_1' : sameStageGlobalCountCancellation
        ? 'group_a' : globalCountCancellation
        ? 'group_values' : lagCancellation
        ? 'lagged' : rowWindowCancellation
        ? 'window_values' : watermarkCancellation
          ? 'watermark_values' : unpivotCancellation
          ? 'unpivot_values' : unnestCancellation
            ? 'unnest_values' : jsonPickCancellation ||
              sameStageJsonFilterCancellation
              ? 'json_pick_values' : 'values_a'),
    );
    if (!capturedRelationChainCancellation && !nestUnwrapCancellation &&
        !equalityJoinCancellation &&
        !dedupeFilterCancellation &&
        !longSelectedTakeCancellation) {
      const reshapeFilterChain = cancellationName ===
        'unpivot-filter-chain-in-flight' ||
        cancellationName === 'unnest-filter-chain-in-flight';
      valuesStage.steps[0].values.rows = nestedCountCancellation
        ? [{id: 1, payload: Array(512).fill(1)}] : Array.from(
      {length: reshapeFilterChain ? 24 : 80}, (_, index) => rowWindowCancellation
        ? {at: index, id: index}
        : lagCancellation
          ? {amount: index, group: index % 2 ? 'a' : null, id: index}
        : watermarkCancellation
          ? {id: index, time: 100 - index}
        : unpivotCancellation
          ? {a: index, b: index + 1, id: index}
          : unnestCancellation
          ? {id: index, items: [index, index + 1]}
          : jsonPickCancellation || sameStageJsonFilterCancellation
            ? {id: index, payload: {inner: {leaf: index}}}
        : cancellationName === 'same-stage-count-if-in-flight'
          ? {flag: index % 3 === 0 ? null : index % 2 === 0}
        : globalCountCancellation || cancellationName === 'append-filter-in-flight' ||
            cancellationName === 'filter-append-in-flight'
          ? {id: index}
        : {id: index, label: `row${index}`});
    }
    const valuesCancellationFixture = fixture.strategyFixtureCreate(
      ...args, JSON.stringify(cancellableValuesProgram),
    );
    const valuesCancellationCapture = await runNativeHostQuery(
      grant,
      fixture.strategyFixtureAcquisition(valuesCancellationFixture),
      suppliedLimits,
    );
    const valuesCancellation = new AbortController();
    let valuesCancellationExecution;
    let valuesManagedStarts = 0;
    let valuesWorkObserved = false;
    let nestedCountWork = 0n;
    let splitKeyedCountWork = 0n;
    let longSelectedTakeWork = 0n;
    let valuesCancellationDeliveredAt;
    let valuesStopObservedAt;
    valuesCancellation.signal.addEventListener('abort', () => {
      valuesCancellationDeliveredAt = performance.now();
    }, {once: true});
    try {
      assert.equal(fixture.strategyFixtureOpen(
        valuesCancellationFixture, valuesCancellationCapture.source(),
      ), true);
      const setup = fixture.strategyFixtureModuleSubset(
        valuesCancellationFixture, 0,
      );
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return configuration => {
            const start = ++valuesManagedStarts;
            const execution = checked(
              target.strategyModule_local_ManagedStart(configuration),
            );
            const observed = new Proxy(execution, {
              get(operation, name, operationReceiver) {
                if (name === 'execution_stopped') {
                  return () => {
                    const stopped = operation.execution_stopped();
                    if (stopped && valuesCancellation.signal.aborted &&
                        valuesStopObservedAt === undefined) {
                      valuesStopObservedAt = performance.now();
                    }
                    return stopped;
                  };
                }
                if (name !== 'advance') {
                  return Reflect.get(operation, name, operationReceiver);
                }
                return quantum => {
                  const stepQuantum = (equalityJoinCancellation ||
                    nestUnwrapCancellation ||
                    longSelectedTakeCancellation) &&
                    start === cancelAtStart ? 1 : start === cancelAtStart &&
                    (capturedRelationChainCancellation ||
                      dedupeFilterCancellation ||
                      cancellationName === 'split-values-take-in-flight' ||
                      rowWindowCancellation || globalCountCancellation ||
                      watermarkCancellation ||
                      lagCancellation ||
                      unpivotCancellation ||
                      unnestCancellation || jsonPickCancellation ||
                      sameStageJsonFilterCancellation)
                    ? Math.min(quantum, 7)
                    : cancellationName === 'append-filter-in-flight' ||
                      cancellationName === 'filter-append-in-flight'
                      ? 1 : quantum;
                  const result = operation.advance(stepQuantum);
                  const observation = checked(result);
                  if (cancellationName === 'nested-global-count-in-flight' &&
                      start === cancelAtStart) {
                    nestedCountWork += observation.work;
                  }
                  if (longSelectedTakeCancellation &&
                      start === cancelAtStart) {
                    longSelectedTakeWork += observation.work;
                  }
                  if (cancellationName === 'same-stage-keyed-count-in-flight' &&
                      start === cancelAtStart) {
                    splitKeyedCountWork += observation.work;
                  }
                  if (start === cancelAtStart) {
                    assert(observation.work <= BigInt(stepQuantum));
                  }
                  if (start === cancelAtStart &&
                      observation?.complete === false &&
                      observation.work > 0n &&
                      (!watermarkCancellation || observation.progress > 0n) &&
                      (cancellationName !== 'nested-global-count-in-flight' ||
                        nestedCountWork >= 100n) &&
                      (cancellationName !== 'same-stage-keyed-count-in-flight' ||
                        splitKeyedCountWork >= 100n) &&
                      (!longSelectedTakeCancellation ||
                        longSelectedTakeWork >= 10n) &&
                      !valuesWorkObserved) {
                    valuesWorkObserved = true;
                    setTimeout(() => valuesCancellation.abort(), 0);
                  }
                  return result;
                };
              },
            });
            return {$tag: 1, _0: observed};
          };
        },
      });
      valuesCancellationExecution = await runInstalledStrategy(
        setup,
        runtimeCore(hostRuntime),
        [localStrategyContribution(observedRuntime, setup, checked, undefined)],
        valuesCancellation.signal,
      );
      assert.equal(valuesManagedStarts, cancelAtStart,
        longSelectedTakeCancellation
          ? `${valuesCancellationCase.name}: ` +
            `target work ${longSelectedTakeWork}`
          : valuesCancellationCase.name);
      assert.equal(valuesWorkObserved, true, valuesCancellationCase.name);
      assert.equal(valuesCancellation.signal.aborted, true);
      assert.equal(Number.isFinite(valuesCancellationDeliveredAt), true);
      assert.equal(Number.isFinite(valuesStopObservedAt), true);
      assert(valuesStopObservedAt >= valuesCancellationDeliveredAt);
      assert.equal(valuesCancellationExecution.status, 'host-tasks-failed');
      assert.equal(valuesCancellationExecution.failure?.name, 'AbortError');
      assert.deepEqual(
        valuesCancellationExecution.completed.map(item => item.task),
        Array.from({length: cancelAtStart - 1}, (_, index) => index + 1),
        'a bounded task cannot publish its partial output',
      );
    } finally {
      valuesCancellationCapture.close();
      await valuesCancellationExecution?.close();
      if (valuesCancellationExecution) {
        let cleaned = false;
        for (let attempt = 0; attempt < 3 && !cleaned; attempt++) {
          cleaned = await valuesCancellationExecution.cleanup();
        }
        assert.equal(cleaned, true);
        assert.equal(valuesCancellationExecution.cleanupPending(), false);
        assert.equal(valuesCancellationExecution.usage().heldBytes, 0n);
        assert.equal(
          valuesCancellationExecution.usage().reservedExecutionBytes,
          0n,
        );
      }
    }
  }
  // The runnable application reads user-supplied documents, not conformance
  // exports or test catalogs. Tests supply their own documents at its boundary.
  const exampleDirectory = await mkdtemp(join(root, '_build/duckdb-fixtures/example-input-'));
  try {
    await exerciseManagedExample(path, args[0], args[1], hash([{id: 3}, {id: 3}]));
    const environment = join(exampleDirectory, 'environment.json');
    const programFile = join(exampleDirectory, 'program.json');
    const parameters = join(exampleDirectory, 'parameters.json');
    // The example installs no account by itself: this Host names its file.
    const accountConfig = join(exampleDirectory, 'account-config.json');
    const exampleProgram = await readFile(join(root, 'adapters/connectors/duckdb/node/examples/program.json'), 'utf8');
    await Promise.all([writeFile(environment, args[0]), writeFile(programFile, exampleProgram),
      writeFile(parameters, '{"minimum":1}'),
      writeFile(accountConfig, exampleAccountConfiguration({database: path}))]);
    for (const [estimate, expected] of [['1', ['duckdb', 'duckdb', 'duckdb']],
      ['20', ['local', 'local', 'local']], ['5', ['duckdb', 'duckdb', 'local']]]) {
      const result = await runExample({ accountConfig, database: path, environment, environmentCid: args[1],
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
      ['0', '5', '0', ['local-managed', 'local-managed',
        'local-managed']],
    ]) {
      const beforeFiles = (await readdir(exampleDirectory)).sort();
      const evidenceRuntime = await import(pathToFileURL(join(root, '_build/js/release/build/retained_host_bridge/retained_host_bridge.js')));
      const observed = [];
      const observer = installCompletionObserver(({task, output, readRetained}) => {
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
        assert.equal(typeof readRetained, 'function');
        observed.push({task, output, evidence, descriptor, readRetained});
      });
      const result = await runExample({accountConfig, database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: native,
        localImportWorkMilliseconds: imports,
        retainedWorkMilliseconds: fileWork,
        retainedOutput: {parentDirectory: exampleDirectory, maxFrameBytes: 100000,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000}}}, observer);
      try {
        assert.equal(result.report.status, 'host-tasks-completed');
        assert.deepEqual(result.report.completed.map(item => item.realization), expected);
        if (expected[2] !== 'local-managed') {
          assert.equal(result.report.internal_output_cids[2].cid,
            hash([{id: 3}, {id: 3}]));
        }
        assert.deepEqual(observed.map(value => value.task), result.report.completed.map(value => value.task));
        for (const record of observed) {
          if (record.descriptor) {
            assert.equal(record.descriptor.rows_cid,
              result.report.internal_output_cids.find(value => value.task === record.task).cid);
            const chunks = [];
            const receipt = await record.readRetained(chunk => {
              chunks.push(Buffer.from(chunk));
            });
            const bytes = Buffer.concat(chunks);
            assert.equal(bytes.length, receipt.bytes);
            assert.equal(`sha256:${createHash('sha256').update(bytes).digest('hex')}`,
              record.descriptor.rows_cid);
          }
        }
        if (imports !== undefined && expected[2] === 'local') {
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
          await assert.rejects(record.readRetained(() => {}),
            {code: 'RetainedUnavailable'});
          assert.equal(evidenceRuntime.retainedCompletionCanHandoff(record.evidence, record.output), false);
          assert.deepEqual(evidenceRuntime.retainedCompletionDescriptor(record.evidence), record.descriptor);
        }
      }
      assert.equal(result.execution.usage().heldBytes, 0n);
      assert.deepEqual((await readdir(exampleDirectory)).sort(), beforeFiles);
    }
    const residentExample = await runExample({ accountConfig, database: path, environment, environmentCid: args[1],
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
      const result = await runExample({ accountConfig, database: path, environment, environmentCid: args[1],
        program: programFile, parameters, nativeMilliseconds: estimate, resident });
      try {
        assert.equal(
          result.report.status,
          'host-tasks-completed',
          result.execution.failure?.stack ?? result.execution.failure,
        );
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
      const result = await runExample({ accountConfig, database: path, environment, environmentCid: args[1],
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
    // Without --account-config the CLI denies before any path read.
    await assert.rejects(promisify(execFile)(process.execPath, [
      'adapters/connectors/duckdb/node/examples/physical-strategy.mjs', '--database', path,
      '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '5',
    ], { cwd: root, maxBuffer: 1000000 }), error => error.code === 1 &&
      /ACTQL_E_ACCOUNT_CONFIG_INVALID/.test(error.stderr) && error.stdout === '');
    const cli = await promisify(execFile)(process.execPath, [
      'adapters/connectors/duckdb/node/examples/physical-strategy.mjs', '--database', path,
      '--account-config', accountConfig, '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '5',
    ], { cwd: root, maxBuffer: 1000000 });
    assert.equal(JSON.parse(cli.stdout).status, 'host-tasks-completed');
    const residentCli = await promisify(execFile)(process.execPath, [
      'adapters/connectors/duckdb/node/examples/physical-strategy.mjs', '--database', path,
      '--account-config', accountConfig, '--environment', environment, '--environment-cid', args[1], '--program', programFile,
      '--parameters', parameters, '--native-ms', '20', '--resident',
    ], { cwd: root, maxBuffer: 1000000 });
    const residentReport = JSON.parse(residentCli.stdout);
    assert.equal(residentReport.status, 'host-tasks-completed');
    assert.deepEqual(residentReport.completed.map(item => item.realization),
      ['duckdb-resident', 'duckdb-resident', 'duckdb-resident']);
    const exampleGuide = await readFile(join(root, 'adapters/connectors/duckdb/node/examples/README.md'), 'utf8');
    assert.match(exampleGuide, /## Resident candidates/);
    assert.match(exampleGuide, /`--resident` defaults to false/);
    assert.match(exampleGuide, /--native-ms 20 --resident/);
    assert.match(exampleGuide, /does not force every task/);
    assert.match(exampleGuide, /500000 cumulative transfer bytes/);
    assert.doesNotMatch(exampleGuide, /no resident DuckDB\s+sharing/);
    await assert.rejects(runExample({ accountConfig, database: path, environment,
      environmentCid: 'sha256:' + '0'.repeat(64), program: programFile,
      parameters, nativeMilliseconds: '5' }));
    const applicationSource = await readFile(join(root, 'src/physical_strategy_example/moon.pkg'), 'utf8');
    assert.doesNotMatch(applicationSource, /conformance|query_integration/);
    const script = await readFile(join(root, 'adapters/connectors/duckdb/node/examples/physical-strategy.mjs'), 'utf8');
    assert.doesNotMatch(script, /duckdb\/conformance|query_integration/);
    await writeFile(programFile, await readFile(join(root,
      'adapters/connectors/duckdb/node/examples/join-count.json'), 'utf8'));
    for (const [estimate, resident, expected, retained] of [
      ['20', false, ['local', 'local', 'local', 'local']],
      ['1', false, ['duckdb', 'duckdb', 'duckdb', 'duckdb']],
      ['20', true, ['local', 'local', 'duckdb-resident', 'duckdb-resident']],
      ['1', false, Array(4).fill('local-managed'), true],
    ]) {
      const result = await runExample({ accountConfig, database: path, environment,
        environmentCid: args[1], program: programFile, parameters,
        nativeMilliseconds: estimate, resident,
        ...(retained ? {localImportWorkMilliseconds: '0',
          retainedWorkMilliseconds: '0',
          retainedOutput: {parentDirectory: exampleDirectory, maxFrameBytes: 100000,
            wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
              max_columns: 10, max_order_work: 10000}}} : {}) });
      try {
        assert.equal(result.report.status, 'host-tasks-completed', String(result.execution.failure));
        assert.deepEqual(result.report.completed.map(item => item.realization), expected,
          `join-count estimate=${estimate} resident=${resident} retained=${Boolean(retained)}`);
        assert.equal(result.report.internal_output_cids.length, 4);
        if (!retained) {
          assert.equal(result.report.internal_output_cids[3].cid,
            hash([{ id: 3, n: 4, present: 4 }]));
        }
        // Every placement, including managed retained inputs, publishes the
        // exact counted row.
        assert.deepEqual(await readPublishedResultRows(runtimeCore(hostRuntime),
          result.execution, 0), [{id: 3, n: 4, present: 4}]);
      } finally { await result.close(); }
      assert.equal(result.execution.usage().heldBytes, 0n);
    }
    // Both branches contain duplicate id=3; NULL rejection succeeds, whereas
    // one-to-one must fail before the join publishes any result. The retained
    // profile is an offer, not a forced physical placement.
    for (const [obligation, succeeds] of [
      [{null_key: 'fail'}, true], [{cardinality: 'one_to_one'}, false],
    ]) {
      const joined = JSON.parse(await readFile(join(root,
        'adapters/connectors/duckdb/node/examples/join-count.json'), 'utf8'));
      Object.assign(joined.stages[3].steps[0].join, obligation);
      await writeFile(programFile, JSON.stringify(joined));
      const result = await runExample({accountConfig, database: path, environment,
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
        assert(result.report.completed.every(item => item.realization === 'local-managed'));
        if (succeeds) {
          assert.equal(result.report.completed[3].outputRows, 1);
          assert.deepEqual(await readPublishedResultRows(runtimeCore(hostRuntime),
            result.execution, 0), [{id: 3, n: 4, present: 4}]);
        } else {
          assert.equal(result.execution.failure.code, 'MoonBitHostFailure');
          assert(result.execution.failure.cause, 'preserve the typed join validation failure');
          assert.equal(result.execution.cleanupPending(), false,
            'managed validation failure settles its physical cleanup');
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
        assert.equal(typeof captured.source, 'function');
        assert.ok(captured.source());
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
    assert.equal(typeof accounted.source, 'function');
    assert.ok(accounted.source());
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
      Array(3).fill('local-managed'),
    );
    assert(managedStandardExecution.completed.every(item =>
      item.outputRows > 0), JSON.stringify(managedStandardExecution.completed));
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
    const twoSiteSetup = fixture.strategyFixtureManagedTwoSiteDispatch(
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
    if (twoSiteExecution.status !== 'host-tasks-completed') {
      const failure = String(
        twoSiteExecution.failure?.code ??
        twoSiteExecution.failure?.message ??
        'none',
      ).slice(0, 256);
      assert.fail(
        `two-site status=${twoSiteExecution.status}; failure=${failure}; ` +
        `completed=${twoSiteExecution.completed.length}; ` +
        `candidates=${twoSiteExecution.candidateComparisons.length}; ` +
        `excluded=${twoSiteExecution.candidateExclusions.length}`,
      );
    }
    assert.equal(twoSiteExecution.status, 'host-tasks-completed');
    const realizations =
      twoSiteExecution.completed.map(item => item.realization);
    if (realizations.join('\n') !== [
      'duckdb-managed',
      'duckdb-managed',
      'local-managed',
      'local-managed',
    ].join('\n')) {
      assert.fail(
        `unexpected two-site realizations: ${realizations.slice(0, 8).join(',')}`,
      );
    }
    assert.deepEqual(realizations, [
      'duckdb-managed',
      'duckdb-managed',
      'local-managed',
      'local-managed',
    ]);
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
    const capacitySetup = fixture.strategyFixtureManagedTwoSiteDispatch(
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
      const failureSetup = fixture.strategyFixtureManagedTwoSiteDispatch(
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
      const observedClosing = Promise.allSettled([closing]);
      if (failureExecution) {
        const [closeObservation] = await observedClosing;
        if (closeObservation.status === 'rejected') {
          const error = closeObservation.reason;
          assert(error.code === 'ManagedOutputCleanupPending' ||
            (error instanceof AggregateError &&
              error.message === 'ManagedSiteTransferCleanupFailed'));
          assert.equal(error.cleanupPending, true);
          assert.equal(typeof error.cleanupHandle?.retry, 'function');
        }
        // Each cleanup pass retries each independent owner once. A Store
        // retry may precede the Transfer retry that releases its reader pin.
        const cleaned = await failureExecution.cleanup();
        if (!cleaned) {
          assert.equal(failureExecution.cleanupPending(), true);
          assert(failureExecution.usage().reservedExecutionBytes > 0n,
            'pending output cleanup must retain its original scratch');
          assert.equal(await failureExecution.cleanup(), true,
            'after source stop, retry must settle the original output owner');
        }
        assert.equal(failureExecution.cleanupPending(), false);
        assert.equal(failureExecution.usage().reservedTransferBytes, 0n);
        assert.equal(failureExecution.usage().reservedRetentionBytes, 0n);
        assert.equal(failureExecution.usage().reservedExecutionBytes, 0n,
          transferFailureCase);
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
      const setup = fixture.strategyFixtureManagedTwoSiteDispatch(failureFixture);
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
      const setup = fixture.strategyFixtureManagedTwoSiteDispatch(cleanupFixture);
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
  // and caller false cannot erase that floor. The Local managed implementation
  // now satisfies the exact identity obligation instead of being excluded by
  // JavaScript before MoonBit checks its registered issuer.
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
        fixture.strategyFixtureManagedAfterFirstDispatch(publicFixture),
        publicOptions,
      );
      assert.equal(publicExecution.status, 'host-tasks-completed');
      assert.equal(publicExecution.failure, undefined);
      assert.deepEqual(
        publicExecution.completed.map(item => item.task),
        [1, 2, 3],
      );
      assert.deepEqual(
        publicExecution.completed.map(item => item.realization),
        ['duckdb-managed', 'local-managed', 'local-managed'],
      );
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
    {name: 'publication', policy: {publication: true}, completed: 3,
      succeeds: true},
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
        fixture.strategyFixtureManagedAfterFirstDispatch(identityFixture),
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
          ['duckdb-managed', 'local-managed', 'local-managed'],
        'identity-capable Local wins the registered candidate comparison');
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
        fixture.strategyFixtureDuckDBManagedDispatch(managedJoinFixture),
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
      fixture.strategyFixtureDuckDBManagedDispatch(managedGroupFixture),
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
      fixture.strategyFixtureDuckDBManagedDispatch(managedFailureFixture),
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
    const delayedStopSetup = fixture.strategyFixtureDuckDBManagedDispatch(
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
        bridge,
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
  // Capture and downstream count consumers share exact retained value evidence.
  // This passes the actual checked DAG and installed resident Host, not a fake
  // verifier callback. Any new comparison still executes its demand scan.
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
      assert.deepEqual(execution.completed.map(item => item.phases.reusedInputValues), [1, 1, 1]);
      assert.deepEqual(execution.completed.map(item => item.phases.directInputScans), [0, 0, 0]);
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
      assert.equal(imported.nativeScalarStaging, Boolean(retainedSource && batchedImport));
      assert.equal(imported.usage.statements, retainedSource ? 1 : batchedImport ? 3 : 4);
      assert.equal(imported.usage.preparations, retainedSource ? 1 : batchedImport ? 3 : 2,
        'retained rows use a typed appender; other imports prepare bounded INSERT shapes');
      if (retainedSource) {
        assert.equal(imported.usage.appendedRows, 3);
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
        assert.equal(output.diagnostics.directInputScans +
          output.diagnostics.demandColumnScans +
          output.diagnostics.reusedDemandMeasurements, retainedSource ? 1 : 0,
        'each retained consumer checks its exact input once: a bounded scan or its reused facts');
        assert.equal(output.diagnostics.reusedInputValues,
          output.diagnostics.demandColumnScans + output.diagnostics.reusedDemandMeasurements,
          'value evidence is reused when the demand is discharged without a full scan');
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
      const imported = await importResidentStrategyInput(environment, 0, 4000000n,
        {...suppliedLimits, maxColumns: 1, maxChunkRows: 2, maxChunkBytes: 4096}, mapping);
      assert.equal(imported.nativeScalarStaging, true);
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
          // Local dispatch starts a bounded attempt; drive it to completion.
          const local = checked(hostRuntime.strategyModule_local_Dispatch(dispatch, task));
          while (!checked(local.advance(256)).complete) {}
          checked(local.settle());
          checked(local.complete());
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
