import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import {DuckDBInstance} from '@duckdb/node-api';
import * as moon from '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as fixture from '../../../../../_build/js/release/build/connectors/duckdb/conformance/conformance.js';
import {canonicalText} from '../../../../../scripts/check-canonical-json.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from '../../../../host-node/client-program-preparation.mjs';
import {createNodeHostEntry} from '../../../../host-node/entry.mjs';
import {installStrategyContributions} from '../../../../connectors-builtin/strategy.generated.mjs';
import {checked} from '../../../../host-common/runtime-result.mjs';
import {sourceFreeTaskPlan, acquiredTaskRunAdmission,
  acquiredTaskPublicationPlan} from '../../../../host-node/local-values-plan.mjs';
import {authorizeLocalDatabase} from '../session.mjs';
import {runNativeHostQuery, runRetainedNativeHostQuery, nativeSourceIdentityMatches,
  issueNativeSourceEvidence} from '../host.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {installLocalRetainedStore} from '../../../../local-node/retained-store.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {identifyRetainedCapturedSource} from '../../../../local-node/captured-source-identity.mjs';
import {openLocalPublicationStore} from '../../../../store-local/publication-store.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const cid = digit => `sha256:${digit.repeat(64)}`;
const resultNames = ['published', 'consumed_a', 'consumed_b'];

async function assertPublishedRows(publication, plan, execution, expected) {
  const inventory = execution.publicationInventory.occurrences;
  assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
  for (const name of resultNames) {
    const occurrence = inventory.find(value => value.name === name);
    const chunks = [];
    const result = await publication.consumeCommittedResult({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, occurrence.definitionContract.identity, () => true,
    chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(result.rowCount, expected.length);
    assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
  }
}

function program(rows, filter = 'id >= 2') {
  const consumers = ['a', 'b'].map(name => ({
    id: `consumer_${name}`,
    inputs: {r: {result: {stage: 'source', result: 'out'}}},
    steps: [{from: 'r', select: ['id'], as: 'selected'}],
    results: {out: {from: 'selected', fields: ['id']}},
  }));
  return JSON.stringify({version: 'actql/0.1', id: 'retained-values-chain',
    stages: [{id: 'source', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false}}, rows},
        as: 'seed'},
      {filter, as: 'kept'},
      {select: ['id'], as: 'selected'},
    ], results: {out: {from: 'selected', fields: ['id']}}}, ...consumers],
    results: Object.fromEntries(resultNames.map((name, index) => [name,
      {from: {stage: index === 0 ? 'source' : `consumer_${index === 1 ? 'a' : 'b'}`,
        result: 'out'}}])),
  });
}

function capturedProgram(filter = 'id >= 2', sort = true) {
  const document = JSON.parse(program([]));
  document.id = 'retained-captured-chain';
  document.params = {minimum: {type: 'number', nullable: false}};
  document.stages.unshift({id: 'acquire',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > $minimum', as: 'scanned'},
      {select: ['id'], as: 'captured'}],
    results: {out: {from: 'captured', fields: ['id']}},
  });
  document.stages[1].inputs = {r: {result: {stage: 'acquire', result: 'out'}}};
  document.stages[1].steps = [{from: 'r', filter, as: 'kept'},
    ...(sort ? [{from: 'kept', sort: [{id: 'asc'}], as: 'ordered'}] : []),
    {from: sort ? 'ordered' : 'kept', select: ['id'], as: 'selected'}];
  return JSON.stringify(document);
}

// Use the checked acquisition planner and real native capture. The
// test installs Compute configuration directly; public Client dispatch mode
// selection remains with its Host owner.
async function openCapturedRetained(prepared, contracts, directory, rows, budgets,
  fileInput = false) {
  const [registry, values, fragment, ordered] = contracts;
  const planned = moon.clientProgramPrepareLocalQueryRequirement(
    prepared, 0, 0, registry, values, fragment, ordered);
  assert.equal(planned?.$tag, 1, `captured requirement: ${inspect(planned, {depth: 8})}`);
  const requirement = checked(planned);
  const facts = checked(moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
  const [sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
  const context = checked(moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
  const bodies = await Promise.all(['actql-query-acquisition.json',
    'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
    .map(name => readFile(join(root, 'spec/contracts', name), 'utf8')));
  const acquisition = checked(moon.clientProgramPrepareDuckDBAcquisition(
    requirement, 'main', 'records', ...bodies));
  const databasePath = join(directory, 'records.duckdb');
  const database = await DuckDBInstance.create(databasePath);
  const connection = await database.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    for (const row of rows) {
      await connection.run('INSERT INTO records VALUES ($1, NULL)', [row.id]);
    }
  } finally {
    connection.closeSync();
    database.closeSync();
  }
  const grant = await authorizeLocalDatabase(databasePath, {
    ...fixtureSourceAccess, sourceRef,
  });
  const captureStartedAt = new Date().toISOString();
  const limits = {
    maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
    maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
    memoryBytes: 128 * 1024 * 1024, threads: 1,
  };
  const capture = fileInput
    ? await runRetainedNativeHostQuery(grant, acquisition, limits, {
      parentDirectory: directory, maxFrameBytes: 4096,
      wire: {max_columns: 10, max_order_work: 10000, max_bytes: 100000,
        max_nodes: 10000, max_depth: 64},
    }) : await runNativeHostQuery(grant, acquisition, limits);
  try {
    const captureCompletedAt = new Date().toISOString();
    const source = capture.source();
    assert.equal(moon.clientProgramCapturedSourceMatches(prepared, source), true);
    const identity = fileInput
      ? await identifyRetainedCapturedSource(moon, source)
      : checked(moon.clientProgramIdentifyCapturedSourceRelation(source));
    if (fileInput && rows.length === 0) {
      // Independent SHA-256 of {"sort":"relation","value":[]}.
      assert.equal(moon.clientProgramCapturedSourceLogicalCid(identity),
        'sha256:d2889f6d3b43fe20f75149d13eb0585918c94cf3a5b0520f5f9e1525b0846f3d');
    }
    assert.equal(nativeSourceIdentityMatches(capture, identity), true);
    const logicalInput = checked(moon.clientProgramIssueCapturedSourceLogical(
      prepared, source, identity, requirement));
    const setup = budgets
      ? fixture.strategyFixtureCapturedRetainedSubset(prepared, source,
        registry, values, fragment, budgets.work, budgets.workspace)
      : moon.clientProgramOpenCapturedLocalRetainedHost(prepared,
        source, registry, values, 1n, 0n, 0n, 0n, fragment, ordered);
    assert.ok(setup, 'the product captured factory must install retained output');
    return {setup, capture, identity, logicalInput,
      checkedSource: {sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid},
      captureStartedAt, captureCompletedAt,
      issueSourceEvidence: options => issueNativeSourceEvidence(capture,
        {...options, context, identity, logicalInput})};
  } catch (error) {
    capture.close();
    await capture.cleanupHandle?.retry();
    throw error;
  }
}

async function retainedRun(document, use, mode = 'success', budgets, captureRows,
  fileInput = false) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retained-values-chain-'));
  let retained, publication, owner, execution, captured;
  let permitCleanup = mode !== 'finalize-failure';
  let dispatches = 0, appendsFailed = 0, finalizationsFailed = 0;
  let producerWork = 0n, sawStop = false, scheduled = false;
  const cancellation = new AbortController();
  try {
    const body = JSON.parse(await readFile(join(root, captureRows
      ? 'adapters/host-node/fixtures/query-amount-environment.json'
      : 'packages/sdk/fixtures/values.environment.json'), 'utf8'));
    const environment = moon.clientProgramCheckEnvironment(canonicalText(body),
      body.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const prepare = installNodeClientProgramPreparation({moon, environment});
    const prepared = prepare({kind: 'aql',
      input: {text: document, format: 'json'},
      parameters: captureRows ? {minimum: 0} : null});
    const contracts = await pinnedEngineContracts(root, ['registered_body',
      'registered_values', 'registered_fragment', 'registered_ordered']);
    const [registry, values, fragment] = contracts;
    if (captureRows) captured = await openCapturedRetained(prepared,
      contracts, directory, captureRows, budgets, fileInput);
    // Boundary injection uses the same checked owner, installed provider and
    // retained driver. Ordinary success/fault cases use the product factory.
    const setup = captured?.setup ?? (budgets
      ? fixture.strategyFixtureSourceFreeRetainedSubset(prepared,
        registry, values, fragment, budgets.work, budgets.workspace)
      : moon.clientProgramOpenSourceFreeLocalRetainedHost(
        prepared, registry, values, 1n, 0n, 0n, 0n, fragment, undefined));
    assert.ok(setup, 'the checked retained factory must admit this chain');
    // The declared producer remains one physical task, not a fixture split.
    const first = captured ? 1 : 0;
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, first),
      JSON.parse(document).stages[first].steps.length);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, first + 1), 1);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, first + 2), 1);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, first + 3), undefined);
    const observedMoon = new Proxy(moon, {
      get(target, property, receiver) {
        if (property !== 'strategyModule_local_Dispatch' &&
            property !== 'strategyModule_local_ManagedStart') {
          return Reflect.get(target, property, receiver);
        }
        return (...args) => {
          const dispatch = ++dispatches;
          const operations = checked(target[property](...args));
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, name, receiver) {
              if (name === 'execute') return () => assert.fail('synchronous Compute');
              if (name === 'execution_stopped') return () => {
                const stopped = operation.execution_stopped();
                if (dispatch === 1 && cancellation.signal.aborted && stopped) {
                  sawStop = true;
                }
                return stopped;
              };
              if (name !== 'advance') return Reflect.get(operation, name, receiver);
              return quantum => {
                const result = operation.advance(Math.min(quantum, 1));
                if (dispatch === 1 && result.$tag === 1) {
                  producerWork += result._0.work;
                  // For Values, eleven polls and one handoff precede Filter.
                  // Captured mode proves positive Compute progress only.
                  if (['cancel-after-filter', 'cancel-after-progress'].includes(mode) && !scheduled &&
                      producerWork >= 13n && !result._0.complete) {
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
    const host = createNodeHostEntry(() => observedMoon, installStrategyContributions);
    const runtime = runtimeCore(observedMoon);
    const options = {moon, control: runtime.publicationControl,
      preparedProgram: prepared, authorityScopeCid: cid('a'), namespaceId: 'local',
      storeAuthorityCid: cid('c'), now: () => captured
        ? new Date().toISOString() : '2026-09-30T00:00:00.000Z'};
    const plan = captured ? acquiredTaskPublicationPlan({...options,
      acquired: acquiredTaskRunAdmission(options), captured,
      sourceEvidenceWire: await captured.issueSourceEvidence({
        authorityScopeCid: options.authorityScopeCid,
        effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}),
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid,
      captureStartedAt: captured.captureStartedAt,
      captureCompletedAt: captured.captureCompletedAt}) : sourceFreeTaskPlan(options);
    retained = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024});
    publication = await openLocalPublicationStore({
      directory: join(directory, 'publication'), storeAuthorityCid: cid('c'),
      capacityBytes: 512 * 1024 * 1024,
      maxObjectBytes: plan.outputLimits.maxWireBytes, maxObjects: 100,
      maxContractNodes: 10000, maxContractDepth: 64,
    }, runtime.publicationControl);
    const leases = [];
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases.push(key);
      const failWrite = leases.length === 1 &&
        (mode === 'append-failure' || mode === 'finalize-failure');
      let writer, closed = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && (!closed ||
          (failWrite && !permitCleanup)) ? bytes : 0,
          cleanupPending: (failWrite && !permitCleanup) ||
            (writer?.cleanupHandle?.status().pending ?? false)}),
        reserve(value) {
          writer = retained.reserve(value);
          if (!failWrite) return writer;
          return Object.freeze({
            start: () => writer.start(),
            async append(part) {
              if (mode !== 'append-failure') return writer.append(part);
              appendsFailed++;
              throw new Error('InjectedRetainedAppendFailure');
            },
            async seal(identity) {
              finalizationsFailed++;
              await writer.seal(identity);
              throw new Error('InjectedRetainedFinalizeFailure');
            },
          });
        },
        close() {
          if (cancellation.signal.aborted) assert.equal(sawStop, true);
          closed = true;
          writer?.cancel();
        },
        async cleanup() {
          if (failWrite && !permitCleanup) throw new Error('InjectedCleanupPending');
          await writer?.cleanupHandle?.retry?.();
        },
      });
    });
    await use({setup, plan, retained, publication, leases, captured,
      observations: () => ({dispatches, producerWork, sawStop, scheduled,
        appendsFailed, finalizationsFailed}),
      permitCleanup() { permitCleanup = true; },
      async run() {
        try {
          owner = await host.runPublishedCapturedStrategy(setup,
            {store: publication, plan}, {local: configuration},
            cancellation.signal);
          execution = owner.execution;
          return owner;
        } catch (error) {
          execution = error.execution;
          if (mode !== 'success') throw error;
          throw new Error(`${error.message}: ${inspect(error.cause)}; ` +
            `failure=${inspect(execution?.failure, {depth: 8})}`, {cause: error});
        }
      },
    });
  } finally {
    const beforeCleanup = dispatches;
    permitCleanup = true;
    try {
      if (owner) {
        await owner.close();
        assert.equal(await owner.cleanup(), true);
      } else if (execution) {
        await execution.close();
        assert.equal(await execution.cleanup(), true);
      }
      if (execution) {
        assert.equal(dispatches, beforeCleanup, 'cleanup must not redispatch Compute');
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
      if (retained) {
        assert.equal(retained.status().reservedBytes, 0);
        assert.equal(retained.status().holdings, 0);
        assert.equal(retained.status().reservedReadBufferBytes, 0);
      }
      if (captured) {
        assert.equal(nativeSourceIdentityMatches(captured.capture,
          captured.identity), true, 'Compute cleanup must not retire the acquisition');
      }
    } finally {
      try {
        await retained?.close();
        await retained?.cleanup();
        await publication?.close();
      } finally {
        try {
          captured?.capture.close();
          await captured?.capture.cleanupHandle?.retry();
        } finally {
          await rm(directory, {recursive: true, force: true});
        }
      }
    }
  }
}

// Independent scalar phase model, also checked in the portable provider test:
// Values 11 + filter true 31 + select 19 + two handoffs = 63 work units.
// Filter's three metadata entries, three roots, snapshot and two predicate
// slots peak at nine workspace entries. These are not sampled from a run.
for (const {name, work, workspace, failure} of [
  {name: 'exact scalar chain budgets', work: 63, workspace: 9},
  {name: 'one-short scalar chain work', work: 62, workspace: 9,
    failure: 'work'},
  {name: 'one-short scalar chain workspace', work: 63, workspace: 8,
    failure: 'workspace'},
]) {
  test(`retained Values honors ${name}`, async () => retainedRun(
    program([{id: 3}, {id: 1}, {id: 2}], 'true'),
    async ({run, plan, publication, observations}) => {
      if (!failure) {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().producerWork, 63n);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(),
          [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')),
            [{id: 3}, {id: 1}, {id: 2}]);
        }
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          execution = error.execution;
          return true;
        });
        assert.deepEqual(execution.completed, []);
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(failure === 'work'
          ? fixture.strategyFixtureRetainedInputLimit(execution.failure.cause)
          : fixture.strategyFixtureRetainedRowLimit(execution.failure.cause), true);
        assert.equal(observations().dispatches, 1);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
    }, failure ?? 'success', {work, workspace}));
}

for (const {name: mode} of [
  {name: 'cancel-after-filter'}, {name: 'arithmetic'},
  {name: 'append-failure'}, {name: 'finalize-failure'},
]) {
  test(`retained source-free Values chain retains responsibility after ${mode}`,
    async () => retainedRun(program([{id: 3}, {id: 1}, {id: 2}],
      mode === 'arithmetic' ? '1 / (id - id) > 0' : 'id >= 2'),
    async ({run, plan, publication, observations, permitCleanup}) => {
      let execution;
      await assert.rejects(run(), error => {
        assert.equal(error.code, 'CapturedRunPublicationFailed');
        execution = error.execution;
        return true;
      });
      assert.equal(execution.status, 'host-tasks-failed');
      assert.deepEqual(execution.completed, []);
      assert.equal(observations().dispatches, 1);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      if (mode === 'cancel-after-filter') {
        assert.ok(observations().producerWork >= 13n);
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
        assert.equal(execution.failure.name, 'AbortError');
      } else if (mode === 'arithmetic') {
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureRetainedChainFilterArithmetic(
          execution.failure.cause), true);
      } else if (mode === 'append-failure') {
        assert.equal(observations().appendsFailed, 1);
      } else {
        assert.equal(observations().finalizationsFailed, 1);
        assert.equal(execution.cleanupPending(), true);
        assert.equal(await execution.cleanup(), false);
        assert.ok(execution.usage().reservedExecutionBytes > 0n ||
          execution.usage().heldBytes > 0n);
        assert.equal(observations().dispatches, 1);
        permitCleanup();
      }
    }, mode));
}

for (const {name, rows, expected} of [
  {name: 'ordered source-free chain',
    rows: [{id: 3}, {id: 1}, {id: 2}], expected: [{id: 3}, {id: 2}]},
  {name: 'empty source-free chain', rows: [], expected: []},
  {name: 'empty filtered output', rows: [{id: 1}], expected: []},
]) {
  test(`retained Values publishes ${name} and two independent consumers`,
    async () => retainedRun(program(rows), async ({run, plan, publication, leases}) => {
      const owner = await run();
      assert.equal(owner.status, 'published');
      assert.deepEqual(owner.execution.completed.map(value => value.task), [0, 1, 2]);
      assert.deepEqual(owner.execution.completed.map(value => value.realization),
        ['local', 'local', 'local']);
      assert.ok(owner.execution.completed.every(value =>
        value.outputRepresentation === 'retained-file'));
      assert.equal(leases.length, 3);
      const inventory = owner.execution.publicationInventory.occurrences;
      assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
      // Resolve each independently named committed Result. A missing consumer
      // cannot remove its own assertion by disappearing from the inventory.
      for (const name of resultNames) {
        const occurrence = inventory.find(value => value.name === name);
        const chunks = [];
        const result = await publication.consumeCommittedResult({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, occurrence.definitionContract.identity, () => true,
        chunk => chunks.push(Buffer.from(chunk)));
        assert.equal(result.rowCount, expected.length);
        assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
      }
    }));
}

for (const fileInput of [false, true]) {
for (const {name, rows, expected} of [
  {name: 'ordered acquired chain',
    rows: [{id: 3}, {id: 1}, {id: 2}], expected: [{id: 2}, {id: 3}]},
  {name: 'empty acquired chain', rows: [], expected: []},
  {name: 'empty acquired filtered output', rows: [{id: 1}], expected: []},
]) {
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host publishes ${name} and two consumers`,
    async () => retainedRun(capturedProgram(),
      async ({run, plan, publication, leases, captured}) => {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.deepEqual(owner.execution.completed.map(value => value.task), [1, 2, 3]);
        assert.ok(owner.execution.completed.every(value =>
          value.realization === 'local' && value.outputRepresentation === 'retained-file'));
        assert.equal(leases.length, 3);
        assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          const result = await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.equal(result.rowCount, expected.length);
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
        }
      }, 'success', undefined, rows, fileInput));
}
}

test('file-captured identity observes delivered cancellation and preserves acquisition custody',
  async () => retainedRun(capturedProgram(),
    async ({run, publication, plan, captured}) => {
      const cancellation = new AbortController();
      let rows = 0, finishes = 0;
      const observed = new Proxy(moon, {get(target, name, receiver) {
        if (name === 'clientProgramAppendCapturedSourceIdentityScan') {
          return (...args) => {
            const result = target[name](...args);
            if (result.$tag === 1 && ++rows === 1) {
              setImmediate(() => cancellation.abort());
            }
            return result;
          };
        }
        if (name === 'clientProgramFinishCapturedSourceIdentityScan') {
          return (...args) => { finishes++; return target[name](...args); };
        }
        return Reflect.get(target, name, receiver);
      }});
      await assert.rejects(identifyRetainedCapturedSource(observed,
        captured.capture.source(), cancellation.signal), {name: 'AbortError'});
      assert.equal(rows, 1);
      assert.equal(finishes, 0);
      assert.equal(captured.capture.storageUsage().reservedReadBufferBytes, 0);
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
      const identity = await identifyRetainedCapturedSource(moon, captured.capture.source());
      assert.equal(moon.clientProgramCapturedSourceLogicalCid(identity),
        moon.clientProgramCapturedSourceLogicalCid(captured.identity));
      const owner = await run();
      assert.equal(owner.status, 'published');
      await assertPublishedRows(publication, plan, owner.execution, [{id: 2}, {id: 3}]);
    }, 'success', undefined, [{id: 3}, {id: 1}, {id: 2}], true));

test('file-captured retained Host preserves source custody after positive Compute cancellation',
  async () => retainedRun(capturedProgram(),
    async ({run, plan, publication, captured, observations}) => {
      await assert.rejects(run, error => {
        const execution = error.execution;
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
        assert.ok(observations().producerWork > 0n);
        assert.equal(execution.completed.length, 0);
        assert.equal(observations().dispatches, 1);
        assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
        return true;
      });
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
    }, 'cancel-after-progress', undefined, [{id: 3}, {id: 1}, {id: 2}], true));

// The same three-row Filter (31), Select (19), and one handoff (1) require
// 51 work units and nine peak workspace entries. No Values child runs here.
for (const fileInput of [false, true]) {
for (const {name, work, workspace, failure} of [
  {name: 'exact captured scalar budgets', work: 51, workspace: 9},
  {name: 'one-short captured scalar work', work: 50, workspace: 9, failure: 'work'},
  {name: 'one-short captured scalar workspace', work: 51, workspace: 8,
    failure: 'workspace'},
]) {
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host honors ${name}`, async () => retainedRun(
    capturedProgram('true', false),
    async ({run, plan, publication, captured, observations}) => {
      if (!failure) {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().producerWork, 51n);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')),
            [{id: 1}, {id: 2}, {id: 3}]);
        }
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          execution = error.execution;
          return true;
        });
        assert.deepEqual(execution.completed, []);
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(failure === 'work'
          ? fixture.strategyFixtureRetainedInputLimit(execution.failure.cause)
          : fixture.strategyFixtureRetainedRowLimit(execution.failure.cause), true);
        assert.equal(observations().dispatches, 1);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
    }, failure ?? 'success', {work, workspace}, [{id: 1}, {id: 2}, {id: 3}], fileInput));
}
}

for (const fileInput of [false, true]) {
for (const {name, mode} of [
  {name: 'captured progress cancellation', mode: 'cancel-after-progress'},
  {name: 'captured filter arithmetic', mode: 'arithmetic'},
  {name: 'captured append failure', mode: 'append-failure'},
  {name: 'captured finalize cleanup retry', mode: 'finalize-failure'},
]) {
  if (fileInput && !['append-failure', 'finalize-failure'].includes(mode)) continue;
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host keeps source and cleanup after ${name}`,
    async () => retainedRun(capturedProgram(mode === 'arithmetic'
      ? '1 / (id - id) > 0' : 'id >= 2'),
    async ({run, plan, publication, captured, observations, permitCleanup}) => {
      let execution;
      await assert.rejects(run(), error => {
        assert.equal(error.code, 'CapturedRunPublicationFailed');
        execution = error.execution;
        return true;
      });
      assert.deepEqual(execution.completed, []);
      assert.equal(observations().dispatches, 1);
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      if (mode === 'cancel-after-progress') {
        assert.equal(execution.failure.name, 'AbortError');
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
      } else if (mode === 'arithmetic') {
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureRetainedCapturedFilterArithmetic(
          execution.failure.cause), true);
      } else if (mode === 'append-failure') {
        assert.equal(observations().appendsFailed, 1);
      } else {
        assert.equal(observations().finalizationsFailed, 1);
        assert.equal(execution.cleanupPending(), true);
        assert.equal(await execution.cleanup(), false);
        assert.ok(execution.usage().heldBytes > 0n ||
          execution.usage().reservedExecutionBytes > 0n);
        assert.equal(observations().dispatches, 1);
        permitCleanup();
      }
    }, mode, undefined, [{id: 3}, {id: 1}, {id: 2}], fileInput));
}
}
