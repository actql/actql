import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { mutationNamesByPart } from './proof-parts.mjs';

// Exercise the real CLI orchestration with instrumented execution boundaries.
// Actual compiler/oracle coverage remains in the complete pipeline-evidence job.
function run(mode, { required = true, fail = null, part = null } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'actql-pipeline-mutations-'));
  const fixture = new URL('./fixtures/mutation-driver.mjs', import.meta.url);
  const result = spawnSync(process.execPath, ['--experimental-test-module-mocks', fileURLToPath(fixture),
    mode, root, JSON.stringify({ required, fail, part })], { encoding: 'utf8' });
  try {
    return { ...result, state: JSON.parse(readFileSync(join(root, 'state.json'), 'utf8')) };
  } finally { rmSync(root, { recursive: true, force: true }); }
}

test('combined verification preserves every fixed/fresh and restored target execution', () => {
  const result = run('verify');
  assert.equal(result.status, 0, result.stderr);
  const { calls, reports, source } = result.state;
  assert.equal(source, 'healthy');
  assert.equal(result.state.mutable, 'healthy');
  for (const variant of ['first', 'second']) {
    const actual = calls.filter(call => call.variant === variant);
    assert.deepEqual(actual.map(call => call.label), [
      `${variant}-fixed`, `${variant}-fixed`, `${variant}-fixed`,
      `${variant}-search`, `${variant}-shrink`,
      `${variant}-minimal`, `${variant}-minimal`, `${variant}-minimal`,
      ...Array(6).fill(`${variant}-restored`),
      ...Array(3).fill(`${variant}-fixed-post-restore`), ...Array(3).fill(`${variant}-explore-post-restore`),
    ]);
    assert(actual.slice(0, 8).every(call => call.source === variant && call.workspace === 'mutable'));
    assert(actual.slice(8, 14).every(call => call.source === 'healthy' && call.workspace === 'pristine'));
    assert(actual.slice(14).every(call => call.source === 'healthy' && call.workspace === 'mutable' && call.owner === 'restoration'));
    for (const label of ['fixed', 'minimal']) {
      assert.deepEqual(actual.filter(call => call.label === `${variant}-${label}`).map(call => call.target),
        ['js', 'wasm', 'native']);
    }
    assert.deepEqual(actual.slice(8, 14).map(call => call.target), ['js', 'wasm', 'native', 'js', 'wasm', 'native']);
  }
  assert.deepEqual(Object.keys(reports).sort(), ['fixed-mutations.json', 'mutations.json']);
  for (const mode of ['fixed', 'explore']) {
    const report = reports[mode === 'fixed' ? 'fixed-mutations.json' : 'mutations.json'];
    assert.equal(report.mode, mode);
    assert.deepEqual(report.results.map(result => result.name), ['first', 'second']);
    assert(report.results.every(result => result.localMinimal === (mode === 'explore')));
    assert(report.results.every(result => result.executions.length === (mode === 'fixed' ? 3 : 5)));
    assert(report.results.every(result => result.healthyExecutions.length === 3));
    assert(report.results.every(result => result.postRestore.executions.length === 3));
  }
  const receipts = Object.values(reports).flatMap(report => report.results.flatMap(result =>
    [...result.executions, ...result.healthyExecutions, ...result.postRestore.executions].map(execution => execution.path)));
  assert.equal(new Set(receipts).size, receipts.length, 'No execution receipt is reused across obligations');
});

test('reviewed non-impactful changes still run fixed mutated/restored checks on all targets', () => {
  const result = run('verify', { required: false });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(Object.keys(result.state.reports), ['fixed-mutations.json']);
  assert.equal(result.state.calls.length, 18);
  assert(result.state.calls.every(call => /-(fixed|restored|post-restore)$/.test(call.label)));
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
    assert.equal(result.state.mutable, 'healthy');
    assert.deepEqual(result.state.reports, {});
    assert(result.state.calls.every(call => call.variant === 'first'));
  });
}

test('source restoration failure stops before healthy replay or success reports', () => {
  const result = run('verify', { fail: 'source-restore' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Source not restored exactly/);
  assert.equal(result.state.source, 'healthy');
  assert.equal(result.state.mutable, 'healthy');
  assert(result.state.calls.every(call => call.workspace === 'mutable' && call.variant === 'first'));
  assert.deepEqual(result.state.reports, {});
});

for (const part of Object.keys(mutationNamesByPart)) {
  test(`${part} owns exactly its four fixed/fresh variants and fresh restored-source owner`, () => {
    const result = run('verify', { part });
    assert.equal(result.status, 0, result.stderr);
    const { calls, reports, lifecycle } = result.state;
    assert.deepEqual(Object.keys(reports).sort(), [`fixed-mutations-${part}.json`, `mutations-${part}.json`]);
    for (const report of Object.values(reports)) {
      assert.deepEqual(report.results.map(r => r.name), mutationNamesByPart[part]);
      assert(report.results.every(r => r.owner === part));
      assert.equal(report.restorationOwner.root, report.workspaces.mutable.root);
      assert.notEqual(report.restorationOwner.id, report.workspaces.mutable.id);
      assert.deepEqual(report.closure, { mutable: true, pristine: true, restoration: true, sourceRestored: true });
    }
    assert.equal(calls.length, 4 * (3 + 5 + 6 + 6));
    assert.deepEqual(lifecycle.map(e => `${e.kind}:${e.id}`),
      ['create:mutable', 'create:pristine', 'close:mutable', 'close:pristine', 'create:restoration', 'close:restoration']);
    assert.equal(lifecycle.find(e => e.kind === 'create' && e.id === 'restoration').source, 'healthy');
    assert(calls.filter(c => c.label.endsWith('post-restore')).every(c => c.owner === 'restoration'));
  });
  test(`${part} reviewed non-impactful changes omit fresh mode without omitting restored fixed minima`, () => {
    const result = run('verify', { part, required: false });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(Object.keys(result.state.reports), [`fixed-mutations-${part}.json`]);
    assert.equal(result.state.calls.length, 4 * 9);
  });
}
for (const fail of ['first-fixed-post-restore:wasm', 'first-explore-post-restore:native', 'mutable-close', 'pristine-close', 'restoration-close']) {
  test(`new-owner restoration or close failure ${fail} prevents success reports`, () => {
    const result = run('verify', { fail });
    assert.notEqual(result.status, 0);
    assert.equal(result.state.source, 'healthy');
    assert.equal(result.state.mutable, 'healthy');
    assert.deepEqual(result.state.reports, {});
    if (fail === 'mutable-close' || fail === 'pristine-close') {
      assert(!result.state.lifecycle.some(e => e.kind === 'create' && e.id === 'restoration'));
    }
  });
}
