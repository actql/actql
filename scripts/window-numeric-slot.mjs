import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
const hash={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
export const contract={
  version:'actql-window-numeric-slot-contract/0.1',
  schemas:{window_slot:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version','unit_definition_cid','source_ordinal','aggregate_name','reduction_profile_cid'],
    properties:{
      version:{const:'actql-window-numeric-slot/0.1'},
      unit_definition_cid:hash,
      source_ordinal:{type:'integer',minimum:0,maximum:Number.MAX_SAFE_INTEGER},
      aggregate_name:{type:'string',minLength:1},
      reduction_profile_cid:hash,
    },
  }},
  semantics:{
    identity:'sha256_entire_canonical_json_body_no_self_cid',
    scope:'window_group_binary64_sum_or_avg_call_template_at_owning_unit_authored_source_ordinal',
    name:'exact_canonical_authored_aggregate_name_not_map_position_or_escaped_path',
    ownership:'same_checked_program_stage_pipeline_step_call_effective_parameters_and_admitted_profile',
    imports:'retain_producer_unit_slot_not_consumer_rebasing',
    group:'runtime_observation_binds_exact_input_full_group_key_including_window_boundary_prefix_contributor_demand_count_type_and_attempt',
    reuse:'equal_aggregate_values_or_contributor_sequences_do_not_identify_distinct_window_groups',
    excludes:'future_input_artifact_group_key_boundary_values_contributors_count_value_algorithm_member_attempt_invocation_result_placement_cost',
    acyclic:'unit_definition_binds_contract_and_selected_profile_not_derived_slot_cid_or_future_observation',
    authority:'shape_and_digest_not_owner_admission_execution_or_durable_capture',
    compatibility:'ordinary_group_and_analytic_slot_contracts_unchanged_no_backend_execution_or_capture_support_claim',
  },
};
const path='spec/contracts/actql-window-numeric-slot.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),contract);
const pins=`// Generated window numeric slot pins.\n\n///|\nfn window_numeric_slot_contract_cid() -> String {\n  ${JSON.stringify(cid(contract))}\n}\n\n///|\nfn window_numeric_slot_schema_cid() -> String {\n  ${JSON.stringify(cid(contract.schemas.window_slot))}\n}\n`;
const pinsPath='src/pipeline_check_context/window_numeric_slot_pins.generated.mbt';
if(process.argv.includes('--write'))writeFileSync(pinsPath,pins);
assert.equal(readFileSync(pinsPath,'utf8'),pins);
if(process.argv.includes('--print-pins'))console.log(JSON.stringify({root:cid(contract),window_slot:cid(contract.schemas.window_slot)}));
