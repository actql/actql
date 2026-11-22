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
/// Retain the selected metadata CID and bound its original canonicalization
/// workspace. Counts come from the Host's closed metadata walk.
#export_name("clientProgramHubSpotMetadataIdentityCapacity")
pub fn client_program_hubspot_metadata_identity_capacity(
  objects : Int,
  encoded_body_units : Int64,
  string_units : Int64,
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  guard objects > 0 &&
    @execution.checked_preparation_add_product(
      encoded_body_units,
      objects.to_int64(),
      128L,
    )
    is Some(units) &&
    @execution.checked_preparation_add_product(units, string_units, 6L)
    is Some(units) &&
    @execution.checked_preparation_add_product(units, 256L, 1L) is Some(units) else {
    return Err(@resources.InvalidExtent)
  }
  let nodes = 15L + 8L * objects.to_int64()
  guard @client_local_host.installed_profile_construction_capacities(
      nodes, units,
    )
    is Some([profile, ..]) &&
    @execution.checked_preparation_add_product(128L, units, 3L) is Some(wire) &&
    @client_local_host.installed_source_construction_capacity(
      2L, 71L, 0L, 2L, 71L, wire,
    )
    is Some(output) &&
    @execution.add_execution_capacity(
      output,
      @client_local_host.installed_source_inspection_construction_capacity(
        profile,
      ),
    )
    is Some(capacity) else {
    return Err(@resources.InvalidExtent)
  }
  Ok(capacity)
}

///|
/// Original target vector, target records and their exact ordered fields.
/// Borrowed metadata and field Strings are already held by the Source.
#export_name("clientProgramHubSpotReadTargetCapacity")
pub fn client_program_hubspot_read_target_capacity(
  targets : Int,
  fields : Int64,
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  guard targets > 0 &&
    @execution.checked_preparation_add_product(fields, targets.to_int64(), 10L)
    is Some(slots) &&
    @execution.checked_preparation_add_product(slots, 1L, 1L) is Some(slots) &&
    @client_local_host.installed_source_construction_capacity(
      slots, 0L, 0L, slots, 0L, 0L,
    )
    is Some(capacity) else {
    return Err(@resources.InvalidExtent)
  }
  Ok(capacity)
}

///|
/// Keep the original aggregate response ceiling and request target encoding
/// bound together as DATA for the existing managed reader recipe.
#export_name("clientProgramHubSpotReadSequenceBounds")
pub fn client_program_hubspot_read_sequence_bounds(
  requests : Int,
  response_bytes : Int,
  origin_units : Int,
  portal_units : Int,
  object_units : Int,
  field_units : Int64,
) -> Result[(Int, Int), @resources.PreparationCapacityIssue] {
  guard requests > 0 &&
    response_bytes > 0 &&
    origin_units > 0 &&
    portal_units > 0 &&
    object_units > 0 else {
    return Err(@resources.InvalidExtent)
  }
  let total = requests.to_int64() * response_bytes.to_int64()
  let prefix = origin_units.to_int64() +
    portal_units.to_int64() +
    object_units.to_int64()
  guard total <= 2147483647L &&
    @execution.checked_preparation_add_product(prefix, field_units, 1L)
    is Some(units) &&
    @execution.checked_preparation_add_product(1024L, units, 6L) is Some(target) &&
    target < 2147483647L else {
    return Err(@resources.InvalidExtent)
  }
  Ok((total.to_int(), target.to_int()))
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
  hubspot_reader_common_capacity(
    reader, columns, secret_bytes, native, received, target_units,
  )
}

///|
#export_name("clientProgramHubSpotSourceReaderObservedCapacity")
pub fn client_program_hubspot_source_reader_observed_capacity(
  reader : Array[Int],
  columns : Int,
  secret_bytes : Int,
  protocol : Array[Int],
  target_units : Int,
  received : Array[Int],
  property_geometry : Array[Int],
) -> @execution.ExecutionCapacity? {
  let native = @hubspot_catalog.source_read_observed_construction_capacity(
    protocol, target_units, received, property_geometry,
  )
  hubspot_reader_common_capacity(
    reader, columns, secret_bytes, native, received, target_units,
  )
}

///|
fn hubspot_reader_common_capacity(
  reader : Array[Int],
  columns : Int,
  secret_bytes : Int,
  native : @execution.ExecutionCapacity?,
  received : Array[Int],
  target_units : Int,
) -> @execution.ExecutionCapacity? {
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
