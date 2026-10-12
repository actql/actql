// Rehash authored source rules against complete independently assembled parents.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {signatureRoleIdentityOracle} from './sga-signature-role-identity-oracle.mjs';
export const rankingFusionIdentityOracle=(options={})=>signatureRoleIdentityOracle({beforePath:'scripts/fixtures/pre-ranking-fusion-values-identities.json',sourceRevision:'authored-ranking-fusion-calls',...options});
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2),['--write']);
  const expected=rankingFusionIdentityOracle();
  writeFileSync('scripts/fixtures/submitted-ranking-fusion-values-identities.json',JSON.stringify(expected,null,2)+'\n');
  console.log(JSON.stringify({grammar:expected.grammar.grammar_manifest_cid,run:expected.run_preimages.run.run_definition_cid}));
}
