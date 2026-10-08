// Own the common zero-Result inventory rule and closed authored Table binding.
// This schema describes source; it never certifies an Effect or grants a write.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const named = {type: 'string', minLength: 1};
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
export const effectRootRule = {
  if: {required: ['results'], properties: {results: {maxProperties: 0}}},
  then: {required: ['effects'], properties: {effects: {minProperties: 1}}},
};
export const tableWriteSchema = {
  ...closed({intent: {enum: ['create', 'create_or_replace']},
    action: {enum: ['create', 'replace']},
    expected_table: {oneOf: [{type: 'null'}, closed({
      table_uuid: {type: 'string', pattern:
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'},
      generation_cid: cid})]},
    mapping_cid: cid, capability_cid: cid, installation_binding_cid: cid}),
  allOf: [
    {if: {required: ['action'], properties: {action: {const: 'create'}}},
      then: {properties: {expected_table: {type: 'null'}}}},
    {if: {required: ['action'], properties: {action: {const: 'replace'}}},
      then: {properties: {intent: {const: 'create_or_replace'},
        expected_table: {type: 'object'}}}},
  ],
};
export const effectOnlySource = {
  public_results: 'empty_only_with_common_checker_validated_effects',
  stage_results: 'empty_only_with_effect_declarations_validated_by_common_checker',
  execution_roots: 'checked_effects_and_public_results',
  no_roots: 'reject',
  hidden_public_results: false,
  unresolved_effect_success: false,
  unknown_operation_resend: false,
  authority: 'existing_input_mapping_capability_approval_and_effect_owners',
};

export function withEffectOnlyProgramContract(registry, stages) {
  const next = structuredClone(registry), source = structuredClone(stages);
  source.source.effect_only = structuredClone(effectOnlySource);
  source.source.table_write_binding = structuredClone(tableWriteSchema);
  for (const program of parameterPrograms(next)) {
    if (program.allOf !== undefined) {
      assert.deepEqual(program.allOf, [effectRootRule],
        'Unreviewed Program root constraints must not be replaced');
    }
    delete program.properties.results.minProperties;
    program.allOf = [structuredClone(effectRootRule)];
    program.properties.table_inputs = structuredClone(source.source.table_inputs.declaration);
    const store = program.properties.effects.additionalProperties.oneOf
      .find(member => member.properties?.store).properties.store;
    store.properties.from = {oneOf: [closed({result: named}), closed({table_input: named})]};
    store.properties.table_write = structuredClone(tableWriteSchema);
  }
  for (const [name, body] of Object.entries(next.artifact_schemas)) {
    next.artifact_schema_cids[name] = machineCid(body);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return {registry: next, stages: source};
}

export function checkEffectOnlyProgramContract(registry, stages) {
  assert.deepEqual({registry, stages}, withEffectOnlyProgramContract(registry, stages),
    'Effect-only Program source contracts are stale');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registryPath = 'spec/contracts/actql-protocol-schemas.json';
  const stagesPath = 'spec/contracts/actql-stage-contracts.json';
  let registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  let stages = JSON.parse(readFileSync(stagesPath, 'utf8'));
  if (process.argv.includes('--write')) {
    ({registry, stages} = withEffectOnlyProgramContract(registry, stages));
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(stagesPath, JSON.stringify(stages, null, 2) + '\n');
  }
  checkEffectOnlyProgramContract(registry, stages);
  console.log('Common Effect-only Program and fixed Table write source contracts verified.');
}
