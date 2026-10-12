import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {signatureRoleIdentityOracle, signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('SGA role syntax retains the complete predecessor and independently changes grammar-bound Run identity', () => {
  const before = read('scripts/fixtures/pre-sga-signature-role-values-identities.json');
  const expected = signatureRoleIdentityOracle();
  const submitted = read('scripts/fixtures/submitted-sga-signature-role-values-identities.json');
  assert.deepEqual(submitted, expected);
  assert.deepEqual(expected.grammar, read('spec/manifests/actql-grammar-0.1.json'));
  assert.equal(before.run_preimages.run.run_definition_cid,
    'sha256:1b65662553b0ec3d4e55ec07eff0f9060b7a8ad6860466712cfb68576bc8d76a');
  assert.notEqual(expected.grammar.grammar_manifest_cid, before.grammar.grammar_manifest_cid);
  assert.notEqual(expected.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  assert.deepEqual(expected.values_dependencies, valuesDependencyOracle());
  assert.deepEqual(expected.program_identity, valuesProgramOracle());
  assert.equal(expected.aoa_contract_cid, signatureRoleCid(read('spec/contracts/actql-aoa.json')));
  assert.equal(expected.barrier_contract_manifest_cid,
    read('spec/manifests/actql-barrier-contracts-0.1.json').barrier_contract_manifest_cid);
  // Every non-query grammar input is the retained baseline, not a new product
  // observation relabeled as the predecessor.
  for (const key of Object.keys(before.grammar)) {
    if (!['query_text_grammar_sha256', 'query_text_rules_sha256', 'grammar_manifest_cid'].includes(key)) {
      assert.deepEqual(expected.grammar[key], before.grammar[key], key);
    }
  }
  for (const [name, field] of [['template', 'bound_invocation_template_cid'],
    ['executable', 'executable_plan_cid'], ['compiled', 'compiled_plan_cid'],
    ['run', 'run_definition_cid']]) {
    const {[field]: sealed, ...body} = submitted.run_preimages[name];
    assert.equal(signatureRoleCid(body), sealed, name);
  }
  assert.deepEqual(expected.run_preimages.executable.resolved_limits,
    before.run_preimages.executable.resolved_limits);
  assert.deepEqual(expected.run_preimages.executable.execution_material.program,
    before.run_preimages.executable.execution_material.program);
});
