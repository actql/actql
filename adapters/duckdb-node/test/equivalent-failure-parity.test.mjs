import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from
  '../../../benchmarks/retained-results/fixtures.mjs';
import {runEquivalentObligations} from
  '../bench/equivalent-obligations.mjs';
import {runRetainedComparator} from '../bench/retained-comparator.mjs';

const root = new URL('../../../', import.meta.url);
const run = promisify(execFile);
const text = path => readFile(new URL(path, root), 'utf8');
let contracts;

test.before(async () => {
  for (const target of [
    'benchmark_obligations',
    'connectors/duckdb/host_node',
    'retained_host_bridge',
    'process_host_bridge',
    'connectors_builtin_node',
    'physical_strategy_example',
  ]) {
    await run('moon', ['build', '--target', 'js', '--release', `src/${target}`], {
      cwd: fileURLToPath(root),
    });
  }
  contracts = {
    adoptedText: await text(
      'adapters/duckdb-node/contracts/adopted-relation.json',
    ),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text(
      'spec/contracts/actql-query-process-evidence.json',
    ),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
});

async function source(directory, fixture) {
  const database = join(directory, 'source.duckdb');
  await run(process.execPath, [
    fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
    database,
    fixture.workload,
    fixture.layout,
    String(fixture.rows),
  ]);
  return database;
}

async function update(database, sql) {
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run(sql);
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
}

async function assertOnlySourceRemains(directory) {
  assert.deepEqual(await readdir(directory), ['source.duckdb']);
}

test('both legs validate excluded source values before filtering', async () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const directory = await mkdtemp(join(tmpdir(), 'actql-failure-parity-'));
  try {
    const database = await source(directory, fixture);
    await update(database,
      "UPDATE records SET payload = 'Infinity'::DOUBLE WHERE id = 0");
    await assert.rejects(
      runEquivalentObligations(fixture, database, directory),
      error => error.code === 'MoonBitHostFailure',
    );
    await assertOnlySourceRemains(directory);
    await assert.rejects(
      runRetainedComparator(fixture, contracts, database, directory),
      error => error.code === 'ExecutionFailed' &&
        error.cause?.code === 'MoonBitHostFailure',
    );
    await assertOnlySourceRemains(directory);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test('both legs reject join expansion before the final count', async () => {
  const fixture = retainedCase(workloads[1], 'narrow', 100);
  const directory = await mkdtemp(join(tmpdir(), 'actql-failure-parity-'));
  try {
    const database = await source(directory, fixture);
    await update(database, 'UPDATE records SET id = 0');
    await assert.rejects(
      runEquivalentObligations(fixture, database, directory),
      /join output guard/,
    );
    await assertOnlySourceRemains(directory);
    await assert.rejects(
      runRetainedComparator(fixture, contracts, database, directory),
      error => error.code === 'ERR_ASSERTION' &&
        error.message.includes('"failure":"Rows"'),
    );
    await assertOnlySourceRemains(directory);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

