import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {fieldPattern} from './aggregate-schema.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
export function executionContract(protocol) {
  const checked = protocol.schemas.canonical_value_contract;
  const type = structuredClone(checked.$defs.value_contract);
  type.oneOf = type.oneOf.filter(b => !['resource_ref', 'artifact_ref'].includes(b.properties.type.const));
  for (const b of type.oneOf) {
    if (b.properties.type.enum) b.properties.type.enum = b.properties.type.enum.filter(t => t !== 'json');
    for (const key of ['min_length', 'max_codepoints', 'max_utf8_bytes', 'max_items']) {
      if (b.properties[key]) b.properties[key].maximum = 9007199254740991;
    }
  }
  return {
    version: 'actql-rel-values-execution/0.1',
    operation: 'REL.values', inputs: [], output: 'relation',
    dependencies: {
      canonical_value_contract: {
        path: 'spec/contracts/actql-protocol-schemas.json',
        pointer: '/schemas/canonical_value_contract', cid: machineCid(checked),
      },
    },
    params_schema: {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: 'https://smooth.dev/schemas/actql/rel-values-params-0.1.json',
      type: 'object', additionalProperties: false, required: ['schema', 'rows'],
      properties: {
        schema: {type: 'object', minProperties: 1, propertyNames: {pattern: fieldPattern}, additionalProperties: {$ref: '#/$defs/value_contract'}},
        rows: {type: 'array', items: {type: 'object', additionalProperties: {$ref: '#/$defs/wire_value'}}},
      },
      $defs: {
        value_contract: type,
        wire_value: {oneOf: [
          {type: ['null', 'boolean', 'number', 'string']},
          {type: 'array', items: {$ref: '#/$defs/wire_value'}},
          {type: 'object', additionalProperties: {$ref: '#/$defs/wire_value'}},
        ]},
      },
    },
    semantics: {
      schema_form: 'nonempty_field_map_of_complete_checked_constructible_contracts',
      cells: 'bound_typed_wire_values_without_cell_wrappers',
      quotation: 'remove_exact_singleton_literal_once_before_execution_params',
      parameter_resolution: 'resolve_only_authored_cell_root_holes_before_execution_params',
      business_objects: 'never_reinterpret_param_or_literal_members',
      row_fields: 'exact_declared_set_including_nullable_fields',
      values: 'recursive_declared_type_admission_without_cast_repair_or_rounding',
      decimal: 'canonical_fixed_scale_string_under_declared_precision_and_scale',
      empty_rows: 'retain_declared_schema',
      row_order: 'retain_occurrence_order', row_multiplicity: 'retain_all_occurrences',
      object_key_order: 'canonical_utf16_order_not_row_order',
      publication: 'validate_all_rows_and_resolved_limits_before_publication',
      unsupported_backend: 'reject_runnable_plan_without_exact_registered_contract_support',
    },
  };
}

export function checkExecutionContract(aoa, protocol) {
  const body = executionContract(protocol);
  assert.deepEqual(aoa.execution_contracts['REL.values'], body);
  assert.deepEqual(aoa.target_registry_requirements['REL.values'], {
    inputs: [], output: 'relation', execution_contract: {
      pointer: '/execution_contracts/REL.values', cid: machineCid(body),
    },
  });
  return body;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const path = 'spec/contracts/actql-aoa.json';
  const aoa = read(path), protocol = read('spec/contracts/actql-protocol-schemas.json');
  if (process.argv.includes('--write')) {
    const body = executionContract(protocol);
    aoa.execution_contracts ??= {};
    aoa.execution_contracts['REL.values'] = body;
    aoa.target_registry_requirements['REL.values'] = {
      inputs: [], output: 'relation', execution_contract: {
        pointer: '/execution_contracts/REL.values', cid: machineCid(body),
      },
    };
    writeFileSync(path, JSON.stringify(aoa, null, 2) + '\n');
  }
  console.log('REL.values execution contract ' + machineCid(checkExecutionContract(aoa, protocol)));
}
