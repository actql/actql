// Count the actual shared Compute entry in unchanged restart acceptance tests.
// This is simulated HTTPS Salesforce, not real-org evidence.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'effect-computation-probe');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'run-'));
const preload = new URL('../../../../scripts/fixtures/' +
  'effect-computation-probe-preload.mjs', import.meta.url).href;
const entry = new URL('../../../host-node/entry.mjs', import.meta.url).href;
const cases = [
  'a restart after a partial apply sends only the unsent rows',
  'an unknown row is never resent after a restart',
];
for (const [index, name] of cases.entries()) {
  const log = join(root, `calls-${index}.txt`);
  await writeFile(log, '');
  const result = spawnSync(process.execPath, [
    '--experimental-test-module-mocks', '--import', preload,
    '--test', '--test-name-pattern', `^${name}$`,
    'adapters/connectors/salesforce/test/installed-salesforce-effect.test.mjs',
  ], {cwd: repository, encoding: 'utf8', timeout: 120_000,
    env: {...process.env, ACTQL_TEST_EFFECT_ENTRY: entry,
      ACTQL_TEST_EFFECT_CALL_LOG: log}});
  assert.equal(result.status, 0,
    `${name}: ${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  const events = (await readFile(log, 'utf8')).trim().split('\n');
  assert.ok(events.includes('probe'), 'the real Host probe must be loaded');
  assert.equal(events.filter(event => event === 'compute').length, 1,
    `${name}: initial Compute must run once; restart must not recompute`);
  console.log(`${name}: initial Compute 1, recovery Compute 0`);
}
