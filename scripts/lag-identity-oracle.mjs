// Independent current preimages retain complete submitted row-watermark history.
// Only the test oracle is imported; no product compiler or manifest generator.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {signatureRoleIdentityOracle} from './sga-signature-role-identity-oracle.mjs';
export const lagIdentityOracle = (options = {}) => signatureRoleIdentityOracle({
  beforePath: 'scripts/fixtures/pre-lag-values-identities.json',
  sourceRevision: 'authored-lag-source',
  ...options,
});
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.deepEqual(process.argv.slice(2), ['--write']);
  const expected = lagIdentityOracle();
  writeFileSync('scripts/fixtures/submitted-lag-values-identities.json',
    JSON.stringify(expected, null, 2) + '\n');
  console.log(JSON.stringify({grammar: expected.grammar.grammar_manifest_cid,
    template: expected.run_preimages.template.bound_invocation_template_cid,
    executable: expected.run_preimages.executable.executable_plan_cid,
    compiled: expected.run_preimages.compiled.compiled_plan_cid,
    run: expected.run_preimages.run.run_definition_cid}));
}
