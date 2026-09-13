import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const queryPath='spec/contracts/actql-query-acquisition.json';
const processPath='spec/contracts/actql-query-process-evidence.json';
const query=read(queryPath), single=read(processPath);
const hash={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const text={type:'string',minLength:1};
const count={type:'integer',minimum:0,maximum:Number.MAX_SAFE_INTEGER};
const object=properties=>({type:'object',additionalProperties:false,required:Object.keys(properties),properties});
const schema=properties=>({$schema:'https://json-schema.org/draft/2020-12/schema',...object(properties)});
const base=query.schemas.completed_observation.properties;
const binding={issuer:text,attempt:text,read_view:text,requirement_cid:hash,
  snapshot:base.snapshot,scan_scope_cid:hash};
const accesses=object({validation_scan_cid:hash,native_result_cid:hash});
const {actual_access,version,...observation}=base;
export const contract={
  version:'actql-query-two-receipt-contract/0.1',
  dependencies:{
    query_acquisition:{path:queryPath,pointer:'',cid:cid(query)},
    process_evidence:{path:processPath,pointer:'',cid:cid(single)},
  },
  schemas:{
    receipt:schema({version:{const:'actql-query-receipt/0.1'},...binding,
      role:{enum:['validation_scan','native_result']},received_rows_cid:hash,
      received_rows:count,received_fields:{type:'array',uniqueItems:true,items:text},received_bytes:count}),
    record:schema({version:{const:'actql-query-two-receipt-evidence/0.1'},...binding,
      role:{enum:['source_validation','filter','select']},accesses,output:base.output}),
    completed_observation:schema({...observation,version:{const:'actql-query-two-receipt-observation/0.1'},
      evidence_contract_cid:hash,execution:object({issuer:text,attempt:text,read_view:text}),accesses}),
  },
  semantics:{
    preimages:'entire_canonical_json_utf8_sha256_without_self_cid_receipts_then_records_then_observation',
    authority:'selected_contract_pins_and_authorized_host_private_issuer_live_task_read_view_and_immutable_retention_not_wire_alone',
    shape:'exactly_one_validation_scan_receipt_then_one_native_result_receipt_no_extra_row_receipts',
    validation:'pinned_host_value_admission_of_all_known_fields_and_all_selected_scan_rows_before_native_filter_select',
    native:'checked_query_equivalent_ordered_output_not_sql_success_or_coercion_alone',
    binding:'both_receipts_all_three_records_and_observation_same_requirement_task_attempt_owned_consistent_read_view_and_applicable_snapshot',
    identity:'receipt_role_is_in_preimage_native_rows_equal_output_rows_without_merging_roles',
    accounting:'each_distinct_transfer_once_sum_received_rows_and_canonical_typed_wire_bytes_retention_copies_and_engine_work_separate',
    lifetime:'issue_all_only_after_successful_validation_query_budgets_and_retention_failure_or_cancellation_is_terminal_no_durable_capture',
    source_order:'null_only_preserve_input_relative_order_without_total_order_evidence',
    compatibility:'separate_observation_version_single_receipt_and_requirement_contracts_unchanged_no_admission_by_old_verifier',
  },
};
const path='spec/contracts/actql-query-two-receipt.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(read(path),contract);
if(process.argv.includes('--print-pins'))console.log(JSON.stringify({root:cid(contract),
  ...Object.fromEntries(Object.entries(contract.schemas).map(([k,v])=>[k,cid(v)]))},null,2));
