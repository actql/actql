// Closed semantic projection only. Actual Store/installation custody is a
// separate nominal handle; admitting these bytes does not grant any operation.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export function modelOriginalStorageBindingSchema() {
  const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
  return {$schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-model-original-storage-binding-0.1.json',
    title: 'actql-model-original-storage-binding-0.1',
    type: 'object', additionalProperties: false,
    required: ['version', 'store_contract_wire', 'store_contract_cid',
      'store_authority_cid', 'key_generation_cid', 'private_namespace', 'self_cid'],
    properties: {
      version: {const: 'actql-model-original-storage-binding/0.1'},
      store_contract_wire: {type: 'string', minLength: 1, maxLength: 256},
      store_contract_cid: {...cid}, store_authority_cid: {...cid},
      key_generation_cid: {...cid},
      private_namespace: {const: 'local-continuation-private'}, self_cid: {...cid},
    }};
}

export function checkModelOriginalStorageBindingContract(write = false) {
  const path = 'spec/contracts/actql-run-publication.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  const schema = modelOriginalStorageBindingSchema();
  assert.deepEqual(registry.schemas.model_original_storage_binding, schema);
  const pin = {path, pointer: '/schemas/model_original_storage_binding',
    cid: machineCid(schema), version: registry.version};
  const manifestPath = 'spec/spec-family.json';
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const owner = manifest.documents.find(d => d.path === 'docs/spec/protocols/artifacts.md');
  assert.ok(owner);
  const old = owner.machine_contracts.find(p => p.path === path && p.pointer === pin.pointer);
  let source = readFileSync(owner.path, 'utf8');
  const section = '<!-- model-original-storage-binding-pins:start -->\n```text\n' +
    `../../../${path}#${pin.pointer} ${pin.cid}\n` +
    '```\n<!-- model-original-storage-binding-pins:end -->';
  const pattern = /<!-- model-original-storage-binding-pins:start -->[\s\S]*?<!-- model-original-storage-binding-pins:end -->/u;
  assert.ok(pattern.test(source));
  if (write) {
    if (old) Object.assign(old, pin); else owner.machine_contracts.push(pin);
    source = source.replace(pattern, section);
    writeFileSync(owner.path, source);
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  } else {
    assert.deepEqual(old, pin);
    assert.equal(source.match(pattern)[0], section);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  checkModelOriginalStorageBindingContract(process.argv.includes('--write'));
  console.log('Original Model private storage binding schema/pin verified.');
}
