// Source/API reference coverage through the existing readers, not a second
// semantic validator or evidence of installed/service execution.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';
import {moonOperations, moonApiInterface} from './moon-interface-inventory.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const declarations = JSON.parse(readFileSync(new URL(
  '../src/connectors/gcs/interface-boundaries.json', import.meta.url))).declarations;
const paths = ['src/connectors/gcs/catalog/upload_construction.mbt',
  'src/connectors/gcs/catalog/source_facts_construction.mbt',
  'src/connectors/gcs/catalog/object_metadata.mbt',
  'src/connectors/gcs/catalog/object_target_observation.mbt',
  'src/connectors/gcs/catalog/target_headers.mbt',
  'src/connectors/gcs/catalog/object_request.mbt',
  'src/connectors/gcs/catalog/object_projection.mbt',
  'src/connectors/gcs/catalog/collection_identity.mbt',
  'src/connectors/gcs/catalog/pkg.generated.mbti',
  'src/connectors/gcs/host_node/object.mbt',
  'src/connectors/gcs/host_node/collection.mbt',
  'src/connectors/gcs/host_node/pkg.generated.mbti',
  'adapters/connectors/gcs/host/gcs-collection-target.mjs',
  'src/connectors/gcs/catalog/upload_declaration.mbt',
  'src/connectors/gcs/catalog/object_mutation_mapping.mbt',
  'src/connectors/gcs/catalog/object_mutation_recovery.mbt',
  'src/connectors/gcs/catalog/object_page.mbt',
  'src/connectors/gcs/host_node/upload.mbt',
  'adapters/connectors/gcs/host/gcs-upload-declaration.mjs',
  'src/connectors/gcs/original_reference/collection.mbt',
  'src/connectors/gcs/original_reference/pkg.generated.mbti',
  'src/connectors/gcs/host_node/original_reference.mbt',
  'src/connectors/gcs/catalog/object_upload.mbt',
  'src/connectors/gcs/catalog/object_upload_outcome.mbt',
  'src/connectors/gcs/catalog/object_mutation_outcome.mbt',
  'src/connectors/gcs/host_node/upload_request.mbt',
  'adapters/connectors/gcs/site/gcs-owned-upload-request.mjs',
  'adapters/connectors/gcs/site/gcs-object-listing.mjs',
  'src/connectors/gcs/catalog/object_compose.mbt',
  'src/connectors/gcs/host_node/compose.mbt',
  'adapters/connectors/gcs/site/gcs-owned-compose-request.mjs',
  'adapters/connectors/gcs/site/gcs-credential-site.mjs',
  'adapters/connectors/gcs/site/gcs-owned-object-request.mjs'];
const moduleOf = (module, source = readFileSync(new URL(`../${module}`, import.meta.url), 'utf8')) => ({
  module, sha256: createHash('sha256').update(source).digest('hex'),
  ...(module.endsWith('.mjs') ? javascriptInterface(source)
    : module.endsWith('.mbti') ? moonApiInterface(source)
      : {operations: moonOperations(source), exports: []}),
});

test('all thirty-three explicit GCS owner modules and APIs retain their ten contract references', () => {
  assert.equal(declarations.length, 33);
  assert.equal(assertInterfaceCoverage({root, modules: paths.map(path => moduleOf(path)), declarations}), 33);
  assert.deepEqual(moduleOf(paths.at(-1)).compilerFields, []);
});

test('an additional private decision cannot inherit a GCS physical module declaration', () => {
  const path = paths.at(-1);
  const changed = moduleOf(path, readFileSync(new URL(`../${path}`, import.meta.url), 'utf8') +
    '\nfunction decideUnregisteredGcsApply() { return "applied"; }\n');
  const modified = structuredClone(declarations);
  modified.find(value => value.module === path).sha256 = changed.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [changed], declarations: modified}),
    /Unregistered interface operation/u);
});

test('the real GCS Result consumer cannot read compiler fields outside the generated binding', () => {
  const path = paths.at(-1);
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const altered = source.replace('return checked(result);',
    'return result.$tag === 1 ? result._0 : checked(result);');
  assert.notEqual(altered, source);
  const changed = moduleOf(path, altered);
  const modified = structuredClone(declarations);
  modified.find(value => value.module === path).sha256 = changed.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [changed], declarations: modified}),
    /Compiler representation outside generated binding/u);
});
