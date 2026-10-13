import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {currentValuesPreimages} from './sequence-current-preimages-oracle.mjs';
import {sequenceIdentityOracle,retainedSequenceIdentityOracle} from './sequence-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('Original sequence source keeps its full historical grammar-bound Run',()=>{
 const before=read('scripts/fixtures/pre-sequence-values-identities.json');
 assert.equal(before.source_revision,'7648dfc099f24e819ccaf49376cec57a45c5ea12');
 const after=retainedSequenceIdentityOracle();
 assert.deepEqual(after,read('scripts/fixtures/submitted-sequence-values-identities.json'));
 for(const v of [before,after]) for(const [name,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
  const {[field]:pin,...body}=v.run_preimages[name];assert.equal(signatureRoleCid(body),pin);
 }
 assert.deepEqual(after.values_dependencies,before.values_dependencies);
 assert.deepEqual(after.program_identity,before.program_identity);
});
test('Merged current contracts retain independent expression and query grammar inputs and containing Run preimages',()=>{
 const before=read('scripts/fixtures/pre-current-sequence-values-identities.json');
 assert.equal(before.source_revision,'d879fb93ae19a314c44f5fb8e1fea1461bc3d0d5');
 assert.deepEqual(currentValuesPreimages(before.grammar,before.source_revision),before);
 const after=sequenceIdentityOracle();assert.deepEqual(after,read('scripts/fixtures/current-sequence-values-identities.json'));
 assert.deepEqual(after.grammar,read('spec/manifests/actql-grammar-0.1.json'));
 const mutable=new Set(['expression_contract_cid','expression_text_grammar_sha256',
  'expression_text_rules_sha256','query_text_grammar_sha256','query_text_rules_sha256','grammar_manifest_cid']);
 const retained=grammar=>Object.fromEntries(Object.entries(grammar).filter(([key])=>!mutable.has(key)));
 assert.deepEqual(retained(after.grammar),retained(before.grammar));
 assert.deepEqual(after.values_dependencies,before.values_dependencies);
 assert.deepEqual(after.program_identity,before.program_identity);
 assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
 assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
});
