import assert from 'node:assert/strict';
import test from 'node:test';
import {valuesUnitIdentity, valuesResultPlan} from './string-contract-identities.mjs';
import {valuesDependencyOracle} from '../client-values-dependency-oracle.mjs';

test('historical Values Unit freezes the pre-string contract closure', () => {
  const program = {version: 'actql/0.1', id: 'client-values',
    stages: [{id: 'source', inputs: {},
      steps: [{as: 'selected', values: {schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 1}, {id: 2}]}}], results: {rows: {from: 'selected', fields: ['id']}}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}};
  const historical = valuesUnitIdentity(program, true);
  // Fixed before the exact-string contract change, independent of runtime output.
  assert.equal(historical, 'sha256:63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9');
  assert.equal(valuesResultPlan(historical).result_plan_logical_cid,
    'sha256:8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38');
  // A second role selection uses separate preimages, not the compiler's issuer.
  assert.equal(historical, valuesDependencyOracle({legacy: true}).unit);
  assert.equal(valuesUnitIdentity(program), valuesDependencyOracle().unit);
  assert.notEqual(valuesUnitIdentity(program), historical);
});
