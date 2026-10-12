import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {currentValuesPreimages} from './ranking-fusion-current-preimages-oracle.mjs';
import {rankingFusionIdentityOracle} from './ranking-fusion-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('ranking syntax retains the complete current parent and changes grammar-bound Runs only',()=>{
 const before=read('scripts/fixtures/pre-ranking-fusion-values-identities.json');
 assert.equal(before.source_revision,'b3a0cfafffeee515fcceb8a5ae59f1b4f63ca617');
 assert.deepEqual(currentValuesPreimages(before.grammar,before.source_revision),before);
 const after=rankingFusionIdentityOracle({
  grammarPath:'reviews/2026-10-12-frontend-ranking-fusion-calls/preimages/submitted-query-grammar.ebnf',
  rulesPath:'reviews/2026-10-12-frontend-ranking-fusion-calls/preimages/submitted-query-rules.md',
 });
 assert.deepEqual(after,read('scripts/fixtures/submitted-ranking-fusion-values-identities.json'));
 assert.deepEqual(after.values_dependencies,before.values_dependencies);
 assert.deepEqual(after.program_identity,before.program_identity);
 assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
 assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
});
