import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const vector = JSON.parse(readFileSync('reviews/2026-10-12-d-native-local-expiry-1701/runtime-policy-upgrade-vector.json'));
const shape = JSON.parse(readFileSync('spec/contracts/actql-local-runtime-policy-upgrade.schema.json'));
const valid = value => typeof value === 'object' && value !== null && !Array.isArray(value)
  && shape.required.every(k => Object.hasOwn(value, k))
  && Object.entries(value).every(([k,v]) => {
    const field = shape.properties[k];
    return field && (Object.hasOwn(field, 'const') ? v === field.const
      : typeof v === 'string' && (!field.pattern || new RegExp(field.pattern).test(v))
        && (!field.minLength || [...v].length >= field.minLength)
        && (!field.maxLength || [...v].length <= field.maxLength));
  });
const cid = body => 'sha256:' + createHash('sha256').update(body).digest('hex');

test('independent runtime upgrade alternative preserves every original policy and pair field', () => {
  assert.equal(cid(vector.body), 'sha256:49d9e9c8f6cce49d488734013b9727c2c934c01692f4ba79a79522231e825526');
  assert.equal(vector.cid, cid(vector.body));
  assert.equal(Buffer.byteLength(vector.body), 2978);
  assert.equal(cid(vector.original_policy_body), 'sha256:50ea4cfc8971b947f7e988bf525f637606bc19a92b88078c8e368374085df4e1');
  assert.equal(cid(vector.runtime_pair_body), 'sha256:00df605c2c1173cdbd982bd7b54107df020de33f57b28d121c58c7daccc67090');
  const {runtime_pair_wire, version, ...fields} = JSON.parse(vector.body);
  const {version: oldVersion, ...oldFields} = JSON.parse(vector.original_policy_body);
  assert.deepEqual(fields, oldFields);
  assert.equal(runtime_pair_wire, vector.runtime_pair_body);
  assert.equal(version, 'actql-local-runtime-policy-upgrade/0.1');
  assert.equal(oldVersion, 'actql-local-run-policy-upgrade/0.1');
  assert.equal(valid(JSON.parse(vector.body)), true);
});

test('missing pair, old alternative, unknown fields and invalid bounds refuse', () => {
  const body = JSON.parse(vector.body);
  assert.equal(valid(JSON.parse(vector.original_policy_body)), false);
  for (const k of shape.required) {
    const missing = {...body}; delete missing[k]; assert.equal(valid(missing), false);
    assert.equal(valid({...body, [k]: null}), false);
  }
  for (const change of [{...body, runtime_pair_wire: ''}, {...body, runtime_pair_wire: 'x'.repeat(4097)},
    {...body, runtime_pair_wire: true}, {...body, grant: 'implicit'},
    {...body, version: 'actql-local-run-policy-upgrade/0.1'}]) assert.equal(valid(change), false);
});
