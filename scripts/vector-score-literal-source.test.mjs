import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {vectorScoreLiteralSuccesses,vectorScoreLiteralRefusals} from './fixtures/vector-score-literal-public-input.mjs';
import {vectorScalarSourceSuccesses} from './fixtures/vector-scalar-source-input.mjs';
import {vectorScoreLiteralIdentityOracle} from './vector-score-literal-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const prefix='reviews/2026-10-13-frontend-vector-score-literal/preimages/';
test('canonical score independent values keep l2 negative and the distance alias positive',()=>{
 assert.equal(vectorScoreLiteralSuccesses.length,9);assert.equal(vectorScoreLiteralRefusals.length,12);
 for(const c of vectorScoreLiteralSuccesses){assert.deepEqual(c.results.answer.columns.map(c=>c.name),['id','value']);assert.equal(c.results.answer.rows[2].value,null);assert.equal(c.sourceReadSessionCount,c.format==='json'?0:1);}
 const l2=vectorScoreLiteralSuccesses.find(c=>c.name==='vector-score-literal-l2-json');
 assert.equal(l2.results.answer.rows[0].value,-5);
 assert.equal(JSON.parse(l2.text).stages[0].steps[1].derive.value.vector_score.metric,'l2');
 assert.equal(vectorScalarSourceSuccesses.find(c=>c.name==='vector-scalar-l2-json').results.answer.rows[0].value,5);
 for(const c of vectorScoreLiteralRefusals)assert.equal(c.expectedCode,'ClientProgramInvalidInput');
 const p=vectorScoreLiteralRefusals.find(c=>c.name.includes('parameter'));assert.deepEqual(p.parameterDeclarations,{metric:{type:'string'}});assert.deepEqual(p.parameters,{metric:'dot'});
 assert.equal(new Set([...vectorScoreLiteralSuccesses,...vectorScoreLiteralRefusals].map(c=>c.name)).size,21);
});
test('canonical score reidentifies only authored rules and retains alias preimages',()=>{
 const before=vectorScoreLiteralIdentityOracle({current:false}),after=vectorScoreLiteralIdentityOracle();
 assert.deepEqual(before,read(prefix+'pre-values.json'));assert.deepEqual(after,read(prefix+'current-values.json'));
 assert.deepEqual(after.grammar,read('spec/manifests/actql-grammar-0.1.json'));
 assert.deepEqual(after.values_dependencies,before.values_dependencies);assert.deepEqual(after.program_identity,before.program_identity);
 assert.deepEqual(after.run_preimages.executable.nodes,before.run_preimages.executable.nodes);
 assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
 assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
 assert.equal(before.grammar.grammar_manifest_cid,read('reviews/2026-10-13-frontend-vector-scalars/preimages/current-values.json').grammar.grammar_manifest_cid);
});
