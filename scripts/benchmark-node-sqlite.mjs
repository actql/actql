// Local comparator for the ordinary Node operation collector, not a product
// substitute. No package preparation, external service or application DB access.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, totalmem} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const digest = value => createHash('sha256').update(value).digest('hex');
const rows = value => value.map(row => Object.fromEntries(Object.entries(row)));
const plain = '[{"id":1}]';
export const sqliteQueryFixtures = Object.freeze([
  {operation: 'warm-select', sql: 'SELECT 1 AS id', parameters: [], expected: [{id: 1}]},
  {operation: 'warm-join', sql: "WITH lhs AS (SELECT 1 AS id), rhs AS (SELECT 1 AS id, 'joined' AS label) "
    + 'SELECT lhs.id AS id, rhs.label AS label FROM lhs JOIN rhs ON lhs.id = rhs.id LIMIT 1',
  parameters: [], expected: [{id: 1, label: 'joined'}]},
  {operation: 'warm-union', sql: 'WITH items AS (SELECT 2 AS id UNION ALL SELECT 1 AS id) '
    + 'SELECT id FROM items ORDER BY id', parameters: [], expected: [{id: 1}, {id: 2}]},
]);
export const sqliteBaselineProtocol = Object.freeze({
  binding: 'node:sqlite DatabaseSync', concurrency: 1,
  warmupPerSeries: 10, prepared: 'prepare outside timed samples; bind/step/all inside',
  oneShot: 'prepare/bind/step/all inside each timed sample',
  materialization: 'SQLite all rows -> ordinary plain JS records; literal oracle inside timed operation',
  readDurability: 'autocommit read; no artificial write/commit charged to a SELECT',
  durableControl: 'BEGIN IMMEDIATE; update one indexed row revision; COMMIT; read/JSON-decode saved [{id:1}]',
  durableControlScope: 'one real WAL/FULL transaction, not an implementation of authorization or durable Run/Result',
  savedRead: 'one indexed row, JSON text -> ordinary rows; no write',
  cold: 'distinct actual child per sample; existing state shared; first-init state distinct per sample',
  cache: 'OS/filesystem and executable caches not purged; process-cold is not machine-cold',
  unsupported: {'warm-decimal-sum': 'SQLite numeric affinity does not supply the exact Decimal/string oracle'},
});

async function openDatabase(file) {
  const {DatabaseSync} = await import('node:sqlite');
  const db = new DatabaseSync(file);
  try { db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA wal_autocheckpoint = 1000'); }
  catch (error) { db.close(); throw error; }
  return db;
}
function settings(db) {
  const result = {sqliteVersion: db.prepare('SELECT sqlite_version() AS version').get().version};
  for (const name of ['journal_mode', 'synchronous', 'fullfsync', 'checkpoint_fullfsync',
    'wal_autocheckpoint', 'page_size', 'cache_size', 'busy_timeout']) {
    result[name] = Object.values(db.prepare(`PRAGMA ${name}`).get())[0];
  }
  assert.equal(result.journal_mode, 'wal'); assert.equal(result.synchronous, 2);
  return result;
}
function seed(db) {
  db.exec('CREATE TABLE saved_result (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL)');
  db.prepare("INSERT INTO saved_result VALUES (1, 0, 'succeeded', ?)").run(plain);
}
async function timed(execute) {
  const cpu = process.cpuUsage(), start = process.hrtime.bigint();
  const result = await execute();
  const wallNs = Number(process.hrtime.bigint() - start), usage = process.cpuUsage(cpu);
  return {wallNs, userUs: usage.user, systemUs: usage.system, pid: process.pid, verified: true,
    outputSha256: digest(JSON.stringify(result.actual)), ...(result.phases ? {phases: result.phases} : {})};
}
export function summarizeSQLiteSamples(samples) {
  assert(samples.length > 0 && samples.every(row => row.verified === true && Number.isSafeInteger(row.wallNs) && row.wallNs >= 0));
  const sorted = samples.map(row => row.wallNs / 1e6).sort((a, b) => a - b);
  const at = fraction => sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
  return {count: sorted.length, medianMs: at(0.5), p95Ms: sorted.length >= 30 ? at(0.95) : null,
    minMs: sorted[0], maxMs: sorted.at(-1), percentileMethod: 'nearest-rank; p95 omitted below 30 samples'};
}
async function series(operation, mode, count, execute, extra = {}) {
  for (let n = 0; n < sqliteBaselineProtocol.warmupPerSeries; n++) await execute();
  const samples = [];
  for (let n = 0; n < count; n++) samples.push({index: n, ...await timed(execute)});
  return {operation, mode, ...extra, samples, summary: summarizeSQLiteSamples(samples)};
}

// Child's phase clock starts at this module body; parent wall includes launch,
// module loading, stdout drain and actual natural exit. It is never collector PID.
async function coldChild(database, initialize) {
  const phases = {}, start = process.hrtime.bigint();
  const stamp = () => Number(process.hrtime.bigint() - start);
  let mark = stamp(); const db = await openDatabase(database); phases.importAndOpenNs = stamp() - mark;
  try {
    mark = stamp(); if (initialize) seed(db); phases.schemaAndSeedNs = stamp() - mark;
    mark = stamp(); const actual = JSON.parse(db.prepare('SELECT payload FROM saved_result WHERE id = ?').get(1).payload);
    assert.deepEqual(actual, [{id: 1}]); phases.queryAndMaterializeNs = stamp() - mark;
  } finally { mark = stamp(); db.close(); phases.closeNs = stamp() - mark; }
  return {pid: process.pid, stateId: database, initialize, verified: true, phases, cpu: process.cpuUsage()};
}
async function childSample(database, initialize) {
  const start = process.hrtime.bigint();
  const child = spawn(process.execPath, [fileURLToPath(import.meta.url), '--sqlite-child', database, String(initialize)],
    {stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', bytes => { stdout += bytes; }); child.stderr.on('data', bytes => { stderr += bytes; });
  const terminal = await new Promise((yes, no) => {
    child.once('error', no); child.once('close', (code, signal) => yes({code, signal}));
  });
  const wallNs = Number(process.hrtime.bigint() - start);
  assert.equal(terminal.signal, null); assert.equal(terminal.code, 0, stderr);
  const row = JSON.parse(stdout);
  assert.equal(row.pid, child.pid); assert.equal(row.stateId, database); assert.equal(row.verified, true);
  return {...row, wallNs, userUs: row.cpu.user, systemUs: row.cpu.system, terminal, stderr};
}

export async function runSQLiteBaseline({output, warmSamples = 100, coldSamples = 5, load}) {
  assert(['isolated', 'concurrent'].includes(load), 'State actual host load explicitly');
  assert(Number.isSafeInteger(warmSamples) && warmSamples >= 1 && warmSamples <= 1000);
  assert(Number.isSafeInteger(coldSamples) && coldSamples >= 0 && coldSamples <= 30);
  output = resolve(output); await mkdir(output, {mode: 0o700}); // Never overwrite prior measured state.
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  const report = {schemaVersion: 1, kind: 'local-sqlite-comparator', environment, load, profiled: false,
    executableSha256: digest(await readFile(process.execPath)), collectorSha256: digest(await readFile(fileURLToPath(import.meta.url))),
    protocol: sqliteBaselineProtocol, protocolSha256: digest(JSON.stringify(sqliteBaselineProtocol)),
    warmSamples, coldSamples, warm: [], cold: [], cleanup: {closed: false}, productAcceptance: false,
    qualification: 'Local comparator only; no ActQL operation or semantic/durability equivalence inferred.'};
  const flags = [...process.execArgv, process.env.NODE_OPTIONS ?? ''].join(' ');
  report.profiled = /--(?:cpu-prof|heap-prof|prof|inspect|perf-basic-prof)(?:[=\s-]|$)/u.test(flags) || Boolean(process.env.NODE_V8_COVERAGE);
  const database = join(output, 'warm.sqlite'), db = await openDatabase(database);
  try {
    report.settings = settings(db); seed(db);
    for (const fixture of sqliteQueryFixtures) {
      const statement = db.prepare(fixture.sql);
      for (const mode of ['prepared', 'one-shot']) {
        const execute = () => {
          const actual = rows((mode === 'prepared' ? statement : db.prepare(fixture.sql)).all(...fixture.parameters));
          assert.deepEqual(actual, fixture.expected);
          return {actual};
        };
        report.warm.push(await series(fixture.operation, mode, warmSamples, execute,
          {fixture, fixtureSha256: digest(JSON.stringify(fixture)), data: 'literal CTE only; no tables or indexes'}));
      }
    }
    const selectSQL = 'SELECT payload FROM saved_result WHERE id = ?', select = db.prepare(selectSQL);
    const saved = () => { const actual = JSON.parse(select.get(1).payload); assert.deepEqual(actual, [{id: 1}]); return actual; };
    report.savedFixture = {schema: 'saved_result(id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL)',
      rows: 1, payload: plain, payloadBytes: Buffer.byteLength(plain), parameters: [1], sql: selectSQL,
      plan: rows(db.prepare(`EXPLAIN QUERY PLAN ${selectSQL}`).all(1))};
    report.warm.push(await series('warm-result', 'prepared', warmSamples, () => {
      return {actual: saved()};
    }));
    const status = db.prepare('SELECT status, revision FROM saved_result WHERE id = ?');
    report.warm.push(await series('warm-status', 'prepared', warmSamples, () => {
      const actual = {...status.get(1)}; assert.deepEqual(actual, {status: 'succeeded', revision: 0}); return {actual};
    }));
    const update = db.prepare('UPDATE saved_result SET revision = revision + 1 WHERE id = ?');
    report.warm.push(await series('durable-transaction-read', 'prepared', warmSamples, () => {
      const phases = {}, stamp = () => process.hrtime.bigint(); let mark = stamp();
      db.exec('BEGIN IMMEDIATE'); phases.beginNs = Number(stamp() - mark);
      try {
        mark = stamp(); assert.equal(update.run(1).changes, 1); phases.updateNs = Number(stamp() - mark);
        mark = stamp(); db.exec('COMMIT'); phases.commitNs = Number(stamp() - mark);
      } catch (error) { if (db.isTransaction) db.exec('ROLLBACK'); throw error; }
      mark = stamp(); const actual = saved(); phases.readAndMaterializeNs = Number(stamp() - mark);
      return {phases, actual};
    }));
  } finally { db.close(); report.cleanup.closed = true; }
  for (const operation of ['cold-existing', 'first-init']) {
    const samples = [];
    for (let n = 0; n < coldSamples; n++) samples.push({index: n,
      ...await childSample(operation === 'first-init' ? join(output, `init-${n}.sqlite`) : database, operation === 'first-init')});
    if (samples.length) report.cold.push({operation, samples, summary: summarizeSQLiteSamples(samples)});
  }
  report.observedAt = new Date().toISOString();
  await writeFile(join(output, 'sqlite-baseline.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] === '--sqlite-child') console.log(JSON.stringify(await coldChild(process.argv[3], process.argv[4] === 'true')));
    else {
      const args = process.argv.slice(2), options = {};
      assert.equal(args.length % 2, 0);
      for (let n = 0; n < args.length; n += 2) {
        const key = {'--output': 'output', '--warm-samples': 'warmSamples', '--cold-samples': 'coldSamples', '--load': 'load'}[args[n]];
        assert(key && !Object.hasOwn(options, key));
        options[key] = key.endsWith('Samples') ? Number(args[n + 1]) : args[n + 1];
      }
      assert(options.output); const report = await runSQLiteBaseline(options);
      console.log(JSON.stringify({warm: report.warm.map(row => ({operation: row.operation, mode: row.mode, ...row.summary})),
        cold: report.cold.map(row => ({operation: row.operation, ...row.summary})), productAcceptance: false}));
    }
  } catch (error) { console.error(error.stack); process.exitCode = 1; }
}
