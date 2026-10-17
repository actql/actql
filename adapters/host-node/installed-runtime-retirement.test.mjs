import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const fixture = fileURLToPath(new URL('./fixtures/installed-runtime-retirement.fixture.mjs', import.meta.url));
for (const mode of ['frozen-primary', 'readonly-handle', 'partial-finalization']) {
  test(`installed Host retains original runtime cleanup after ${mode}`, t => {
    const child = spawnSync(process.execPath, ['--experimental-test-module-mocks', fixture, mode], {
      env: {...process.env, ACTQL_TEST_PRESERVE_SCRATCH: '1'},
      encoding: 'utf8', timeout: 30000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024,
    });
    assert.equal(child.error, undefined);
    assert.equal(child.signal, null);
    assert.equal(child.status, 0, child.stderr);
    const report = JSON.parse(child.stdout.trim());
    t.diagnostic(`Original runtime cleanup counter: ${report.scratch}`);
    assert.equal(report.mode, mode);
    assert.equal(report.checked, true);
    assert.equal(report.providerCalls, 0);
    assert.equal(report.commonScopes, 0);
    assert.equal(report.publicE2E, 0);
  });
}
