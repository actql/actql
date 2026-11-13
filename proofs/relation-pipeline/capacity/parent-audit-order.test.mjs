import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Fresh child/module namespace per ordering control, using the existing test
// mock mechanism only for the two parent boundaries. No validator stub is used.
for (const [mode, title] of [
  ['invalid-corpus', 'invalid generic corpus refuses before either Native parent boundary'],
  ['healthy', 'otherwise-valid synthetic support calls both parent boundaries before success'],
  ['parent-refusal', 'the unchanged original parent validator still refuses an invalid receipt'],
  ['substitution-refusal', 'parent substitution failure cannot become audit success'],
  ['portable', 'portable foreign-parent refusal stays before generic corpus work'],
]) test(title, () => {
  const result = spawnSync(process.execPath, ['--experimental-test-module-mocks',
    fileURLToPath(new URL('../fixtures/parent-audit-order.mjs', import.meta.url)), mode],
  { encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.signal, null);
  assert.equal(JSON.parse(result.stdout.trim()).mode, mode);
});
