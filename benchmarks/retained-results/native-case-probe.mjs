import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {retainedMatrix} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';

// Registered-case native product-path diagnostic. No independent holding or formal
// four-comparator performance acceptance is provided by this command.
const [caseId, ...extra] = process.argv.slice(2);
if (!caseId || extra.length) throw new TypeError('Expected one exact registered case ID');
const fixture = retainedMatrix().find(item => item.id === caseId);
if (!fixture) throw new TypeError(`Unknown registered case: ${caseId}`);
const root = fileURLToPath(new URL('../../', import.meta.url));
const scratchRoot = resolve(root, '.codex-scratch', 'native-retained-case-probe');
await mkdir(scratchRoot, {recursive: true});
const directory = await mkdtemp(join(scratchRoot, 'run-'));
const run = promisify(execFile);
const text = path => readFile(join(root, path), 'utf8');

try {
  const contracts = {
    adoptedText: await text('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
    query: await text('spec/contracts/actql-query-acquisition.json'),
    evidence: await text('spec/contracts/actql-query-process-evidence.json'),
    receipts: await text('spec/contracts/actql-query-two-receipt.json'),
  };
  const database = join(directory, 'source.duckdb');
  await run(process.execPath, [
    join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
    database, fixture.workload, fixture.layout, String(fixture.rows),
  ], {cwd: root, timeout: fixture.limits.timeoutMs});
  const {input, limits, finalTask} = managedCaseConfiguration(
    fixture, contracts, database, directory,
  );
  const adopted = JSON.parse(input.adoptedText);
  const files = {
    'program.json': input.programText,
    'environment.json': input.environmentText,
    'environment.cid': input.environmentCid,
    'parameters.json': input.parameterText,
    'registry.json': JSON.stringify(adopted.registry),
    'values.json': JSON.stringify(adopted.values),
    'fragment.json': JSON.stringify(adopted.fragment),
    'query.json': input.query,
    'evidence.json': input.evidence,
    'two-receipt.json': input.receipts,
  };
  for (const [name, content] of Object.entries(files)) {
    await writeFile(join(directory, name), content);
  }
  const libraryName = process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so';
  const library = join(root, 'adapters/connectors/duckdb/node/node_modules/@duckdb',
    `node-bindings-${process.platform}-${process.arch}`, libraryName);
  assert(existsSync(library), `native DuckDB library unavailable: ${library}`);
  const binary = join(root, '_build/native/release/build/cmd/native_retained_case_probe',
    'native_retained_case_probe.exe');
  assert(existsSync(binary), 'build src/cmd/native_retained_case_probe --target native --release first');
  const expected = fixture.identity(); // Independent oracle remains outside the child timer.
  const started = performance.now();
  const data = input.dataProfile;
  const {stdout} = await run(binary, [
    '--application-root', directory,
    '--database', database,
    '--duckdb-library', library,
    '--expected-cid', expected.rowsCid,
    '--expected-tasks', String(finalTask),
    '--source-rows', String(data.source_rows),
    '--task-rows', String(data.task_rows),
    '--columns', String(data.columns),
    '--value-bytes', String(data.value_bytes),
    '--wire-bytes', String(data.wire_bytes),
    '--value-nodes', String(data.value_nodes),
    '--text-bytes', String(data.text_bytes),
    '--work', String(data.work),
    '--entries', String(data.entries),
    '--batch-bytes', String(data.batch_bytes),
    '--planning-work', String(limits.planning_work),
    '--transfer-cap', String(limits.transfer_bytes),
    '--retained-cap', String(limits.retained_bytes),
    '--execution-cap', String(limits.execution_bytes),
  ], {cwd: root, timeout: fixture.limits.timeoutMs, maxBuffer: 65536});
  const elapsedMilliseconds = performance.now() - started;
  const result = JSON.parse(stdout.trim().split('\n').at(-1));
  assert.equal(result.rows_cid, expected.rowsCid);
  assert.equal(result.task_count, finalTask);
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', status: 'verified-diagnostic', case: fixture.id,
    elapsedMilliseconds, result,
  }));
} catch (error) {
  const output = String(error.stdout ?? '').trim().split('\n');
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', status: 'failed', case: fixture.id,
    name: error.name,
    message: error.stdout ? undefined : error.message?.split('\n')[0],
    code: error.code ?? null, signal: error.signal ?? null,
    phases: output.filter(line => line.startsWith('phase:')),
    strategyRejections: output.filter(line => line.startsWith('strategy-rejection:')),
    terminal: output.at(-1),
  }));
  process.exitCode = 1;
} finally {
  await rm(directory, {recursive: true, force: true});
}
