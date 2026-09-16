import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readdir, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from '../../../benchmarks/retained-results/fixtures.mjs';
import {runEquivalentObligations} from '../bench/equivalent-obligations.mjs';

test('comparator assembly cannot import product Host or strategy wiring', async () => {
  const source = await readFile(new URL('../bench/equivalent-obligations.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /createManagedExampleHost|runCapturedStrategy|physical_strategy_example|runRetainedComparator/);
  const manifest = await readFile(new URL('../../../src/benchmark_obligations/moon.pkg', import.meta.url), 'utf8');
  const imports = [...manifest.matchAll(/"actql\/actql\/([^"]+)"/g)].map(match => match[1]);
  assert.deepEqual(imports.sort(), ['connectors/duckdb/adapter', 'encode_core', 'execution_relation',
    'relation_schema', 'value_admission', 'value_contract']);
});

test('independent assembly validates hashes and holds every named boundary without product Host', async () => {
  const root = new URL('../../../', import.meta.url);
  await promisify(execFile)('moon', ['build', 'src/benchmark_obligations', '--target', 'js', '--release'], {cwd: root});
  const directory = await mkdtemp(join(tmpdir(), 'actql-equivalent-'));
  try {
    for (const [i, workload] of workloads.entries()) for (const layout of ['narrow', 'numeric-64', 'text-1024']) {
      const fixture = retainedCase(workload, layout, 100);
      const database = join(directory, `source-${i}-${layout}.duckdb`);
      await promisify(execFile)(process.execPath, [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
        database, workload, layout, '100']);
      const result = await runEquivalentObligations(fixture, database, directory);
      assert.equal(result.validationRows, 100);
      assert.equal(result.stages.at(-1).cid, fixture.identity().rowsCid);
      assert.equal(result.stages.length, workload === workloads[1] ? 5 : 4);
      for (const stage of result.stages) {
        if (['capture', 'a', 'b', 'c'].includes(stage.stage)) {
          assert.equal(stage.comparisonDemand.true_rows, stage.rows);
          assert.equal(stage.comparisonDemand.rows,
            stage.stage === 'capture' ? fixture.rows : fixture.cardinalities.capture);
        }
      }
      assert.equal(result.acceptanceEligible, false);
      assert(result.missing.length > 0);
      assert.equal(result.capacity.independentRetention.limitBytes, 1073741824);
      assert.equal(result.capacity.independentRetention.fileReservedBytes, result.holding.reservedBytes);
      assert.equal(result.capacity.execution.limitBytes, fixture.limits.executionMemoryBytes);
      assert.equal(result.capacity.conformance, 'incomplete');
      assert((await readdir(directory)).every(name => /^source-\d-[a-z0-9-]+.duckdb$/.test(name)));
      if (i === 0 && layout === 'narrow') {
        // Row zero is excluded by the acquisition predicate, but full scan
        // validation must still reject its invalid known field.
        const db = await DuckDBInstance.create(database);
        const connection = await db.connect();
        try { await connection.run("UPDATE records SET payload = 'Infinity'::DOUBLE WHERE id = 0"); }
        finally { connection.closeSync(); db.closeSync(); }
        await assert.rejects(runEquivalentObligations(fixture, database, directory));
        const signal = AbortSignal.abort(Error('cancel before start'));
        await assert.rejects(runEquivalentObligations(fixture, database, directory, signal), /cancel before start/);
        assert((await readdir(directory)).every(name => name.endsWith('.duckdb')));
      }
    }
    // Observe a real second output writer, not an elapsed-time assumption:
    // source validation and the first independently held result already exist.
    const fixture = retainedCase(workloads[2], 'narrow', 10000);
    const database = join(directory, 'cancel-source.duckdb');
    await promisify(execFile)(process.execPath, [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)),
      database, fixture.workload, fixture.layout, String(fixture.rows)]);
    const controller = new AbortController();
    let finished = false, observedWriter = false;
    const outcome = runEquivalentObligations(fixture, database, directory, controller.signal)
      .then(value => ({value}), error => ({error})).finally(() => { finished = true; });
    while (!finished) {
      const stores = (await readdir(directory)).filter(name => name.startsWith('actql-retained-'));
      for (const name of stores) {
        const files = await readdir(join(directory, name)).catch(error => {
          if (error.code === 'ENOENT') return [];
          throw error;
        });
        if (files.includes('body-1')) {
          observedWriter = true;
          controller.abort(Error('cancel during second output'));
          break;
        }
      }
      await delay(1);
    }
    const result = await outcome;
    assert.equal(observedWriter, true, 'must cancel actual in-flight output');
    assert(result.error, 'cancelled run must not return a timing sample');
    assert((await readdir(directory)).every(name => name.endsWith('.duckdb')),
      'cancelled partial and completed holdings must be reclaimed on run teardown');
  } finally { await rm(directory, {recursive: true, force: true}); }
});
