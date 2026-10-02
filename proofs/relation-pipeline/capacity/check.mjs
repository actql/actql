import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
const model = readFileSync(new URL('./Structure.lean', import.meta.url), 'utf8');
const capacity = readFileSync(new URL('../../relation-capacity/Capacity.lean', import.meta.url), 'utf8');
const pin = readFileSync(new URL('../../relation-capacity/lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { encoding: 'utf8' });
if (version.status !== 0 || version.stdout.trim() !== pin.split(':v')[1]) throw new Error('Wrong Lean pin');
const clean = model.replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '');
if (/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test(clean)) throw new Error('Unchecked proof');
const names = [...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, name]) => name);
assert.deepEqual(names, ['first_occurrence_count_bound', 'distinct_structural_bound',
  'output_cells_bound', 'numeric_content_octets_bound', 'serial_bounds',
  'conditional_bytes', 'shared_structural_chain', 'output_holder_keeps_charge']);
const expected = `
example {Row : Type} [DecidableEq Row] (rows seen : List Row) :
  (RelationStructure.firstOccurrenceRows seen rows).length ≤ rows.length :=
  RelationStructure.first_occurrence_count_bound rows seen
example (n w : Nat) (c : RelationStructure.Counts) (h : RelationStructure.bounded n w c) :
  RelationStructure.total c ≤ n*w + 5*n + 11*w + 5 := RelationStructure.distinct_structural_bound n w c h
example (n w u : Nat) (h : u ≤ n) : u*w ≤ n*w :=
  RelationStructure.output_cells_bound n w u h
example (n w u : Nat) (h : u ≤ n) : 8*(u*w) ≤ 8*(n*w) :=
  RelationStructure.numeric_content_octets_bound n w u h
example (cs : List RelationStructure.Child)
  (h : ∀ c ∈ cs, RelationStructure.bounded c.rows c.width c.state) :
  RelationStructure.finiteTotal cs ≤ RelationStructure.finiteBound cs :=
  RelationStructure.serial_bounds cs h
example (actual elements unit management upper : Nat)
  (rep : actual ≤ elements*unit + management) (h : elements ≤ upper) :
  actual ≤ upper*unit + management := RelationStructure.conditional_bytes actual elements unit management rep upper h
example (r : RelationCapacity.Registry) (cs : List RelationCapacity.Child)
  (h : ∀ c ∈ cs, RelationCapacity.charge r.ids r.size c.live ≤ c.retained + c.execution) :
  RelationCapacity.charge r.ids r.size (RelationCapacity.childrenLive cs) ≤
    RelationCapacity.childCapacity cs := RelationStructure.shared_structural_chain r cs h
example (r : RelationCapacity.Registry) (executor output : Nat → Bool)
  (h : ∀ id ∈ r.ids, executor id = true → output id = true) :
  RelationCapacity.charge r.ids r.size (fun id => executor id || output id) =
    RelationCapacity.charge r.ids r.size output :=
  RelationStructure.output_holder_keeps_charge r executor output h
`;
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], { encoding: 'utf8',
  input: capacity + model + expected + names.map(n => `\n#print axioms RelationStructure.${n}`).join(''), maxBuffer: 4 * 1024 * 1024 });
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
if (result.status !== 0 || /sorryAx/.test(result.stdout)) process.exit(1);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  if (axioms.split(',').some(n => !['propext', 'Quot.sound'].includes(n.trim()))) throw new Error('Unexpected axiom');
}
console.log(`${names.length} structural model propositions checked; allocator bytes remain conditional`);
