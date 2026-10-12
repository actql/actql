import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {vectorPoolIdentityOracle} from './vector-pool-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('vector pooling changes only authored grammar-bound identities and retains complete SGA history', () => {
  const before = read('scripts/fixtures/pre-vector-pool-values-identities.json');
  assert.deepEqual(before, read('scripts/fixtures/submitted-sga-signature-role-values-identities.json'));
  const expected = vectorPoolIdentityOracle({
    grammarPath: 'scripts/fixtures/pre-event-window-query-grammar.ebnf',
    rulesPath: 'scripts/fixtures/pre-event-window-query-rules.md',
  });
  assert.deepEqual(expected, read('scripts/fixtures/submitted-vector-pool-values-identities.json'));
  assert.deepEqual(expected, read('scripts/fixtures/pre-event-window-values-identities.json'));
  assert.equal(before.run_preimages.run.run_definition_cid,
    'sha256:12bf2b06808781ed3ee15ce8fd7e9ad229401a075bfc69f00960899fb9ff912c');
  assert.notEqual(expected.grammar.grammar_manifest_cid, before.grammar.grammar_manifest_cid);
  assert.notEqual(expected.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  assert.deepEqual(expected.values_dependencies, valuesDependencyOracle());
  assert.deepEqual(expected.program_identity, valuesProgramOracle());
  for (const key of Object.keys(before.grammar)) {
    if (!['query_text_grammar_sha256', 'query_text_rules_sha256', 'grammar_manifest_cid'].includes(key))
      assert.deepEqual(expected.grammar[key], before.grammar[key], key);
  }
  for (const [name, field] of [['template', 'bound_invocation_template_cid'],
    ['executable', 'executable_plan_cid'], ['compiled', 'compiled_plan_cid'],
    ['run', 'run_definition_cid']]) {
    const {[field]: sealed, ...body} = expected.run_preimages[name];
    assert.equal(signatureRoleCid(body), sealed, name);
  }
  assert.deepEqual(expected.run_preimages.executable.resolved_limits, before.run_preimages.executable.resolved_limits);
  assert.deepEqual(expected.run_preimages.executable.execution_material.program,
    before.run_preimages.executable.execution_material.program);
});
