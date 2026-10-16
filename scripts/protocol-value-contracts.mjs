import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {commandTargetBindingSchemas} from './command-target-bindings.mjs';
import {publishedCommandTargetSchemas} from './published-command-target.mjs';
import {commandInputKeySchemas} from './command-input-key.mjs';

export const valueKinds=['request_schema','command_input','command_output','idempotency_key','checkpoint',
  'lookup_request_key','lookup_batch_request','lookup_response_key'];
const otherKinds=['carrier_schema','carrier_facts','pushdown','reconciliation','poll','cancel',
  'request_data_handling','data_policy','provider_execution_capability'];

export function commandInputPresenceBody(protocol) {
  const checked=protocol.schemas.canonical_value_contract;
  const object=checked.$defs.value_contract.oneOf.find(value=>value.properties?.type?.const==='object');
  assert.ok(object,'existing checked Object field-name grammar');
  return {schema:{$schema:'https://json-schema.org/draft/2020-12/schema',
    type:'object',additionalProperties:false,required:['additional_properties','fields','required_fields'],
    properties:{additional_properties:{const:false},
      fields:{type:'object',propertyNames:structuredClone(object.properties.fields.propertyNames),
        additionalProperties:{$ref:'#/$defs/value_contract'}},
      required_fields:{type:'array',uniqueItems:true,items:{type:'string',
        ...structuredClone(object.properties.fields.propertyNames)}}},
    $defs:structuredClone(checked.$defs)},
    role:'command_input_only_other_value_roles_keep_the_legacy_checked_grammar',
    inline:'required_fields_present_only_closed_complete_record_absence_keeps_legacy_all_required',
    required_fields:'duplicate_free_subset_of_declared_names_empty_allowed_preserve_exact_array_order',
    admission:'validate_and_budget_every_declared_child_even_when_optional_input_absent_and_every_unused_supplied_role_body',
    correspondence:'same_original_command_catalog_environment_input_schema_occurrence_and_command_input_envelope_complete_inline_body_equality_not_bare_body_hash',
    values:'omit_only_unsupplied_optional_bindings_no_synthetic_null_false_default_placeholder_or_Ref_keep_supplied_type_nullability_and_unknown_field_refusal',
    identity:'unchanged_existing_envelope_command_catalog_preimages_no_version_bump_or_saved_byte_upgrade',
    authority:'type_declaration_and_original_pair_only_not_permission_currentness_Ref_issuance_or_execution'};
}

// Keep the original Command and its Catalog-owned structural copy on the
// same additional presence grammar. Existing required members and field types
// remain untouched; this is not optional-property support for ValueContracts.
export function commandInputPresenceSchemas(protocol, write=false) {
  const required=commandInputPresenceBody(protocol).schema.properties.required_fields;
  const commands=[protocol.schemas.command_contract,
    protocol.schemas.connector_catalog.$defs.command_contract];
  for(const command of commands){
    assert.equal(command.properties.schema.const,'actql.command_contract/0.1');
    const inline=command.properties.input_contract;
    assert.equal(inline.additionalProperties,false);
    assert.deepEqual(inline.required,['additional_properties','fields']);
    assert.deepEqual(inline.properties.additional_properties,{const:false});
    assert.deepEqual(inline.properties.fields.additionalProperties,{$ref:'#/$defs/value_contract'});
    if(write)inline.properties.required_fields=structuredClone(required);
    assert.deepEqual(inline.properties.required_fields,required);
    assert.deepEqual(Object.keys(inline.properties),['additional_properties','fields','required_fields']);
  }
  assert.deepEqual(commands[0],commands[1]);
  if(write){
    for(const name of ['command_contract','connector_catalog'])protocol.schema_cids[name]=machineCid(protocol.schemas[name]);
    protocol.registry_cid=machineCid(protocol.schemas);
  }
  for(const name of ['command_contract','connector_catalog'])assert.equal(protocol.schema_cids[name],machineCid(protocol.schemas[name]));
  assert.equal(protocol.registry_cid,machineCid(protocol.schemas));
}

export function valueBodyContract(protocol) {
  const kinds=protocol.schemas.contract_envelope.properties.kind.enum;
  assert.deepEqual([...kinds].sort(),[...valueKinds,...otherKinds].sort(),'Every envelope kind needs an explicit body-grammar classification');
  return {kinds:valueKinds,schema:{file:'spec/contracts/actql-protocol-schemas.json',
    pointer:'/schemas/canonical_value_contract',cid:machineCid(protocol.schemas.canonical_value_contract)},
    admission:'all_supplied_bodies_including_unused_exact_checked_grammar_no_author_defaults_or_JSON_Schema_conversion',
    ownership:'retain_exact_registry_envelope_and_environment_not_only_bare_body_cid',
    scope:'type_declarations_only_not_value_admission_reference_authority_or_behavioral_contract_validation',
    command_input_presence:commandInputPresenceBody(protocol)};
}

export function generateValueKinds(protocol) {
  const body = valueBodyContract(protocol);
  return ['// Generated by scripts/protocol-value-contracts.mjs; do not edit.','','///|',
    'fn protocol_value_kind(kind : String) -> Bool {','  match kind {',
    ...valueKinds.map((k,i)=>`    ${i?'| ':''}${JSON.stringify(k)}${i===valueKinds.length-1?' => true':''}`),
    '    _ => false','  }','}', '', '///|',
    'fn protocol_value_grammar_cid() -> String {',
    `  ${JSON.stringify(body.schema.cid)}`, '}', ''].join('\n');
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const read=p=>JSON.parse(readFileSync(p,'utf8'));
  const protocol=read('spec/contracts/actql-protocol-schemas.json');
  if(process.argv.includes('--write-schema')){
    commandTargetBindingSchemas(protocol,true);
    publishedCommandTargetSchemas(protocol,true);
    commandInputKeySchemas(protocol,true);
    commandInputPresenceSchemas(protocol,true);
    writeFileSync('spec/contracts/actql-protocol-schemas.json',JSON.stringify(protocol,null,2)+'\n');
    console.log('Command presence inline structural copies and initial-0.1 pins updated.');
  }else{
    commandTargetBindingSchemas(protocol);
    publishedCommandTargetSchemas(protocol);
    commandInputKeySchemas(protocol);
    commandInputPresenceSchemas(protocol);
    assert.deepEqual(read('spec/contracts/actql-check-environment.json').value_contract_bodies,valueBodyContract(protocol));
    const path='src/check_environment/value_roles.generated.mbt',text=generateValueKinds(protocol);
    if(process.argv.includes('--write'))writeFileSync(path,text);
    assert.equal(readFileSync(path,'utf8'),text);
    await import('./command-input-presence-vectors.mjs');
    const {commandTargetBindingVectors}=await import('./command-target-binding-vectors.mjs');
    assert.equal(readFileSync('src/check_environment/command_target_bindings.generated_test.mbt','utf8'),
      commandTargetBindingVectors(read('portability/corpus/command-target-bindings.json')));
    console.log('All 17 kinds classified; eight legacy value roles and Command-only presence verified.');
  }
}
