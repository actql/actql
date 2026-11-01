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

///|
#export_name("clientProgramPreparedLocalPublicationLimits")
pub fn client_program_prepared_local_publication_limits(
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> Array[Int] {
  guard @client_local_host.prepared_installed_managed_publication_limits(
      original, prepared, max_payload_bytes,
    )
    is Some(limits) else {
    return []
  }
  client_publication_limit_values(limits)
}

///|
#export_name("clientProgramInstalledManagedPublicationLimits")
pub fn client_program_installed_managed_publication_limits(
  original : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> Array[Int] {
  guard @client_local_host.installed_managed_publication_limits(
      original, prepared, max_payload_bytes,
    )
    is Some(limits) else {
    return []
  }
  client_publication_limit_values(limits)
}
