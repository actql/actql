import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const count = {type: 'integer', minimum: 0, maximum: 9007199254740991};
const object = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const names = {type: 'array', items: text, uniqueItems: true};
const owner = object({program_source_cid: cid, stage: text, input: text});
const pointer = {type: 'string', pattern: '^/steps/(0|[1-9][0-9]*)/(filter|select)$'};
const protocol = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
const capacity = JSON.parse(readFileSync('spec/contracts/actql-consumer-capacity.json', 'utf8'));
export const contract = {
  version: 'actql-query-acquisition-contract/0.1',
  scope: 'exclusive_finite_relation_scan_filter_select',
  dependencies: {
    canonical_value_contract: {path: 'spec/contracts/actql-protocol-schemas.json',
      pointer: '/schemas/canonical_value_contract', cid: machineCid(protocol.schemas.canonical_value_contract)},
    consumer_capacity: {path: 'spec/contracts/actql-consumer-capacity.json', pointer: '', cid: machineCid(capacity)},
  },
  schemas: {
    requirement: object({
      version: {const: 'actql-query-acquisition/0.1'}, owner, source_ref: text,
      source_contract_cid: cid, input_contract_cid: cid, output_contract_cid: cid,
      request: {type: 'object'}, parameter_values_cid: cid,
      filter: object({occurrence: pointer, expression_cid: cid}),
      select: object({occurrence: pointer, fields: {type: 'array', minItems: 1,
        items: object({input: text, output: text})}}),
      source_validation: object({scope: {const: 'selected_scan'}, fields: names}),
      source_order_cid: {anyOf: [cid, {type: 'null'}]},
      logical_guards: object({max_rows: count, max_value_bytes: count}),
    }),
    completed_observation: object({
      version: {const: 'actql-query-observation/0.1'}, requirement_cid: cid,
      owner, source_ref: text, source_contract_cid: cid, parameter_values_cid: cid,
      resolved_request_cid: cid,
      snapshot: {anyOf: [object({contract_cid: cid, token_cid: cid}), {type: 'null'}]},
      actual_access: object({scope_cid: cid, provider_scope_cid: {anyOf: [cid, {type: 'null'}]},
        received_rows: count, received_fields: names, received_bytes: count}),
      coverage: object({scope_cid: cid, complete: {const: true},
        source_validation_evidence_cid: cid, filter_evidence_cid: cid, select_evidence_cid: cid}),
      output: object({contract_cid: cid, rows_cid: cid, row_count: count}),
      retention: {const: 'process'},
    }),
  },
  semantics: {
    derivation: 'checked_exclusive_scan_filter_select_without_backend_cost_or_placement',
    capture: 'completed_select_output_before_any_consumer',
    identity: 'sha256_of_canonical_json_utf8_entire_body_no_self_cid',
    request_values: 'bound_wire_values_no_reinterpretation_of_business_param_or_literal',
    parameter_identity: 'existing_typed_parameter_values_projection_of_used_request_and_query_names',
    source_validation: 'all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter',
    demand: 'existing_checked_expression_demand_without_eager_undemanded_evaluation',
    native: 'preserve_mandatory_admission_and_demanded_failures_before_projection',
    logical_guards: 'max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots',
    physical_budget: 'actual_received_bytes_rows_and_retention_independent_of_logical_output',
    failure: 'atomic_no_success_capture_or_consumer_on_failure_or_cancellation',
    evidence: 'verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only',
    snapshot: 'source_specific_no_universal_snapshot_token_or_isolation_requirement',
    retention: 'same_process_immutable_completed_observation_not_durable_run_or_recovery',
    invocation: 'existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only',
  },
};
for (const schema of Object.values(contract.schemas)) {
  schema.$schema = 'https://json-schema.org/draft/2020-12/schema';
}
const path = 'spec/contracts/actql-query-acquisition.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(contract, null, 2) + '\n');
assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), contract);
if (process.argv.includes('--print-pin')) console.log(machineCid(contract));
