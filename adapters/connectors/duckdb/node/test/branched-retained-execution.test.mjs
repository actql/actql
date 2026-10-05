import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {inspect, promisify} from 'node:util';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';
import {authorizeLocalDatabase} from '../session.mjs';
import {runNativeHostQuery} from '../host.mjs';
import {runCapturedInternalStrategy} from '../../../../host-node/entry.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {installLocalRetainedStore} from
  '../../../../local-node/retained-store.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const queryLimits = {
  maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
};

test('retained Relation forks execute bounded ranking and row transforms',
  async t => {
    await promisify(execFile)('moon', [
      'build', '--target', 'js', '--release',
      'src/connectors/duckdb/conformance',
      'src/connectors/duckdb/host_node',
      'src/connectors_builtin_node',
    ], {cwd: root});
    const fixture = await import(pathToFileURL(join(root,
      '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
    const catalogs = await readFile(join(root,
      'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
    const catalog = catalogs.slice(catalogs.indexOf(
      'fn query_amount_nullable_catalog'))
      .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
    assert(catalog);
    const args = [JSON.parse(catalog[1]), catalog[2],
      ...await pinnedEngineContracts(root),
      await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'),
        'utf8'),
      await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'),
        'utf8'),
      await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'),
        'utf8')];
    const base = {
      version: 'actql/0.1', id: 'p',
      params: {minimum: {type: 'number', nullable: false}},
      stages: [
        {id: 'a', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
          steps: [{filter: 'id > $minimum', as: 'filtered'},
            {select: ['id'], as: 'captured'}],
          results: {r: {from: 'captured', fields: ['id']}}},
        ...['l', 'r'].map((id, index) => ({
          id, inputs: {}, steps: [{values: {
            schema: {id: {type: 'number', nullable: false},
              origin: {type: 'string', nullable: false}},
            rows: (index === 0 ? [1, 2] : [2, 3, 4]).map(value =>
              ({id: value, origin: id})),
          }, as: 'out'}],
          results: {r: {from: 'out', fields: ['id', 'origin']}},
        })),
        {id: 'crossed', inputs: {
          l: {result: {stage: 'l', result: 'r'}},
          r: {result: {stage: 'r', result: 'r'}},
        }, steps: [], results: {r: {from: 'out', fields: ['id']}}},
        {id: 'consumer', inputs: {
          x: {result: {stage: 'crossed', result: 'r'}},
        }, steps: [{select: ['id'], as: 'out'}],
        results: {r: {from: 'out', fields: ['id']}}},
      ],
      results: {source: {from: {stage: 'a', result: 'r'}},
        producer: {from: {stage: 'crossed', result: 'r'}},
        consumer: {from: {stage: 'consumer', result: 'r'}}},
    };
    const directory = await mkdtemp(join(tmpdir(), 'actql-ranked-fork-'));
    t.after(async () => rm(directory, {recursive: true, force: true}));
    const database = join(directory, 'source.duckdb');
    const db = await DuckDBInstance.create(database);
    const connection = await db.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      await connection.run('INSERT INTO records VALUES (1,10)');
    } finally {
      connection.closeSync();
      db.closeSync();
    }
    const grant = await authorizeLocalDatabase(database, fixtureSourceAccess);
    for (const [name, ranked, deduped] of [
      ['top-k', true, false],
      ['dedupe', false, true],
      ['combined', true, true],
      ['lag', false, false],
      ['watermark', false, false],
      ['json-pick', false, false],
      ['row-window', false, false],
      ['unpivot', false, false],
      ['unnest', false, false],
    ]) {
      const program = structuredClone(base);
      if (['watermark', 'json-pick', 'unpivot', 'unnest'].includes(name)) {
        for (const stage of program.stages.slice(1, 3)) {
          if (name === 'watermark') {
            stage.steps[0].values.schema.time = {
              type: 'number', nullable: false,
            };
            stage.steps[0].values.rows = stage.steps[0].values.rows.map(row =>
              ({...row, time: row.id === 2 ? 80 : 100}));
            stage.results.r.fields = ['id', 'origin', 'time'];
          } else if (name === 'json-pick') {
            stage.steps[0].values.schema.payload = {
              type: 'object', nullable: false, fields: {
                inner: {type: 'object', nullable: false, fields: {
                  leaf: {type: 'number', nullable: false},
                }},
              },
            };
            stage.steps[0].values.rows = stage.steps[0].values.rows.map(row =>
              ({...row, payload: {inner: {leaf: row.id}}}));
            stage.results.r.fields = ['id', 'origin', 'payload'];
          } else if (name === 'unpivot') {
            stage.steps[0].values.schema.amount = {
              type: 'number', nullable: false,
            };
            stage.steps[0].values.rows = stage.steps[0].values.rows.map(row =>
              ({...row, amount: row.id * 10}));
            stage.results.r.fields = ['id', 'origin', 'amount'];
          } else {
            stage.steps[0].values.schema.items = {
              type: 'array', nullable: false,
              items: {type: 'number', nullable: false}, max_items: 2,
            };
            stage.steps[0].values.rows = stage.steps[0].values.rows.map(row =>
              ({...row, items: [row.id, row.id + 1]}));
            stage.results.r.fields = ['id', 'origin', 'items'];
          }
        }
      }
      if (name === 'lag') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', assert_rows: {unique_by: ['id', 'origin']},
            as: 'unique'},
          {from: 'unique', lag: {partition_by: [],
            order_by: [{id: 'asc'}, {origin: 'asc'}], field: 'id',
            output: 'previous', offset: 1}, as: 'lagged'},
          {from: 'lagged', filter: 'previous >= 3', as: 'lag_filtered'},
          {from: 'lag_filtered', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else if (name === 'watermark') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', watermark_rows: {time: 'time',
            late_policy: 'mark', watermark_ms: 90}, as: 'marked'},
          {from: 'marked', filter: 'watermark_late = true', as: 'late_rows'},
          {from: 'late_rows', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else if (name === 'json-pick') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', json_pick: {column: 'payload',
            path: ['inner', 'leaf'], output: 'picked'}, as: 'picked'},
          {from: 'picked', filter: 'picked >= 3', as: 'picked_rows'},
          {from: 'picked_rows', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else if (name === 'row-window') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', row_window: {
            kind: 'fixed', time: 'id', size: 2,
          }, as: 'windowed'},
          {from: 'windowed', filter: 'window_start >= 2', as: 'later'},
          {from: 'later', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else if (name === 'unpivot') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', unpivot: {
            columns: ['amount'], keep: ['id'], name_column: 'metric',
            value_column: 'value',
          }, as: 'expanded'},
          {from: 'expanded', filter: 'value >= 30', as: 'greater'},
          {from: 'greater', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else if (name === 'unnest') {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', unnest: {
            column: 'items', as: 'item', outer: false,
          }, as: 'expanded'},
          {from: 'expanded', filter: 'item >= 4', as: 'greater'},
          {from: 'greater', select: ['id'], as: 'selected'},
          {from: 'appended', select: ['id'], as: 'raw_ids'},
          {from: 'selected', append: {with: 'raw_ids'}, as: 'out'},
        ];
      } else {
        program.stages[3].steps = [
          {from: 'l', append: {with: 'r'}, as: 'appended'},
          {from: 'appended', filter: 'id > 2', as: 'greater'},
          {from: 'appended', filter: 'id < 3', as: 'less'},
          {from: 'greater', assert_rows: {unique_by: ['id']},
            as: 'unique_greater'},
          ranked ? {from: 'unique_greater', top_k: {k: 2, by: [{id: 'desc'}]},
            as: 'ranked'} : {from: 'unique_greater', sort: [{id: 'desc'}],
            as: 'ranked'},
          deduped ? {from: 'less', dedupe_rows: {
            by: ['id'], order_by: [{origin: 'asc'}],
          }, as: 'deduped'} : {from: 'less', distinct: true, as: 'deduped'},
          {from: 'ranked', append: {with: 'deduped'}, as: 'joined'},
          {from: 'joined', select: ['id'], as: 'out'},
        ];
      }
      const prepared = fixture.strategyFixtureCreate(
        ...args, JSON.stringify(program));
      const capture = await runNativeHostQuery(grant,
        fixture.strategyFixtureAcquisition(prepared), queryLimits);
      let execution;
      try {
        assert.equal(fixture.strategyFixtureOpen(prepared, capture.source()),
          true, name);
        const setup = fixture.strategyFixtureModuleSubset(prepared, 0);
        execution = await runCapturedInternalStrategy(setup, {
          duckdb: new Proxy({}, {get() { assert.fail('unused DuckDB'); }}),
        });
        assert.equal(execution.status, 'host-tasks-completed',
          `${name}: ${inspect(execution.failure?.cause ?? execution.failure,
            {depth: 8})}`);
      } finally {
        await execution?.close();
        capture.close();
        if (execution) {
          assert.equal(await execution.cleanup(), true);
          assert.equal(execution.usage().heldBytes, 0n);
          assert.equal(execution.usage().reservedExecutionBytes, 0n);
        }
      }
      if (name === 'combined' || name === 'lag' ||
          name === 'watermark' || name === 'json-pick' ||
          name === 'row-window' || name === 'unpivot' || name === 'unnest') {
        const retained = fixture.strategyFixtureCreate(
          ...args, JSON.stringify(program));
        const retainedCapture = await runNativeHostQuery(grant,
          fixture.strategyFixtureAcquisition(retained), queryLimits);
        const store = await createLocalRetainedStore({
          parentDirectory: directory,
          capacityBytes: 8 * 1024 * 1024,
          maxFrameBytes: 1024 * 1024,
        });
        const configuration = installLocalRetainedStore((_key, bytes) => {
          let writer;
          let closed = false;
          return Object.freeze({
            status: () => ({reservedBytes: writer && !closed ? bytes : 0,
              cleanupPending: false}),
            reserve: value => (writer = store.reserve(value)),
            close() { closed = true; writer?.cancel(); },
            async cleanup() { await writer?.cleanupHandle?.retry?.(); },
          });
        });
        let retainedExecution;
        try {
          assert.equal(fixture.strategyFixtureOpen(retained,
            retainedCapture.source()), true);
          retainedExecution = await runCapturedInternalStrategy(
            fixture.strategyFixtureRetainedLocalSubset(retained),
            {local: configuration});
          assert.equal(retainedExecution.status, 'host-tasks-completed',
            inspect(retainedExecution.failure?.cause, {depth: 8}));
          assert.deepEqual(retainedExecution.completed.map(item => item.task),
            [1, 2, 3, 4]);
          assert(retainedExecution.completed.every(item =>
            item.outputRepresentation === 'retained-file'));
          assert.equal(fixture.strategyFixtureCid(retained, 3),
            fixture.strategyFixtureCid(retained, 4));
        } finally {
          retainedCapture.close();
          await retainedExecution?.close();
          if (retainedExecution) {
            assert.equal(await retainedExecution.cleanup(), true);
            assert.equal(retainedExecution.usage().heldBytes, 0n);
            assert.equal(retainedExecution.usage().reservedExecutionBytes, 0n);
          }
          store.close();
          await store.cleanup();
        }
      }
    }
  });
