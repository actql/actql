import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
test('capacity consumer rejects a weakened upper bound even with the theorem name present', () => {
  const model = readFileSync(new URL('Capacity.lean', import.meta.url), 'utf8');
  const start = model.indexOf('theorem live_chain_bound ');
  const end = model.indexOf('-- Cleanup pending', start);
  assert.ok(start > 0 && end > start);
  const changed = model.slice(0, start) + 'theorem live_chain_bound : True := by trivial\n\n' + model.slice(end);
  const claims = readFileSync(new URL('Claims.lean', import.meta.url), 'utf8');
  const result = spawnSync('lean', ['--stdin'], { cwd: fileURLToPath(new URL('.', import.meta.url)), input: changed + '\n' + claims, encoding: 'utf8' });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /function expected|type mismatch/i);
});
