import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {retainedCase} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';

// Narrow-100 native product-path diagnostic. No independent holding or formal
// four-comparator performance acceptance is provided by this command.
const root = fileURLToPath(new URL('../../', import.meta.url));
const scratchRoot = resolve(root, '.codex-scratch', 'native-retained-case-probe');
await mkdir(scratchRoot, {recursive: true});
const directory = await mkdtemp(join(scratchRoot, 'run-'));
const run = promisify(execFile);
const fixture = retainedCase('native-acquisition-full-validation-low-selectivity', 'narrow', 100);
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
  const {input} = managedCaseConfiguration(fixture, contracts, database, directory);
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
  const started = performance.now();
  const {stdout} = await run(binary, [
    '--application-root', directory,
    '--database', database,
    '--duckdb-library', library,
    '--expected-cid', fixture.identity().rowsCid,
  ], {cwd: root, timeout: fixture.limits.timeoutMs, maxBuffer: 65536});
  const elapsedMilliseconds = performance.now() - started;
  const result = JSON.parse(stdout.trim().split('\n').at(-1));
  assert.equal(result.rows_cid, fixture.identity().rowsCid);
  assert.equal(result.task_count, 3);
  console.log(JSON.stringify({
    kind: 'native-case-probe-diagnostic', case: fixture.id,
    elapsedMilliseconds, result,
  }));
} finally {
  await rm(directory, {recursive: true, force: true});
}
