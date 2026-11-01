// Local comparator for the ordinary Node operation collector, not a product
// substitute. No package preparation, external service or application DB access.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
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
  {operation: 'warm-parameters', sql: 'SELECT ? AS id', parameters: [7], expected: [{id: 7}]},
  {operation: 'warm-unicode', sql: "SELECT 'é😀' AS label", parameters: [], expected: [{label: 'é😀'}]},
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

function checkFullfsync(fullfsync) {
  assert.equal(typeof fullfsync, 'boolean', 'fullfsync must be explicitly boolean');
  assert(!fullfsync || platform() === 'darwin', 'F_FULLFSYNC comparison requires Darwin');
}
async function openDatabase(file, fullfsync = false) {
  checkFullfsync(fullfsync);
  const {DatabaseSync} = await import('node:sqlite');
  const db = new DatabaseSync(file);
  try {
    db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA wal_autocheckpoint = 1000');
    db.exec(`PRAGMA fullfsync = ${fullfsync ? 'ON' : 'OFF'}`);
    assert.equal(Object.values(db.prepare('PRAGMA fullfsync').get())[0], Number(fullfsync));
  }
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
async function coldChild(database, initialize, fullfsync) {
  const phases = {}, start = process.hrtime.bigint();
  const stamp = () => Number(process.hrtime.bigint() - start);
  let mark = stamp(); const db = await openDatabase(database, fullfsync); phases.importAndOpenNs = stamp() - mark;
  let actualSettings;
  try {
    actualSettings = settings(db);
    mark = stamp(); if (initialize) seed(db); phases.schemaAndSeedNs = stamp() - mark;
    mark = stamp(); const actual = JSON.parse(db.prepare('SELECT payload FROM saved_result WHERE id = ?').get(1).payload);
    assert.deepEqual(actual, [{id: 1}]); phases.queryAndMaterializeNs = stamp() - mark;
  } finally { mark = stamp(); db.close(); phases.closeNs = stamp() - mark; }
  return {pid: process.pid, stateId: database, initialize, verified: true, settings: actualSettings, phases, cpu: process.cpuUsage()};
}
async function childSample(database, initialize, fullfsync) {
  const start = process.hrtime.bigint();
  const child = spawn(process.execPath, [fileURLToPath(import.meta.url), '--sqlite-child', database, String(initialize), String(fullfsync)],
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
  assert.equal(row.settings.fullfsync, Number(fullfsync));
  return {...row, wallNs, userUs: row.cpu.user, systemUs: row.cpu.system, terminal, stderr};
}

export async function runSQLiteBaseline({output, warmSamples = 100, coldSamples = 5, load, fullfsync = false}) {
  checkFullfsync(fullfsync);
  assert(['isolated', 'concurrent'].includes(load), 'State actual host load explicitly');
  assert(Number.isSafeInteger(warmSamples) && warmSamples >= 1 && warmSamples <= 1000);
  assert(Number.isSafeInteger(coldSamples) && coldSamples >= 0 && coldSamples <= 30);
  output = resolve(output); await mkdir(output, {mode: 0o700}); // Never overwrite prior measured state.
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  const report = {schemaVersion: 1, kind: 'local-sqlite-comparator', environment, load, profiled: false,
    executableSha256: digest(await readFile(process.execPath)), collectorSha256: digest(await readFile(fileURLToPath(import.meta.url))),
    protocol: {...sqliteBaselineProtocol, fullfsyncRequested: fullfsync},
    warmSamples, coldSamples, warm: [], cold: [], cleanup: {closed: false}, productAcceptance: false,
    qualification: 'Local comparator only; no ActQL operation or semantic/durability equivalence inferred.'};
  report.protocolSha256 = digest(JSON.stringify(report.protocol));
  const flags = [...process.execArgv, process.env.NODE_OPTIONS ?? ''].join(' ');
  report.profiled = /--(?:cpu-prof|heap-prof|prof|inspect|perf-basic-prof)(?:[=\s-]|$)/u.test(flags) || Boolean(process.env.NODE_V8_COVERAGE);
  const database = join(output, 'warm.sqlite'), db = await openDatabase(database, fullfsync);
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
      ...await childSample(operation === 'first-init' ? join(output, `init-${n}.sqlite`) : database, operation === 'first-init', fullfsync)});
    if (samples.length) report.cold.push({operation, samples, summary: summarizeSQLiteSamples(samples)});
  }
  report.observedAt = new Date().toISOString();
  await writeFile(join(output, 'sqlite-baseline.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  return report;
}

// A bounded storage control for the existing Result delivery protocol. Opaque
// size-matched envelopes below are benchmark data, never issued grants, actual
// ActQL contracts, or an implementation of their authorization/validation.
export const resultControlKeyWidths = Object.freeze({namespaceId: 5, authorityScopeCid: 71,
  runDefinitionCid: 71, principalId: 4, purpose: 8, resultName: 4, attemptId: 36});
const businessBodies = ['grant', 'attempt', 'streaming', 'receipt', 'terminalSucceeded'];
function sizedControlBody(bytes, kind, identity) {
  const value = {kind, identity, fixture: ''};
  const remaining = bytes - Buffer.byteLength(JSON.stringify(value));
  assert(remaining >= 0); value.fixture = 'x'.repeat(remaining);
  const wire = JSON.stringify(value); assert.equal(Buffer.byteLength(wire), bytes); return wire;
}
export async function runSQLiteResultControl({output, resultOwnerMap, warmSamples = 100, load, warmup = 10, fullfsync = false}) {
  checkFullfsync(fullfsync);
  assert(['isolated', 'concurrent'].includes(load));
  assert(Number.isSafeInteger(warmSamples) && warmSamples >= 1 && warmSamples <= 1000);
  assert(Number.isSafeInteger(warmup) && warmup >= 0 && warmup <= 100);
  const mapBytes = await readFile(resultOwnerMap), mapping = JSON.parse(mapBytes);
  assert.match(mapping.source?.commit ?? '', /^[a-f0-9]{40}$/u);
  assert.deepEqual(mapping.groups?.map(row => row.id), ['clock', 'start', 'end']);
  assert.deepEqual(mapping.minimalRowModel?.logicalKeyFields, Object.keys(resultControlKeyWidths));
  const sizes = mapping.minimalRowModel.bytesObserved;
  for (const key of [...businessBodies, 'clock']) assert(Number.isSafeInteger(sizes[key]) && sizes[key] >= 128 && sizes[key] <= 65536);
  assert.equal(sizes.totalCanonicalBusinessBytes, businessBodies.reduce((sum, key) => sum + sizes[key], 0));
  assert.equal(sizes.outputJsonlBytes, Buffer.byteLength('{"id":1}\n'));
  output = resolve(output); await mkdir(output, {mode: 0o700});
  const cid = () => 'sha256:' + digest(randomUUID());
  const context = {namespaceId: 'bench', authorityScopeCid: cid(), runDefinitionCid: cid(),
    principalId: 'test', purpose: 'fixture0', resultName: 'main'};
  const clockCid = cid(), payloadCid = cid(), payload = '{"id":1}\n';
  const storedPayload = plain, schema = '{"id":{"nullable":false,"type":"number"}}';
  const clockEpoch = Date.now();
  const clockBody = floor => {
    const value = {clockContractCid: clockCid, observedAt: new Date(clockEpoch + floor).toISOString()};
    const wire = JSON.stringify({...value, contentSha256: digest(JSON.stringify(value))});
    assert.equal(Buffer.byteLength(wire), sizes.clock); return wire;
  };
  const database = join(output, 'result-control.sqlite');
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  const report = {schemaVersion: 2, kind: 'local-sqlite-result-control', environment, load,
    ownerMapping: {source: mapping.source.commit, sha256: digest(mapBytes), groups: mapping.groups},
    executableSha256: digest(await readFile(process.execPath)), collectorSha256: digest(await readFile(fileURLToPath(import.meta.url))),
    protocol: {binding: 'node:sqlite DatabaseSync', concurrency: 1, fullfsyncRequested: fullfsync,
      preparation: 'prepared statements; fresh identities/envelopes inside each timed sample',
      groups: ['durable clock acceptance', 'atomic grant/use/attempt/streaming before payload', 'atomic receipt/terminal/head CAS after payload completion'],
      keyWidths: resultControlKeyWidths, bodyBytes: sizes, payload, expected: [{id: 1}], warmup,
      materialization: {
        storedFormat: 'json-array-utf8', storedBytes: Buffer.byteLength(storedPayload), storedSha256: digest(storedPayload),
        schemaFormat: 'actql-schema-json-utf8', schemaBytes: Buffer.byteLength(schema), schemaSha256: digest(schema),
        outputFormat: 'jsonl-utf8', outputBytes: Buffer.byteLength(payload), outputSha256: digest(payload),
        conversion: 'stored-array-and-schema -> JSONL -> ordinary-JS-records',
      },
      serialization: 'Fresh size-matched opaque JSON envelopes, not actual typed/canonical ActQL contracts',
      coverage: 'Minimal independently required durable groups only; excludes Account/cryptographic/type admission and new Run claim/publication',
      history: 'One fixed Run/payload; fresh grant/attempt per sample; indexed keys/quota/head, no unrelated row inventory'},
    warmSamples, samples: [], cleanup: {closed: false}, productAcceptance: false};
  report.protocolSha256 = digest(JSON.stringify(report.protocol));
  const flags = [...process.execArgv, process.env.NODE_OPTIONS ?? ''].join(' ');
  report.profiled = /--(?:cpu-prof|heap-prof|prof|inspect|perf-basic-prof)(?:[=\s-]|$)/u.test(flags) || Boolean(process.env.NODE_V8_COVERAGE);
  const db = await openDatabase(database, fullfsync);
  try {
    report.settings = settings(db);
    db.exec(`CREATE TABLE clock (cid TEXT PRIMARY KEY, floor INTEGER NOT NULL, body TEXT NOT NULL);
      CREATE TABLE grant_use (cid TEXT PRIMARY KEY, max_uses INTEGER NOT NULL, uses INTEGER NOT NULL, body TEXT NOT NULL);
      CREATE TABLE attempt (cid TEXT PRIMARY KEY, namespace TEXT NOT NULL, scope TEXT NOT NULL, run TEXT NOT NULL,
        principal TEXT NOT NULL, purpose TEXT NOT NULL, result TEXT NOT NULL, attempt_id TEXT NOT NULL,
        grant_cid TEXT NOT NULL, head TEXT NOT NULL, body TEXT NOT NULL,
        UNIQUE(namespace,scope,run,principal,purpose,result,attempt_id));
      CREATE INDEX attempt_grant ON attempt(grant_cid);
      CREATE TABLE record (attempt TEXT NOT NULL, sequence INTEGER NOT NULL, cid TEXT NOT NULL UNIQUE,
        prior TEXT, body TEXT NOT NULL, PRIMARY KEY(attempt,sequence));
      CREATE TABLE receipt (cid TEXT PRIMARY KEY, body TEXT NOT NULL);
      CREATE TABLE payload (cid TEXT PRIMARY KEY, wire TEXT NOT NULL, schema TEXT NOT NULL);`);
    db.prepare('INSERT INTO clock VALUES (?,0,?)').run(clockCid, clockBody(0));
    db.prepare('INSERT INTO payload VALUES (?,?,?)').run(payloadCid, storedPayload, schema);
    const statement = Object.fromEntries(Object.entries({
      clock: 'SELECT floor FROM clock WHERE cid=?',
      floor: 'UPDATE clock SET floor=?,body=? WHERE cid=? AND floor=?',
      lookup: 'SELECT cid FROM attempt WHERE namespace=? AND scope=? AND run=? AND principal=? AND purpose=? AND result=? AND attempt_id=?',
      grant: 'INSERT INTO grant_use VALUES (?,1,0,?)',
      use: 'UPDATE grant_use SET uses=uses+1 WHERE cid=? AND uses<max_uses',
      attempt: 'INSERT INTO attempt VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      record: 'INSERT INTO record VALUES (?,?,?,?,?)',
      payload: 'SELECT wire,schema FROM payload WHERE cid=?',
      receipt: 'INSERT INTO receipt VALUES (?,?)',
      terminal: 'UPDATE attempt SET head=? WHERE cid=? AND head=?',
    }).map(([key, sql]) => [key, db.prepare(sql)]));
    report.indexPlans = rows(db.prepare('EXPLAIN QUERY PLAN SELECT cid FROM attempt WHERE namespace=? AND scope=? AND run=? AND principal=? AND purpose=? AND result=? AND attempt_id=?')
      .all(...Object.values(context), randomUUID()));
    const execute = () => {
      const phases = {}, events = [], counts = {begins: 0, commits: 0, rollbacks: 0, reads: 0, writes: 0};
      let mark = process.hrtime.bigint();
      const ids = {grant: cid(), attempt: cid(), streaming: cid()};
      const attemptId = randomUUID(), key = [...Object.values(context), attemptId];
      assert(key.every((value, n) => Buffer.byteLength(value) === Object.values(resultControlKeyWidths)[n]));
      const bodies = Object.fromEntries(['grant', 'attempt', 'streaming'].map(kind => [kind, sizedControlBody(sizes[kind], kind, ids[kind])]));
      phases.fixtureConstructionNs = Number(process.hrtime.bigint() - mark);
      const read = (key, ...args) => { counts.reads++; return statement[key].get(...args); };
      const write = (key, ...args) => { counts.writes++; return statement[key].run(...args); };
      const transaction = (name, action) => {
        const start = process.hrtime.bigint(); db.exec('BEGIN IMMEDIATE'); counts.begins++;
        try {
          action(); const commitStart = process.hrtime.bigint(); db.exec('COMMIT'); counts.commits++;
          phases[name] = {totalNs: Number(process.hrtime.bigint() - start), commitNs: Number(process.hrtime.bigint() - commitStart)};
          events.push(`${name}-committed`);
        } catch (error) { db.exec('ROLLBACK'); counts.rollbacks++; throw error; }
      };
      transaction('clock', () => {
        const previous = read('clock', clockCid).floor;
        assert.equal(write('floor', previous + 1, clockBody(previous + 1), clockCid, previous).changes, 1);
      });
      transaction('start', () => {
        assert.equal(read('lookup', ...key), undefined);
        write('grant', ids.grant, bodies.grant); assert.equal(write('use', ids.grant).changes, 1);
        write('attempt', ids.attempt, ...key, ids.grant, ids.streaming, bodies.attempt);
        write('record', ids.attempt, 0, ids.streaming, null, bodies.streaming);
      });
      mark = process.hrtime.bigint();
      const stored = read('payload', payloadCid), decoded = JSON.parse(stored.wire);
      assert.deepEqual(JSON.parse(stored.schema), {id: {nullable: false, type: 'number'}});
      events.push('stored-array-decoded');
      const jsonl = decoded.map(row => JSON.stringify(row) + '\n').join('');
      assert.equal(jsonl, payload); events.push('jsonl-serialized');
      const actual = jsonl.trimEnd().split('\n').map(line => JSON.parse(line));
      const materialization = {storedBytes: Buffer.byteLength(stored.wire), schemaBytes: Buffer.byteLength(stored.schema),
        jsonlBytes: Buffer.byteLength(jsonl), decodedRows: actual.length, outputSha256: digest(jsonl)};
      assert.deepEqual(actual, [{id: 1}]); events.push('payload-materialized');
      phases.payloadAndMaterializeNs = Number(process.hrtime.bigint() - mark);
      mark = process.hrtime.bigint();
      for (const kind of ['receipt', 'terminalSucceeded']) {
        ids[kind] = cid(); bodies[kind] = sizedControlBody(sizes[kind], kind, ids[kind]);
      }
      phases.terminalConstructionNs = Number(process.hrtime.bigint() - mark);
      transaction('end', () => {
        write('receipt', ids.receipt, bodies.receipt);
        write('record', ids.attempt, 1, ids.terminalSucceeded, ids.streaming, bodies.terminalSucceeded);
        assert.equal(write('terminal', ids.terminalSucceeded, ids.attempt, ids.streaming).changes, 1);
      });
      assert.deepEqual(events, ['clock-committed', 'start-committed', 'stored-array-decoded',
        'jsonl-serialized', 'payload-materialized', 'end-committed']);
      return {actual, phases, events, counts, materialization, attemptCid: ids.attempt};
    };
    for (let n = 0; n < warmup; n++) execute();
    for (let n = 0; n < warmSamples; n++) {
      const cpu = process.cpuUsage(), start = process.hrtime.bigint(), value = execute();
      const wallNs = Number(process.hrtime.bigint() - start), usage = process.cpuUsage(cpu);
      report.samples.push({index: n, pid: process.pid, wallNs, userUs: usage.user, systemUs: usage.system, verified: true,
        outputSha256: digest(JSON.stringify(value.actual)), phases: value.phases, events: value.events,
        counts: value.counts, materialization: value.materialization, attemptCid: value.attemptCid});
    }
    report.summary = summarizeSQLiteSamples(report.samples);
  } catch (error) {
    report.failure = {name: error.name, message: error.message}; throw error;
  } finally {
    db.close(); report.cleanup.closed = true; report.observedAt = new Date().toISOString();
    await writeFile(join(output, 'sqlite-result-control.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] === '--sqlite-child') {
      assert(['true', 'false'].includes(process.argv[5]), 'Explicit child fullfsync setting required');
      console.log(JSON.stringify(await coldChild(process.argv[3], process.argv[4] === 'true', process.argv[5] === 'true')));
    }
    else {
      const args = process.argv.slice(2), options = {};
      assert.equal(args.length % 2, 0);
      for (let n = 0; n < args.length; n += 2) {
        const key = {'--output': 'output', '--warm-samples': 'warmSamples', '--cold-samples': 'coldSamples', '--load': 'load',
          '--result-owner-map': 'resultOwnerMap', '--fullfsync': 'fullfsync'}[args[n]];
        assert(key && !Object.hasOwn(options, key));
        if (key === 'fullfsync') {
          assert(['on', 'off'].includes(args[n + 1]), 'fullfsync must be on or off');
          options[key] = args[n + 1] === 'on';
        } else options[key] = key.endsWith('Samples') ? Number(args[n + 1]) : args[n + 1];
      }
      assert(options.output);
      if (options.resultOwnerMap) {
        assert(!Object.hasOwn(options, 'coldSamples'), 'Result control does not replace cold/init sampling');
        const report = await runSQLiteResultControl(options);
        console.log(JSON.stringify({kind: report.kind, summary: report.summary, productAcceptance: false}));
      } else {
        const report = await runSQLiteBaseline(options);
        console.log(JSON.stringify({warm: report.warm.map(row => ({operation: row.operation, mode: row.mode, ...row.summary})),
        cold: report.cold.map(row => ({operation: row.operation, ...row.summary})), productAcceptance: false}));
      }
    }
  } catch (error) { console.error(error.stack); process.exitCode = 1; }
}
