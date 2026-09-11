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
  assert.deepEqual([...schema.required].sort(), Object.keys(schema.properties).sort());
  const fields = schema.required.filter(k => k !== 'version');
  assert.equal(fields.length, 17);
  assert.equal(new Set(fields).size, fields.length);
  assert.deepEqual(schema.properties.version, { const: 'actql-capacity-host-policy/0.1' });
  for (const field of fields) assert.deepEqual(schema.properties[field], {
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
