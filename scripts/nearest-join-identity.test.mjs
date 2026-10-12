import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {nearestJoinIdentityOracle} from './nearest-join-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('JOIN continuation preserves complete parent identities and changes only authored rules',()=>{
  const before=read('scripts/fixtures/pre-nearest-join-values-identities.json');
  assert.deepEqual(before,read('scripts/fixtures/submitted-nearest-continuation-values-identities.json'));
  const after=nearestJoinIdentityOracle({grammarPath:'reviews/2026-10-12-frontend-time-series-primary/preimages/query-grammar.ebnf',rulesPath:'reviews/2026-10-12-frontend-time-series-primary/preimages/query-rules.md'});
  assert.deepEqual(after,read('scripts/fixtures/submitted-nearest-join-values-identities.json'));
  assert.deepEqual(after.grammar,read('reviews/2026-10-12-frontend-time-series-primary/preimages/grammar-manifest.json'));
  assert.deepEqual(after.values_dependencies,before.values_dependencies);
  assert.deepEqual(after.program_identity,before.program_identity);
  assert.deepEqual(after.grammar,{...before.grammar,
    query_text_rules_sha256:after.grammar.query_text_rules_sha256,
    grammar_manifest_cid:after.grammar.grammar_manifest_cid});
  assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
  for(const [name,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
    for(const v of [before,after]) {
      const {[field]:seal,...body}=v.run_preimages[name];
      assert.equal(signatureRoleCid(body),seal);
    }
  }
  assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
  assert.deepEqual(after.run_preimages.executable.execution_material.program,before.run_preimages.executable.execution_material.program);
});
