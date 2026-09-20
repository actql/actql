import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeQuery } from '../native-query.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const hash = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

// Independent contract preimages and fixed rows; no product receipt, record,
// observation or returned SQL value is used to construct expected content.
function expectedObservation(requirement, [issuer, attempt, read_view], scan, selected) {
  const requirementCid = hash(requirement);
  const requestCid = hash(requirement.request);
  const scope = hash({ version: 'actql-query-scan-scope/0.1', source_ref: requirement.source_ref,
    source_contract_cid: requirement.source_contract_cid, resolved_request_cid: requestCid });
  const receipts = [[scan, ['amount', 'id'], 'validation_scan'], [selected, ['id'], 'native_result']]
    .map(([rows, received_fields, role]) => hash({ version: 'actql-query-receipt/0.1', issuer, attempt, read_view,
      received_bytes: Buffer.byteLength(canonical(rows)), received_fields,
      received_rows: rows.length, received_rows_cid: hash(rows), requirement_cid: requirementCid,
      role, scan_scope_cid: scope, snapshot: null }));
  const accesses = { validation_scan_cid: receipts[0], native_result_cid: receipts[1] };
  const output = { contract_cid: requirement.output_contract_cid, rows_cid: hash(selected), row_count: selected.length };
  const records = ['source_validation', 'filter', 'select'].map(role => hash({
    version: 'actql-query-two-receipt-evidence/0.1', issuer, attempt, read_view,
    requirement_cid: requirementCid, role, snapshot: null, scan_scope_cid: scope, accesses, output,
  }));
  return { version: 'actql-query-two-receipt-observation/0.1', requirement_cid: requirementCid,
    evidence_contract_cid: 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8',
    execution: { issuer, attempt, read_view }, owner: requirement.owner,
    source_ref: requirement.source_ref, source_contract_cid: requirement.source_contract_cid,
    parameter_values_cid: requirement.parameter_values_cid, resolved_request_cid: requestCid,
    snapshot: null, accesses,
    coverage: { scope_cid: scope, complete: true, source_validation_evidence_cid: records[0],
      filter_evidence_cid: records[1], select_evidence_cid: records[2] }, output, retention: 'process' };
}

function realBridge(moon, configuration, options, inspect) {
  return verify => {
    const fixture = moon.issuedNativeCreate(...configuration, options.outputRows ?? 100, verify);
    inspect.fixture = fixture;
    const attempt = moon.issuedNativeAttempt(fixture);
    const accepted = (ok, stage) => { if (!ok) throw new Error(`MoonBitNativeRejected: ${stage}`); };
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      assert.equal(view, current);
      assert.equal(moon.issuedNativeDocument(fixture), 'null');
      assert.equal(verify(attempt), false);
    };
    return {
      attempt,
      port: {
        metadataSql: () => moon.issuedNativeSql(fixture, 0),
        metadataParameters: () => [0, 1].map(index => JSON.parse(moon.issuedNativeParameter(fixture, index))),
        acceptMetadata(chunk, current) {
          owns(current);
          accepted(moon.issuedNativeMetadata(fixture, chunk.rowCount, JSON.stringify(chunk.fields), JSON.stringify(chunk.columns)), 'metadata');
        },
        finishMetadata(_fields, current) { owns(current); },
        validationSql: () => moon.issuedNativeSql(fixture, 1),
        nativeSql: () => { inspect.nativeQueries++; return moon.issuedNativeSql(fixture, 2); },
        nativeParameters: () => [JSON.parse(moon.issuedNativeParameter(fixture, 2))],
        beginReceipt(role, fields, current) {
          owns(current); accepted(moon.issuedNativeBegin(fixture, role === 'native_result', JSON.stringify(fields)), 'begin');
        },
        acceptChunk(role, chunk, current) {
          owns(current);
          accepted(moon.issuedNativeAccept(fixture, chunk.rowCount, JSON.stringify(chunk.columns)), `admission-${role}`);
        },
        finishReceipt(role, current) {
          owns(current); accepted(moon.issuedNativeFinish(fixture), 'receipt');
          if (options.early) assert.equal(moon.issuedNativeComplete(fixture, 1000000), false);
          if (options.cancelRole === role) options.cancel.abort();
          return attempt;
        },
        abort() { moon.issuedNativeAbort(fixture); },
      },
      complete() {
        inspect.completions++;
        assert.equal(verify(attempt), true);
        accepted(moon.issuedNativeComplete(fixture, options.artifactBytes ?? 1000000), 'complete');
        return moon.issuedNativeObservation(fixture);
      },
      bindInput(observation, rows) { return moon.issuedNativeBind(fixture, observation, rows); },
      abort() { moon.issuedNativeAbort(fixture); },
      close() { moon.issuedNativeClose(fixture); },
    };
  };
}

test('real native SQL and public CheckedProgram produce independently checked two-receipt capture without Local replay', async () => {
  await promisify(execFile)('moon', ['build', '--target', 'js', 'src/connectors/duckdb/conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/debug/build/connectors/duckdb/conformance/conformance.js')));
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const contracts = await pinnedEngineContracts(root);
  const configuration = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-two-receipt.json'), 'utf8')];
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'issued-native-'));
  try {
    for (const name of ['valid', 'empty', 'invalid-unused']) {
      const path = join(directory, `${name}.duckdb`);
      const db = await DuckDBInstance.create(path);
      const connection = await db.connect();
      try {
        await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
        if (name !== 'empty') await connection.run(name === 'invalid-unused'
          ? "INSERT INTO records VALUES (3,30),(1,'Infinity'::DOUBLE)"
          : 'INSERT INTO records VALUES (3,30),(1,NULL),(2,20),(3,30)');
      } finally { connection.closeSync(); db.closeSync(); }
      const grant = await authorizeLocalDatabase(path);
      const inspect = { nativeQueries: 0, completions: 0 };
      const run = runNativeQuery(grant, realBridge(moon, configuration, {}, inspect), limits);
      if (name === 'invalid-unused') {
        await assert.rejects(run, /admission-validation_scan/);
        assert.equal(inspect.nativeQueries, 0);
        assert.equal(inspect.completions, 0);
        assert.equal(moon.issuedNativeDocument(inspect.fixture), 'null');
        continue;
      }
      const captured = await run;
      const scan = name === 'empty' ? [] : [{ amount: 30, id: 3 }, { amount: null, id: 1 }, { amount: 20, id: 2 }, { amount: 30, id: 3 }];
      const selected = name === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
      const expected = expectedObservation(JSON.parse(moon.issuedNativeRequirement(inspect.fixture)),
        JSON.parse(moon.issuedNativeIds(inspect.fixture)), scan, selected);
      assert.equal(moon.issuedNativeDocument(inspect.fixture), canonical(expected));
      assert.equal(moon.issuedNativeVerify(inspect.fixture), true);
      if (name !== 'empty') {
        assert.equal(moon.issuedNativeMaterialize(inspect.fixture, 1), 'null');
        assert.equal(moon.issuedNativeVerify(inspect.fixture), true);
      }
      assert.equal(moon.issuedNativeMaterialize(inspect.fixture, 100), canonical(selected));
      if (selected.length) {
        assert.equal(captured.bindInput(0), 'null');
        assert.equal(moon.issuedNativeVerify(inspect.fixture), true);
      }
      assert.equal(captured.bindInput(100), hash(selected));
      assert.equal(inspect.nativeQueries, 1);
      assert.equal(inspect.completions, 1);
      captured.close();
      assert.equal(moon.issuedNativeVerify(inspect.fixture), false);
      assert.equal(moon.issuedNativeMaterialize(inspect.fixture, 100), 'null');
      const options = [{ artifactBytes: 0 }, { early: true },
        ...['validation_scan', 'native_result'].map(cancelRole => ({ cancelRole, cancel: new AbortController() }))];
      if (name !== 'empty') options.push({ outputRows: 0 });
      for (const option of options) {
        const failed = { nativeQueries: 0, completions: 0 };
        await assert.rejects(runNativeQuery(grant, realBridge(moon, configuration, option, failed), limits, option.cancel?.signal));
        assert.equal(moon.issuedNativeDocument(failed.fixture), 'null');
        assert.equal(moon.issuedNativeVerify(failed.fixture), false);
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
