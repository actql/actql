import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {nativeLocalDefaultAssets, nativeLocalDefaultFixture} from './native-cli-default-assets.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('Local product assets retain source-free environment and unknown Result Policy', () => {
  const assets = nativeLocalDefaultAssets();
  assert.deepEqual([...assets.keys()], ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy']);
  const environment = JSON.parse(assets.get('environment'));
  assert.equal(assets.get('environment').toString('utf8'), JSON.stringify(JSON.parse(readFileSync(new URL('../spec/local-check-environment.json', import.meta.url)))));
  for (const name of ['source_views', 'model_task_contracts', 'command_contracts', 'connector_capabilities',
    'connector_catalogs', 'mapping_contracts', 'schema_snapshots', 'contract_registry']) assert.deepEqual(environment[name], []);
  assert.equal(environment.host_policy_profile.capacity.max_artifact_bytes, 1000);
  assert.equal(digest(assets.get('result-policy')), '470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563');
  assert.deepEqual(JSON.parse(assets.get('result-policy')), {classification: 'unknown', source_data_policy_cids: [],
    source_response_policy_cids: [], unknown_provenance: true, version: 'actql-effective-data-policy/0.1'});
});

test('Local input fixtures are fresh and use the existing contract originals', () => {
  assert.equal(readFileSync(new URL('../src/run_publication_host/client_local_product_assets.generated_wbtest.mbt', import.meta.url), 'utf8'), nativeLocalDefaultFixture());
  const aoa = JSON.parse(readFileSync(new URL('../spec/contracts/actql-aoa.json', import.meta.url)));
  const assets = nativeLocalDefaultAssets();
  for (const [role, contract] of [['values', 'REL.values'], ['fragment', 'ACTQL.expression_fragment/0.1'], ['ordered', 'REL.derive.ordered']]) {
    assert.deepEqual(JSON.parse(assets.get(role)), aoa.execution_contracts[contract]);
  }
  assert(assets.get('registry').length + assets.get('values').length + assets.get('fragment').length + assets.get('ordered').length < 65536);
});
