// Actual Native processes exercise the original SQLite journal, not a Node
// Host or CLI fallback. Run through the existing bounded heavy supervisor.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {nativeClientCheckpointFixture} from './native-client-checkpoint-fixture.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

test('Original Native saved response survives exited writer and repeated independent readers', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-response-process-',
    label: 'Original Native Effect response process handoff'});
  const env = {...process.env, ACTQL_TEST_NATIVE_SQLITE_ROOT: scratch.path};
  Object.assign(env, nativeClientCheckpointFixture(root, env));
  const folder = join(root, '_build/native/debug/test/platform_native/client_host');
  const binary = join(folder, 'client_host.whitebox_test.exe');
  const file = 'run_effect_response_process_wbtest.mbt';
  const info = JSON.parse(readFileSync(join(folder, '__whitebox_test_info.json'), 'utf8'));
  const cases = info.tests[file];
  assert.equal(cases.length, 1, 'Select the actual generated Native case, never all tests');
  assert.equal(cases[0].name,
    'Native saved Effect response handoff reads original custody without preparation or dispatch');
  const sha256 = createHash('sha256').update(readFileSync(binary)).digest('hex');
  const receipts = [];
  for (const phase of ['write', 'read', 'read']) {
    // This is the selected pinned moon Native runner protocol. Only this one
    // generated file/index is executed; the actual Native PID must exit before
    // another process can reopen the original custody.
    const args = [`${file}:${cases[0].index}-${cases[0].index + 1}`];
    const startedAt = new Date().toISOString();
    const result = spawnSync(binary, args, {cwd: root,
      env: {...env, ACTQL_TEST_NATIVE_EFFECT_RESPONSE_PHASE: phase},
      encoding: 'utf8', timeout: 15_000, maxBuffer: 1024 * 1024});
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    const records = result.stdout.split(/\r?\n/u).filter(line => line.startsWith('{'))
      .map(line => JSON.parse(line)).filter(record => record.type === 'result');
    assert.equal(records.length, 1, result.stdout);
    assert.equal(records[0].file, file);
    assert.equal(records[0].index, cases[0].index);
    assert.equal(records[0].message, '', result.stdout);
    assert(Number.isSafeInteger(result.pid) && result.pid > 0);
    receipts.push({phase, pid: result.pid, startedAt, exitedAt: new Date().toISOString(),
      status: result.status, signal: result.signal, command: [binary, ...args], sha256});
  }
  assert.equal(new Set(receipts.map(receipt => receipt.pid)).size, 3);
  writeFileSync(join(scratch.path, 'process-receipts.json'), JSON.stringify(receipts, null, 2) + '\n');
  console.log('Native original response process receipts: ' + join(scratch.path, 'process-receipts.json'));
  await scratch.passed();
});
