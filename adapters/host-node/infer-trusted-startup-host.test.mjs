import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const fixture = fileURLToPath(new URL('./infer-trusted-startup-host.fixture.mjs', import.meta.url));
for (const phase of ['open-close', 'schema', 'prepare']) {
  test(`selected real startup carries its original through installed Host ${phase}`, () => {
    const result = spawnSync(process.execPath, ['--require', preload, fixture, phase], {
      env: {PATH: process.env.PATH}, timeout: 25000, encoding: 'utf8', maxBuffer: 1024 * 1024,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout.trim()), {phase, registrations: phase === 'open-close' ? 2 : 3,
      checked: true, realHost: true, realSqlite: true, providerCalls: 0, realCoreScopes: 0, publicE2E: 0});
  });
}
