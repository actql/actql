import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {currentValuesPreimages} from './sequence-current-preimages-oracle.mjs';
import {sequenceIdentityOracle} from './sequence-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('source Expression connection retains complete parent and changes grammar-bound Runs only',()=>{
 const before=read('scripts/fixtures/pre-sequence-values-identities.json');
 assert.equal(before.source_revision,'7648dfc099f24e819ccaf49376cec57a45c5ea12');
 assert.deepEqual(currentValuesPreimages(before.grammar,before.source_revision),before);
 const after=sequenceIdentityOracle();assert.deepEqual(after,read('scripts/fixtures/submitted-sequence-values-identities.json'));
 assert.deepEqual(after.grammar,read('spec/manifests/actql-grammar-0.1.json'));
 assert.deepEqual(after.values_dependencies,before.values_dependencies);
 assert.deepEqual(after.program_identity,before.program_identity);
 assert.deepEqual(after.run_preimages.executable.resolved_limits,before.run_preimages.executable.resolved_limits);
 assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
});
