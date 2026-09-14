import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText} from './check-canonical-json.mjs';
import {contract} from './pivot-numeric-slot.mjs';
const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
// Symbolic Units isolate the normative preimage, not fabricated CheckedPrograms.
const base = {version: 'actql-pivot-numeric-slot/0.1', unit_definition_cid: 'sha256:' + '0'.repeat(64),
  source_ordinal: 0, output_name: 'a', reduction_profile_cid: 'sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df'};
const bodies = [base, {...base, unit_definition_cid: 'sha256:' + '1'.repeat(64)},
  {...base, source_ordinal: 1}, {...base, output_name: 'z'}, {...base, output_name: 'é~/\n😀'},
  {...base, reduction_profile_cid: 'sha256:' + '2'.repeat(64)}];
const vectors = bodies.map(body => ({body, canonical: canonicalText(body), cid: cid(body)}));
const path = 'portability/corpus/pivot-numeric-slot-identities.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(vectors, null, 2) + '\n');
const moon = '// Generated independent pivot numeric slot preimages.\n' + vectors.map((v, i) => `\n///|\ntest "pivot numeric slot preimage ${i}" {\n  let input = @json.parse(\n    ${JSON.stringify(v.canonical)},\n  )\n  let value = @canonical_json.from_json(input, 10000, 100, 100000)\n  assert_eq(\n    @canonical_json.cid_value(value, 100000, 10000, 100),\n    ${JSON.stringify(v.cid)},\n  )\n}\n`).join('');
const moonPath = 'src/canonical_json/pivot_numeric_slot.generated_test.mbt';
if (process.argv.includes('--write')) writeFileSync(moonPath, moon);
assert.equal(readFileSync(moonPath, 'utf8'), moon);
function shape(v) {
  const s = contract.schemas.pivot_slot;
  if (!v || typeof v !== 'object' || Array.isArray(v) || Object.keys(v).length !== s.required.length) return false;
  return s.required.every(k => {
    const p = s.properties[k], x = v[k];
    if (p.const) return x === p.const;
    if (p.type === 'integer') return Number.isSafeInteger(x) && x >= 0 && !Object.is(x, -0);
    return typeof x === 'string' && (!p.pattern || new RegExp(p.pattern).test(x)) && (!p.minLength || x.length >= p.minLength);
  });
}
test('pivot slot independent vectors distinguish owners columns steps and profiles', () => {
  assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), vectors);
  assert.equal(new Set(vectors.map(v => v.cid)).size, vectors.length);
  assert.equal(cid(Object.fromEntries(Object.entries(base).reverse())), cid(base));
  for (const version of ['actql-group-numeric-slot/0.1', 'actql-window-numeric-slot/0.1', 'actql-analytic-numeric-slot/0.1']) {
    assert.notEqual(cid({...base, version}), cid(base));
    assert(!shape({...base, version}));
  }
});
test('closed shape rejects future observations and malformed static coordinates', () => {
  for (const body of bodies) assert(shape(body));
  for (const key of ['input_artifact_cid', 'index_key', 'value', 'fill_result', 'count', 'invocation_cid', 'member_cid', 'producer_visit', 'self_cid']) assert(!shape({...base, [key]: 0}));
  for (const source_ordinal of [-1, 0.5, Number.MAX_SAFE_INTEGER + 1, -0]) assert(!shape({...base, source_ordinal}));
  for (const output_name of ['', null, 0]) assert(!shape({...base, output_name}));
  for (const key of Object.keys(base)) { const copy = {...base}; delete copy[key]; assert(!shape(copy)); }
});
test('bucket membership and fill do not redefine static column templates', () => {
  const slots = values => values.map(output_name => ({...base, output_name}));
  assert.deepEqual(slots([]), []);
  assert.deepEqual(new Set(slots(['a', 'z']).map(cid)), new Set(slots(['z', 'a']).map(cid)));
  // Holding the Unit fixed isolates column selection; reordering authored values
  // can still change the real Unit identity under the language's ordinary rules.
  const rows = [{id: 1, kind: null, value: 9}, {id: 1, kind: 'a', value: null},
    {id: 1, kind: 'z', value: 2}, {id: 1, kind: 'z', value: 2}, {id: 2, kind: 'a', value: 2}];
  const contributors = (id, name) => rows.filter(r => r.id === id && r.kind === name && r.value !== null).map(r => r.value);
  assert.deepEqual(contributors(1, 'a'), []);
  assert.deepEqual(contributors(1, 'z'), [2, 2]);
  assert.deepEqual(contributors(2, 'a'), [2]);
  const fill = 7;
  assert.equal(contributors(1, 'a').length === 0 ? fill : 0, 7);
  assert.deepEqual(contributors(1, 'a'), []);
  assert.equal(contract.semantics.empty_columns, 'zero_slots_without_waiving_operation_type_profile_fill_or_budget_checks');
});
test('matching shape and self hash do not identify a selected owned slot', () => {
  const selected = canonicalText(base);
  for (const body of bodies.slice(1)) {
    assert(shape(body));
    assert.notEqual(canonicalText(body), selected);
  }
});
