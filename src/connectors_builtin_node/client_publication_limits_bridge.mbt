///|
/// Read-only projection of the existing checked Local publication policy.
/// The prepared owner is nominal; this does not issue execution authority.
#export_name("clientProgramLocalPublicationLimits")
pub fn client_program_local_publication_limits(
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> Array[Int] {
  guard @client_local_host.client_node_values_publication_limits(
      prepared, max_payload_bytes,
    )
    is Some(limits) else {
    return []
  }
  client_publication_limit_values(limits)
}

///|
// Inverse of the existing 22-field Result output ABI.
fn client_publication_limit_values(
  limits : @publication_host.PublicationOutputExportLimits,
) -> Array[Int] {
  [
    limits.max_result_fields,
    limits.max_result_mapping_work,
    limits.max_result_order_work,
    limits.max_result_workspace_entries,
    limits.max_rows,
    limits.values.max_nodes,
    limits.values.max_text_bytes,
    limits.values.max_depth,
    limits.values.max_work,
    limits.payload_wire.max_bytes,
    limits.payload_wire.max_nodes,
    limits.payload_wire.max_depth,
    limits.payload_wire.max_columns,
    limits.payload_wire.max_order_work,
    limits.logical_wire.max_bytes,
    limits.logical_wire.max_nodes,
    limits.logical_wire.max_depth,
    limits.schema.max_fields,
    limits.schema.max_bytes,
    limits.schema.max_nodes,
    limits.schema.max_depth,
    limits.max_batch_bytes,
  ]
}
