import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { validateRegistry, loadRegistry, renderRegistry, renderGuardLaws } from './capacity-law-registry.mjs';

test('registry fixes its identity, rejects missing Host entries and malformed names', () => {
  const { body, policy } = loadRegistry();
  assert.equal(validateRegistry(body, policy), 'sha256:e8f2bc38c037ab19204ad4863714351140c2aea9de3a30683e868ea08fd87e40');
  assert.ok(body.law_ids.includes('actql.bound.text-rank'));
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
