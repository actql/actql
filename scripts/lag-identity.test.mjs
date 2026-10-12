import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {lagIdentityOracle} from './lag-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
test('Lag independently reseals grammar identities and retains watermark preimages', () => {
  const before = read('scripts/fixtures/pre-lag-values-identities.json');
  assert.deepEqual(before, read('scripts/fixtures/submitted-row-watermark-values-identities.json'));
  const expected = lagIdentityOracle({grammarPath:'reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/query-grammar.ebnf',rulesPath:'reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/query-rules.md'});
  assert.deepEqual(expected, read('scripts/fixtures/submitted-lag-values-identities.json'));
  assert.deepEqual(expected.grammar, read('reviews/2026-10-12-frontend-nearest-carrier-roles/preimages/grammar-manifest.json'));
  assert.equal(before.run_preimages.run.run_definition_cid,
    'sha256:f20f0c27ff197830a5bb7fd601e02d738547745bd1657cb42db376f754498adb');
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
