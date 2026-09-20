import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeHostQuery, runBroadHostQuery } from '../host.mjs';
import { canonical, hash, typedCatalog } from './typed-catalog.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };
// Every expected logical value is authored here, never decoded from product output.
const cases = [
  ['text', 'VARCHAR', { type: 'string' }, "'日本語'", '日本語', "concat('e', chr(769))"],
  ['boolean', 'BOOLEAN', { type: 'boolean' }, 'TRUE', true, null],
  ['integer', 'BIGINT', { type: 'number' }, '9007199254740992', 9007199254740992, '9007199254740993'],
  ['number', 'DOUBLE', { type: 'number' }, '-1.5', -1.5, "'Infinity'::DOUBLE"],
  ['decimal', 'DECIMAL(38,2)', { type: 'decimal', precision: 38, scale: 2 },
    "'999999999999999999999999999999999999.99'::DECIMAL(38,2)",
    '999999999999999999999999999999999999.99', null],
  ['date', 'DATE', { type: 'date' }, "DATE '2000-02-29'", '2000-02-29', "DATE 'infinity'"],
  ['timestamp', 'TIMESTAMPTZ', { type: 'timestamp' },
    "TIMESTAMPTZ '1969-12-31 23:59:59.999+00'", '1969-12-31T23:59:59.999Z',
    "TIMESTAMPTZ '1969-12-31 23:59:59.999001+00'"],
];

test('standard native and broad Hosts admit exact scalar families and reject discarded invalid values', async () => {
  const exec = promisify(execFile);
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/host_node'], { cwd: root });
  await exec('moon', ['build', '--target', 'js', '--release', 'src/connectors/duckdb/conformance'], { cwd: root });
  const moon = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/conformance/conformance.js')));
  const source = await readFile(join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
  const match = source.split('fn query_amount_nullable_catalog')[1]
    .match(/query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")/);
  const seed = JSON.parse(JSON.parse(match[1]));
  const contracts = await pinnedEngineContracts(root);
  const shared = await Promise.all(['actql-query-acquisition.json', 'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
    .map(name => readFile(join(root, 'spec/contracts', name), 'utf8')));
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'typed-host-'));
  try {
    for (const [name, sqlType, type, sql, wire, badSql] of cases) {
      const environment = typedCatalog(seed, { ...type, nullable: true });
      const setupArgs = [canonical(environment), environment.evidence_bundle_cid, ...contracts, ...shared];
      for (const invalid of badSql === null ? [false] : [false, true]) {
        const path = join(directory, `${name}-${invalid}.duckdb`);
        const db = await DuckDBInstance.create(path);
        const connection = await db.connect();
        try {
          await connection.run(`CREATE TABLE records(id DOUBLE, amount ${sqlType})`);
          await connection.run(`INSERT INTO records VALUES (3,${sql}),(1,${invalid ? badSql : 'NULL'}),(3,${sql})`);
        } finally { connection.closeSync(); db.closeSync(); }
        const grant = await authorizeLocalDatabase(path);
        for (const native of [true, false]) {
          const fixture = native ? moon.issuedNativeCreate(...setupArgs, 100, () => false)
            : moon.issuedBroadCreate(...setupArgs.slice(0, -1), 100, () => false);
          const configuration = native ? moon.issuedNativeConfiguration(fixture) : moon.issuedBroadConfiguration(fixture);
          if (native) moon.issuedNativeClose(fixture); else moon.issuedBroadClose(fixture);
          const execute = native ? runNativeHostQuery : runBroadHostQuery;
          if (invalid) {
            await assert.rejects(execute(grant, configuration, limits), { code: 'MoonBitHostFailure' }, `${name}/${native}`);
            continue;
          }
          const capture = await execute(grant, configuration, limits);
          try {
            const observation = JSON.parse(capture.document());
            const selected = [{ id: 3 }, { id: 3 }];
            const scan = [{ amount: wire, id: 3 }, { amount: null, id: 1 }, { amount: wire, id: 3 }];
            assert.equal(observation.output.rows_cid, hash(selected), name);
            assert.equal(observation.output.row_count, 2);
            const requirement = JSON.parse(native ? moon.issuedNativeRequirement(fixture) : moon.issuedBroadRequirement(fixture));
            const scope = hash({ version: 'actql-query-scan-scope/0.1',
              source_ref: requirement.source_ref, source_contract_cid: requirement.source_contract_cid,
              resolved_request_cid: hash(requirement.request) });
            assert.equal(observation.coverage.scope_cid, scope, name);
            if (native) {
              // Runtime ownership labels are not value expectations. The full
              // scan preimage is fixed above, including the unused typed column.
              const receipt = { version: 'actql-query-receipt/0.1', ...observation.execution,
                received_bytes: Buffer.byteLength(canonical(scan)), received_fields: ['amount', 'id'],
                received_rows: 3, received_rows_cid: hash(scan), requirement_cid: hash(requirement),
                role: 'validation_scan', scan_scope_cid: scope, snapshot: null };
              assert.equal(observation.accesses.validation_scan_cid, hash(receipt), name);
              assert.equal(moon.issuedNativeConsumeOutput(fixture, capture.output(), 100), hash(selected));
            } else {
              assert.equal(observation.actual_access.scope_cid, hash({ version: 'actql-query-access-scope/0.1',
                requirement_cid: hash(requirement), received_fields: ['amount', 'id'], received_rows_cid: hash(scan) }), name);
              assert.equal(moon.issuedBroadConsumeInput(fixture, capture.bindInput(moon.issuedBroadConsumer(fixture), 0), 100), hash(selected));
            }
          } finally { capture.close(); }
        }
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
