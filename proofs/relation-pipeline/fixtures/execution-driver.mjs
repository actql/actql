// Tiny Moon process boundary for executor/workspace tests. The executor,
// snapshots, receipts and filesystem are real; this is not semantic proof.
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync,
  readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const modules = ['proofs/relation-pipeline/execute.mjs', 'proofs/relation-pipeline/engine.mjs',
  'proofs/relation-pipeline/fixture.mjs', 'proofs/relation-pipeline/harness.mbt',
  'proofs/relation-pipeline/inventory.mjs', 'proofs/relation-pipeline/workspaces.mjs',
  'proofs/relation-pipeline/take.mjs', 'proofs/bounded-session/evidence.mjs',
  'proofs/bounded-session/nest-obligations.json', 'scripts/owned-scratch.mjs', 'scripts/ar', 'toolchain.json'];

const fakeMoon = String.raw`import assert from 'node:assert/strict';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
const args = process.argv.slice(2);
assert.deepEqual(args.slice(0, 2), ['test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt']);
assert.equal(args.at(-1), '--deny-warn');
const target = args[args.indexOf('--target') + 1];
assert(['js', 'wasm', 'native'].includes(target));
const settings = JSON.parse(readFileSync(process.env.ACTQL_TEST_EXECUTION_CONTROL, 'utf8'));
const inputs = JSON.parse(process.env.ACTQL_RELATION_PIPELINE_CASES);
const fixture = readFileSync(args[1], 'utf8');
const targetBinding = fixture.split('#cfg(target="' + target + '")')[1]?.split('}')[0];
const buildIdentity = /ACTQL_PIPELINE_BUILD:([0-9a-f]{64})/.exec(targetBinding ?? '')?.[1];
assert(buildIdentity, 'the real fixture must compile an identity marker');
const extension = { js: 'js', wasm: 'wasm', native: 'exe' }[target];
const binaryPath = join('_build', target, 'debug/test/query_integration', 'observation.' + extension);
const event = { cwd: process.cwd(), target, args, inputs, buildIdentity, binaryPath,
  mode: settings.mode ?? 'normal', compiled: false };
const log = () => appendFileSync(process.env.ACTQL_TEST_EXECUTION_CALLS, JSON.stringify(event) + '\n');
if (settings.mode === 'compile-failure') { log(); console.error('simulated compiler failure'); process.exit(17); }
if (settings.mode === 'no-execution') { log(); process.exit(0); }
const old = existsSync(binaryPath) ? JSON.parse(readFileSync(binaryPath, 'utf8')) : null;
if (!old || (old.buildIdentity !== buildIdentity && !settings.stale)) {
  mkdirSync(dirname(binaryPath), { recursive: true });
  writeFileSync(binaryPath, JSON.stringify({ buildIdentity, target,
    source: readFileSync('src/query_integration/source.mbt', 'utf8') }));
  event.compiled = true;
}
// Emission reads the marker from the compiled file, never from runtime inputs.
const binary = JSON.parse(readFileSync(settings.binaryFrom ?? binaryPath, 'utf8'));
log();
console.log('ACTQL_PIPELINE_BUILD:' + binary.buildIdentity);
if (settings.mode !== 'no-observations') for (const input of inputs) {
  let rows = JSON.parse(input.source)[0].values.rows;
  for (const step of JSON.parse(input.steps)) {
    assert(step.take, 'test fixture only implements Take');
    rows = rows.slice(step.take.offset, step.take.offset + step.take.count);
  }
  const columns = ['extra', 'k', 'tag'];
  console.log('ACTQL_PIPELINE_CASE:' + JSON.stringify(input.id));
  console.log('ACTQL_PIPELINE:' + JSON.stringify({ id: settings.wrongId ? 'old-case-id' : input.id,
    checked: !settings.unchecked, registered: !settings.unregistered, columns,
    rows: rows.map(row => columns.map(field => row[field])), wireRows: rows,
    observedSource: input.source, observedSteps: input.steps,
    observedCorrespondence: input.correspondence, compiledSource: binary.source }));
}
if (settings.mutateSource) writeFileSync('src/query_integration/source.mbt', settings.mutateSource);
if (settings.mutateFixture) writeFileSync(args[1], fixture + '// changed while executing\n');
if (settings.mode !== 'no-test-summary') console.log('Total tests: 1, passed: 1, failed: 0');
`;

function put(root, path, bytes) {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), bytes);
}

export function minimalRepository(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-pipeline-execution-'));
  t.after(() => {
    // A cleanup-failure test intentionally leaves its fixture directory read-only.
    const unlock = directory => {
      chmodSync(directory, 0o700);
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (entry.isDirectory()) unlock(join(directory, entry.name));
      }
    };
    if (existsSync(root)) { unlock(root); rmSync(root, { recursive: true, force: true }); }
  });
  for (const path of modules) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    copyFileSync(join(repository, path), join(root, path));
    if (path === 'scripts/ar') chmodSync(join(root, path), 0o755);
  }
  // All inventory roots must exist in both source-only materializations.
  put(root, 'proofs/relation-chain/input.txt', 'chain source\n');
  put(root, 'proofs/relation-capacity/input.txt', 'capacity source\n');
  put(root, 'src/query_integration/source.mbt', '// pristine source\n');
  put(root, 'src/query_integration/exact-bytes.dat', Buffer.from([0, 13, 10, 127, 128, 255]));
  put(root, 'moon.mod', 'name = "execution-fixture"\n');
  put(root, 'package.json', '{"type":"module"}\n');
  put(root, 'package-lock.json', '{}\n');
  put(root, '.github/workflows/ci.yml', 'name: fixture\n');
  put(root, 'docs/spec/language.md', 'fixture language\n');
  put(root, 'docs/spec/execution.md', 'fixture execution\n');
  put(root, 'scripts/native-cxx-link-driver.sh', '#!/bin/sh\nexit 0\n');
  chmodSync(join(root, 'scripts/native-cxx-link-driver.sh'), 0o755);
  put(root, 'vendor/native/include/fixture.h', '// vendored native input\n');
  put(root, '.execution-control.json', '{}');
  const pin = JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8'));
  const tools = {
    moon: fakeMoon,
    moonc: `console.log(${JSON.stringify(pin.moonc)});\n`,
    moonrun: '// Unused executable whose bytes are still part of the tool identity.\n',
    node: '// JS runtime identity input.\n', cc: '// C compiler identity input.\n',
    'c++': '// C++ compiler identity input.\n',
  };
  for (const [name, source] of Object.entries(tools)) {
    put(root, `.fake-moon/bin/${name}`, `#!${process.execPath}\n${source}`);
    chmodSync(join(root, '.fake-moon/bin', name), 0o755);
  }
  for (const path of ['lib/core/core.mi', 'lib/runtime/runtime.c', 'include/moonbit.h']) {
    put(root, '.fake-moon/' + path, '// pinned toolchain input\n');
  }
  return root;
}

export function runDriver(root, body) {
  const url = name => JSON.stringify(pathToFileURL(join(root, 'proofs/relation-pipeline', name)).href);
  const source = `
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync,
  renameSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createExecutor, execute, executions, fixture, root, digest } from ${url('execute.mjs')};
import { mutationWorkspaces, workspaceIdentity } from ${url('workspaces.mjs')};
import { snapshot } from ${url('inventory.mjs')};
import { take } from ${url('take.mjs')};
const registry = [take];
const sourcePath = 'src/query_integration/source.mbt';
const original = readFileSync(join(root, sourcePath), 'utf8');
const makeCase = (id = 'case', value = 1, count = 1) => ({ id,
  rows: [{ id: 'r0', values: { extra: value, k: null, tag: 1 } },
    { id: 'r1', values: { extra: 0, k: 2, tag: -1 } }],
  steps: [{ id: 'take', op: 'take', args: { count, offset: 0 } }] });
const configure = settings => writeFileSync(join(root, '.execution-control.json'), JSON.stringify(settings));
const calls = () => existsSync(join(root, '.execution-calls.jsonl'))
  ? readFileSync(join(root, '.execution-calls.jsonl'), 'utf8').trim().split('\\n').filter(Boolean).map(line => JSON.parse(line)) : [];
const report = value => console.log('TEST_RESULT=' + JSON.stringify(value));
${body}
`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', source], {
    cwd: root, encoding: 'utf8', timeout: 30_000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, MOON_HOME: join(root, '.fake-moon'), CC: 'cc', CXX: 'c++',
      ACTQL_TEST_PRESERVE_SCRATCH: '', ACTQL_TEST_EXECUTION_CONTROL: join(root, '.execution-control.json'),
      ACTQL_TEST_EXECUTION_CALLS: join(root, '.execution-calls.jsonl') },
  });
  const reports = result.stdout.split('\n').filter(line => line.startsWith('TEST_RESULT='))
    .map(line => JSON.parse(line.slice('TEST_RESULT='.length)));
  return { ...result, reports };
}

export function successful(result) {
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Execution driver failed (${result.status})\n${result.stdout}\n${result.stderr}`);
  return result.reports.at(-1);
}
