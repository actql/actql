// Independently reseal the adopted source-only generator connection. Complete
// parent preimages remain data; no product or returned identity is consulted.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {signatureRoleIdentityOracle} from './sga-signature-role-identity-oracle.mjs';
export const timeSeriesPrimaryIdentityOracle=(options={})=>signatureRoleIdentityOracle({
  beforePath:'scripts/fixtures/pre-time-series-primary-values-identities.json',
  sourceRevision:'authored-time-series-primary',...options,
});
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2),['--write']);
  const expected=timeSeriesPrimaryIdentityOracle();
  writeFileSync('scripts/fixtures/submitted-time-series-primary-values-identities.json',JSON.stringify(expected,null,2)+'\n');
  console.log(JSON.stringify({grammar:expected.grammar.grammar_manifest_cid,run:expected.run_preimages.run.run_definition_cid}));
}
