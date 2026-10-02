import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const version = 'actql-observation-set/0.1';
export const modelSlotCaptureReferences = Object.freeze({
  type: 'array', uniqueItems: true,
  items: {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'},
});

// Update every embedded ObservationSet, including receipt and capture copies.
// Existing non-model bodies omit this optional field and keep their identities.
export function applyModelSlotObservationSchema(registry) {
  const next = structuredClone(registry);
  function visit(value) {
    if (value === null || typeof value !== 'object') return;
    if (value.properties?.version?.const === version) {
      value.properties.model_slot_capture_cids =
        structuredClone(modelSlotCaptureReferences);
    }
    for (const child of Object.values(value)) visit(child);
  }
  visit(next.artifact_schemas);
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schema_cids[name] = machineCid(schema);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return next;
}

export function checkModelSlotObservationSchema(registry) {
  assert.deepEqual(registry, applyModelSlotObservationSchema(registry));
  const schema = registry.artifact_schemas.observation_set;
  assert.equal(schema.additionalProperties, false);
  assert.ok(!schema.required.includes('model_slot_capture_cids'));
  assert.deepEqual(schema.properties.model_slot_capture_cids,
    modelSlotCaptureReferences);
  assert.equal(Object.hasOwn(schema.properties, 'model_capture_bundle_cids'),
    false);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    registry = applyModelSlotObservationSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkModelSlotObservationSchema(registry);
}
