import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {valueBodyContract} from './protocol-value-contracts.mjs';
import {carrierBodyContract} from './carrier-schema.mjs';

export const sections = ['schema_snapshots','connector_capabilities','mapping_contracts','source_views','command_contracts','model_task_contracts','contract_registry','connector_catalogs'];
const records = {type:'array',items:{type:'object'}};
const body = {
  version:'actql-check-environment-contract/0.1',
  schema:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version',...sections,'host_policy_profile','evidence_bundle_cid'],
    properties:{
      version:{const:'actql-check-environment/0.1'},
      ...Object.fromEntries(sections.map(s=>[s,records])),
      host_policy_profile:{type:'object'},
      evidence_bundle_cid:{type:'string',pattern:'^sha256:[0-9a-f]{64}$'},
    },
  },
  semantics:{
    preimage:'entire_envelope_except_root_evidence_bundle_cid',
    identity_alias:'check_environment_cid_refers_to_evidence_bundle_cid_not_a_second_body',
    canonical_bytes:'nfc_lf_utf16_key_order_canonical_numbers_utf8_without_repair',
    evidence_array_order:'ascending_full_canonical_body_cid_in_each_section',
    repeated_snapshots:'reject_repeated_source_ref_even_for_identical_bodies',
    contract_envelopes:'identical_bodies_deduplicated_before_canonical_envelope_construction',
    closure:'catalog_authority_and_exact_derived_arrays_required_separately',
    catalog_preimage:'complete_catalog_except_root_catalog_cid',
    catalog_member_preimages:'source_view_and_command_except_root_contract_cid_contract_envelope_except_root_cid',
    catalog_member_order:'strict_ascending_self_cid_per_array_no_repair',
    catalog_membership:'each_reference_resolves_inside_its_own_catalog_shared_envelopes_deduplicate_only_in_derived_registry',
    policy:'validate_selected_profile_and_every_supplied_policy_component',
    authority:'shape_hash_and_membership_are_not_authorization_or_runtime_evidence',
    source_read_modes:'unique_names_declared_default_snapshot_bounded_watch_unbounded_changes_and_watch_require_checkpoint_preserve_array_order_no_selection_authority',
    source_requests:'nonnull_checked_object_request_all_views_correlation_non_scan_record_carriers_ordered_equal_arity_KeyComparable_pairs_nonnull_comparable_identity_tuple_no_data_or_batch_transport_proof',
  },
  value_contract_bodies:valueBodyContract(JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'))),
  carrier_contract_bodies:carrierBodyContract(JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8')),JSON.parse(readFileSync('spec/contracts/actql-aoa.json','utf8'))),
  contract_bodies:{
    data_policy:{
      type:'object',additionalProperties:false,
      required:['version','source_ref','classification'],
      properties:{
        version:{const:'actql-source-data-policy/0.1'},
        source_ref:{type:'string',minLength:1},
        classification:{enum:['public','internal','confidential','restricted','unknown']},
      },
    },
  },
  policy_components:{
    text_time_evaluation:{
      pointer:'/host_policy_profile/text_time_evaluation',
      schema:{path:'spec/contracts/actql-expressions.json',pointer:'/schemas/fragment/properties/request/properties/text_time_policy',cid:machineCid(JSON.parse(readFileSync('spec/contracts/actql-expressions.json','utf8')).schemas.fragment.properties.request.properties.text_time_policy)},
      identity:'full_canonical_component_body_no_exclusions',
      absent:'unresolved_no_implicit_defaults',
      present:'validate_even_when_unused_null_is_not_absence',
      selection:'retain_exact_environment_membership_use_component_cid_for_text_time_envelopes',
    },
    capacity:{
      pointer:'/host_policy_profile/capacity',
      contract:{path:'spec/contracts/actql-capacity-host-policy.json',pointer:'',cid:machineCid(JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json','utf8')))},
      identity:'full_canonical_component_body_no_exclusions',
      absent:'unresolved_no_implicit_defaults',
      present:'validate_even_when_unused_null_is_not_absence',
      selection:'retain_exact_environment_membership_and_match_selected_policy_cid',
    },
  },
};
const path='spec/contracts/actql-check-environment.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(body,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),body);
console.log('Check Environment envelope contract '+machineCid(body));
