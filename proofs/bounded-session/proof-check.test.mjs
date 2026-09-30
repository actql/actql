import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test('Lean rejects an existing theorem name with a weakened proposition', () => {
  const model = readFileSync(new URL('Session.lean', import.meta.url), 'utf8');
  const claims = readFileSync(new URL('Claims.lean', import.meta.url), 'utf8');
  const original = '(delta before after).work ≤ quantum ∧ after.work ≤ limit := by\n  exact ⟨h.2.2.2.1, h.2.2.2.2.2⟩';
  assert.equal(model.split(original).length, 2);
  const changed = model.replace(original, 'True := by\n  trivial');
  const result = spawnSync('lean', ['--stdin'], {
    cwd: fileURLToPath(new URL('.', import.meta.url)), input: `${changed}\n${claims}\n`, encoding: 'utf8',
  });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/i);
});
