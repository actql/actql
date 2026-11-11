import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {assertTestExecution, nodeTestArguments} from '../../scripts/test-execution.mjs';
import {assertPartialEffectSeedExit} from './fixtures/effect-crash-evidence.mjs';
import './effect-crash-evidence.test.mjs';

const scratch = new URL('../../_build/effect-partial-refusal/', import.meta.url);
const childFile = fileURLToPath(new URL('./remote-checkpoint-host.test.mjs', import.meta.url));
await mkdir(scratch, {recursive: true});
const cases = [
  ['applied', 'none'], ['applied', 'answer_deadline'],
  ...['prepared', 'applied', 'accepted', 'unknown'].flatMap(state =>
    ['read', 'commit', 'guard'].map(refusal => [state, refusal])),
];

test('failed reference Effect constructor keeps its real token through same cleanup retry', async t => {
  const root = await mkdtemp(join(scratch.pathname, 'constructor-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const hostRoot = join(root, 'host');
  await mkdir(hostRoot);
  const keys = Object.fromEntries(['reviewer', 'host'].map(name => [name,
    generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'})]));
  const keyPath = join(root, 'keys.json');
  await writeFile(keyPath, JSON.stringify(keys), {mode: 0o600});
  const args = nodeTestArguments(['--test', '--test-name-pattern',
    '^partial Effect historical refusal crash fixture$', childFile]);
  const {NODE_TEST_CONTEXT: _outerContext, ...childEnvironment} = process.env;
  const result = spawnSync(process.execPath, args, {
    cwd: new URL('../../', import.meta.url), encoding: 'utf8', timeout: 45_000,
    env: {...childEnvironment, ACTQL_TEST_HOST_CRASH_ROOT: hostRoot,
      ACTQL_TEST_HOST_CRASH_KEYS: keyPath, ACTQL_TEST_PARTIAL_EFFECT_PHASE: 'constructor_failure',
      ACTQL_TEST_PARTIAL_EFFECT_ROW: 'applied', ACTQL_TEST_PARTIAL_EFFECT_REFUSAL: 'none'},
  });
  assertTestExecution('node', process.execPath, args, result);
});

for (const [rowState, refusal] of cases) {
  test(`restarted ${rowState} Effect preserves its row partition on ${refusal} refusal`, async t => {
    const root = await mkdtemp(join(scratch.pathname, 'run-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const hostRoot = join(root, 'host');
    await mkdir(hostRoot);
    const keys = Object.fromEntries(['reviewer', 'host'].map(name => [name,
      generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'})]));
    const keyPath = join(root, 'keys.json');
    await writeFile(keyPath, JSON.stringify(keys), {mode: 0o600});
    const args = nodeTestArguments(['--test', '--test-name-pattern',
      '^partial Effect historical refusal crash fixture$',
      childFile]);
    const {NODE_TEST_CONTEXT: _outerContext, ...childEnvironment} = process.env;
    const run = phase => spawnSync(process.execPath, args, {
      cwd: new URL('../../', import.meta.url), encoding: 'utf8', timeout: 45_000,
      env: {...childEnvironment, ACTQL_TEST_HOST_CRASH_ROOT: hostRoot,
        ACTQL_TEST_HOST_CRASH_KEYS: keyPath, ACTQL_TEST_PARTIAL_EFFECT_PHASE: phase,
        ACTQL_TEST_PARTIAL_EFFECT_ROW: rowState, ACTQL_TEST_PARTIAL_EFFECT_REFUSAL: refusal},
    });
    const seed = run('seed');
    assertPartialEffectSeedExit(seed, childFile);
    const seeded = JSON.parse(await readFile(join(hostRoot, 'partial-effect-seed.json'), 'utf8'));
    assert.deepEqual(seeded.states, [{prepared: 0, applied: 2, accepted: 3, unknown: 5}[rowState], 0]);
    assert.equal(seeded.started, true);
    const recovery = run('recover');
    let observed;
    try { observed = JSON.parse(await readFile(join(hostRoot, 'partial-effect-result.json'), 'utf8')); }
    catch {}
    t.diagnostic(JSON.stringify({rowState, refusal, seeded: seeded.states,
      state: observed?.state.status, sends: observed?.sends,
      receipts: observed?.receipts.map(receipt => receipt.status),
      durableStates: observed?.durableStates, captureCount: observed?.captureCount}));
    assertTestExecution('node', process.execPath, args, recovery);
  });
}
