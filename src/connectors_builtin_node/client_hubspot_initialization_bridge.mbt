// Pure initialization demand, compiled in the SAME Common capacity issuer.
// Actual HubSpot catalogs remain provider-runtime originals; no foreign opaque
// capacity, declaration, account or observation crosses this bridge.

///|
#export_name("clientProgramHubSpotMappingConstructionCapacity")
pub fn client_program_hubspot_mapping_construction_capacity(
  fields : Int,
  sources : Int,
  input_units : Int64,
  max_properties : Int,
  max_fields : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  @hubspot_catalog.execution_mapping_construction_capacity(
    fields,
    sources,
    input_units,
    {
      max_properties,
      max_fields,
      max_name_bytes,
      max_bytes,
      max_nodes,
      max_depth,
    },
  )
}

///|
#export_name("clientProgramHubSpotAccountConstructionCapacity")
pub fn client_program_hubspot_account_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  portal_units : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  @hubspot_catalog.account_initialization_construction_capacity(
    body_bytes, encoded_units, portal_units, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramHubSpotObjectConstructionCapacity")
pub fn client_program_hubspot_object_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  object_units : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_properties : Int,
  max_name_units : Int,
  max_columns : Int,
  max_name_bytes : Int,
  max_schema_bytes : Int,
  max_schema_nodes : Int,
  max_schema_depth : Int,
) -> @execution.ExecutionCapacity? {
  @hubspot_catalog.object_initialization_construction_capacity(
    body_bytes,
    encoded_units,
    object_units,
    { max_bytes, max_nodes, max_depth, max_properties, max_name_units, },
    max_columns,
    max_name_bytes,
    max_schema_bytes,
    max_schema_nodes,
    max_schema_depth,
  )
}
