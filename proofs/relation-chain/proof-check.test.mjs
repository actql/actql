import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test('Lean rejects an existing theorem name with a weakened proposition', () => {
  const model = readFileSync(new URL('Chain.lean', import.meta.url), 'utf8');
  const claims = readFileSync(new URL('Claims.lean', import.meta.url), 'utf8');
  const original = 'theorem handoff_budget_not_reset (s : State) (started : Bool) :\n    (handoff s started).used = s.used + 1 ∧\n    remaining (handoff s started) = s.budget - (s.used + 1) := by\n  cases started <;> simp [handoff, charge, remaining]';
  assert.equal(model.split(original).length, 2);
  const changed = model.replace(original, 'theorem handoff_budget_not_reset (s : State) (started : Bool) : True := by trivial');
  const session = readFileSync(new URL('../bounded-session/Session.lean', import.meta.url), 'utf8');
  const result = spawnSync('lean', ['--stdin'], {
    cwd: fileURLToPath(new URL('.', import.meta.url)), input: `${session}\n${changed}\n${claims}\n`, encoding: 'utf8',
  });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/i);
});
