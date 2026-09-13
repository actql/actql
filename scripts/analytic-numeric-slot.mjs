import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
const hash={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
export const contract={
  version:'actql-analytic-numeric-slot-contract/0.1',
  schemas:{analytic_slot:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version','unit_definition_cid','source_ordinal','output_name','reduction_profile_cid'],
    properties:{
      version:{const:'actql-analytic-numeric-slot/0.1'},
      unit_definition_cid:hash,
      source_ordinal:{type:'integer',minimum:0,maximum:Number.MAX_SAFE_INTEGER},
      output_name:{type:'string',minLength:1},
      reduction_profile_cid:hash,
    },
  }},
  semantics:{
    identity:'sha256_entire_canonical_json_body_no_self_cid',
    scope:'analytic_binary64_sum_or_avg_call_template_at_owning_unit_authored_source_ordinal',
    name:'exact_canonical_authored_output_name_not_call_index_or_escaped_path',
    ownership:'same_checked_program_stage_pipeline_step_call_effective_parameters_and_admitted_profile',
    imports:'retain_producer_unit_slot_not_consumer_rebasing',
    frame:'runtime_observation_binds_exact_partition_output_occurrence_completed_position_and_contributor_demand_not_static_slot_identity',
    reuse:'equal_frame_values_or_equal_contributor_sequences_do_not_by_themselves_identify_output_occurrences',
    excludes:'future_input_artifact_partition_key_output_position_members_contributors_count_value_algorithm_member_attempt_invocation_result_placement_cost',
    acyclic:'unit_definition_binds_contract_and_selected_profile_not_derived_slot_cid_or_future_observation',
    authority:'shape_and_digest_not_owner_admission_execution_or_durable_capture',
    compatibility:'ordinary_group_slot_contract_unchanged_no_native_ordered_reduction_or_capture_support_claim',
  },
};
const path='spec/contracts/actql-analytic-numeric-slot.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),contract);
if(process.argv.includes('--print-pins'))console.log(JSON.stringify({root:cid(contract),analytic_slot:cid(contract.schemas.analytic_slot)}));
