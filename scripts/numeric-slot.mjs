import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';
const hash={type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
export const contract={
  version:'actql-numeric-slot-contract/0.1',
  schemas:{group_slot:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version','unit_definition_cid','source_ordinal','aggregate_name','reduction_profile_cid'],
    properties:{
      version:{const:'actql-group-numeric-slot/0.1'},
      unit_definition_cid:hash,
      source_ordinal:{type:'integer',minimum:0,maximum:Number.MAX_SAFE_INTEGER},
      aggregate_name:{type:'string',minLength:1},
      reduction_profile_cid:hash,
    },
  }},
  semantics:{
    identity:'sha256_entire_canonical_json_body_no_self_cid',
    scope:'ordinary_group_binary64_sum_or_avg_call_at_owning_unit_authored_source_ordinal',
    name:'exact_canonical_authored_aggregate_name_not_array_position_or_escaped_path',
    profile:'exact_selected_admitted_profile_in_owning_unit_local_contract_closure',
    ownership:'same_checked_program_stage_local_pipeline_step_call_and_effective_parameter_ownership',
    imports:'reference_producer_unit_slot_do_not_rebase_to_consumer_unit',
    excludes:'future_input_artifact_contributors_group_key_observation_count_value_algorithm_member_attempt_invocation_result_placement_and_cost',
    acyclic:'unit_definition_preimage_does_not_include_derived_slot_cid_or_future_observation',
    authority:'wire_shape_and_cid_are_not_owned_slot_admission_or_completed_capture',
  },
};
const path='spec/contracts/actql-numeric-slot.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(contract,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),contract);
const pins=`// Generated numeric slot contract pins.\n///|\nfn numeric_slot_contract_cid() -> String { ${JSON.stringify(cid(contract))} }\n///|\nfn numeric_slot_schema_cid() -> String { ${JSON.stringify(cid(contract.schemas.group_slot))} }\n`;
const pinsPath='src/pipeline_check_context/numeric_slot_pins.generated.mbt';
if(process.argv.includes('--write'))writeFileSync(pinsPath,pins);
assert.equal(readFileSync(pinsPath,'utf8'),pins);
if(process.argv.includes('--print-pins'))console.log(JSON.stringify({root:cid(contract),group_slot:cid(contract.schemas.group_slot)},null,2));
