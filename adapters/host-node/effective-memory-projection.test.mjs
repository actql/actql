import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {localResourceResultReadLimits, selectInstalledLocalMaterializationEnvironment}
  from './installed-host-policy.mjs';

const baseWire = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
const baseCapacity = JSON.parse(baseWire).host_policy_profile.capacity;

test('selected memory reaches Common for both collection and checking, including equal reopen', () => {
  const original = {}, calls = [];
  const memory = {retainedBytes: 67108864, executionBytes: 134217728};
  const moon = {
    clientLocalResourcePolicyOriginal: () => original,
    clientLocalPreparationResourceLimits(policy, retained, execution) {
      assert.strictEqual(policy, original);
      assert.equal(retained, 67108864n); assert.equal(execution, 134217728n);
      return [1n, 1n, 1n, 20000000n, retained, execution];
    },
    clientLocalResourcePolicyRowCeiling(policy, retained, execution) {
      assert.strictEqual(policy, original);
      calls.push([retained, execution]);
      assert.equal(retained, 67108864n); assert.equal(execution, 134217728n);
      // Explicit Common result: the adapter must not duplicate its tariff.
      return 12345;
    },
    clientLocalResourcePolicyModelRequestByteCeiling: () => 1000000n,
    clientProgramCheckEnvironment: () => ({}),
  };
  assert.equal(localResourceResultReadLimits(moon, memory).maxRows, 12345);
  const selected = selectInstalledLocalMaterializationEnvironment(moon, baseWire,
    undefined, undefined, memory);
  assert.equal(selectInstalledLocalMaterializationEnvironment(moon, baseWire,
    undefined, undefined, {...memory}), selected);
  const capacity = JSON.parse(selected).host_policy_profile.capacity;
  for (const name of ['max_relation_output_rows', 'max_artifact_rows', 'max_file_listing_items']) {
    assert.equal(capacity[name], 12345);
  }
  assert.deepEqual(calls, Array.from({length: 3}, () => [67108864n, 134217728n]));
});

test('explicit checking dimensions narrow selected Common rows and omitted dimensions remain unresolved', () => {
  const moon = {
    clientLocalResourcePolicyOriginal: () => ({}),
    clientLocalResourcePolicyRowCeiling: () => 12345,
    clientProgramCheckEnvironment: () => ({}),
  };
  const explicit = {...baseCapacity, max_relation_output_rows: 9, max_artifact_rows: 20000};
  delete explicit.max_file_listing_items;
  const selected = selectInstalledLocalMaterializationEnvironment(moon, baseWire,
    explicit, undefined, {retainedBytes: 67108864, executionBytes: 67108864});
  const capacity = JSON.parse(selected).host_policy_profile.capacity;
  assert.equal(capacity.max_relation_output_rows, 9);
  assert.equal(capacity.max_artifact_rows, 12345);
  assert.equal(Object.hasOwn(capacity, 'max_file_listing_items'), false);
});
