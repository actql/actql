import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const operation = 'BRIDGE.rows.to_property_graph';
export const pointer = `/execution_contracts/${operation}`;
const ownerPath = 'spec/contracts/actql-aoa.json';
const registryPath = 'spec/dependencies/aoa-pipeline-registry.json';
const lawPath = 'spec/dependencies/actql-property-graph-laws.json';
const valuePath = 'spec/contracts/actql-protocol-schemas.json';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const array = items => ({type: 'array', items});
const name = {type: 'string', minLength: 1};
const index = {type: 'integer', minimum: 0, maximum: 9007199254740991};
const cid = {type: 'string', pattern: '^sha256:[a-f0-9]{64}$'};
const columns = {...array(index), minItems: 1, uniqueItems: true};
const signature = () => ({finite_inputs: {repeated_input: 'relation', minimum_inputs: 0},
  output: 'graph'});

export function executionContract(law, protocol) {
  const lawCid = machineCid(law);
  const value = {$ref: '#/$defs/value_contract'};
  const definition = {
    key_contracts: {...array({allOf: [value, {properties: {nullable: {const: false}}}]}), minItems: 1},
    labels: {type: 'object', additionalProperties: {...array(name), uniqueItems: true}},
    name,
    properties: {type: 'object', additionalProperties: value},
  };
  const binding = closed({definition: name, input: index, keys: columns,
    properties: array(index)});
  return {
    version: 'actql-property-graph-construction-execution/0.1', operation,
    ...signature(),
    dependencies: {
      property_graph_law: {file: lawPath, pointer: '', cid: lawCid},
      canonical_value_contract: {file: valuePath, pointer: '/schemas/canonical_value_contract',
        cid: machineCid(protocol.schemas.canonical_value_contract)},
    },
    params_schema: {
      $schema: 'https://json-schema.org/draft/2020-12/schema',
      $id: 'urn:actql:property-graph-construction-params:0.1',
      ...closed({
        contract: closed({
          domain: cid,
          edge_definitions: array(closed({...definition, source_definition: name, target_definition: name})),
          identity_law_cid: {const: lawCid},
          node_definitions: array(closed(definition)),
          value_law_cid: {const: lawCid},
          version: {const: 'actql-property-graph-contract/0.1'},
        }),
        edges: array(closed({element: binding, source: columns, target: columns})),
        nodes: array(binding),
      }),
      // The pinned shared value schema is generated, not independently maintained.
      $defs: structuredClone(protocol.schemas.canonical_value_contract.$defs),
    },
    semantics: {
      admission: 'use_existing_checked_constructor_and_typed_contract_owner_before_execution_schema_validation_alone_is_not_admission',
      profile: 'distinct_property_graph_contract_no_legacy_graph_reading_conversion_or_fallback',
      inputs: 'one_ordered_relation_occurrence_per_node_then_edge_definition_preserve_repeated_producers_exact_input_count_equals_nodes_plus_edges_zero_only_for_empty_definition_set',
      correspondence: 'each_binding_names_exact_admitted_definition_once_keys_and_properties_are_checked_producer_column_coordinates_endpoint_coordinates_match_referenced_node_key_types',
      identity: 'definition_domain_and_complete_nonnull_typed_key_independent_of_properties_labels_endpoints_input_artifact_parameter_values_run_invocation_and_current_content_CIDs',
      domain: 'existing_checker_issues_domain_from_admitted_constructor_definition_and_producer_provenance_not_caller_claimed_current_data',
      null_keys: 'exclude_rows_with_null_element_key_before_uniqueness_and_endpoint_resolution',
      duplicates: 'reject_duplicate_complete_definition_keys_even_identical_edges_before_missing_endpoint_exclusion_no_partial_graph_publication',
      endpoints: 'exclude_missing_endpoints_without_synthesized_nodes_preserve_independently_keyed_parallel_edges',
      labels: 'static_per_definition_label_sets_and_exposed_property_subsets_not_data_properties',
      resources: 'existing_Graph_storage_builder_output_builder_retention_capacity_cancel_and_cleanup_owners_no_second_engine_or_accounting_owner',
      unsupported: 'reject_unimplemented_property_profile_operations_without_fallback_to_legacy_SGA',
      authority: 'registration_is_not_execution_authorization_or_a_claim_of_all_SGA_support',
    },
  };
}

export function checkRegistration(aoa, law, protocol, registry) {
  const body = executionContract(law, protocol);
  const ref = {pointer, cid: machineCid(body)};
  assert.deepEqual(aoa.execution_contracts[operation], body);
  assert.equal(aoa.property_graph_law_manifest_cid, machineCid(law));
  assert.deepEqual(aoa.target_registry_requirements[operation], {...signature(), execution_contract: ref});
  assert.deepEqual(registry[operation], {...signature(), execution_contract: {file: ownerPath, ...ref}});
  assert.equal(aoa.pipeline_registry_file, registryPath);
  assert.equal(aoa.pipeline_registry_cid, machineCid(registry));
  return body;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const aoa = read(ownerPath), law = read(lawPath), protocol = read(valuePath), registry = read(registryPath);
  if (process.argv.includes('--write')) {
    const body = executionContract(law, protocol), ref = {pointer, cid: machineCid(body)};
    aoa.execution_contracts[operation] = body;
    aoa.property_graph_law_manifest_cid = machineCid(law);
    aoa.target_registry_requirements[operation] = {...signature(), execution_contract: ref};
    registry[operation] = {...signature(), execution_contract: {file: ownerPath, ...ref}};
    aoa.pipeline_registry_cid = machineCid(registry);
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(ownerPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  console.log('Property Graph constructor execution contract', machineCid(checkRegistration(aoa, law, protocol, registry)));
  console.log('Pipeline registry', aoa.pipeline_registry_cid);
}
