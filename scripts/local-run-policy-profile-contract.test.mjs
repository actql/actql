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
    'minLength', 'not', 'anyOf', 'enum', 'items', 'uniqueItems', 'minItems', 'maxItems', 'minimum', 'maximum', 'oneOf',
  ].includes(keyword), keyword);
  if (shape.required && (value === null || typeof value !== 'object'
      || shape.required.some(key => !Object.hasOwn(value, key)))) return false;
  if (shape.not && valid(shape.not, value)) return false;
  if (shape.anyOf && !shape.anyOf.some(alternative => valid(alternative, value))) return false;
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
  assert.equal(vector.cid, 'sha256:a9f3763dd497b71ef891cb741842cc5e608cfe522474b841b083550d962d385a');
  assert.equal('sha256:' + createHash('sha256').update(vector.body).digest('hex'), vector.cid);
  assert.equal(valid(shape, body), true);
  const read = body.native.result_read;
  const check = value => valid(shape, {...body, native: {result_read: value}});
  const {run_policy_profile_cid: profile, run_file: run, retention_file: retention, store_file: store, ...withoutExpiry} = read;
  assert.deepEqual([run, retention, store], ['run.json', 'retention.json', 'store.json']);
  assert.equal(profile, 'sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243');
  assert.equal(check(withoutExpiry), false);
  assert.equal(check({...read, expires_at: '2026-10-13T00:00:00.000Z'}), false);
  assert.equal(check({...withoutExpiry, expires_at: '2026-10-13T00:00:00.000Z'}), true);
  assert.equal(check({...read, max_bytes: 536870913}), false);
  assert.equal(check({...read, max_uses: 0}), false);
  assert.equal(check({...read, run_policy_profile_cid: null}), false);
  for (const sink of ['stdout', 'material', 'file']) assert.equal(check({...read, sink}), true);
  assert.equal(check({...read, sink: 'network'}), false);
  assert.equal(check({...read, extra: true}), false);
  for (const role of ['run_file', 'retention_file', 'store_file']) {
    const missing = {...read}; delete missing[role];
    assert.equal(check(missing), false);
    assert.equal(check({...withoutExpiry, expires_at: '2026-10-13T00:00:00.000Z', [role]: read[role]}), false);
    for (const value of ['', '.', '..', 'a/b', 'a\\b', '\u0000', null, 'a'.repeat(129)])
      assert.equal(check({...read, [role]: value}), false);
  }
  assert.equal(check({...read, run_file: 'custom-run.json', retention_file: 'custom-retention.json', store_file: 'custom-store.json'}), true);

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
