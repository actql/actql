import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {installModelProviders} from './installed-model.mjs';

for (const mode of ['eager', 'static-only']) {
  test(`private installed eager SDK predicate preserves same original ${mode}`, () => {
    const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
    const entry = fileURLToPath(new URL('../../packages/provider-ai-sdk/sdk-eager-installation.fixture.mjs', import.meta.url));
    const result = spawnSync(process.execPath,
      [...(mode === 'eager' ? ['--no-lazy'] : []), '--require', preload, entry, mode],
      {env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 15000,
        maxBuffer: 1024 * 1024});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout.trim()), {mode, constructors: 1,
      checked: true, actualHost: false, actualCore: false, providerCalls: 0,
      normalNumericProfile: null, publicE2E: 0});
  });
}
test('generic registration has no fabricated eager startup predicate', () => {
  const entry = {providerId: 'fixture', invoke() { assert.fail('No Provider'); },
    validatePrompt() { return true; }};
  const installed = installModelProviders({clientProgramInstallModelProvider() { return {}; }},
    () => [entry]).get('fixture');
  assert.equal(installed.requireEagerSdkStartup, undefined);
});
