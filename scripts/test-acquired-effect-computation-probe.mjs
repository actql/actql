// Exercise the real HTTP Host and count its actual shared Compute entry.
// Source I/O is local DuckDB; Effect dispatch is a reference Site, not an org.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const scratch = join(repository, '_build', 'acquired-effect-compute-probe');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'run-'));
const cases = [
  'acquired Effect waits durably and resumes through the public Host',
  'acquired Effect preserves unknown across Host restart',
  'acquired Effect cancel retires upstream payloads after restart',
  'acquired Effect reject retires upstream payloads after restart',
  'a missing acquired input rejects only its Run after Host restart',
  'a corrupt acquired input rejects only its Run after Host restart',
];
for (const [index, name] of cases.entries()) {
const log = join(root, `calls-${index}.txt`);
await writeFile(log, '');
const args = nodeTestArguments([
  '--experimental-test-module-mocks', '--import',
  new URL('./fixtures/effect-computation-probe-preload.mjs', import.meta.url).href,
  '--test', '--test-name-pattern', `^${name}$`,
  'adapters/host-node/remote-checkpoint-host.test.mjs',
]);
const result = spawnSync(process.execPath, args, {cwd: repository, encoding: 'utf8', timeout: 120_000,
  env: {...process.env,
    ACTQL_TEST_EFFECT_ENTRY:
      new URL('../adapters/host-node/entry.mjs', import.meta.url).href,
    ACTQL_TEST_ACQUIRED_SOURCE_ENTRY:
      new URL('../adapters/host-node/captured-duckdb-source.mjs', import.meta.url).href,
    ACTQL_TEST_EFFECT_CALL_LOG: log}});
assertTestExecution('node', process.execPath, args, result);
const events = (await readFile(log, 'utf8')).trim().split('\n');
assert.ok(events.includes('probe'), 'the actual Host entry must be wrapped');
assert.ok(events.includes('source-probe'), 'the actual Source entry must be wrapped');
assert.equal(events.filter(event => event === 'source').length, 1,
  'initial acquisition must run; recovery must not reacquire Source input');
assert.equal(events.filter(event => event === 'compute').length, 1,
  'initial Compute must run; approval and terminal restarts must not recompute');
console.log(`${name}: initial Source/Compute 1, restart Source/Compute 0`);
}
