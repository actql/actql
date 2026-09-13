import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { machineCid } from './actql-spec-family.mjs';

const contract = JSON.parse(readFileSync(new URL('../spec/contracts/actql-capacity-host-policy.json', import.meta.url), 'utf8'));
const source = readFileSync(new URL('../src/capacity_policy/policy.mbt', import.meta.url), 'utf8');

test('capacity policy schema and admitted field set are identical and closed', () => {
  assert.equal(contract.version, 'actql-capacity-host-policy-contract/0.1');
  const { schema } = contract;
  assert.equal(schema.type, 'object');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual([...schema.required, 'max_aggregate_string_bytes'].sort(), Object.keys(schema.properties).sort());
  const fields = schema.required.filter(k => k !== 'version');
  assert.equal(fields.length, 17);
  assert.equal(new Set(fields).size, fields.length);
  assert.deepEqual(schema.properties.version, { const: 'actql-capacity-host-policy/0.1' });
  for (const field of [...fields, 'max_aggregate_string_bytes']) assert.deepEqual(schema.properties[field], {
    type: 'integer', minimum: 1, maximum: Number.MAX_SAFE_INTEGER,
  });
  const body = source.match(/let fields : Array\[String\] = \[([\s\S]*?)\]/)?.[1];
  assert.ok(body, 'Missing closed product field inventory');
  const product = [...body.matchAll(/"([a-z_]+)"/g)].map(m => m[1]);
  assert.deepEqual(product, [...fields].sort(), 'Product field inventory or canonical order drift');
});

test('synthetic all-one policy has a fixed independent canonical identity', () => {
  const policy = Object.fromEntries(contract.schema.required.map(field => [field,
    field === 'version' ? 'actql-capacity-host-policy/0.1' : 1]));
  assert.equal(machineCid(policy), 'sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63');
});

test('host witness field units and laws match the closed product mapping', () => {
  const unitNames = {Rows:'rows', DistinctKeys:'distinct_keys', EffectItems:'effect_items',
    Bytes:'bytes', ArrayItems:'array_items', Nodes:'nodes', Edges:'edges', Paths:'paths', MatchesPerKey:'matches_per_key'};
  const product = readFileSync(new URL('../src/capacity_host_witness/witness.mbt', import.meta.url), 'utf8');
  const pairs = [...product.matchAll(/"(max_[a-z_]+)"\s*=>\s*Some\(\((\w+), "([^"]+)"\)\)/g)]
    .map(([,field,unit,law_id]) => [field, { unit: unitNames[unit], law_id }]);
  assert.equal(pairs.length, 15);
  assert.equal(new Set(pairs.map(([field]) => field)).size, pairs.length);
  assert.deepEqual(Object.fromEntries(pairs), contract.host_witness_laws);
  const unsupported = contract.schema.required.filter(k => k !== 'version' && !Object.hasOwn(contract.host_witness_laws, k));
  assert.deepEqual(unsupported.sort(), ['max_model_input_tokens_per_item', 'max_model_total_duration_ms', 'max_nested_value_depth']);
});

test('fixed host witness wire bytes and identities match an independent canonical oracle', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/host-capacity-witnesses.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-host-capacity-witness-vectors/0.1');
  assert.deepEqual(corpus.cases.map(c => c.field).sort(), Object.keys(contract.host_witness_laws).filter(k => contract.schema.required.includes(k)).sort());
  const policy_cid = machineCid(corpus.policy);
  assert.equal(new Set(corpus.cases.map(c => c.cid)).size, corpus.cases.length);
  for (const c of corpus.cases) {
    assert.deepEqual({unit:c.unit, law_id:c.law_id}, contract.host_witness_laws[c.field]);
    const core = {dependencies:[policy_cid], derivation:{op:'source'}, law_id:c.law_id,
      role:'host_ceiling', source:{field:c.field, kind:'host_policy', policy_cid},
      unit:c.unit, value:corpus.policy[c.field], version:'actql-bound-witness/0.1'};
    assert.equal(machineCid(core), c.cid);
    assert.equal(JSON.stringify({...core, witness_cid:c.cid}), c.text);
  }
  assert.equal(corpus.rejections.length, 1);
  for (const c of corpus.rejections) {
    const { witness_cid, ...core } = JSON.parse(c.text);
    assert.equal(machineCid(core), c.cid, 'Rejection must have an internally correct CID');
    assert.equal(witness_cid, c.cid);
    assert.equal(c.expected_issue, 'IdentityMismatch');
    assert.notEqual(core.unit, contract.host_witness_laws[core.source.field].unit);
  }
});

test('optional string ceiling and witness have independent fixed identities', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/aggregate-string-ceiling.json', import.meta.url), 'utf8'));
  const policy = Object.fromEntries(contract.schema.required.map(field => [field,
    field === 'version' ? 'actql-capacity-host-policy/0.1' : 1]));
  policy.max_aggregate_string_bytes = corpus.value;
  assert.equal(machineCid(policy), corpus.policy_cid);
  const body = {dependencies:[corpus.policy_cid], derivation:{op:'source'},
    law_id:'actql.host.aggregate-string-bytes', role:'host_ceiling',
    source:{field:'max_aggregate_string_bytes', kind:'host_policy', policy_cid:corpus.policy_cid},
    unit:'bytes', value:corpus.value, version:'actql-bound-witness/0.1'};
  assert.equal(machineCid(body), corpus.witness_cid);
  for (const c of corpus.payloads) {
    assert.equal(c.value === null ? 0 : Buffer.byteLength(c.value, 'utf8'), c.bytes);
    assert.equal(c.bytes <= corpus.value, c.within_ceiling);
  }
});
