import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const vector = JSON.parse(readFileSync(new URL('../reviews/2026-10-12-d-native-local-expiry-1701/upgrade-vector.json', import.meta.url)));
const schema = JSON.parse(readFileSync(new URL('../spec/contracts/actql-local-run-policy-upgrade.schema.json', import.meta.url)));
const body = JSON.parse(vector.body);
const cid = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
// Independent flat schema interpreter; reject unsupported schema keywords.
function valid(shape, value) {
  for (const key of Object.keys(shape)) assert.ok([
    '$schema', '$id', 'type', 'additionalProperties', 'required', 'properties',
    'const', 'pattern', 'minLength', 'maxLength',
  ].includes(key), key);
  if (Object.hasOwn(shape, 'const')) return value === shape.const;
  if (shape.type === 'string') return typeof value === 'string'
    && (!shape.pattern || new RegExp(shape.pattern).test(value))
    && (!shape.minLength || [...value].length >= shape.minLength)
    && (!shape.maxLength || [...value].length <= shape.maxLength);
  if (shape.type !== 'object' || !value || typeof value !== 'object' || Array.isArray(value)) return false;
  return shape.required.every(key => Object.hasOwn(value, key))
    && Object.entries(value).every(([key, field]) => Object.hasOwn(shape.properties, key) && valid(shape.properties[key], field));
}

test('upgrade independent exact metadata identity keeps old read and required actual selectors', () => {
  assert.equal(vector.cid, 'sha256:50ea4cfc8971b947f7e988bf525f637606bc19a92b88078c8e368374085df4e1');
  assert.equal(cid(vector.body), vector.cid);
  assert.equal(cid(vector.finite_read), 'sha256:c03a2f30d887f6d5797b4e005bf4c4ad8e962c937cae28bde377a23647c05bb9');
  assert.equal(vector.finite_read_cid, cid(vector.finite_read));
  assert.equal(valid(schema, body), true);
  const old = JSON.parse(vector.old_read).native.result_read;
  const finite = JSON.parse(vector.finite_read).native.result_read;
  const {expires_at, ...priorValues} = old;
  const {run_file, retention_file, store_file, run_policy_profile_cid, ...values} = finite;
  assert.equal(expires_at, '2026-10-13T00:00:00.000Z');
  assert.deepEqual(values, priorValues);
  assert.deepEqual([run_file, retention_file, store_file], ['work.json', 'keep.json', 'payload.json']);
  assert.equal(run_policy_profile_cid, 'sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243');
  assert.equal(body.read_original_cid, cid(vector.old_read));
});

test('closed upgrade shape refuses missing identity invalid role null and oversized metadata', () => {
  for (const field of schema.required) {
    const missing = {...body}; delete missing[field];
    assert.equal(valid(schema, missing), false);
    assert.equal(valid(schema, {...body, [field]: null}), false);
  }
  for (const field of ['adoption_cid', 'authority_scope_cid', 'read_original_cid', 'run_configuration_cid']) {
    assert.equal(valid(schema, {...body, [field]: 'copied'}), false);
  }
  for (const field of ['read_configuration_name', 'run_configuration_name', 'retention_configuration_name', 'store_configuration_name']) {
    for (const name of ['', 'a/b', 'a\\b', '\0', 'x'.repeat(129)]) assert.equal(valid(schema, {...body, [field]: name}), false);
  }
  assert.equal(valid(schema, {...body, operation_id: ''}), false);
  assert.equal(valid(schema, {...body, profile_wire: 'x'.repeat(4097)}), false);
  assert.equal(valid(schema, {...body, extra: true}), false);
});
