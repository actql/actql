import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
export const installationStorageSchemaName = 'installation_publication_storage_binding';

// The existing publication Owner supplies this private DATA contract. It is
// deliberately separate from Model/Run evidence and supplies no admission.
export function installationPublicationStorageSchema() {
  const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-installation-publication-storage-binding-0.1.json',
    title: 'actql-installation-publication-storage-binding-0.1',
    type: 'object', additionalProperties: false,
    required: ['key_generation_cid', 'private_namespace', 'store_authority_cid',
      'store_contract_wire', 'version'],
    properties: {
      key_generation_cid: cid,
      private_namespace: {const: 'publication-private'},
      store_authority_cid: cid,
      store_contract_wire: {type: 'string', minLength: 1},
      version: {const: 'actql-installation-publication-storage-binding/0.1'},
    },
    $comment: 'Byte-addressed DATA, no self CID. Common checks the exact existing Store contract serialization against store_authority_cid. Physical original membership, authenticated installation generation, metadata capture and funding remain independent.',
  };
}

export function checkInstallationPublicationStorageSchema(registry) {
  const schema = installationPublicationStorageSchema();
  assert.deepEqual(registry.artifact_schemas[installationStorageSchemaName], schema);
  assert.equal(registry.artifact_schema_cids[installationStorageSchemaName], machineCid(schema));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    const schema = installationPublicationStorageSchema();
    registry.artifact_schemas[installationStorageSchemaName] = schema;
    registry.artifact_schema_cids[installationStorageSchemaName] = machineCid(schema);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    const familyPath = 'spec/spec-family.json';
    const family = JSON.parse(readFileSync(familyPath, 'utf8'));
    const owner = family.documents.find(value => value.document_id === 'run');
    assert.ok(owner);
    const pointer = '/artifact_schemas/' + installationStorageSchemaName;
    const reference = {path, pointer,
      cid: registry.artifact_schema_cids[installationStorageSchemaName], version: registry.version};
    const index = owner.machine_contracts.findIndex(value => value.path === path && value.pointer === pointer);
    if (index < 0) owner.machine_contracts.push(reference);
    else owner.machine_contracts[index] = reference;
    writeFileSync(familyPath, JSON.stringify(family, null, 2) + '\n');
  }
  checkInstallationPublicationStorageSchema(registry);
}
