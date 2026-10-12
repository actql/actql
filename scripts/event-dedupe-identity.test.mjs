import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {eventDedupeIdentityOracle} from './event-dedupe-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('event dedupe independently reseals grammar identities and retains window preimages', () => {
  const before = read('scripts/fixtures/pre-event-dedupe-values-identities.json');
  assert.deepEqual(before, read('scripts/fixtures/submitted-event-window-values-identities.json'));
  const expected = eventDedupeIdentityOracle({grammarPath:'scripts/fixtures/pre-row-watermark-query-grammar.ebnf',rulesPath:'scripts/fixtures/pre-row-watermark-query-rules.md'});
  assert.deepEqual(expected, read('scripts/fixtures/submitted-event-dedupe-values-identities.json'));
  assert.deepEqual(expected, read('scripts/fixtures/pre-row-watermark-values-identities.json'));
  assert.equal(before.run_preimages.run.run_definition_cid,
    'sha256:04a7dab8cbc36acd31b768288dce3bf69d8924a17561c6dcd1a923dd3216b81f');
  assert.notEqual(expected.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
  assert.deepEqual(expected.values_dependencies, valuesDependencyOracle());
  assert.deepEqual(expected.program_identity, valuesProgramOracle());
  for (const key of Object.keys(before.grammar)) {
    if (!['query_text_grammar_sha256','query_text_rules_sha256','grammar_manifest_cid'].includes(key))
      assert.deepEqual(expected.grammar[key], before.grammar[key], key);
  }
  for (const [name, field] of [['template','bound_invocation_template_cid'],
    ['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
    const {[field]: seal, ...body} = expected.run_preimages[name];
    assert.equal(signatureRoleCid(body), seal, name);
  }
  assert.deepEqual(expected.run_preimages.executable.resolved_limits, before.run_preimages.executable.resolved_limits);
  assert.deepEqual(expected.run_preimages.executable.execution_material.program,
    before.run_preimages.executable.execution_material.program);
});
