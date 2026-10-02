import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { checkCore } from './source.mjs';
const pin = JSON.parse(readFileSync(new URL('../../../../toolchain.json', import.meta.url)));
assert(process.env.MOON_HOME, 'Set the pinned MOON_HOME');
checkCore(process.env.MOON_HOME + '/lib/core', pin);
const leanPin = readFileSync(new URL('../../../relation-capacity/lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { encoding: 'utf8' });
assert.equal(version.status, 0); assert.equal(version.stdout.trim(), leanPin.split(':v')[1]);
const model = readFileSync(new URL('./ArrayBacking.lean', import.meta.url), 'utf8');
const clean = model.replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '');
assert(!/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test(clean));
const names = ['initial_fits', 'push_fits', 'reuse_fits', 'growth_overlap', 'clear_keeps_backing', 'wrapped_doubling_triggers_fallback'];
assert.deepEqual([...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, n]) => n), names);
const expected = `
example (i h : Nat) : i ≤ ArrayBacking.ceiling i h := ArrayBacking.initial_fits i h
example (i h len cap next : Nat) (full : cap = len) (bound : len + 1 ≤ h)
  (growth : next = 8 ∨ next = 2 * cap ∨ next = len + 1) :
  next ≤ ArrayBacking.ceiling i h := ArrayBacking.push_fits i h len cap next full bound growth
example (i h old : Nat) (held : old ≤ ArrayBacking.ceiling i h) :
  old ≤ ArrayBacking.ceiling i h := ArrayBacking.reuse_fits i h old held
example (i h old next : Nat) (a : old ≤ ArrayBacking.ceiling i h)
  (b : next ≤ ArrayBacking.ceiling i h) : old + next ≤ 2 * ArrayBacking.ceiling i h :=
  ArrayBacking.growth_overlap i h old next a b
example (s : ArrayBacking.ArrayState) :
  (ArrayBacking.clear s).capacity = s.capacity ∧ (ArrayBacking.clear s).backing = s.backing :=
  ArrayBacking.clear_keeps_backing s
example (cap : Int) (a : 0 ≤ cap) (b : cap ≤ 2147483647) (c : 2147483647 < 2 * cap) :
  ArrayBacking.wrapDouble cap ≤ cap := ArrayBacking.wrapped_doubling_triggers_fallback cap a b c
`;
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], { encoding: 'utf8',
  input: model + expected + names.map(n => `\n#print axioms ArrayBacking.${n}`).join(''), maxBuffer: 1024 * 1024 });
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
assert.equal(result.status, 0);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  assert(axioms.split(',').every(n => ['propext', 'Quot.sound'].includes(n.trim())));
}
console.log('6 array backing model propositions checked; byte representation and holder census remain separate');
