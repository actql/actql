// Source-bound inputs for the existing Native Local runtime recipe. This does
// not create a Host, grant authority or assemble a consumer configuration.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const policy = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';

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
    '  }\n}\n';
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
