import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { checkParentCensus } from './bounds.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
checkParentCensus(path => readFileSync(join(root, path)));
const pin = readFileSync(new URL('../../../relation-capacity/lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { encoding: 'utf8' });
assert.equal(version.status, 0); assert.equal(version.stdout.trim(), pin.split(':v')[1]);
const array = readFileSync(new URL('../backing/ArrayBacking.lean', import.meta.url), 'utf8');
const model = readFileSync(new URL('./NativeParentCore.lean', import.meta.url), 'utf8');
assert(!/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test((array + model)
  .replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '')));
const names = ['phase_bound', 'growth_overlap', 'retired_owner_witness'];
assert.deepEqual([...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, n]) => n), names);
const consumers = `
example (n : Nat) (s : NativeParentCore.Footprint)
  (r : s.references ≤ 160) (o : s.owner ≤ 56) (c : s.callbacks ≤ 248)
  (e : s.environment ≤ 120) (w : s.reported ≤ 32) (a : s.arrayOwners ≤ 48)
  (h : s.backingHeaders ≤ 16) (b : s.backingSlots ≤ 2 * NativeParentCore.slots n) :
  s.bytes ≤ NativeParentCore.envelope n := NativeParentCore.phase_bound n s r o c e w a h b
example (n old next : Nat) (a : old ≤ NativeParentCore.slots n) (b : next ≤ NativeParentCore.slots n) :
  8 * (old + next) ≤ 16 * NativeParentCore.slots n := NativeParentCore.growth_overlap n old next a b
example : NativeParentCore.retired.bytes = 600 := NativeParentCore.retired_owner_witness
`;
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], { encoding: 'utf8',
  input: array + '\n' + model + consumers + names.map(n => `\n#print axioms NativeParentCore.${n}`).join(''),
  maxBuffer: 1024 * 1024 });
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
assert.equal(result.status, 0);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  assert(axioms.split(',').every(n => ['propext', 'Quot.sound'].includes(n.trim())));
}
console.log('3 conditional retained parent-core propositions checked; complete parent/edge and retirement correspondence remain open');
