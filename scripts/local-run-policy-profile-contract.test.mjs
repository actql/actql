import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {isDeepStrictEqual} from 'node:util';

const schema = JSON.parse(readFileSync(new URL(
  '../spec/contracts/actql-local-run-policy-profile.schema.json', import.meta.url)));
const vector = JSON.parse(readFileSync(new URL(
  '../reviews/2026-10-12-d-native-local-expiry-1701/profile-vector.json', import.meta.url)));
// Test-only interpreter for this flat closed schema, following the existing
// source-state schema tests. New unsupported keywords must fail explicitly.
function valid(shape, value) {
  for (const keyword of Object.keys(shape)) assert.ok([
    '$schema', '$id', 'type', 'additionalProperties', 'required', 'properties', 'const', 'pattern', 'maxLength',
  ].includes(keyword), keyword);
  if (shape.type === 'object') {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (shape.required.some(key => !Object.hasOwn(value, key))) return false;
    return Object.entries(value).every(([key, item]) =>
      Object.hasOwn(shape.properties, key) && valid(shape.properties[key], item));
  }
  if (Object.hasOwn(shape, 'const')) return isDeepStrictEqual(value, shape.const);
  return shape.type === 'string' && typeof value === 'string'
    && (!Object.hasOwn(shape, 'pattern') || new RegExp(shape.pattern).test(value))
    && (!Object.hasOwn(shape, 'maxLength') || [...value].length <= shape.maxLength);
}
const validate = value => valid(schema, value);

test('independent finite profile vector has its fixed identity and closed shape', () => {
  assert.equal(vector.cid, 'sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243');
  assert.equal('sha256:' + createHash('sha256').update(vector.canonical).digest('hex'), vector.cid);
  assert.equal(validate(JSON.parse(vector.canonical)), true);
});

test('profile schema refuses extended lifetimes missing bindings and extra fields', () => {
  const original = JSON.parse(vector.canonical);
  for (const field of ['available_for_ms', 'delete_after_ms', 'metadata_after_ms', 'read_for_ms']) {
    assert.equal(validate({...original, [field]: original[field] + 1}), false);
    assert.equal(validate({...original, [field]: String(original[field])}), false);
  }
  for (const field of schema.required) {
    const missing = {...original};
    delete missing[field];
    assert.equal(validate(missing), false);
  }
  assert.equal(validate({...original, adoption_time: '2026-10-12T00:00:00.000Z'}), false);
  assert.equal(validate({...original, effective_data_policy_cid: 'public'}), false);
});

test('independent original packet identity and closed shape retain original bindings', () => {
  const packetSchema = JSON.parse(readFileSync(new URL(
    '../spec/contracts/actql-local-run-policy-original.schema.json', import.meta.url)));
  const packet = JSON.parse(readFileSync(new URL(
    '../reviews/2026-10-12-d-native-local-expiry-1701/original-packet-vector.json', import.meta.url)));
  assert.equal(packet.cid, 'sha256:24d9f490b5dbb2a3db3cf499badfb521fa7d4f0ce6806ef84e97b21e38639014');
  assert.equal('sha256:' + createHash('sha256').update(packet.body).digest('hex'), packet.cid);
  const body = JSON.parse(packet.body);
  assert.equal(valid(packetSchema, body), true);
  for (const field of packetSchema.required) {
    const missing = {...body};
    delete missing[field];
    assert.equal(valid(packetSchema, missing), false);
    if (field !== 'version') assert.equal(valid(packetSchema, {...body, [field]: null}), false);
  }
  assert.equal(valid(packetSchema, {...body, profile_wire: 'x'.repeat(4097)}), false);
  assert.equal(valid(packetSchema, {...body, host_adoption_cid: 'copied'}), false);
  assert.equal(valid(packetSchema, {...body, extra: true}), false);
});
