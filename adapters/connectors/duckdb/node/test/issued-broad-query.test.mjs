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
import { runBroadQuery } from '../broad-query.mjs';
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

// Independent composition from the static requirement and fixed expected rows.
// No product observation/record or returned database value is an oracle input.
function expectedObservation(requirement, [issuer, attempt], scan, selected) {
  const requirementCid = hash(requirement);
  const requestCid = hash(requirement.request);
  const scope = hash({ version: 'actql-query-scan-scope/0.1', source_ref: requirement.source_ref,
    source_contract_cid: requirement.source_contract_cid, resolved_request_cid: requestCid });
  const access = {
    scope_cid: hash({ version: 'actql-query-access-scope/0.1', requirement_cid: requirementCid,
      received_fields: ['amount', 'id'], received_rows_cid: hash(scan) }),
    provider_scope_cid: null, received_rows: scan.length, received_fields: ['amount', 'id'],
    received_bytes: Buffer.byteLength(canonical(scan)),
  };
  const output = { contract_cid: requirement.output_contract_cid, rows_cid: hash(selected), row_count: selected.length };
  const records = ['source_validation', 'filter', 'select'].map(role => hash({
    version: 'actql-query-process-evidence/0.1', issuer, attempt, requirement_cid: requirementCid,
    role, snapshot: null, scan_scope_cid: scope, actual_access: access, output,
  }));
  return { version: 'actql-query-observation/0.1', requirement_cid: requirementCid,
    owner: requirement.owner, source_ref: requirement.source_ref, source_contract_cid: requirement.source_contract_cid,
    parameter_values_cid: requirement.parameter_values_cid, resolved_request_cid: requestCid,
    snapshot: null, actual_access: access,
    coverage: { scope_cid: scope, complete: true, source_validation_evidence_cid: records[0],
      filter_evidence_cid: records[1], select_evidence_cid: records[2] }, output, retention: 'process' };
}

function realBridge(moon, configuration, options, inspect) {
  return verify => {
    const fixture = moon.issuedBroadCreate(...configuration, options.outputRows ?? 100, verify);
    inspect.fixture = fixture;
    const attempt = moon.issuedBroadAttempt(fixture);
    const accepted = (ok, stage) => { if (!ok) throw new Error(`MoonBitBroadRejected: ${stage}`); };
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      assert.equal(view, current);
      assert.equal(moon.issuedBroadDocument(fixture), 'null');
      assert.equal(verify(attempt), false);
    };
    return {
      attempt,
      port: {
        metadataSql: () => moon.issuedBroadSql(fixture, true),
        metadataParameters: () => [0, 1].map(index => JSON.parse(moon.issuedBroadParameter(fixture, index))),
        acceptMetadata(chunk, current) {
          owns(current);
          accepted(moon.issuedBroadMetadata(fixture, chunk.rowCount, JSON.stringify(chunk.fields), JSON.stringify(chunk.columns)), 'metadata');
        },
        finishMetadata(_fields, current) { owns(current); },
        scanSql: () => moon.issuedBroadSql(fixture, false),
        beginReceipt(fields, current) { owns(current); accepted(moon.issuedBroadBegin(fixture, JSON.stringify(fields)), 'begin'); },
        acceptChunk(chunk, current) {
          owns(current); inspect.chunks++;
          accepted(moon.issuedBroadAccept(fixture, chunk.rowCount, JSON.stringify(chunk.columns)), 'admission');
        },
        finishReceipt(current) {
          owns(current); accepted(moon.issuedBroadFinish(fixture), 'receipt');
          if (options.early) assert.equal(moon.issuedBroadComplete(fixture, 1000000), false);
          options.cancel?.abort();
          return attempt;
        },
        abort() { moon.issuedBroadAbort(fixture); },
      },
      complete() {
        inspect.completions++;
        assert.equal(verify(attempt), true);
        accepted(moon.issuedBroadComplete(fixture, options.artifactBytes ?? 1000000), 'complete');
        return moon.issuedBroadObservation(fixture);
      },
      bindInput(observation, rows) {
        const cid = moon.issuedBroadBind(fixture, observation, rows);
        accepted(cid !== 'null', 'consumer');
        return cid;
      },
      abort() { moon.issuedBroadAbort(fixture); },
      close() { moon.issuedBroadClose(fixture); },
    };
  };
}

test('real DuckDB and public CheckedProgram complete owned broad evidence capture and consumer in one process', async () => {
  await promisify(execFile)('moon', ['build', '--target', 'js', 'src/connectors/duckdb/conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/debug/build/connectors/duckdb/conformance/conformance.js')));
  const catalogs = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const catalog = catalogs.slice(catalogs.indexOf('fn query_amount_nullable_catalog'))
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/);
  assert(catalog);
  const contracts = await pinnedEngineContracts(root);
  const configuration = [JSON.parse(catalog[1]), catalog[2], ...contracts,
    await readFile(join(root, 'spec/contracts/actql-query-acquisition.json'), 'utf8'),
    await readFile(join(root, 'spec/contracts/actql-query-process-evidence.json'), 'utf8')];
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'issued-broad-'));
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
      const inspect = { chunks: 0, completions: 0 };
      const run = runBroadQuery(grant, realBridge(moon, configuration, {}, inspect), limits);
      if (name === 'invalid-unused') {
        await assert.rejects(run, /MoonBitBroadRejected: admission/);
        assert.equal(inspect.completions, 0);
        assert.equal(moon.issuedBroadDocument(inspect.fixture), 'null');
        continue;
      }
      const captured = await run;
      const scan = name === 'empty' ? [] : [{ amount: 30, id: 3 }, { amount: null, id: 1 }, { amount: 20, id: 2 }, { amount: 30, id: 3 }];
      const selected = name === 'empty' ? [] : [{ id: 3 }, { id: 2 }, { id: 3 }];
      const expected = expectedObservation(JSON.parse(moon.issuedBroadRequirement(inspect.fixture)),
        JSON.parse(moon.issuedBroadIds(inspect.fixture)), scan, selected);
      assert.equal(moon.issuedBroadDocument(inspect.fixture), canonical(expected));
      if (name !== 'empty') assert.throws(() => captured.bindInput(1), /consumer/);
      // Source changes cannot affect the already captured consumer input.
      const changed = await DuckDBInstance.create(path);
      const write = await changed.connect();
      try { await write.run('INSERT INTO records VALUES (9,90)'); }
      finally { write.closeSync(); changed.closeSync(); }
      assert.equal(captured.bindInput(100), hash(selected));
      assert.equal(captured.bindInput(100), hash(selected));
      assert.equal(inspect.completions, 1);
      captured.close();
      assert.throws(() => captured.bindInput(100), error => error.code === 'IssuerClosed');
      for (const options of [{ outputRows: 0 }, { artifactBytes: 0 }, { early: true }, { cancel: new AbortController() }]) {
        const failed = { chunks: 0, completions: 0 };
        await assert.rejects(runBroadQuery(grant, realBridge(moon, configuration, options, failed), limits, options.cancel?.signal));
        assert.equal(moon.issuedBroadDocument(failed.fixture), 'null');
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
