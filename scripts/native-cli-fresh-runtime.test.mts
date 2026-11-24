import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';
import {assertNativeLocalFreshRuntimeRecipe, assertNativeLocalDefaultAssetsFresh} from './native-cli-default-assets.mjs';
import {assertScalarPairEvidenceFresh, loadScalarPairBodies} from './native-local-scalar-pair-evidence.mjs';

type Aoa = {pipeline_registry_file: string; execution_contracts: Record<string, unknown>};
type Recipe = ReturnType<typeof currentRecipe>;

const source = 'a'.repeat(40);
function currentRecipe() {
  const aoa = JSON.parse(readFileSync('spec/contracts/actql-aoa.json') as unknown as string) as Aoa;
  const bodies = {
    environment: JSON.parse(readFileSync('spec/local-check-environment.json') as unknown as string),
    registry: JSON.parse(readFileSync(aoa.pipeline_registry_file) as unknown as string),
    values: aoa.execution_contracts['REL.values'],
    fragment: aoa.execution_contracts['ACTQL.expression_fragment/0.1'],
    ordered: aoa.execution_contracts['REL.derive.ordered'],
    'result-policy': {classification:'unknown', source_data_policy_cids:[],
      source_response_policy_cids:[], unknown_provenance:true, version:'actql-effective-data-policy/0.1'},
    query: JSON.parse(readFileSync('spec/contracts/actql-query-acquisition.json') as unknown as string),
    'query-evidence': JSON.parse(readFileSync('spec/contracts/actql-query-process-evidence.json') as unknown as string),
  };
  return {sourceSha:source, assets:Object.entries(bodies).map(([role, body]) => {
    const bytes = Buffer.from(JSON.stringify(body));
    return {role, original:{path:'/not-opened-by-metadata-check/'+role,
      bytes:bytes.length, sha256:createHash('sha256').update(bytes).digest('hex')}};
  })};
}

test('fresh current originals remain distinct from the refused historical implementation', () => {
  assertNativeLocalDefaultAssetsFresh();
  assertNativeLocalFreshRuntimeRecipe(currentRecipe(), source);
  assertScalarPairEvidenceFresh();
  assert.throws(() => loadScalarPairBodies(), /Unknown scalar implementation change: /u);
});

test('fresh recipe refuses foreign source and incomplete duplicate unknown or altered asset originals', () => {
  for (const change of [
    (x: Recipe) => {x.sourceSha='b'.repeat(40);},
    (x: Recipe) => {x.assets.pop();},
    (x: Recipe) => {x.assets[1]={...x.assets[0]};},
    (x: Recipe) => {x.assets[0].role='historical';},
    (x: Recipe) => {x.assets[0].original.bytes++;},
    (x: Recipe) => {x.assets[0].original.sha256='0'.repeat(64);},
  ]) {
    const recipe=currentRecipe();change(recipe);
    assert.throws(() => assertNativeLocalFreshRuntimeRecipe(recipe, source));
  }
});

test('fresh current generated inputs cannot be replaced by a stale compiled asset body', () => {
  const root=mkdtempSync(join(tmpdir(),'actql-fresh-runtime-inputs-'));
  try {
    // Copy only the normal generator's declared finite input owners and outputs.
    const aoa=JSON.parse(readFileSync('spec/contracts/actql-aoa.json') as unknown as string) as Aoa;
    for (const path of ['spec/contracts/actql-aoa.json', aoa.pipeline_registry_file,
      'spec/local-check-environment.json', 'spec/contracts/local-signing-bootstrap-policy.json',
      'spec/contracts/actql-query-acquisition.json', 'spec/contracts/actql-query-process-evidence.json']) {
      const target=join(root,path);mkdirSync(dirname(target),{recursive:true});copyFileSync(path,target);
    }
    mkdirSync(join(root,'src/run_publication_host'),{recursive:true});
    for (const name of ['client_local_product_assets.generated.mbt','client_local_product_assets.generated_wbtest.mbt']) {
      writeFileSync(join(root,'src/run_publication_host',name),readFileSync('src/run_publication_host/'+name));
    }
    assertNativeLocalDefaultAssetsFresh(root);
    const output=join(root,'src/run_publication_host/client_local_product_assets.generated.mbt');
    writeFileSync(output,readFileSync(output,'utf8')+'\n// stale original\n');
    assert.throws(() => assertNativeLocalFreshRuntimeRecipe(currentRecipe(), source, root),
      /stale source-bound Local asset inputs/u);
  } finally {rmSync(root,{recursive:true,force:true});}
});
