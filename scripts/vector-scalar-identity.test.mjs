import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {vectorScalarIdentityOracle} from './vector-scalar-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const prefix='reviews/2026-10-13-frontend-vector-scalars/preimages/';
test('vector scalar grammar-bound identity changes retain original Values bodies and history',()=>{
  const before=vectorScalarIdentityOracle({current:false}),after=vectorScalarIdentityOracle({rulesPath:'reviews/2026-10-13-frontend-vector-score-literal/preimages/query-rules.md'});
  assert.deepEqual(before,read(prefix+'pre-values.json'));
  assert.deepEqual(after,read(prefix+'current-values.json'));
  assert.deepEqual(after.grammar,read('reviews/2026-10-13-frontend-vector-score-literal/preimages/grammar.json')); // immutable parent grammar
  assert.deepEqual(after.values_dependencies,before.values_dependencies);
  assert.deepEqual(after.program_identity,before.program_identity);
  assert.deepEqual(after.run_preimages.executable.nodes,before.run_preimages.executable.nodes);
  assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
  assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
  assert.notEqual(after.grammar.grammar_manifest_cid,before.grammar.grammar_manifest_cid);
  for(const key of Object.keys(before.grammar)) if(!['query_text_rules_sha256','grammar_manifest_cid'].includes(key)) assert.deepEqual(after.grammar[key],before.grammar[key]);
});
