import assert from 'node:assert/strict';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyLookupBarrierSchemas} from './lookup-barrier-contract.mjs';

test('runtime barrier retains the exact static schema and all non-capacity obligations', () => {
  const {schema, staticPin} = verifyLookupBarrierSchemas();
  const [old, runtime] = schema.oneOf;
  assert.equal(machineCid({$schema: schema.$schema, $id: schema.$id, ...old}), staticPin);
  assert.equal(runtime.additionalProperties, false);
  assert.ok(runtime.required.includes('lookup_execution_cid'));
  assert.deepEqual(runtime.properties.capacity_guarantee, {const: 'complete'});
  for (const key of ['bounds', 'capacity_proof_cid']) {
    assert.equal(Object.hasOwn(runtime.properties,key), false);
    assert.equal(runtime.required.includes(key), false);
  }
  for (const key of old.required.filter(key => !['bounds','capacity_proof_cid'].includes(key))) {
    assert.ok(runtime.required.includes(key), key);
    if (key !== 'capacity_guarantee') assert.deepEqual(runtime.properties[key],old.properties[key],key);
  }
});

test('both Plan summaries retain the static predecessor and omit unknown runtime aggregate estimates', () => {
  const {summaries} = verifyLookupBarrierSchemas();
  for (const summary of summaries) {
    const [old,runtime] = summary.oneOf;
    assert.equal(machineCid(old), 'sha256:04fa18ab4d331206aa083f0a1c0c17271b1d778f7743be79d187f321ff799a52');
    assert.equal(runtime.additionalProperties,false);
    assert.equal(runtime.required.includes('max_distinct_keys'),false);
    assert.equal(runtime.required.includes('capacity_proof_cid'),false);
    assert.equal(Object.hasOwn(runtime.properties,'max_distinct_keys'),false);
    assert.ok(runtime.required.includes('lookup_execution_cid'));
    assert.equal(runtime.required.includes('max_output_rows'),false);
    assert.deepEqual(runtime.properties.max_output_rows,old.properties.max_output_rows);
    assert.deepEqual(runtime.properties.completeness,{const:'complete_per_requested_key'});
    for (const key of old.required.filter(key => !['max_distinct_keys','capacity_proof_cid','max_output_rows'].includes(key))) {
      assert.ok(runtime.required.includes(key),key);
      assert.deepEqual(runtime.properties[key],old.properties[key],key);
    }
  }
});
