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
    'minLength', 'enum', 'items', 'uniqueItems', 'minItems', 'maxItems', 'minimum', 'maximum', 'oneOf',
  ].includes(keyword), keyword);
  if (shape.required && (value === null || typeof value !== 'object'
      || shape.required.some(key => !Object.hasOwn(value, key)))) return false;
  if (shape.oneOf && shape.oneOf.filter(alternative => valid(alternative, value)).length !== 1) return false;
  if (shape.type === 'object') {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    return Object.entries(value).every(([key, item]) =>
      Object.hasOwn(shape.properties, key) && valid(shape.properties[key], item));
  }
  if (Object.hasOwn(shape, 'const')) return isDeepStrictEqual(value, shape.const);
  if (shape.enum) return shape.enum.some(item => isDeepStrictEqual(item, value));
  if (shape.type === 'boolean') return typeof value === 'boolean';
  if (shape.type === 'integer') return Number.isSafeInteger(value) && value >= shape.minimum && value <= shape.maximum;
  if (shape.type === 'array') return Array.isArray(value)
    && value.length >= shape.minItems && value.length <= shape.maxItems
    && (!shape.uniqueItems || new Set(value.map(item => JSON.stringify(item))).size === value.length)
    && value.every(item => valid(shape.items, item));
  if (!shape.type) return true;
  return shape.type === 'string' && typeof value === 'string'
    && (!Object.hasOwn(shape, 'pattern') || new RegExp(shape.pattern).test(value))
    && (!Object.hasOwn(shape, 'maxLength') || [...value].length <= shape.maxLength)
    && (!Object.hasOwn(shape, 'minLength') || [...value].length >= shape.minLength);
}
const validate = value => valid(schema, value);

test('independent finite profile vector has its fixed identity and closed shape', () => {
  assert.equal(vector.cid, 'sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243');
  assert.equal('sha256:' + createHash('sha256').update(vector.canonical).digest('hex'), vector.cid);
  assert.equal(validate(JSON.parse(vector.canonical)), true);
});

test('finite read mode is explicit and exclusive of the legacy absolute endpoint', () => {
  const shape = JSON.parse(readFileSync(new URL('../spec/contracts/actql-native-local-result-read.schema.json', import.meta.url)));
  const vector = JSON.parse(readFileSync(new URL('../reviews/2026-10-12-d-native-local-expiry-1701/finite-read-selection-vector.json', import.meta.url)));
  const body = JSON.parse(vector.body);
  assert.equal(vector.cid, 'sha256:b96c3fb837026fc7f4e8442ffc2bc4551ecd49a935e0376b7c0b3884684a7706');
  assert.equal('sha256:' + createHash('sha256').update(vector.body).digest('hex'), vector.cid);
  assert.equal(valid(shape, body), true);
  const read = body.native.result_read;
  const check = value => valid(shape, {...body, native: {result_read: value}});
  const {run_policy_profile_cid: profile, ...withoutExpiry} = read;
  assert.equal(profile, 'sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243');
  assert.equal(check(withoutExpiry), false);
  assert.equal(check({...read, expires_at: '2026-10-13T00:00:00.000Z'}), false);
  assert.equal(check({...withoutExpiry, expires_at: '2026-10-13T00:00:00.000Z'}), true);
  assert.equal(check({...read, max_bytes: 536870913}), false);
  assert.equal(check({...read, max_uses: 0}), false);
  assert.equal(check({...read, run_policy_profile_cid: null}), false);
  assert.equal(check({...read, sink: 'network'}), false);
  assert.equal(check({...read, extra: true}), false);
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
