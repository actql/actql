import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const entry = fileURLToPath(new URL('../../packages/provider-ai-sdk/sdk-static-host.fixture.mjs', import.meta.url));
for (const route of ['generic', 'Undici']) {
  test(`actual installed Host retains the selected eager SDK callback for ${route}`, () => {
    const result = spawnSync(process.execPath,
      ['--no-lazy', '--require', preload, entry, route], {
        env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 25000,
        maxBuffer: 1024 * 1024,
      });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout.trim()), {route, callbacks: 2,
      hostClosed: true, providerCalls: 0, coreScopes: 0,
      normalNumericProfile: null, publicE2E: 0});
  });
}
