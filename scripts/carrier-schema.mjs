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
  // Reuse the admitted constructor's owned structural grammar. A catalog
  // schema is not a second definition/domain issuer or a runtime snapshot.
  const graph = structuredClone(aoa.execution_contracts['BRIDGE.rows.to_property_graph'].params_schema.properties.contract);
  assert.equal(graph.properties.version.const, 'actql-property-graph-contract/0.1');
  assert.equal(graph.properties.identity_law_cid.const, aoa.property_graph_law_manifest_cid);
  assert.equal(graph.properties.value_law_cid.const, aoa.property_graph_law_manifest_cid);
  const schema = {
    $schema:'https://json-schema.org/draft/2020-12/schema',
    oneOf:[
      record,
      graph,
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
    graph:'ActQL_owned_definition_domain_typed_node_and_independent_edge_keys_complete_properties_label_sets_exact_selected_laws_no_retired_endpoint_tuple_body_or_conversion',
    ownership:'retain_exact_envelope_environment_and_sourceview_output_reference_match_declared_carrier',
    unknown:'missing_schema_is_not_a_json_type_or_an_opaque_body_in_a_present_contract_envelope',
    identity:'body_has_no_self_cid_envelope_cid_is_not_bare_body_cid_no_row_names_or_runtime_data_in_graph_body',
  }};
}
