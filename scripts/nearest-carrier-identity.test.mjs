import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {nearestCarrierIdentityOracle} from './nearest-carrier-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('NEAREST Carrier roles preserve complete old identity preimages', () => {
  const before = read('scripts/fixtures/pre-nearest-carrier-values-identities.json');
  assert.deepEqual(before, read('scripts/fixtures/submitted-lag-values-identities.json'));
  assert.deepEqual(before.grammar,
    read('reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/grammar-manifest.json'));
  const expected = nearestCarrierIdentityOracle();
  assert.deepEqual(expected, read('scripts/fixtures/submitted-nearest-carrier-values-identities.json'));
  assert.deepEqual(expected.grammar, read('spec/manifests/actql-grammar-0.1.json'));
  assert.deepEqual(expected.values_dependencies, before.values_dependencies);
  assert.deepEqual(expected.program_identity, before.program_identity);
  assert.deepEqual(expected.run_preimages.executable.resolved_limits,
    before.run_preimages.executable.resolved_limits);
  assert.deepEqual(expected.run_preimages.executable.execution_material.program,
    before.run_preimages.executable.execution_material.program);
  assert.notEqual(expected.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  for (const [name, field] of [['template','bound_invocation_template_cid'],
    ['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
    for (const vector of [before, expected]) {
      const {[field]: seal, ...body} = vector.run_preimages[name];
      assert.equal(signatureRoleCid(body), seal, name);
    }
  }
});
