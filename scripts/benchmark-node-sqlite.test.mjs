import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {resultControlKeyWidths, runSQLiteBaseline, runSQLiteResultControl, sqliteQueryFixtures, summarizeSQLiteSamples} from './benchmark-node-sqlite.mjs';

test('real SQLite comparator materializes literal rows and commits a distinct minimal control', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-sqlite-comparator-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const output = join(root, 'new');
  const report = await runSQLiteBaseline({output, warmSamples: 2, coldSamples: 0, load: 'concurrent'});
  assert.equal(report.kind, 'local-sqlite-comparator'); assert.equal(report.productAcceptance, false);
  assert.equal(report.cleanup.closed, true); assert.equal(report.settings.synchronous, 2);
  assert.equal(report.settings.journal_mode, 'wal'); assert.equal(report.warm.length, 13);
  assert.equal(sqliteQueryFixtures.length, 5);
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

const resultMapping = () => ({source: {commit: 'a'.repeat(40)}, groups: ['clock', 'start', 'end'].map(id => ({id})),
  minimalRowModel: {logicalKeyFields: Object.keys(resultControlKeyWidths), bytesObserved: {
    grant: 1009, attempt: 740, streaming: 374, receipt: 963, terminalSucceeded: 657,
    totalCanonicalBusinessBytes: 3743, clock: 217, outputJsonlBytes: 9}}});

test('Result SQLite control commits clock/start/end in order with full-key quota and head CAS', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-result-sqlite-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const mappingPath = join(root, 'owner.json'); await writeFile(mappingPath, JSON.stringify(resultMapping()));
  const output = join(root, 'new');
  const report = await runSQLiteResultControl({output, resultOwnerMap: mappingPath, warmSamples: 2, warmup: 1, load: 'concurrent'});
  assert.equal(report.cleanup.closed, true); assert.equal(report.productAcceptance, false);
  assert.equal(report.kind, 'local-sqlite-result-control'); assert.equal(report.samples.length, 2);
  assert.equal(report.schemaVersion, 2);
  const stored = '[{"id":1}]', schema = '{"id":{"nullable":false,"type":"number"}}', jsonl = '{"id":1}\n';
  const sha256 = text => createHash('sha256').update(text).digest('hex');
  assert.equal(report.protocol.payload, jsonl);
  assert.deepEqual(report.protocol.materialization, {
    storedFormat: 'json-array-utf8', storedBytes: 10, storedSha256: sha256(stored),
    schemaFormat: 'actql-schema-json-utf8', schemaBytes: 41, schemaSha256: sha256(schema),
    outputFormat: 'jsonl-utf8', outputBytes: 9, outputSha256: sha256(jsonl),
    conversion: 'stored-array-and-schema -> JSONL -> ordinary-JS-records',
  });
  assert.equal(report.summary.p95Ms, null); assert.equal(report.settings.synchronous, 2);
  for (const row of report.samples) {
    assert.deepEqual(row.events, ['clock-committed', 'start-committed', 'stored-array-decoded',
      'jsonl-serialized', 'payload-materialized', 'end-committed']);
    assert.deepEqual(row.counts, {begins: 3, commits: 3, rollbacks: 0, reads: 3, writes: 8});
    assert.deepEqual(row.materialization, {storedBytes: 10, schemaBytes: 41, jsonlBytes: 9,
      decodedRows: 1, outputSha256: sha256(jsonl)});
    assert(row.phases.clock.commitNs > 0 && row.phases.start.commitNs > 0 && row.phases.end.commitNs > 0);
  }
  assert(report.indexPlans.every(row => !row.detail.includes('SCAN attempt')));
  const {DatabaseSync} = await import('node:sqlite'), db = new DatabaseSync(join(output, 'result-control.sqlite'));
  try {
    assert.equal(db.prepare('SELECT floor FROM clock').get().floor, 3);
    assert.equal(db.prepare('SELECT count(*) AS n FROM attempt').get().n, 3);
    assert.equal(db.prepare('SELECT count(*) AS n FROM receipt').get().n, 3);
    assert.equal(db.prepare('SELECT count(*) AS n FROM record').get().n, 6);
    const quota = db.prepare('SELECT cid FROM grant_use LIMIT 1').get().cid;
    assert.equal(db.prepare('UPDATE grant_use SET uses=uses+1 WHERE cid=? AND uses<max_uses').run(quota).changes, 0);
    const attempt = db.prepare('SELECT cid,head FROM attempt LIMIT 1').get();
    assert.equal(db.prepare('UPDATE attempt SET head=? WHERE cid=? AND head=?').run('foreign', attempt.cid, 'stale').changes, 0);
    assert.equal(db.prepare('SELECT head FROM attempt WHERE cid=?').get(attempt.cid).head, attempt.head);
    assert.equal(db.prepare('SELECT length(CAST(body AS BLOB)) AS n FROM clock').get().n, 217);
    assert.deepEqual({...db.prepare('SELECT wire,schema FROM payload').get()}, {wire: stored, schema});
    const width = db.prepare('SELECT namespace,scope,run,principal,purpose,result,attempt_id FROM attempt LIMIT 1').get();
    assert.deepEqual(Object.values(width).map(value => Buffer.byteLength(value)), Object.values(resultControlKeyWidths));
  } finally { db.close(); }
});

test('Result SQLite control refuses a missing durable group or mismatched payload before opening state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-result-map-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const resultOwnerMap = join(root, 'owner.json');
  const missing = resultMapping(); missing.groups.pop(); await writeFile(resultOwnerMap, JSON.stringify(missing));
  const options = {output: join(root, 'never-opened'), resultOwnerMap, warmSamples: 1, warmup: 0, load: 'concurrent'};
  await assert.rejects(runSQLiteResultControl(options));
  const wrong = resultMapping(); wrong.minimalRowModel.bytesObserved.outputJsonlBytes = 10;
  await writeFile(resultOwnerMap, JSON.stringify(wrong)); await assert.rejects(runSQLiteResultControl(options));
  await assert.rejects(readFile(join(options.output, 'result-control.sqlite')), {code: 'ENOENT'});
});

test('SQLite full-sync mode reaches warm, Result and actual process-cold connections', {skip: process.platform !== 'darwin'}, async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-full-sync-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const common = {warmSamples: 1, load: 'concurrent', fullfsync: true};
  const baseline = await runSQLiteBaseline({...common, output: join(root, 'baseline'), coldSamples: 1});
  assert.equal(baseline.protocol.fullfsyncRequested, true);
  assert.equal(baseline.settings.fullfsync, 1);
  const cold = baseline.cold.flatMap(row => row.samples);
  assert.equal(cold.length, 2);
  assert.equal(new Set(cold.map(row => row.pid)).size, 2);
  assert(cold.every(row => row.pid !== process.pid && row.settings.fullfsync === 1 && row.terminal.code === 0));
  const resultOwnerMap = join(root, 'owner.json'); await writeFile(resultOwnerMap, JSON.stringify(resultMapping()));
  const control = await runSQLiteResultControl({...common, resultOwnerMap, output: join(root, 'result'), warmup: 0});
  assert.equal(control.protocol.fullfsyncRequested, true); assert.equal(control.settings.fullfsync, 1);
  assert.deepEqual(control.samples[0].counts, {begins: 3, commits: 3, rollbacks: 0, reads: 3, writes: 8});
  assert.equal(control.cleanup.closed, true); assert.equal(baseline.cleanup.closed, true);
  await assert.rejects(runSQLiteBaseline({...common, output: join(root, 'invalid'), fullfsync: 'on'}), /explicitly boolean/u);
  await assert.rejects(readFile(join(root, 'invalid', 'warm.sqlite')), {code: 'ENOENT'});
});
