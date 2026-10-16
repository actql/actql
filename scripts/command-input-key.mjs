// Command row correspondence is distinct from target and mutation identities.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export const commandInputKeySchema = {type: 'string', minLength: 1};

export function commandInputKeySchemas(protocol, write = false) {
  const prior = JSON.parse(readFileSync(new URL(
    '../portability/fixtures/program-grammar-before-command-input-key.json', import.meta.url), 'utf8'));
  const original = prior.properties.effects.additionalProperties.oneOf
    .find(member => member.properties?.command).properties.command;
  for (const program of parameterPrograms(protocol)) {
    const command = program.properties.effects.additionalProperties.oneOf
      .find(member => member.properties?.command).properties.command;
    if (write) {
      if (Object.hasOwn(command.properties, 'input_key')) {
        assert.deepEqual(command.properties.input_key, commandInputKeySchema);
      }
      command.properties.input_key = structuredClone(commandInputKeySchema);
    }
    assert.deepEqual(command.properties.input_key, commandInputKeySchema);
    assert.equal(command.additionalProperties, false);
    assert.deepEqual(command.required, original.required,
      'Input-key absence retains the original Command required fields');
  }
  if (write) {
    for (const [name, body] of Object.entries(protocol.artifact_schemas)) {
      protocol.artifact_schema_cids[name] = machineCid(body);
    }
    protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  }
  for (const [name, body] of Object.entries(protocol.artifact_schemas)) {
    assert.equal(protocol.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const protocol = JSON.parse(readFileSync(path, 'utf8'));
  commandInputKeySchemas(protocol, process.argv.includes('--write'));
  if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(protocol, null, 2) + '\n');
  console.log('Canonical Command input-key correspondence retains the original absent-field Program.');
}
