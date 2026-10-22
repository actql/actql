import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {assessNativeSqliteDiagnostic, assessPerformanceEvidence} from './operation-performance.mjs';

// Entirely synthetic process/timing evidence tests the assessor, not SQLite or
// product performance. Unknown counters stay unknown even in these fixtures.
const hash = text => createHash('sha256').update(text).digest('hex');
function fixture() {
  const output = '{"x":1}\n', settings = {journalMode: 'wal', lockingMode: 'normal', synchronous: 2,
    fullfsync: 1, checkpointFullfsync: 0, cacheSize: -2000, tempStore: 1, queryOnly: 1, pageSize: 4096};
  const protocol = {nodeExecutable: '/synthetic/node', sqliteExecutable: '/synthetic/sqlite3',
    concurrency: 1, prepared: 'one-shot/fresh process', samplesPerOperation: 2, warmupsPerOperation: 1,
    expectedSettings: settings, expectedJsonl: output,
    mmapSettingObservation: {requestedBytes: 0, actualBytes: 0, probeSql: 'PRAGMA mmap_size;'},
    operations: {select: {sql: 'SELECT 1 AS x;\n', materialization: 'SQLite JSON to JSONL', durableLogicalTransitions: 0},
      savedRow: {sql: "SELECT row_json,schema_json FROM saved_result WHERE result_key='answer';\n",
        materialization: 'Indexed row and schema to JSONL', durableLogicalTransitions: 0}},
    missingCorrespondence: ['SQLite build differs from product', 'Essential public work is unmatched']};
  const protocolText = JSON.stringify(protocol, null, 2) + '\n';
  let pid = 10;
  const raw = [];
  for (const operation of ['select', 'savedRow']) for (const index of [-1, 0, 1]) {
    const values = index < 0 ? [8, 2, 1] : operation === 'select'
      ? [[9, 1, 4], [11, 7, 1]][index] : [[10, 7, 1], [8, 1, 4]][index];
    const [total, sqlite, conversion] = values.map(value => value * 1e6);
    raw.push({operation, index, warmup: index < 0, collectorPid: 1,
      wallStart: '2026-01-01T00:00:00Z', wallEnd: '2026-01-01T00:00:01Z',
      publicLikeProcessTotalNs: String(total), sqliteProcessElapsedNs: String(sqlite),
      conversionAndOracleElapsedNs: String(conversion), launcherAndRemainingNs: String(total - sqlite - conversion),
      output, child: {kind: 'sqlite-cli-control-child', operation, launcherPid: pid++, sqlitePid: pid++,
        parentPid: 1, stateId: 'synthetic-state', nodeExecutable: protocol.nodeExecutable,
        outputBytes: 8, outputSha256: hash(output), sqliteProcessElapsedNs: String(sqlite),
        conversionAndOracleElapsedNs: String(conversion), adapterElapsedNs: String(sqlite + conversion + 1e6),
        engineOnlyElapsedNs: null, durableLogicalTransitions: 0}});
  }
  const control = {kind: 'native-cli-sqlite-process-control-diagnostic', schemaVersion: 1,
    protocol: {bytes: Buffer.byteLength(protocolText), sha256: hash(protocolText)},
    environment: {platform: 'synthetic', arch: 'synthetic', nodeVersion: 'synthetic-node',
      sqliteVersion: 'synthetic-sqlite', concurrency: 1, startup: 'fresh launcher and child'},
    binaries: [{path: protocol.nodeExecutable, bytes: 1, sha256: '1'.repeat(64)},
      {path: protocol.sqliteExecutable, bytes: 2, sha256: '2'.repeat(64)}],
    actualSettings: settings, mmapSettingObservation: protocol.mmapSettingObservation,
    actualIndexedPlan: [{detail: 'SEARCH saved_result USING PRIMARY KEY (result_key=?)'}],
    preparation: 'new process', completion: 'exit after conversion',
    fixture: {totalRows: 1, expectedJsonl: output, materialization: protocol.operations,
      databaseBefore: {path: 'synthetic-state', bytes: 8192, sha256: '3'.repeat(64)},
      databaseAfter: {path: 'synthetic-state', bytes: 8192, sha256: '3'.repeat(64)}},
    operations: {select: {count: 2, minMs: 9, medianMs: 11, maxMs: 11, p95Ms: null},
      savedRow: {count: 2, minMs: 8, medianMs: 10, maxMs: 10, p95Ms: null}},
    raw, actualPhysicalDbReads: null, sqlPrepareCalls: null, engineOnlyElapsedNs: null, fullfsyncCalls: null,
    childrenAllExitedSynchronously: true, liveDuties: [], externalRunOrKeyStateOpened: false,
    publicActqlOperationMeasured: false, productAcceptance: 'incomplete', comparisonProfile: null,
    essentialOverheadAllowance: null, missingCorrespondence: protocol.missingCorrespondence};
  return {control, protocolText};
}
function report(native) {
  return {sourceSha: 'a'.repeat(40), cohortSha256: 'b'.repeat(64), environmentSha256: 'c'.repeat(64),
    historyProtocolSha256: 'd'.repeat(64), comparison: {nativeSqliteDiagnostic: native}};
}

test('Native control preserves startup components, unknown counters and incomplete public scope', () => {
  const {control, protocolText} = fixture(), result = assessNativeSqliteDiagnostic(control, protocolText);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.operations.select.total.count, 2);
  assert.equal(result.operations.select.total.medianMs, 11);
  assert.equal(result.operations.savedRow.total.medianMs, 10);
  assert.equal(result.operations.savedRow.sqliteProcess.medianMs, 7);
  assert.notEqual(result.operations.savedRow.total.medianMs,
    result.operations.savedRow.sqliteProcess.medianMs + result.operations.savedRow.conversionAndOracle.medianMs +
      result.operations.savedRow.launcherAndRemaining.medianMs);
  assert.equal(result.operations.select.total.p95Ms, null);
  assert.deepEqual(Object.values(result.unmeasuredCounters), [null, null, null, null]);
  assert.equal(result.comparisonProfile, null);
  assert.equal(result.essentialOverheadAllowance, null);
  assert.deepEqual(result.missing.slice(1), control.missingCorrespondence);
});

test('Native diagnostic cannot supply a public gate or overwrite missing coverage', () => {
  const result = assessPerformanceEvidence(report(fixture()));
  assert.equal(result.status, 'incomplete');
  assert.equal(result.diagnostics.nativeSqlite.status, 'incomplete');
  assert.ok(result.missing.includes('warm-select'));
  assert.ok(result.missing.includes('functional'));
});

test('Native control rejects protocol, process, output, clock and settings mismatches', () => {
  for (const mutate of [
    ({control}) => control.protocol.sha256 = '0'.repeat(64),
    ({control}) => control.protocol.bytes++,
    ({control}) => control.binaries[1].path = control.binaries[0].path,
    ({control}) => control.actualSettings = {...control.actualSettings, fullfsync: 0},
    ({control}) => control.mmapSettingObservation = {...control.mmapSettingObservation, actualBytes: null},
    ({control}) => control.actualIndexedPlan = [{detail: 'SCAN saved_result'}],
    ({control}) => control.fixture.databaseAfter = {...control.fixture.databaseAfter, sha256: '4'.repeat(64)},
    ({control}) => control.raw[0].child.sqlitePid = 0,
    ({control}) => control.raw[0].child.parentPid = 99,
    ({control}) => control.raw[0].output = '{"x":2}\n',
    ({control}) => control.raw[0].child.outputSha256 = '4'.repeat(64),
    ({control}) => control.raw[0].launcherAndRemainingNs = '0',
    ({control}) => control.raw[0].sqliteProcessElapsedNs = '1e6',
    ({control}) => control.raw[0].child.adapterElapsedNs = control.raw[0].publicLikeProcessTotalNs,
    ({control}) => control.operations.select.medianMs = 1,
    ({control}) => control.raw[0] = structuredClone(control.raw[1]),
    ({control}) => control.raw.pop(),
  ]) {
    const value = fixture(); mutate(value);
    assert.throws(() => assessNativeSqliteDiagnostic(value.control, value.protocolText));
  }
});

test('Native control refuses known failures, unclosed work and invented acceptance or counters', () => {
  for (const mutate of [
    ({control}) => control.firstFailure = {message: 'failed close'},
    ({control}) => control.packageFailure = 'changed package',
    ({control}) => control.cleanupFailure = 'unclosed child',
    ({control}) => control.childrenAllExitedSynchronously = false,
    ({control}) => control.liveDuties.push('child'),
    ({control}) => control.productAcceptance = true,
    ({control}) => control.comparisonProfile = {},
    ({control}) => control.essentialOverheadAllowance = 0,
    ({control}) => control.actualPhysicalDbReads = 0,
    ({control}) => delete control.sqlPrepareCalls,
    ({control}) => control.raw[0].child.engineOnlyElapsedNs = '0',
    ({control}) => control.missingCorrespondence = [],
  ]) {
    const value = fixture(); mutate(value);
    assert.throws(() => assessNativeSqliteDiagnostic(value.control, value.protocolText));
  }
});

test('Native diagnostic CLI consumes explicit paired files and remains nonpassing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'native-control-assessor-'));
  try {
    const {control, protocolText} = fixture();
    const input = join(dir, 'report.json'), raw = join(dir, 'control.json'), protocol = join(dir, 'protocol.json');
    const empty = report(fixture()); delete empty.comparison;
    writeFileSync(input, JSON.stringify(empty)); writeFileSync(raw, JSON.stringify(control)); writeFileSync(protocol, protocolText);
    const base = ['scripts/operation-performance.mjs', '--input', input];
    const run = extra => spawnSync(process.execPath, [...base, ...extra], {encoding: 'utf8'});
    const paired = run(['--native-sqlite-control', raw, '--native-sqlite-protocol', protocol]);
    assert.equal(paired.status, 1, paired.stderr);
    const result = JSON.parse(paired.stdout);
    assert.equal(result.status, 'incomplete'); assert.equal(result.diagnostics.nativeSqlite.status, 'incomplete');
    assert.equal(result.diagnostics.nativeSqlite.operations.select.total.medianMs, 11);
    const unpaired = run(['--native-sqlite-control', raw]);
    assert.equal(unpaired.status, 2); assert.match(unpaired.stderr, /supplied together/u);
    writeFileSync(input, JSON.stringify(report(fixture())));
    const duplicate = run(['--native-sqlite-control', raw, '--native-sqlite-protocol', protocol]);
    assert.equal(duplicate.status, 2); assert.match(duplicate.stderr, /already supplied/u);
  } finally { rmSync(dir, {recursive: true}); }
});
