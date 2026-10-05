import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {authorizeLocalDatabase} from '../session.mjs';
import {runNativeHostQuery} from '../host.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';
import {hash} from './typed-catalog.mjs';
import {publicationResultExportLimits, standardPublicationPlan} from
  './publication-plan-fixture.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {createNodeHostEntry, runPublishedCapturedStrategy} from
  '../../../../host-node/entry.mjs';
import {installStrategyContributions} from
  '../../../../connectors-builtin/strategy.generated.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {checked} from '../../../../host-common/runtime-result.mjs';
import {installLocalRetainedStore} from '../../../../local-node/retained-store.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {openLocalPublicationStore} from '../../../../store-local/publication-store.mjs';
import {deliverAuthorizedResult, installNodeResultAccessService,
  installResultAccessAuthority} from '../../../../host-node/result-access.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const queryLimits = {
  maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
};

// Independent ordinary-Nest fixture: duplicate parents stay distinct, NULL
// keys do not match, and children keep their authored order. Both consumers
// independently read the retained producer; publication checks all three views.
function nestProgram() {
  return {
    version: 'actql/0.1', id: 'retained-nest',
    params: {minimum: {type: 'number', nullable: false}},
    stages: [{
      id: 'a', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{filter: 'id > $minimum', as: 'filtered'},
        {select: ['id'], as: 'captured'}],
      results: {r: {from: 'captured', fields: ['id']}},
    }, {
      id: 'nest_parents', inputs: {},
      steps: [{values: {
        schema: {id: {type: 'number', nullable: false},
          key: {type: 'number', nullable: true}},
        rows: [{id: 1, key: 1}, {id: 2, key: 1},
          {id: 3, key: null}, {id: 4, key: 2}],
      }, as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'key']}},
    }, {
      id: 'nest_children', inputs: {},
      steps: [{values: {
        schema: {child_id: {type: 'number', nullable: false},
          key: {type: 'number', nullable: true},
          value: {type: 'number', nullable: true}},
        rows: [{child_id: 2, key: 1, value: null},
          {child_id: 1, key: 1, value: 10},
          {child_id: 3, key: null, value: 30}],
      }, as: 'out'}],
      results: {r: {from: 'out', fields: ['child_id', 'key', 'value']}},
    }, {
      id: 'nested', inputs: {
        parents: {result: {stage: 'nest_parents', result: 'r'}},
        children: {result: {stage: 'nest_children', result: 'r'}},
      }, from: 'parents',
      steps: [{nest: {with: 'children', on: [{left: 'key', right: 'key'}],
        into: 'items', fields: [{amount: 'value'}], max_items: 2}, as: 'out'}],
      results: {r: {from: 'out', fields: ['id', 'items', 'key']}},
    }, ...['a', 'b'].map(id => ({
      id: `nest_consumer_${id}`,
      inputs: {x: {result: {stage: 'nested', result: 'r'}}},
      steps: [{select: id === 'a'
        ? ['id', 'key', 'items'] : ['items', 'id', 'key'], as: 'out'}],
      results: {r: {from: 'out', fields: id === 'a'
        ? ['id', 'key', 'items'] : ['items', 'id', 'key']}},
    }))],
    results: {
      producer: {from: {stage: 'nested', result: 'r'}},
      first: {from: {stage: 'nest_consumer_a', result: 'r'}},
      second: {from: {stage: 'nest_consumer_b', result: 'r'}},
    },
  };
}

const expectedRows = [
  {id: 1, items: [{amount: null}, {amount: 10}], key: 1},
  {id: 2, items: [{amount: null}, {amount: 10}], key: 1},
  {id: 3, items: [], key: null},
  {id: 4, items: [], key: 2},
];

test('retained Nest uses the real Host, Store, and publication owners', async t => {
  await promisify(execFile)('moon', [
    'build', '--target', 'js', '--release',
    'src/connectors/duckdb/conformance', 'src/connectors/duckdb/host_node',
    'src/connectors_builtin_node', 'src/retained_host_bridge',
    'src/process_host_bridge',
  ], {cwd: root});
  const loadBuild = name => import(pathToFileURL(join(root,
    `_build/js/release/build/${name}/${name.split('/').at(-1)}.js`)));
  const fixture = await loadBuild('connectors/duckdb/conformance');
  const hostRuntime = await loadBuild('connectors_builtin_node');
  const catalogs = await readFile(join(root,
    'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const args = [JSON.parse(catalog[1]), catalog[2],
    ...await pinnedEngineContracts(root),
    ...await Promise.all(['acquisition', 'process-evidence', 'two-receipt'].map(
      name => readFile(join(root, `spec/contracts/actql-query-${name}.json`), 'utf8'))),
  ];
  const directory = await mkdtemp(join(tmpdir(), 'actql-retained-nest-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const database = join(directory, 'source.duckdb');
  const db = await DuckDBInstance.create(database);
  const connection = await db.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),(2,20)');
  } finally {
    connection.closeSync();
    db.closeSync();
  }
  const grant = await authorizeLocalDatabase(database, fixtureSourceAccess);
  for (const mode of ['published', 'cancelled', 'item-limit']) {
    await t.test(mode, async () => {
      const program = nestProgram();
      if (mode === 'item-limit') {
        program.stages.find(stage => stage.id === 'nested').steps[0].nest.max_items = 1;
      }
      const prepared = fixture.strategyFixtureCreate(...args, JSON.stringify(program));
      assert.equal(fixture.strategyFixtureTaskStepCount(prepared, 3), 1,
        'Nest remains one selected physical task');
      const capture = await runNativeHostQuery(grant,
        fixture.strategyFixtureAcquisition(prepared), queryLimits);
      const store = await createLocalRetainedStore({parentDirectory: directory,
        capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024});
      const leases = [];
      const configuration = installLocalRetainedStore((key, bytes) => {
        leases.push(key);
        let writer, closed = false;
        return Object.freeze({
          status: () => ({reservedBytes: writer && !closed ? bytes : 0,
            cleanupPending: writer?.cleanupHandle?.status?.().pending ?? false}),
          reserve: value => (writer = store.reserve(value)),
          close() { closed = true; writer?.cancel(); },
          async cleanup() { await writer?.cleanupHandle?.retry?.(); },
        });
      });
      const cancellation = new AbortController();
      let sawWork = false, sawStop = false, dispatches = 0;
      // Observe the existing runtime and limit its real advances. No result,
      // completion, provider, or Store operation is fabricated by this probe.
      const observedRuntime = new Proxy(hostRuntime, {
        get(target, property, receiver) {
          if (property !== 'strategyModule_local_Dispatch' &&
              property !== 'strategyModule_local_ManagedStart') {
            return Reflect.get(target, property, receiver);
          }
          return (...arguments_) => {
            const dispatch = ++dispatches;
            const operations = checked(target[property](...arguments_));
            return {$tag: 1, _0: new Proxy(operations, {
              get(operation, name, operationReceiver) {
                if (name === 'execute') assert.fail('Nest ran synchronously');
                if (name === 'execution_stopped') return () => {
                  const stopped = operation.execution_stopped();
                  if (dispatch === 3 && cancellation.signal.aborted && stopped) sawStop = true;
                  return stopped;
                };
                if (name !== 'advance') return Reflect.get(operation, name, operationReceiver);
                return quantum => {
                  const result = operation.advance(Math.min(quantum, 1));
                  if (dispatch === 3 && !sawWork) {
                    const poll = checked(result);
                    if (!poll.complete && poll.progress > 0n) {
                      sawWork = true;
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
      // Publication tokens are owned by the exact runtime identity used by
      // the Host, including the cancellation observer's runtime wrapper.
      const runtime = runtimeCore(mode === 'cancelled' ? observedRuntime : hostRuntime);
      let owner, execution, publication;
      try {
        assert.equal(fixture.strategyFixtureOpen(prepared, capture.source()), true);
        const setup = fixture.strategyFixtureRetainedLocalSubset(prepared);
        publication = await openLocalPublicationStore({
          directory: join(directory, `publication-${mode}`),
          storeAuthorityCid: hash(`retained-nest-${mode}-store`),
          capacityBytes: 4 * 1024 * 1024,
          maxObjectBytes: publicationResultExportLimits.maxWireBytes,
          maxObjects: 100, maxContractNodes: 10000, maxContractDepth: 64,
        }, runtime.publicationControl);
        const plan = standardPublicationPlan(runtime,
          runtime.programDefinitionCid(setup), runtime.resultInventory(setup).length,
          `retained-nest-${mode}`);
        const indexKey = {
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        };
        const execute = mode === 'cancelled'
          ? createNodeHostEntry(() => observedRuntime, installStrategyContributions)
            .runPublishedCapturedStrategy : runPublishedCapturedStrategy;
        const run = async () => {
          try {
            return await execute(setup, {store: publication, plan},
              {local: configuration}, cancellation.signal);
          } catch (error) {
            execution = error.execution;
            throw error;
          }
        };
        if (mode === 'published') {
          owner = await run();
          execution = owner.execution;
          assert.equal(owner.status, 'published');
          assert.equal(execution.status, 'host-tasks-completed');
          assert.deepEqual(execution.completed.map(item => item.task), [1, 2, 3, 4, 5]);
          assert(execution.completed.every(item => item.realization === 'local' &&
            item.outputRepresentation === 'retained-file'));
          assert.equal(leases.length, 5);
          const authority = installResultAccessAuthority({
            authorizeResultReadRequest: () => true,
            admitResultRead: () => ({
              authorizationContextCid: hash('retained-nest-context'),
              dataCeilingCid: hash('retained-nest-ceiling'),
              egressAdmissionCid: hash('retained-nest-egress'),
              expiresAt: '2026-09-18T01:00:00.000Z', maxBytes: 100000, maxUses: 1,
            }),
            authorizeResultRead: () => true,
          });
          const access = installNodeResultAccessService({store: publication,
            control: runtime.publicationControl, authority,
            now: () => '2026-09-18T00:30:00.000Z',
            limits: {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64},
            frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096}});
          for (const resultName of ['producer', 'first', 'second']) {
            const delivered = [];
            await deliverAuthorizedResult(access, {indexKey, principalId: 'principal-a',
              purpose: 'download', resultName, format: 'json',
              attemptId: `retained-nest-${resultName}`}, {
              async write(bytes) {
                delivered.push(Buffer.from(bytes));
                return {confirmedBytes: bytes.byteLength};
              },
              async finish() { return {confirmed: true}; },
            }, cancellation.signal);
            assert.deepEqual(JSON.parse(Buffer.concat(delivered).toString('utf8')),
              expectedRows, resultName);
          }
          for (const [task, name] of [[3, 'producer'], [4, 'first consumer'],
            [5, 'second consumer']]) {
            assert.equal(fixture.strategyFixtureCid(prepared, task), hash(expectedRows),
              `${name} identity uses the independent expected rows`);
          }
        } else {
          await assert.rejects(run, error => {
            execution = error.execution;
            return error.code === 'CapturedRunPublicationFailed';
          });
          assert.equal(execution.status, 'host-tasks-failed');
          assert.deepEqual(execution.completed.map(item => item.task), [1, 2]);
          assert.equal(leases.length, 2, 'no partial Nest output is retained');
          if (mode === 'cancelled') {
            assert.equal(sawWork, true);
            assert.equal(sawStop, true);
            assert.equal(dispatches, 3, 'cancelled Nest never dispatches either consumer');
            assert.equal(execution.failure?.name, 'AbortError');
          } else {
            assert.equal(execution.failure?.code, 'MoonBitHostFailure');
            assert.equal(fixture.strategyFixtureRetainedNestItemLimit(
              execution.failure.cause), true);
          }
          await assert.rejects(publication.lookupCommittedIndex(indexKey, () => true),
            /PublicationLookupDenied/);
        }
      } finally {
        const dispatchesBeforeCleanup = dispatches;
        capture.close();
        await execution?.close();
        if (execution) {
          assert.equal(await execution.cleanup(), true);
          assert.equal(execution.cleanupPending(), false);
          assert.equal(execution.usage().heldBytes, 0n);
          assert.equal(execution.usage().reservedExecutionBytes, 0n);
        }
        if (mode === 'cancelled') {
          assert.equal(dispatches, dispatchesBeforeCleanup,
            'cancelled Nest cleanup never reruns Compute');
        }
        await publication?.close();
        store.close();
        assert.equal(await store.cleanup(), true);
        assert.equal(store.status().reservedBytes, 0);
        assert.equal(store.status().activeReaders, 0);
        assert.equal(store.status().cleanupPending, false);
      }
    });
  }
});
