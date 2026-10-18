import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {emitSchema} from './run-publication-protocol.mjs';
import {checkInstallationPublicationStorageSchema,
  installationPublicationStorageSchema} from './installation-publication-storage-contract.mjs';

test('installation publication storage DATA schema has exact registered identity', () => {
  checkInstallationPublicationStorageSchema(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
  const schema = installationPublicationStorageSchema();
  assert.equal(schema.additionalProperties, false);
  assert.equal(schema.required.length, 5);
  assert.equal(schema.properties.private_namespace.const, 'publication-private');
  assert.equal(Object.hasOwn(schema.properties, 'self_cid'), false);
  assert.equal(Object.hasOwn(schema.properties, 'run_definition_cid'), false);
  assert.doesNotThrow(() => emitSchema(schema));
});

test('ordinary publication generation rejects a removed or weakened storage declaration', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  const missing = structuredClone(registry);
  delete missing.artifact_schemas.installation_publication_storage_binding;
  assert.throws(() => checkInstallationPublicationStorageSchema(missing));
  const changed = structuredClone(registry);
  changed.artifact_schemas.installation_publication_storage_binding.additionalProperties = true;
  assert.throws(() => checkInstallationPublicationStorageSchema(changed));
});

test('installation storage independent fixed vector is consumed by actual Common', () => {
  // The contract's raw Store serialization is intentionally not lexically sorted.
  const authority = 'sha256:' + '1'.repeat(64), key = 'sha256:' + '2'.repeat(64);
  const wire = JSON.stringify({key_generation_cid: key,
    private_namespace: 'publication-private', store_authority_cid: authority,
    store_contract_wire: JSON.stringify({version: 'actql-local-publication-store/0.1',
      isolation: 'execution-namespace', store_authority_cid: authority}),
    version: 'actql-installation-publication-storage-binding/0.1'});
  assert.equal(Buffer.byteLength(wire), 511);
  assert.equal(createHash('sha256').update(wire).digest('hex'),
    'bd174597f54d8a6dc4f7df7a5dc5ee41fb05f4e25651d6553983a5de9824c7f7');
  const source = readFileSync('src/run_publication/installation_publication_storage_binding_wbtest.mbt', 'utf8');
  assert.ok(source.includes('#|' + wire));
});
