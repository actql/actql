import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const cwd = fileURLToPath(new URL('.', import.meta.url));
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
test('executed early-retirement checker admits 19 added and 36 reused typed/axiom laws', () => {
  const result = spawnSync(process.execPath, ['retirement-check.mjs'], {cwd, encoding: 'utf8', timeout: 60000});
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /Checked 55 theorems, expected claim types and axiom dependencies/);
});
for (const [label, name, replacement] of [
  ['original productive budget', 'chain_accounting',
    'theorem chain_accounting (budget : Nat) (t : State) (run : Run (initial budget) t) : True := by trivial'],
  ['completed output preservation', 'retire_preserves_outputs',
    'theorem retire_preserves_outputs (s : State) (done : Bool) : True := by trivial'],
  ['cleanup pending custody', 'pending_cleanup_identity',
    'theorem pending_cleanup_identity (s : State) : True := by trivial'],
  ['exactly one retirement', 'successful_retirement_once',
    'theorem successful_retirement_once (s : State) (id : Nat) (ready : s.pending = true) (single : s.core.owed = [id]) : True := by trivial'],
  ['single execution responsibility', 'step_single_execution',
    'theorem step_single_execution {s t : State} (step : Step s t) (h : s.core.owed.length ≤ 1) : True := by trivial'],
]) test(`real Lean refuses retirement claim weakening: ${label}`, () => {
  const model = read('Retirement.lean');
  assert.equal(model.split(`theorem ${name} `).length, 2);
  const begin = model.indexOf(`theorem ${name} `), end = model.indexOf('\n\n', begin);
  assert(begin >= 0 && end > begin);
  const changed = model.slice(0, begin) + replacement + model.slice(end);
  const input = ['../bounded-session/Session.lean', 'Chain.lean'].map(read).join('\n') +
    `\n${changed}\n${read('RetirementClaims.lean')}`;
  const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], {cwd, input, encoding: 'utf8', timeout: 60000});
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout + result.stderr, /type mismatch/iu);
});
