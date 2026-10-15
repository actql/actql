import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

test('admitted original Run retains its same cleanup custody after late startup loss before Scope', t => {
  const preload = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
  const fixture = fileURLToPath(new URL('./infer-trusted-startup-scope.fixture.mjs', import.meta.url));
  const coverage = mkdtempSync(join(tmpdir(), 'actql-a-late-startup-coverage-'));
  t.diagnostic(`Original coverage retained: ${coverage}`);
  const result = spawnSync(process.execPath, ['--require', preload, fixture, 'late-current'], {
    env: {PATH: process.env.PATH, NODE_V8_COVERAGE: coverage}, timeout: 25000,
    encoding: 'utf8', maxBuffer: 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  const actual = JSON.parse(result.stdout.trim());
  assert.equal(actual.lateCurrentLoss, true);
  assert.equal(actual.invalidations, 1);
  assert.equal(actual.actualHost, true);
  assert.equal(actual.actualCoreScope, 0);
  assert.equal(actual.providerCalls, 0);
  assert.equal(actual.preflights, 0);
  assert.equal(actual.normalNumericProfile, null);
  assert.equal(actual.publicE2E, 0);
});
