import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';

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
    policy:'validate_selected_profile_and_every_supplied_policy_component',
    authority:'shape_hash_and_membership_are_not_authorization_or_runtime_evidence',
  },
};
const path='spec/contracts/actql-check-environment.json';
if(process.argv.includes('--write'))writeFileSync(path,JSON.stringify(body,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),body);
console.log('Check Environment envelope contract '+machineCid(body));
