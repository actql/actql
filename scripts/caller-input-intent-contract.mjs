import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
export const noInputBody = Object.freeze({
  version: 'actql-caller-input-intent/0.1', selection: 'none',
});
export const noInputCid = machineCid(noInputBody);

export function callerInputIntentSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-caller-input-intent-0.1.json',
    title: 'actql-caller-input-intent-0.1',
    type: 'object', additionalProperties: false,
    required: ['version', 'selection'],
    properties: {
      version: {const: 'actql-caller-input-intent/0.1'},
      selection: {const: 'none'},
    },
  };
}

export function admitNoInputIntent(body, claimedCid) {
  assert.deepEqual(body, noInputBody);
  assert.equal(claimedCid, noInputCid);
  return noInputCid;
}

export function applyCallerInputIntentSchema(registry) {
  const schema = callerInputIntentSchema();
  registry.artifact_schemas.caller_input_intent = schema;
  registry.artifact_schema_cids.caller_input_intent = machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkCallerInputIntentSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.caller_input_intent,
    callerInputIntentSchema());
  assert.equal(registry.artifact_schema_cids.caller_input_intent,
    machineCid(callerInputIntentSchema()));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyCallerInputIntentSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkCallerInputIntentSchema(registry);
}
