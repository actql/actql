import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';

const query = JSON.parse(readFileSync('spec/contracts/actql-query-acquisition.json','utf8'));
const cid = {type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const text = {type:'string',minLength:1};
const object = properties => ({type:'object',additionalProperties:false,
  required:Object.keys(properties),properties});
const observation = query.schemas.completed_observation.properties;
export const contract = {
  version:'actql-query-process-evidence-contract/0.1',
  dependencies:{query_acquisition:{path:'spec/contracts/actql-query-acquisition.json',pointer:'',cid:machineCid(query)}},
  schemas:{record:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    ...object({version:{const:'actql-query-process-evidence/0.1'},
      issuer:text, attempt:text, requirement_cid:cid,
      role:{enum:['source_validation','filter','select']},
      snapshot:observation.snapshot,
      scan_scope_cid:cid,
      actual_access:observation.actual_access,
      output:observation.output,
    }),
  }},
  semantics:{
    preimage:'entire_record_canonical_json_utf8_sha256_no_self_cid',
    authority:'authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone',
    issuance:'after_complete_scan_validation_filter_select_limits_and_immutable_output_retention',
    attempt:'host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected',
    binding:'exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles',
    native:'authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns',
    source_order:'null_only_in_this_profile_relative_order_is_not_total_order_evidence',
    lifetime:'same_process_no_deserialization_rehydration_or_durable_capture',
    host_adapter:'host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success',
    read_view:'private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution',
    access_accounting:'engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted',
    receipt_scope:'one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract',
    scan_failure:'invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal',
  },
};
const path='spec/contracts/actql-query-process-evidence.json';
if(process.argv.includes('--write')) writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),contract);
if(process.argv.includes('--print-pin')) console.log(machineCid(contract));
