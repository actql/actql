import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runSQLiteBaseline, sqliteQueryFixtures, summarizeSQLiteSamples} from './benchmark-node-sqlite.mjs';

test('real SQLite comparator materializes literal rows and commits a distinct minimal control', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-sqlite-comparator-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const output = join(root, 'new');
  const report = await runSQLiteBaseline({output, warmSamples: 2, coldSamples: 0, load: 'concurrent'});
  assert.equal(report.kind, 'local-sqlite-comparator'); assert.equal(report.productAcceptance, false);
  assert.equal(report.cleanup.closed, true); assert.equal(report.settings.synchronous, 2);
  assert.equal(report.settings.journal_mode, 'wal'); assert.equal(report.warm.length, 9);
  assert.equal(sqliteQueryFixtures.length, 3);
  for (const fixture of sqliteQueryFixtures) for (const mode of ['prepared', 'one-shot']) {
    const series = report.warm.find(row => row.operation === fixture.operation && row.mode === mode);
    assert.deepEqual(series.fixture, fixture); assert.equal(series.samples.length, 2);
    assert(series.samples.every(row => row.verified && /^[a-f0-9]{64}$/u.test(row.outputSha256)));
  }
  const durable = report.warm.find(row => row.operation === 'durable-transaction-read');
  assert(durable.samples.every(row => row.phases.commitNs > 0));
  const {DatabaseSync} = await import('node:sqlite'), db = new DatabaseSync(join(output, 'warm.sqlite'));
  try { assert.equal(db.prepare('SELECT revision FROM saved_result WHERE id=1').get().revision, 12); }
  finally { db.close(); }
  assert.deepEqual(JSON.parse(await readFile(join(output, 'sqlite-baseline.json'))), report);
  await assert.rejects(runSQLiteBaseline({output, warmSamples: 1, coldSamples: 0, load: 'concurrent'}), /EEXIST/u);
});

test('SQLite process-cold rows bind actual distinct child PIDs and new init states', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-sqlite-process-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const report = await runSQLiteBaseline({output: join(root, 'new'), warmSamples: 1, coldSamples: 2, load: 'concurrent'});
  const cold = report.cold.find(row => row.operation === 'cold-existing'), init = report.cold.find(row => row.operation === 'first-init');
  const all = [...cold.samples, ...init.samples];
  assert.equal(new Set(all.map(row => row.pid)).size, 4);
  assert(all.every(row => row.pid !== process.pid && row.terminal.code === 0 && row.terminal.signal === null));
  assert.equal(new Set(cold.samples.map(row => row.stateId)).size, 1);
  assert.equal(new Set(init.samples.map(row => row.stateId)).size, 2);
  assert(init.samples.every(row => row.phases.schemaAndSeedNs > 0 && row.phases.closeNs > 0));
  assert(cold.samples.every(row => row.phases.closeNs > 0 && row.wallNs > row.phases.queryAndMaterializeNs));
  assert.equal(cold.summary.p95Ms, null); assert.equal(init.summary.p95Ms, null);
});

test('SQLite summary retains insufficient percentile coverage and rejects malformed samples', () => {
  const samples = Array.from({length: 30}, (_, n) => ({wallNs: (n + 1) * 1000000, verified: true}));
  assert.deepEqual({...summarizeSQLiteSamples(samples), percentileMethod: undefined},
    {count: 30, medianMs: 15, p95Ms: 29, minMs: 1, maxMs: 30, percentileMethod: undefined});
  assert.equal(summarizeSQLiteSamples(samples.slice(0, 3)).p95Ms, null);
  assert.throws(() => summarizeSQLiteSamples([]));
  assert.throws(() => summarizeSQLiteSamples([{wallNs: -1, verified: true}]));
});
