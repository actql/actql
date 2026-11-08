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

///|
/// Same Common capacity issuer; provider Catalogs remain in their own runtime.
#export_name("clientProgramHubSpotSourceReaderCapacity")
pub fn client_program_hubspot_source_reader_capacity(
  reader : Array[Int],
  columns : Int,
  secret_bytes : Int,
  protocol : Array[Int],
  target_units : Int,
  received : Array[Int],
) -> @execution.ExecutionCapacity? {
  let native = @hubspot_catalog.source_read_construction_capacity(
    protocol, target_units, received,
  )
  let mut total = 0L
  for bytes in received {
    total = total + bytes.to_int64()
  }
  @client_local_host.installed_native_source_reader_capacity(
    reader,
    columns,
    secret_bytes,
    native,
    received=Some((total, received.length())),
    max_query_bytes=target_units,
  )
}
