// Source-bound inputs for the existing Native Local runtime recipe. This does
// not create a Host, grant authority or assemble a consumer configuration.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const policy = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';

// A distinct original for explicit initial signing adoption, not an execution
// profile, Submission TTL, generic issue permission or initialization itself.
export function nativeLocalDefaultSigningPolicy(sourceRoot = root) {
  const value = JSON.parse(readFileSync(resolve(sourceRoot,
    'spec/contracts/local-signing-bootstrap-policy.json'), 'utf8'));
  assert.deepEqual(Object.keys(value), ['max_issue_interval_ms', 'max_uses', 'version']);
  assert.equal(value.max_issue_interval_ms, 300000);
  assert.equal(value.max_uses, 1);
  assert.equal(value.version, 'actql-local-signing-bootstrap-policy/0.1');
  return value;
}

export function nativeLocalDefaultAssets(sourceRoot = root) {
  const read = path => readFileSync(resolve(sourceRoot, path));
  const aoa = JSON.parse(read('spec/contracts/actql-aoa.json'));
  const json = value => Buffer.from(JSON.stringify(value));
  const assets = new Map([
    // The environment Owner requires canonical envelope bytes. Serializing
    // the source JSON removes file formatting only; no string normalization.
    ['environment', json(JSON.parse(read('spec/local-check-environment.json')))],
    ['registry', json(JSON.parse(read(aoa.pipeline_registry_file)))],
    ['values', json(aoa.execution_contracts['REL.values'])],
    ['fragment', json(aoa.execution_contracts['ACTQL.expression_fragment/0.1'])],
    ['ordered', json(aoa.execution_contracts['REL.derive.ordered'])],
    ['result-policy', Buffer.from(policy)],
  ]);
  for (const [role, bytes] of assets) {
    assert(bytes.length > 0 && bytes.length <= 65536, `Bounded original required: ${role}`);
    JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  }
  return assets;
}

export function nativeLocalDefaultFixture(sourceRoot = root) {
  const assets = nativeLocalDefaultAssets(sourceRoot);
  // Registry/Values/ordered fixtures already come from the authoritative
  // lowering-registry generator. Generate only the two additional inputs;
  // expectations in the tests are independent of the product assembler.
  return '// Generated inputs by scripts/native-cli-default-assets.mjs --write. Do not edit.\n' +
    ['environment', 'fragment'].map(role => `\n///|\nfn product_test_${role}_wire() -> String {\n  ${JSON.stringify(assets.get(role).toString('utf8'))}\n}\n`).join('');
}

export function localProductDefaultAssets(sourceRoot = root) {
  const assets = nativeLocalDefaultAssets(sourceRoot);
  const signing = nativeLocalDefaultSigningPolicy(sourceRoot);
  const fields = ['environment', 'registry', 'values', 'fragment'];
  // Embed the same original recipe bytes for installed portable Hosts. This
  // getter issues no authority and must not replace retained adoption originals.
  return '// Generated inputs by scripts/native-cli-default-assets.mjs --write. Do not edit.\n' +
    '\n///|\n/// Packaged source-free originals for explicit first adoption only.\n' +
    '/// Existing Account, Policy, Store and custody Owners still decide admission.\n' +
    'pub fn client_local_product_assets() -> ClientLocalProductAssets {\n  {\n' +
    fields.map(role => `    ${role}: ${JSON.stringify(assets.get(role).toString('utf8'))},\n`).join('') +
    `    ordered: Some(\n      ${JSON.stringify(assets.get('ordered').toString('utf8'))},\n    ),\n` +
    `    result_policy: ${JSON.stringify(assets.get('result-policy').toString('utf8'))},\n` +
    '  }\n}\n' +
    '\n///|\n// Packaged DATA only; the actual Host retains authenticated first-adoption custody.\n' +
    'fn client_local_default_signing_policy_wire() -> String {\n  ' +
    JSON.stringify(JSON.stringify(signing)) + '\n}\n' +
    '\n///|\nfn client_local_default_signing_issue_interval() -> Int64 {\n  ' +
    signing.max_issue_interval_ms + 'L\n}\n' +
    '\n///|\nfn client_local_default_signing_max_uses() -> Int {\n  ' +
    signing.max_uses + '\n}\n';
}

// Fresh construction binds the current generated originals. It does not
// certify a historical implementation, installation, permission or funding.
export function assertNativeLocalDefaultAssetsFresh(sourceRoot = root) {
  for (const [relative, body] of [
    ['src/run_publication_host/client_local_product_assets.generated_wbtest.mbt', nativeLocalDefaultFixture(sourceRoot)],
    ['src/run_publication_host/client_local_product_assets.generated.mbt', localProductDefaultAssets(sourceRoot)],
  ]) assert.equal(readFileSync(resolve(sourceRoot, relative), 'utf8'), body,
    'stale source-bound Local asset inputs');
}

export function assertNativeLocalFreshRuntimeRecipe(recipe, expectedSource, sourceRoot = root) {
  assert.match(expectedSource, /^[a-f0-9]{40}$/u);
  assert.equal(recipe.sourceSha, expectedSource, 'Fresh runtime requires the exact producer source');
  assertNativeLocalDefaultAssetsFresh(sourceRoot);
  const originals = nativeLocalDefaultAssets(sourceRoot);
  assert(Array.isArray(recipe.assets) && recipe.assets.length === originals.size,
    'Fresh runtime requires every current generated asset');
  const seen = new Set();
  for (const asset of recipe.assets) {
    assert(originals.has(asset.role) && !seen.has(asset.role), 'Unknown or duplicate fresh asset role');
    seen.add(asset.role);
    const bytes = originals.get(asset.role);
    assert.equal(asset.original.bytes, bytes.length, 'Fresh asset size differs from its current original');
    assert.equal(asset.original.sha256, createHash('sha256').update(bytes).digest('hex'),
      'Fresh asset differs from its current generated original');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert(process.argv.length === 3 && ['--check', '--write'].includes(process.argv[2]));
  const outputs = [
    ['src/run_publication_host/client_local_product_assets.generated_wbtest.mbt', nativeLocalDefaultFixture()],
    ['src/run_publication_host/client_local_product_assets.generated.mbt', localProductDefaultAssets()],
  ];
  for (const [relative, body] of outputs) {
    const path = resolve(root, relative);
    if (process.argv[2] === '--write') writeFileSync(path, body);
    else assert.equal(readFileSync(path, 'utf8'), body, 'stale source-bound Local asset inputs');
  }
}
