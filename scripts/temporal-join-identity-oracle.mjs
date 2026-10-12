// Rehash the authored rule update from retained complete parent preimages.
// No product compiler, canonicalizer or runtime output supplies expectations.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {signatureRoleIdentityOracle} from './sga-signature-role-identity-oracle.mjs';
export const temporalJoinIdentityOracle = (options = {}) => signatureRoleIdentityOracle({
  beforePath:'scripts/fixtures/pre-temporal-join-values-identities.json',
  sourceRevision:'authored-temporal-join-calls',...options,
});
if(process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2),['--write']);
  const expected=temporalJoinIdentityOracle();
  writeFileSync('scripts/fixtures/submitted-temporal-join-values-identities.json',JSON.stringify(expected,null,2)+'\n');
  console.log(JSON.stringify({grammar:expected.grammar.grammar_manifest_cid,
    run:expected.run_preimages.run.run_definition_cid}));
}
