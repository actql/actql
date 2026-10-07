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

test('executed chain checker admits both original and stop-inclusive typed laws', () => {
  const result = spawnSync(process.execPath, ['check.mjs'], {
    cwd: fileURLToPath(new URL('.', import.meta.url)), encoding: 'utf8', timeout: 60000,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /Checked 50 theorems, expected claim types and axiom dependencies/);
});

for (const [label, theorem, replacement] of [
  ['terminal stop work omitted', 'stop_poll_reporting',
    'theorem stop_poll_reporting (s : State) (work : Nat) (done : Bool) : True := by trivial'],
  ['stop request treated as physical stop', 'request_not_stopped',
    'theorem request_not_stopped (s : State) : True := by trivial'],
  ['productive budget guarantee omitted', 'chain_accounting',
    'theorem chain_accounting (budget : Nat) (t : State) (run : Run (initial budget) t) : True := by trivial'],
  ['stopping no-Compute guarantee omitted', 'stopping_run_no_compute',
    'theorem stopping_run_no_compute {s t : State} (run : Run s t) (h : s.requested = true) : True := by trivial'],
]) test(`Lean refuses stop-inclusive claim weakening: ${label}`, () => {
  const model = readFileSync(new URL('StopAccounting.lean', import.meta.url), 'utf8');
  const start = model.indexOf(`theorem ${theorem} `);
  const end = model.indexOf('\n\n', start + 1);
  assert(start >= 0 && end > start, 'Missing uniquely extracted theorem');
  assert.equal(model.split(`theorem ${theorem} `).length, 2);
  const changed = model.slice(0, start) + replacement + '\n' + model.slice(end);
  const inputs = ['../bounded-session/Session.lean', 'Chain.lean']
    .map(path => readFileSync(new URL(path, import.meta.url), 'utf8')).join('\n');
  const claims = readFileSync(new URL('StopClaims.lean', import.meta.url), 'utf8');
  const result = spawnSync('lean', ['--stdin'], {
    cwd: fileURLToPath(new URL('.', import.meta.url)), input: `${inputs}\n${changed}\n${claims}`,
    encoding: 'utf8', timeout: 60000,
  });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/i);
});
