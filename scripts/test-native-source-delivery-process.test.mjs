// Actual Native processes, selected from compiler-generated test metadata.
// This does not substitute for public Local CLI recovery or package acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';

test('Actual Native Source delivery returns to original Run in exited-process metadata lookup and explicit rereads', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-source-delivery-process-',
    label: 'Actual Native Source delivery process handoff'});
  const folder = join(root, '_build/native/debug/test/platform_native/remote_resident_source_compute_tests');
  const binary = join(folder, 'remote_resident_source_compute_tests.whitebox_test.exe');
  const file = 'local_client_delivery_process_wbtest.mbt';
  const info = JSON.parse(readFileSync(join(folder, '__whitebox_test_info.json'), 'utf8'));
  const cases = info.tests[file];
  assert.equal(cases.length, 1);
  assert.equal(cases[0].name, 'Native actual Source delivery survives exited writer and original Submission readers');
  const sha256 = createHash('sha256').update(readFileSync(binary)).digest('hex');
  const receipts = [];
  for (const [index, phase] of ['write', 'read', 'read'].entries()) {
    const args = [`${file}:${cases[0].index}-${cases[0].index + 1}`];
    const startedAt = new Date().toISOString();
    const result = spawnSync(binary, args, {cwd: scratch.path,
      env: {...process.env, ACTQL_TEST_NATIVE_STORE_ROOT: scratch.path,
        ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: scratch.path,
        ACTQL_TEST_NATIVE_SOURCE_DELIVERY_PHASE: phase,
        ACTQL_TEST_NATIVE_SOURCE_DELIVERY_READ_ID: `explicit-reread-${index}`},
      encoding: 'utf8', timeout: 30_000, maxBuffer: 2 * 1024 * 1024});
    const receipt = {phase, pid: result.pid, startedAt, exitedAt: new Date().toISOString(),
      status: result.status, signal: result.signal, command: [binary, ...args], sha256,
      stdout: result.stdout ?? '', stderr: result.stderr ?? ''};
    receipts.push(receipt);
    writeFileSync(join(scratch.path, 'process-receipts.json'), JSON.stringify(receipts, null, 2) + '\n');
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
  }
  assert.equal(new Set(receipts.map(receipt => receipt.pid)).size, 3);
  console.log('Native Source delivery process receipts: ' + join(scratch.path, 'process-receipts.json'));
  scratch.passed();
});
