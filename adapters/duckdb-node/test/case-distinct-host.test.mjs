import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify, inspect } from 'node:util';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeHostQuery } from '../host.mjs';
import { runCapturedStrategy } from '../../host-node/entry.mjs';
import { prepareDuckDBStrategyConfiguration } from '../configuration.mjs';
import { canonical, hash, typedCatalog } from './typed-catalog.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
// Authored values/order, not expectations obtained from either execution engine.
const cases = [
  ['text', 'VARCHAR', { type: 'string' }, "chr(57344)", "chr(65536)", '\ue000', '\u{10000}'],
  ['boolean', 'BOOLEAN', { type: 'boolean' }, 'TRUE', 'FALSE', true, false],
  ['integer', 'BIGINT', { type: 'number' }, '9007199254740992', '-2', 9007199254740992, -2],
  ['number', 'DOUBLE', { type: 'number' }, '1.5', '-1.5', 1.5, -1.5],
  ['decimal', 'DECIMAL(38,2)', { type: 'decimal', precision: 38, scale: 2 },
    "'999999999999999999999999999999999999.99'", "'-1.00'",
    '999999999999999999999999999999999999.99', '-1.00'],
  ['date', 'DATE', { type: 'date' }, "DATE '9999-12-31'", "DATE '0001-01-01 (BC)'", '9999-12-31', '0000-01-01'],
  ['timestamp', 'TIMESTAMPTZ', { type: 'timestamp' },
    "TIMESTAMPTZ '9999-12-31 23:59:59.999+00'", "TIMESTAMPTZ '1969-12-31 23:59:59.999+00'",
    '9999-12-31T23:59:59.999Z', '1969-12-31T23:59:59.999Z'],
];

test('case-distinct names preserve group order and exclude lossy resident storage', async () => {
  const exec = promisify(execFile);
  for (const name of ['connectors/duckdb/host_node', 'connectors_builtin_node',
    'connectors/duckdb/conformance']) {
    await exec('moon', ['build', '--target', 'js', '--release', `src/${name}`], { cwd: root });
  }
  const moon = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
  const source = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const match = source.split('fn query_amount_nullable_catalog')[1].match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")/);
  const seed = JSON.parse(JSON.parse(match[1]));
  const contracts = await pinnedEngineContracts(root);
  const shared = await Promise.all(['actql-query-acquisition.json', 'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
    .map(name => readFile(join(root, 'spec/contracts', name), 'utf8')));
  const output = fields => ({ r: { from: 'out', fields } });
  const branch = id => ({ id, inputs: { x: { result: { stage: 'acquire', result: 'r' } } },
    steps: [{ filter: 'id > 0' }, { select: ['id', 'amount'], as: 'out' }], results: output(['id', 'amount']) });
  for (const [key, aggregate, collision] of [['K', 'k', false], ['k', 'K', false], ['K', 'k', true]]) {
  const program = JSON.stringify({ version: 'actql/0.1', id: 'typed-resident',
    params: { minimum: { type: 'number', nullable: false } }, stages: [
      { id: 'acquire', inputs: { remote: { connector: 'crm/main', resource: 'r' } },
        steps: [{ filter: 'id > $minimum' }, { select: ['id', 'amount'], as: 'out' }], results: output(['id', 'amount']) },
      branch('a'), branch('b'),
      { id: 'joined', inputs: { l: { result: { stage: 'a', result: 'r' } }, r: { result: { stage: 'b', result: 'r' } } },
        steps: [{ from: 'l', join: { with: 'r', kind: 'inner',
          on: [{ left: 'amount', right: 'amount' }, { left: 'id', right: 'id' }],
          select: collision ? { K: 'left.amount', k: 'right.amount' } : { [key]: 'left.amount' } }, as: 'out' }], results: output(collision ? ['K', 'k'] : [key]) },
      { id: 'counted', inputs: { x: { result: { stage: 'joined', result: 'r' } } },
        steps: [{ group: { by: [key], aggregates: { [aggregate]: { fn: 'count' } } }, as: 'out' }],
        results: output([key, aggregate]) },
    ], results: { out: { from: { stage: 'counted', result: 'r' } } } });
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'typed-resident-join-'));
  try {
    for (const [name, sqlType, type, highSql, lowSql, high, low] of cases.filter(c => ['number', 'text'].includes(c[0]))) {
      const environment = typedCatalog(seed, { ...type, nullable: true });
      const path = join(directory, `${name}.duckdb`);
      const write = async reset => {
        const db = await DuckDBInstance.create(path);
        const connection = await db.connect();
        try {
          if (!reset) await connection.run(`CREATE TABLE records(id DOUBLE, amount ${sqlType})`);
          await connection.run('DELETE FROM records');
          if (reset !== 'empty') await connection.run(`INSERT INTO records VALUES (3,${lowSql}),(3,NULL),(3,${highSql}),(3,${lowSql})`);
        } finally { connection.closeSync(); db.closeSync(); }
      };
      await write(false);
      const grant = await authorizeLocalDatabase(path);
      for (const placement of ['local', 'duckdb', 'resident']) {
        await write(true);
        const f = moon.strategyFixtureJoinCreate(canonical(environment), environment.evidence_bundle_cid, ...contracts, ...shared, program);
        const capture = await runNativeHostQuery(grant, moon.strategyFixtureAcquisition(f), limits);
        let execution;
        try {
          assert.equal(moon.strategyFixtureOpen(f, capture.source()), true);
          await write('empty'); // Neither branch may reread the source.
          const dispatch = placement === 'resident' ? moon.strategyFixtureResidentDispatch(f)
            : moon.strategyFixtureCostedDispatch(f, placement === 'local' ? 20n : 1n);
          execution = await runCapturedStrategy(dispatch, {duckdb: prepareDuckDBStrategyConfiguration({transportLimits: limits, importLimits: { maxRows: 100, maxCells: 1000 }})});
          const expected = hash([{[key]: low,[aggregate]:4},{[key]:high,[aggregate]:1}]);
          const actual = moon.strategyFixtureCid(f,4);
          assert.equal(execution.status, 'host-tasks-completed', `${name}/${placement}/${key}/${collision}: ${inspect(execution.failure, { depth: 10 })}`);
          assert.equal(actual, expected, name + '/' + placement + '/' + key);
          if (placement === 'resident') {
            assert.notEqual(execution.completed[3].realization, 'duckdb-resident');
            if (collision) assert.notEqual(execution.completed[2].realization, 'duckdb-resident');
          }
          if (collision) assert.equal(execution.completed[3].realization, 'local');
          capture.close();
          for (const task of [1, 2, 3]) moon.strategyFixtureCloseOutput(f, task);
          assert.equal(moon.strategyFixtureCid(f, 4), expected);
          assert.equal(moon.strategyFixtureConsume(f, 4, JSON.stringify([{select: [key, aggregate]}])), expected);
          if (placement === 'resident') {
            assert(JSON.stringify(execution.explain()).includes('unsupported_resident_output_names'));
          }
        } finally { execution?.close(); capture.close(); }
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
        assert.equal(execution.cleanupPending(), false);
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
  }
});
