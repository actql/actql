import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('selected stock startup preserves the original pinned SDK raw-only loopback caller', () => {
  const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
  const fixture = fileURLToPath(new URL('./infer-trusted-startup-sdk.fixture.mjs', import.meta.url));
  const result = spawnSync(process.execPath, ['--require', preload, fixture], {
    env: {PATH: process.env.PATH}, timeout: 25000, encoding: 'utf8', maxBuffer: 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {requests: 1, rawComplete: true,
    sdkRetired: true, cleanup: true, actualCommonEntry: false, actualStore: false,
    normalNumericProfile: null, publicE2E: 0});
});
