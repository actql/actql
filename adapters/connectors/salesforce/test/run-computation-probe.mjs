// Count the actual shared Compute entry in unchanged restart acceptance tests.
// This is simulated HTTPS Salesforce, not real-org evidence.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertTestExecution, nodeTestArguments} from '../../../../scripts/test-execution.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'effect-computation-probe');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'run-'));
const preload = new URL('../../../../scripts/fixtures/' +
  'effect-computation-probe-preload.mjs', import.meta.url).href;
const entry = new URL('../../../host-node/entry.mjs', import.meta.url).href;
const installed =
  'adapters/connectors/salesforce/test/installed-salesforce-effect-recovery.test.mjs';
// Read→Compute→Effect through the Remote HTTP Host, whose restarts run in
// the test process: each case acquires and computes once, and no restart
// computes again.
const acquired =
  'adapters/connectors/salesforce/test/read-compute-effect.acceptance.test.mjs';
const cases = [
  [installed, 'a restart after a partial apply sends only the unsent rows'],
  [installed, 'an unknown row is never resent after a restart'],
  [acquired, 'Read→Compute→Effect previews, waits across a restart, ' +
    'writes once and publishes'],
  [acquired, 'a reply lost after the org applied the write is unknown and ' +
    'never resent'],
  [acquired, 'halt: applied, then a definite failure, and the rest never ' +
    'sent'],
];
const pattern = name => `^${name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&')}$`;
for (const [index, [file, name]] of cases.entries()) {
  const log = join(root, `calls-${index}.txt`);
  await writeFile(log, '');
  const args = nodeTestArguments([
    '--experimental-test-module-mocks', '--import', preload,
    '--test-name-pattern', pattern(name), file,
  ]);
  const result = spawnSync(process.execPath, args,
    {cwd: repository, encoding: 'utf8', timeout: 180_000,
    env: {...process.env, ACTQL_TEST_EFFECT_ENTRY: entry,
      ACTQL_TEST_EFFECT_CALL_LOG: log}});
  const checked = assertTestExecution('node', process.execPath, args, result);
  assert.equal(checked.counts.passed, 1,
    `${name}: the original restart case must execute exactly once`);
  const events = (await readFile(log, 'utf8')).trim().split('\n');
  assert.ok(events.includes('probe'), 'the real Host probe must be loaded');
  assert.equal(events.filter(event => event === 'compute').length, 1,
    `${name}: initial Compute must run once; restart must not recompute`);
  console.log(`${name}: initial Compute 1, recovery Compute 0`);
}
