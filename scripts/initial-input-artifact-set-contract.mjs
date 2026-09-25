import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
export const emptyInitialInputSetBody = Object.freeze({
  version: 'actql-initial-input-artifact-set/0.1',
  captured_artifact_cids: Object.freeze([]),
});
export const emptyInitialInputSetCid = machineCid(emptyInitialInputSetBody);

export function initialInputArtifactSetSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-initial-input-artifact-set-0.1.json',
    title: 'actql-initial-input-artifact-set-0.1',
    type: 'object', additionalProperties: false,
    required: ['version', 'captured_artifact_cids'],
    properties: {
      version: {const: 'actql-initial-input-artifact-set/0.1'},
      captured_artifact_cids: {type: 'array', maxItems: 0},
    },
  };
}

export function admitEmptyInitialInputSet(body, claimedCid) {
  assert.deepEqual(body, emptyInitialInputSetBody);
  assert.equal(claimedCid, emptyInitialInputSetCid);
  return emptyInitialInputSetCid;
}

export function applyInitialInputArtifactSetSchema(registry) {
  const schema = initialInputArtifactSetSchema();
  registry.artifact_schemas.initial_input_artifact_set = schema;
  registry.artifact_schema_cids.initial_input_artifact_set =
    machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkInitialInputArtifactSetSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.initial_input_artifact_set,
    initialInputArtifactSetSchema());
  assert.equal(registry.artifact_schema_cids.initial_input_artifact_set,
    machineCid(initialInputArtifactSetSchema()));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyInitialInputArtifactSetSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkInitialInputArtifactSetSchema(registry);
}
