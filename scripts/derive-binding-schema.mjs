import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const nonemptyOrdered = {
  if: {properties: {mode: {const: 'ordered_array'}}, required: ['mode']},
  then: {properties: {bindings: {minItems: 1}}},
};

export function checkDeriveBinding(stages) {
  const s = stages.schemas.derive_binding;
  assert.deepEqual(s.properties.mode.enum, ['snapshot_map', 'ordered_array']);
  assert.equal(s.properties.bindings.minItems, 0);
  assert.deepEqual(s.allOf, [nonemptyOrdered]);
  assert.ok(s.required.includes('mode') && s.required.includes('bindings'));
  assert.equal(s.additionalProperties, false);
  assert.equal(stages.schema_cids.derive_binding, machineCid(s));
  return s;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-stage-contracts.json';
  const stages = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    stages.schemas.derive_binding.properties.bindings.minItems = 0;
    stages.schemas.derive_binding.allOf = [nonemptyOrdered];
    stages.schema_cids.derive_binding = machineCid(stages.schemas.derive_binding);
    writeFileSync(path, JSON.stringify(stages, null, 2) + '\n');
  }
  console.log('Derive binding schema', machineCid(checkDeriveBinding(stages)));
}
