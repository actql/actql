import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {emitSchema} from './run-publication-protocol.mjs';

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
const oldFieldTarget = {type: 'object', additionalProperties: false,
  required: ['field'], properties: {field: {type: 'string', minLength: 1}}};
const originalStoreTarget = {type: 'object', additionalProperties: false,
  required: ['published_store'], properties: {published_store: {
    type: 'object', additionalProperties: false, required: ['target_ref', 'mapping_ref'],
    properties: {target_ref: {type: 'string', pattern: '^connector://'},
      mapping_ref: {type: 'string', pattern: '^mapping:[A-Za-z0-9][A-Za-z0-9._/-]*\\.v[0-9]+$'}}}}};

test('both real artifact Program schemas retain exclusive original field and published STORE targets', () => {
  for (const program of parameterPrograms(registry)) {
    const command = program.properties.effects.additionalProperties.oneOf
      .find(member => member.properties?.command).properties.command;
    assert.deepEqual(command.properties.target, {oneOf: [oldFieldTarget, originalStoreTarget]});
    assert.deepEqual(command.required, ['from', 'target', 'contract', 'input']);
    assert.equal(command.additionalProperties, false);
    // Use the real protocol emitter: no second schema validator or target parser.
    assert.doesNotThrow(() => emitSchema(command.properties.target));
    const store = program.properties.effects.additionalProperties.oneOf
      .find(member => member.properties?.store).properties.store;
    assert.equal(store.properties.target.type, 'string');
    assert.equal(store.properties.target.oneOf, undefined);
  }
});

test('changed artifact schemas retain their actual canonical pins', () => {
  for (const [name, schema] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
});
