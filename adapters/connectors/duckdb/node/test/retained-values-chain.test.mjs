import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import * as moon from '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as fixture from '../../../../../_build/js/release/build/connectors/duckdb/conformance/conformance.js';
import {canonicalText} from '../../../../../scripts/check-canonical-json.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from '../../../../host-node/client-program-preparation.mjs';
import {createNodeHostEntry} from '../../../../host-node/entry.mjs';
import {installStrategyContributions} from '../../../../connectors-builtin/strategy.generated.mjs';
import {checked} from '../../../../host-common/runtime-result.mjs';
import {sourceFreeTaskPlan} from '../../../../host-node/local-values-plan.mjs';
import {installLocalRetainedStore} from '../../../../local-node/retained-store.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {openLocalPublicationStore} from '../../../../store-local/publication-store.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const cid = digit => `sha256:${digit.repeat(64)}`;
const resultNames = ['published', 'consumed_a', 'consumed_b'];

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

async function retainedRun(document, use, mode = 'success') {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retained-values-chain-'));
  let retained, publication, owner, execution;
  let permitCleanup = mode !== 'finalize-failure';
  let dispatches = 0, appendsFailed = 0, finalizationsFailed = 0;
  let producerWork = 0n, sawStop = false, scheduled = false;
  const cancellation = new AbortController();
  try {
    const body = JSON.parse(await readFile(join(root,
      'packages/sdk/fixtures/values.environment.json'), 'utf8'));
    const environment = moon.clientProgramCheckEnvironment(canonicalText(body),
      body.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const prepare = installNodeClientProgramPreparation({moon, environment});
    const prepared = prepare({kind: 'aql',
      input: {text: document, format: 'json'}, parameters: null});
    const contracts = await pinnedEngineContracts(root);
    const setup = fixture.strategyFixtureSourceFreeRetainedSubset(
      prepared, ...contracts, 100000, 10000);
    // The source-free root is one physical task with three checked steps,
    // not a test-only acquisition task or an artificially split chain.
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, 0), 3);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, 1), 1);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, 2), 1);
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, 3), undefined);
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
                  // Three scalar Values rows take eleven polls, followed by
                  // one handoff. Work thirteen is inside the filter child.
                  if (mode === 'cancel-after-filter' && !scheduled &&
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
    const plan = sourceFreeTaskPlan({moon, control: runtime.publicationControl,
      preparedProgram: prepared, authorityScopeCid: cid('a'), namespaceId: 'local',
      storeAuthorityCid: cid('c'), now: () => '2026-09-30T00:00:00.000Z'});
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
    await use({setup, plan, retained, publication, leases,
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
    } finally {
      await retained?.close();
      await retained?.cleanup();
      await publication?.close();
      await rm(directory, {recursive: true, force: true});
    }
  }
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
