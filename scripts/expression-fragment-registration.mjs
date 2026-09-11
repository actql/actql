import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const operation = 'ACTQL.expression_fragment/0.1';
export const pointer = '/execution_contracts/ACTQL.expression_fragment~10.1';
const path = 'spec/contracts/actql-aoa.json';
const expressionPath = 'spec/contracts/actql-expressions.json';
const registryPath = 'spec/dependencies/aoa-pipeline-registry.json';
const read = p => JSON.parse(readFileSync(p, 'utf8'));

export function executionContract(expressions) {
  return {
    version: 'actql-expression-fragment-execution/0.1',
    operation, inputs: ['relation'], output: 'relation',
    dependencies: {
      expression_contract: {file: expressionPath, pointer: '', cid: machineCid(expressions)},
      fragment_schema: {file: expressionPath, pointer: '/schemas/fragment',
        cid: machineCid(expressions.schemas.fragment)},
    },
    params_schema: {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: 'urn:actql:expression-fragment-params:0.1',
      type: 'object', additionalProperties: false, required: ['fragment'],
      properties: {fragment: {$ref: expressions.schemas.fragment.$id}},
    },
    semantics: {
      schema_resolution: 'resolve_fragment_schema_from_exact_pinned_dependency_without_network_lookup',
      local_source: 'exactly_one_request_pipeline_source_named_input',
      admission: 'regenerate_and_compare_sealed_fragment_under_pinned_expression_contract_before_evaluation',
      fragment_identity: 'hash_complete_canonical_fragment_excluding_only_root_fragment_cid',
      retained_material: 'retain_opcode_and_complete_fragment_in_canonical_composition',
      inner_graph: 'not_a_standalone_execution_artifact',
      carrier_projection: 'validation_witness_only_never_hashed_executed_or_used_as_type_evidence',
      obligations: 'enforce_fragment_input_root_output_limits_demands_and_runtime_checks',
      backend: 'reject_execution_without_support_for_exact_contract_and_all_used_extensions',
      authority: 'registration_does_not_establish_program_completion_or_execution_permission',
    },
  };
}

export function checkRegistration(aoa, expressions, registry) {
  const body = executionContract(expressions);
  const ref = {pointer, cid: machineCid(body)};
  assert.deepEqual(aoa.execution_contracts[operation], body);
  assert.equal(aoa.expression_contract_cid, machineCid(expressions));
  assert.deepEqual(aoa.target_registry_requirements[operation], {
    inputs: ['relation'], output: 'relation', execution_contract: ref,
  });
  assert.deepEqual(registry[operation], {
    inputs: ['relation'], output: 'relation', execution_contract: {file: path, ...ref},
  });
  assert.equal(aoa.pipeline_registry_file, registryPath);
  assert.equal(aoa.pipeline_registry_cid, machineCid(registry));
  return body;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const aoa = read(path), expressions = read(expressionPath), registry = read(registryPath);
  if (process.argv.includes('--write')) {
    const body = executionContract(expressions), ref = {pointer, cid: machineCid(body)};
    aoa.execution_contracts[operation] = body;
    aoa.expression_contract_cid = machineCid(expressions);
    aoa.target_registry_requirements[operation] = {
      inputs: ['relation'], output: 'relation', execution_contract: ref,
    };
    registry[operation] = {inputs: ['relation'], output: 'relation', execution_contract: {file: path, ...ref}};
    aoa.pipeline_registry_cid = machineCid(registry);
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(path, JSON.stringify(aoa, null, 2) + '\n');
  }
  console.log('Expression fragment execution contract', machineCid(checkRegistration(aoa, expressions, registry)));
  console.log('Pipeline registry', aoa.pipeline_registry_cid);
}
