import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const queryPath = 'spec/contracts/actql-query-acquisition.json';
const expressionPath = 'spec/contracts/actql-expressions.json';
export const contract = {
  version: 'actql-query-resource-scopes/0.1',
  dependencies: {
    acquisition: {path: queryPath, pointer: '', cid: cid(read(queryPath))},
    fragment: {path: expressionPath, pointer: '/schemas/fragment', cid: cid(read(expressionPath).schemas.fragment)},
  },
  limits: {
    acquisition_rows: {measure: 'complete_select_output_occurrences', subject: 'every_realization', binding: 'requirement.logical_guards.max_rows'},
    acquisition_value: {measure: 'canonical_typed_wire_UTF8_per_admitted_record_and_demanded_root', subject: 'every_realization', binding: 'requirement.logical_guards.max_value_bytes'},
    fragment_rows: {measure: 'logical_rows_at_fragment_input_and_operation_boundaries', subject: 'selected_fragment_execution', binding: 'fragment.request.max_rows'},
    fragment_value: {measure: 'canonical_typed_wire_UTF8_per_input_evaluated_root_and_published_value', subject: 'selected_fragment_execution', binding: 'fragment.request.max_value_bytes'},
    ordered_rows: {measure: 'all_input_occurrences_before_evaluation', subject: 'selected_ordered_step', binding: 'fragment.request.row_kernel_limits[step].max_input_rows'},
    ordered_value: {measure: 'typed_wire_bytes_per_input_value_demanded_root_and_retained_output_row', subject: 'selected_ordered_step', binding: 'fragment.request.row_kernel_limits[step].max_value_bytes'},
    ordered_live: {measure: 'sum_live_logical_roots_aliases_separate_release_at_last_use', subject: 'selected_ordered_step', binding: 'fragment.request.row_kernel_limits[step].max_live_value_bytes'},
    ordered_work: {measure: 'ordered_derive_logical_work_no_caching_discount', subject: 'selected_ordered_step', binding: 'fragment.request.row_kernel_limits[step].max_work'},
    physical: {measure: 'actual_engine_receipt_and_retention_usage_at_separate_scopes', subject: 'executing_candidate', binding: 'selected_Host_task_resource_contract'},
    consumer: {measure: 'selected_consumer_contract_measure', subject: 'downstream_consumer', binding: 'unchanged_selected_consumer_capacity'},
  },
  semantics: {
    selection: 'canonical_requirement_backend_independent_local_fragment_selection_not_inherited_by_native_no_waiver_of_explicit_common_contract',
    initial_shape: 'scan_filter_select_has_no_ordered_derive_row_kernel_limits_omitted_not_synthesized',
    native: 'exact_output_count_and_typed_wire_value_guard_checks_with_demand_and_full_source_validation_evidence_no_local_replay_required',
    evidence: 'authorized_live_issuer_same_requirement_owner_parameters_task_attempt_read_view_checked_demand_guard_values_and_retained_output_not_SQL_success_or_self_hash',
    unsupported: 'no_exact_enforcement_or_admitted_evidence_no_candidate_no_approximation_or_budget_waiver',
    failure: 'physical_or_selected_implementation_exhaustion_may_stop_before_later_errors_admission_before_predicate_no_cross_candidate_diagnostic_equivalence',
    consumer: 'capture_not_consumer_success_consumer_limits_not_reset_enlarged_or_charged_for_upstream_residual',
    compatibility: 'requirement_receipt_record_observation_wire_unchanged_no_new_success_evidence_by_schema_alone',
  },
};
const path = 'spec/contracts/actql-query-resource-scopes.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(contract, null, 2) + '\n');
assert.deepEqual(read(path), contract);
if (process.argv.includes('--print-pin')) console.log(cid(contract));
