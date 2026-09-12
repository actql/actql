import assert from 'node:assert/strict';

// Catalog type declarations, not backend physical layouts or data evidence.
export function carrierBodyContract(protocol, aoa) {
  const checked = protocol.schemas.canonical_value_contract;
  const object = structuredClone(checked.$defs.value_contract.oneOf.find(x => x.properties?.type?.const === 'object'));
  assert.ok(object, 'checked object grammar');
  object.properties.nullable = {const:false};
  const name = structuredClone(object.properties.fields.propertyNames);
  const closed = properties => ({type:'object',additionalProperties:false,required:Object.keys(properties),properties});
  const record = {$ref:'#/$defs/record'};
  const schema = {
    $schema:'https://json-schema.org/draft/2020-12/schema',
    oneOf:[
      record,
      closed({version:{const:'actql-graph-contract/0.1'},node_id_contract:{$ref:'#/$defs/value_contract'},
        node_properties:structuredClone(object.properties.fields),edge_properties:structuredClone(object.properties.fields),
        edge_labels:{oneOf:[{type:'null'},{type:'array',uniqueItems:true,items:{type:'string'}}]},
        identity_law_cid:{const:aoa.sga_identity_law_manifest_cid},value_law_cid:{const:aoa.sga_identity_law_manifest_cid}}),
      closed({version:{const:'actql-events-contract/0.1'},records:record,id:{type:'string',...name},time:{type:'string',...name}}),
      closed({version:{const:'actql-vectors-contract/0.1'},records:record,
        ids:{type:'array',minItems:1,uniqueItems:true,items:{type:'string',...name}},components:{type:'string',...name}}),
    ],
    $defs:{...structuredClone(checked.$defs),record:object},
  };
  return {schema,semantics:{
    scope:'all_carrier_schema_bodies_including_unused_complete_structural_declarations_not_runtime_evidence',
    dispatch:'checked_object_relation_graph_events_vectors_versioned_bodies_no_role_inference',
    roles:'exact_record_fields_nonnull_KeyComparable_ids_number_or_timestamp_event_time_nonnull_vector_components',
    vector_identity:'nonempty_ordered_unique_tuple_components_disjoint_no_implicit_stringification',
    graph:'existing_structural_body_with_complete_properties_exact_selected_laws_sorted_unique_labels',
    ownership:'retain_exact_envelope_environment_and_sourceview_output_reference_match_declared_carrier',
    unknown:'missing_schema_is_not_a_json_type_or_an_opaque_body_in_a_present_contract_envelope',
    identity:'body_has_no_self_cid_envelope_cid_is_not_bare_body_cid_no_row_names_or_runtime_data_in_graph_body',
  }};
}
