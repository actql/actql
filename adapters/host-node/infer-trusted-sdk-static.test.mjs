import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const fixture = fileURLToPath(new URL('./infer-trusted-sdk-static.fixture.mjs', import.meta.url));
for (const mode of ['current', 'foreign', 'registration', 'late']) {
  test(`selected SDK static module responsibility: ${mode}`, () => {
    const result = spawnSync(process.execPath,
      [...(mode === 'late' ? [] : ['--require', preload]), fixture, mode], {
        env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 10000,
        maxBuffer: 1024 * 1024,
      });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout.trim()), {mode, checked: true,
      providerCalls: 0, physicalAcks: 0, actualCore: false,
      normalNumericProfile: null, publicE2E: 0});
  });
}
for (const value of ['', 'synthetic-unsupported-startup-input']) {
  test(`selected preload rejects a ${value === '' ? 'present empty' : 'nonempty'} ambient SDK input before entry imports`, () => {
    const entry = fileURLToPath(new URL('./infer-trusted-sdk-entry.fixture.mjs', import.meta.url));
    const result = spawnSync(process.execPath, ['--require', preload, entry], {
      env: {PATH: process.env.PATH, OPENAI_BASE_URL: value},
      encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /InferTrustedStartupUnavailable/u);
    assert.equal(result.stderr.includes('synthetic-unsupported-startup-input'), false);
  });
}
