import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { machineCid } from './actql-spec-family.mjs';
import { validateRegistry, loadRegistry, renderRegistry, renderGuardLaws } from './capacity-law-registry.mjs';

test('values count law has a separately pinned semantic body', () => {
  const path = 'spec/contracts/actql-bound-values-law.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:0e0f9b4b6585ab7b17bafe484e82f44cd8f3acc9eec5ef9329cea200237a7971';
  assert.equal(machineCid(body), cid);
  assert.equal(body.law_id, 'actql.bound.values');
  assert.equal(body.unit, 'rows');
  assert.ok(loadRegistry().body.law_ids.includes(body.law_id));
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(document => document.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === path), [{
    path, pointer: '', cid, version: 'actql-bound-values-law/0.1',
  }]);
  assert.notEqual(machineCid(loadRegistry().body), cid);
});

test('independent values count vectors count row occurrences, not cell contents', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-values.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-values-vectors/0.1');
  // This is only the authored row shape/count oracle. It does not bind or
  // validate cells, and a known count does not authorize execution.
  function count(rows) {
    assert.ok(Array.isArray(rows));
    let result = 0;
    for (const row of rows) {
      assert.ok(row !== null && typeof row === 'object' && !Array.isArray(row));
      result += 1;
    }
    return result;
  }
  for (const vector of corpus.cases) {
    assert.equal(count(vector.rows), vector.expected_rows, vector.name);
  }
  for (const rows of corpus.rejections) assert.throws(() => count(rows));
});

test('registry fixes its identity, rejects missing Host entries and malformed names', () => {
  const { body, policy } = loadRegistry();
  assert.equal(validateRegistry(body, policy), 'sha256:45f824fa077ac7eb6fecda6e25fa954834f1854c512f99f6803ad2ab84dd899a');
  assert.ok(body.law_ids.includes('actql.bound.text-rank'));
  for (const name of ['values', 'time-series', 'calendar-series']) {
    assert.ok(body.law_ids.includes(`actql.bound.${name}`));
  }
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(document => document.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === 'spec/contracts/actql-bound-law-registry.json'), [{
    path: 'spec/contracts/actql-bound-law-registry.json', pointer: '',
    cid: validateRegistry(body, policy), version: body.version,
  }]);
  for (const mutate of [
    value => { value.version = 'actql-bound-law-registry/1.0'; },
    value => { value.law_ids = []; },
    value => { value.law_ids.push(value.law_ids[0]); },
    value => { value.law_ids.reverse(); },
    value => { value.law_ids = value.law_ids.filter(id => id !== 'actql.host.relation-output'); },
    value => { value.law_ids[0] = ' actql.bound.append'; },
    value => { value.extra = true; },
    value => { delete value.author_guard_laws.nest; },
    value => { value.author_guard_laws.nest.unit = 'nodes'; },
    value => { value.author_guard_laws.nest.law_id = 'actql.bound.take'; },
    value => { value.author_guard_laws.nest.field = 'max_hops'; },
  ]) {
    const variant = structuredClone(body);
    mutate(variant);
    assert.throws(() => validateRegistry(variant, policy));
  }
  const generated = renderRegistry(body);
  for (const id of body.law_ids) assert.ok(generated.includes(`${JSON.stringify(id)} => Some(RegisteredLaw(law))`));
});

test('author guard source mappings preserve scope units and registered laws', () => {
  const {body} = loadRegistry();
  const expected = {
    join:['max_output_rows','rows','actql.guard.join-output'],
    cross_join:['max_output_rows','rows','actql.guard.join-output'],
    interval_join:['max_output_rows','rows','actql.guard.join-output'],
    nest:['max_items','array_items','actql.guard.nested-array-items'],
    array_agg:['max_items','array_items','actql.guard.array-aggregate'],
    string_agg:['max_bytes','bytes','actql.guard.string-aggregate'],
    sequence_matches:['max_matches_per_key','matches_per_key','actql.guard.sequence-matches'],
    sequence_output:['max_output_rows','rows','actql.guard.sequence-output'],
    components:['max_output_rows','rows','actql.guard.components-output'],
    traverse:['max_output_rows','rows','actql.guard.traverse-output'],
    shortest_path:['max_output_rows','rows','actql.guard.shortest-output'],
  };
  assert.deepEqual(Object.fromEntries(Object.entries(body.author_guard_laws).map(([scope,rule]) =>
    [scope,[rule.field,rule.unit,rule.law_id]])),expected);
  assert.ok(!body.law_ids.includes('actql.expression-fragment.capacity'));
  assert.equal(readFileSync(new URL('../src/pipeline_typing/guard_laws.generated.mbt',import.meta.url),'utf8'),renderGuardLaws(body));
});
