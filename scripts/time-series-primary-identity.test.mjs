import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {timeSeriesPrimaryIdentityOracle} from './time-series-primary-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('time-series primary preserves machine contracts and complete parent identities',()=>{
  const before=read('scripts/fixtures/pre-time-series-primary-values-identities.json');
  assert.deepEqual(before,read('scripts/fixtures/submitted-nearest-join-values-identities.json'));
  // Retain this submitted frontend unit; later FILES grammar is checked separately.
  const after=timeSeriesPrimaryIdentityOracle({
    grammarPath:'reviews/2026-10-12-frontend-time-series-primary/preimages/submitted-query-grammar.ebnf',
    rulesPath:'reviews/2026-10-12-frontend-time-series-primary/preimages/submitted-query-rules.md'});
  assert.deepEqual(after,read('scripts/fixtures/submitted-time-series-primary-values-identities.json'));
  assert.deepEqual(after.values_dependencies,before.values_dependencies);
  assert.deepEqual(after.program_identity,before.program_identity);
  assert.deepEqual(after.grammar,{...before.grammar,query_text_rules_sha256:after.grammar.query_text_rules_sha256,
    query_text_grammar_sha256:after.grammar.query_text_grammar_sha256,grammar_manifest_cid:after.grammar.grammar_manifest_cid});
  for(const [name,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
    for(const v of [before,after]) { const {[field]:seal,...body}=v.run_preimages[name]; assert.equal(signatureRoleCid(body),seal); }
  }
  assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
  assert.deepEqual(after.run_preimages.executable.execution_material.program,before.run_preimages.executable.execution_material.program);
  assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
});
