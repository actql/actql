import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { checkParentCensus } from './bounds.mjs';
import { providerConstructionBound } from './provider-construction.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
checkParentCensus(path => readFileSync(join(root, path)));
providerConstructionBound(path => readFileSync(join(root, path)));
const pin = readFileSync(new URL('../../../relation-capacity/lean-toolchain', import.meta.url), 'utf8').trim();
// Resolve the repository pin before asking an elan shim for its version; a
// developer's default 'stable' is not this proof's compiler identity.
const environment = {...process.env, ELAN_TOOLCHAIN: pin};
const version = spawnSync('lean', ['--short-version'], { encoding: 'utf8', env: environment });
assert.equal(version.status, 0); assert.equal(version.stdout.trim(), pin.split(':v')[1]);
const array = readFileSync(new URL('../backing/ArrayBacking.lean', import.meta.url), 'utf8');
const identities = readFileSync(new URL('../../../relation-capacity/Capacity.lean', import.meta.url), 'utf8');
const model = readFileSync(new URL('./NativeParentCore.lean', import.meta.url), 'utf8');
const selection = readFileSync(new URL('./ProviderConstruction.lean', import.meta.url), 'utf8');
assert(!/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test((array + identities + model + selection)
  .replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '')));
const names = ['phase_bound', 'growth_overlap', 'retired_owner_witness'];
assert.deepEqual([...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, n]) => n), names);
const selectionNames = ['candidate_component', 'retained_core_union'];
assert.deepEqual([...selection.matchAll(/^theorem\s+(\w+)/gm)].map(([, n]) => n), selectionNames);
const consumers = `
example (n : Nat) (s : NativeParentCore.Footprint)
  (r : s.references ≤ 80) (o : s.owner ≤ 56) (st : s.state ≤ 56) (c : s.callbacks ≤ 240)
  (e : s.environment ≤ 80) (w : s.reported ≤ 32) (a : s.arrayOwners ≤ 48)
  (h : s.backingHeaders ≤ 16) (b : s.backingSlots ≤ 2 * NativeParentCore.slots n)
  (co : s.completedOwners ≤ 48) (ch : s.completedHeaders ≤ 8) (cs : s.completedSlots ≤ n) :
  s.bytes ≤ NativeParentCore.envelope n := NativeParentCore.phase_bound n s r o st c e w a h b co ch cs
example (n old next : Nat) (a : old ≤ NativeParentCore.slots n) (b : next ≤ NativeParentCore.slots n) :
  8 * (old + next) ≤ 16 * NativeParentCore.slots n := NativeParentCore.growth_overlap n old next a b
example : NativeParentCore.retired.bytes = 560 := NativeParentCore.retired_owner_witness
example (s : ProviderConstruction.Footprint) (r : s.records ≤ 11 * 40)
  (c : s.callbacks ≤ 44 * 40) (a : s.candidates ≤ 120) (f : s.defaultFamily ≤ 24) :
  s.bytes ≤ 2344 := ProviderConstruction.candidate_component s r c a f
example (n : Nat) (r : RelationCapacity.Registry) (a b : Nat → Bool)
  (core : NativeParentCore.Footprint) (s : ProviderConstruction.Footprint)
  (c : core.bytes ≤ NativeParentCore.envelope n) (sb : s.bytes ≤ 2344)
  (cc : RelationCapacity.charge r.ids r.size a ≤ core.bytes)
  (sc : RelationCapacity.charge r.ids r.size b ≤ s.bytes) :
  RelationCapacity.charge r.ids r.size (fun id => a id || b id) ≤ NativeParentCore.envelope n + 2344 :=
  ProviderConstruction.retained_core_union n r a b core s c sb cc sc
`;
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], { encoding: 'utf8',
  env: environment, input: array + '\n' + identities + '\n' + model + '\n' + selection + consumers +
    names.map(n => `\n#print axioms NativeParentCore.${n}`).join('') +
    selectionNames.map(n => `\n#print axioms ProviderConstruction.${n}`).join(''),
  maxBuffer: 1024 * 1024 });
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
assert.equal(result.status, 0);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  assert(axioms.split(',').every(n => ['propext', 'Quot.sound'].includes(n.trim())));
}
console.log('3 conditional retained parent-core propositions checked; complete parent/edge and retirement correspondence remain open');
console.log('2 conditional provider-construction propositions checked; complete parent/pipeline capacity remains open');
