// Focused synthetic diagnostics for audit setup sharing and case isolation.
// These never establish actual MoonBit execution or replace hosted proof checks.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

function run(scenario) {
  const root = mkdtempSync(join(tmpdir(), 'actql-synthetic-audit-batch-'));
  try {
    const result = spawnSync(process.execPath, ['--experimental-test-module-mocks',
      fileURLToPath(new URL('./fixtures/audit-batch-driver.mjs', import.meta.url)), root, scenario],
    { encoding: 'utf8', timeout: 20_000, maxBuffer: 2 * 1024 * 1024 });
    assert.ifError(result.error);
    assert(Number.isInteger(result.status), `Synthetic driver did not exit normally: ${result.signal}`);
    return result;
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
function accepted(scenario) {
  const result = run(scenario);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const summary = result.stdout.split('\n').find(line => line.startsWith('SYNTHETIC_AUDIT_BATCH:'));
  assert(summary, 'Synthetic driver did not reach its assertions');
  return { ...result, summary: JSON.parse(summary.slice('SYNTHETIC_AUDIT_BATCH:'.length)) };
}

test('importing the general audit performs no preparation or artifact reads', () => {
  accepted('import-only');
});
test('one preparation supports repeated and reversed audits with fresh receipt and observation identities', () => {
  accepted('repeated-and-reversed');
});
test('prepared source and decision are detached from mutable preparation results', () => {
  accepted('detached-preparation');
});
test('a prior successful audit revalidates changed archived artifact bytes', () => {
  accepted('revalidate-artifacts');
});
for (const stage of ['baseline', 'foundation', 'snapshot', 'decision']) {
  test(`mandatory ${stage} preparation failure stops the factory`, () => {
    accepted(`setup-failure-${stage}`);
  });
}
test('target regression batch prepares once and preserves repeated/reversed target rejections', () => {
  accepted('batch-targets');
});
test('ordinary audit CLI retains successful three-target checks', () => {
  const { stdout } = accepted('cli-healthy');
  for (const target of ['js', 'wasm', 'native']) assert(stdout.includes(`${target}: exact normal corpus`));
});
test('target regression CLI accepts only expected target-binding rejections', () => {
  const { stdout } = accepted('cli-targets');
  const { results: result, preparation } = JSON.parse(stdout.split('\n').find(line => line.startsWith('{')));
  assert.deepEqual(Object.keys(preparation), ['baselineMs', 'foundationMs', 'snapshotMs', 'decisionMs']);
  assert.deepEqual(result.map(entry => entry.name), ['native-in-js-slot', 'native-in-wasm-slot', 'native-in-base-js-slot']);
  assert(result.every(entry => entry.rejected === true && !Object.hasOwn(entry, 'exit')));
});
for (const [scenario, reason] of [
  ['cli-admitted-negative', /Audit accepted|accepted unexpectedly|unexpectedly-healthy|admitted/i],
  ['cli-wrong-rejection', /Wrong rejection|unrelated|requested audit target js/i],
  ['cli-preparation-failure', /Synthetic foundation preparation failure/],
]) {
  test(`target regression CLI exits nonzero for ${scenario.replace('cli-', '')}`, () => {
    const result = run(scenario);
    assert.notEqual(result.status, 0, `${scenario} was admitted`);
    assert.match(result.stderr, reason);
    assert(!result.stdout.includes('SYNTHETIC_AUDIT_BATCH:'), 'Failed CLI returned successfully');
  });
}
