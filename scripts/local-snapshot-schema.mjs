import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
const read = p => JSON.parse(readFileSync(p,'utf8'));
const checked = read('spec/contracts/actql-protocol-schemas.json').schemas.canonical_value_contract;
const selector = read('spec/contracts/actql-local-source-reference.json');
const cid = {type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const body = {
  version:'actql-local-relation-snapshot-contract/0.1',
  dependencies:{
    checked_type:{path:'spec/contracts/actql-protocol-schemas.json',pointer:'/schemas/canonical_value_contract',cid:machineCid(checked)},
    source_reference:{path:'spec/contracts/actql-local-source-reference.json',pointer:'',cid:machineCid(selector)},
  },
  schema:{
    $schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,
    required:['version','source_ref','output_carrier','schema'],
    properties:{
      version:{const:'actql-local-input-schema/0.1'},
      source_ref:{type:'string',pattern:selector.schema.pattern},
      output_carrier:{const:'relation'},
      schema:{allOf:[{$ref:'#/$defs/value_contract'},{type:'object',required:['type','nullable'],properties:{type:{const:'object'},nullable:{const:false}}}]},
      input_cid:cid,
      completeness:{enum:['complete','partial']},
      integration_binding_cid:cid,
    },
    allOf:[
      {if:{required:['input_cid']},then:{required:['completeness']}},
      {if:{required:['completeness']},then:{required:['input_cid']}},
      {if:{required:['integration_binding_cid']},then:{required:['input_cid','completeness']}},
    ],
    $defs:structuredClone(checked.$defs),
  },
  semantics:{
    identity:'canonical_json_utf8_sha256_of_entire_body_without_self_cid',
    schema:'complete_checked_nonnullable_object_including_empty_fields',
    static_only:'absent_materialization_is_not_empty_data_or_complete_data',
    materialization:'input_cid_and_completeness_are_paired_claims_not_verified_rows',
    integration:'optional_integration_binding_cid_requires_materialization_claim',
    admission:'exact_program_source_resolution_recursive_assertion_agreement_and_environment_membership',
    authority:'content_integrity_does_not_establish_host_authorization_or_runtime_validation',
  },
};
const path='spec/contracts/actql-local-relation-snapshot.json';
if(process.argv.includes('--write')) writeFileSync(path,JSON.stringify(body,null,2)+'\n');
assert.deepEqual(read(path),body);
console.log('Local Relation snapshot contract '+machineCid(body));
