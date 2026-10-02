// Actual public Host process death before Checkpoint creation. No finally,
// graceful close or simulated provider failure substitutes for the stop.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const scratch = new URL('../_build/effect-capture-host-crash/', import.meta.url);
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch.pathname, 'run-'));
const hostRoot = join(root, 'host');
await mkdir(hostRoot);
const keys = Object.fromEntries(['reviewer', 'host'].map(name => [name,
  generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'})]));
const keyPath = join(root, 'fixture-keys.json');
await writeFile(keyPath, JSON.stringify(keys), {mode: 0o600});
const log = join(root, 'calls.log');
await writeFile(log, '');
const boundary = process.argv[2] ?? 'effect-capture';
assert.ok(['before-effect-source', 'effect-source',
  'before-effect-capture', 'effect-capture', 'before-publication-private',
  'publication-private'].includes(boundary));
const environment = {...process.env,
  ACTQL_TEST_HOST_CRASH_ROOT: hostRoot, ACTQL_TEST_HOST_CRASH_KEYS: keyPath,
  ACTQL_TEST_EFFECT_ENTRY: new URL('../adapters/host-node/entry.mjs', import.meta.url).href,
  ACTQL_TEST_ACQUIRED_SOURCE_ENTRY: new URL('../adapters/host-node/captured-duckdb-source.mjs', import.meta.url).href,
  ACTQL_TEST_EFFECT_CALL_LOG: log};
const args = phase => nodeTestArguments([
  '--experimental-test-module-mocks',
  '--import', new URL('./fixtures/effect-computation-probe-preload.mjs', import.meta.url).href,
  ...(phase === 'prepare' ? ['--import',
    new URL('./fixtures/effect-capture-crash-preload.mjs', import.meta.url).href] : []),
  '--test', '--test-name-pattern',
  '^acquired Effect waits durably and resumes through the public Host$',
  'adapters/host-node/remote-checkpoint-host.test.mjs',
]);
const run = phase => spawnSync(process.execPath, args(phase), {cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 120_000,
  env: {...environment, ACTQL_TEST_HOST_CRASH_PHASE: phase,
    ...(phase === 'prepare' ? {ACTQL_TEST_CAPTURE_CRASH_BOUNDARY: boundary,
      ACTQL_TEST_CAPTURE_CRASH_RECORD: join(root, 'capture.json')} : {})}});
const initial = run('prepare');
assert.notEqual(initial.status, 0);
assert.match(initial.stdout + initial.stderr, /77/,
  'must stop at the selected real Store commit');
const calls = () => readFile(log, 'utf8');
const before = await calls();
assert.equal(before.split('\n').filter(line => line === 'compute').length, 1);
assert.equal(before.split('\n').filter(line => line === 'source').length, 1);
const recovery = run('recover');
assertTestExecution('node', process.execPath, args('recover'), recovery);
const after = await calls();
assert.equal(after.split('\n').filter(line => line === 'compute').length, 1);
assert.equal(after.split('\n').filter(line => line === 'source').length, 1);
console.log(`${boundary}: public Host cleanup; restart Source/Compute calls = 0`);
