import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Exercise the real CLI orchestration with instrumented execution boundaries.
// Actual compiler/oracle coverage remains in the complete pipeline-evidence job.
function run(mode, { required = true, fail = null } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'actql-pipeline-mutations-'));
  const fixture = new URL('./fixtures/mutation-driver.mjs', import.meta.url);
  const result = spawnSync(process.execPath, ['--experimental-test-module-mocks', fileURLToPath(fixture),
    mode, root, JSON.stringify({ required, fail })], { encoding: 'utf8' });
  try {
    return { ...result, state: JSON.parse(readFileSync(join(root, 'state.json'), 'utf8')) };
  } finally { rmSync(root, { recursive: true, force: true }); }
}

test('combined verification preserves every fixed/fresh and restored target execution', () => {
  const result = run('verify');
  assert.equal(result.status, 0, result.stderr);
  const { calls, reports, source } = result.state;
  assert.equal(source, 'healthy');
  for (const variant of ['first', 'second']) {
    const actual = calls.filter(call => call.variant === variant);
    assert.deepEqual(actual.map(call => call.label), [
      `${variant}-fixed`, `${variant}-fixed`, `${variant}-fixed`,
      `${variant}-search`, `${variant}-shrink`,
      `${variant}-minimal`, `${variant}-minimal`, `${variant}-minimal`,
      ...Array(6).fill(`${variant}-restored`),
    ]);
    assert(actual.slice(0, 8).every(call => call.source === variant));
    assert(actual.slice(8).every(call => call.source === 'healthy'));
    for (const label of ['fixed', 'minimal']) {
      assert.deepEqual(actual.filter(call => call.label === `${variant}-${label}`).map(call => call.target),
        ['js', 'wasm', 'native']);
    }
    assert.deepEqual(actual.slice(8).map(call => call.target), ['js', 'wasm', 'native', 'js', 'wasm', 'native']);
  }
  assert.deepEqual(Object.keys(reports).sort(), ['fixed-mutations.json', 'mutations.json']);
  for (const mode of ['fixed', 'explore']) {
    const report = reports[mode === 'fixed' ? 'fixed-mutations.json' : 'mutations.json'];
    assert.equal(report.mode, mode);
    assert.deepEqual(report.results.map(result => result.name), ['first', 'second']);
    assert(report.results.every(result => result.localMinimal === (mode === 'explore')));
    assert(report.results.every(result => result.executions.length === (mode === 'fixed' ? 3 : 5)));
    assert(report.results.every(result => result.healthyExecutions.length === 3));
  }
  const receipts = Object.values(reports).flatMap(report => report.results.flatMap(result =>
    [...result.executions, ...result.healthyExecutions].map(execution => execution.path)));
  assert.equal(new Set(receipts).size, receipts.length, 'No execution receipt is reused across obligations');
});

test('reviewed non-impactful changes still run fixed mutated/restored checks on all targets', () => {
  const result = run('verify', { required: false });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(Object.keys(result.state.reports), ['fixed-mutations.json']);
  assert.equal(result.state.calls.length, 12);
  assert(result.state.calls.every(call => /-(fixed|restored)$/.test(call.label)));
});

for (const mode of ['fixed', 'explore', 'auto']) {
  test(`existing ${mode} mode retains its report and executions`, () => {
    const result = run(mode);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(Object.keys(result.state.reports), [mode === 'fixed' ? 'fixed-mutations.json' : 'mutations.json']);
  });
}

test('auto retains its reviewed exploration skip', () => {
  const result = run('auto', { required: false });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.state.calls.length, 0);
  assert.deepEqual(result.state.reports, {});
});

for (const fail of ['first-fixed:wasm', 'first-search:js', 'first-shrink:js', 'first-minimal:native', 'first-restored:wasm', 'first-restored:wasm:2']) {
  test(`failure at ${fail} stops verification, restores source and writes no success reports`, () => {
    const result = run('verify', { fail });
    assert.notEqual(result.status, 0);
    assert.equal(result.state.source, 'healthy');
    assert.deepEqual(result.state.reports, {});
    assert(result.state.calls.every(call => call.variant === 'first'));
  });
}
