///|
/// Host-private allowances for the actual installed Content composition. These
/// bound retained roots/wire buffers, not measured heap or logical work. The
/// original prefix reservation retains them through physical cleanup.
pub(all) struct ClientSerializationWorkspaceLimits {
  generation_bytes : Int
  generation_nodes : Int
  generation_depth : Int
  generation_frames : Int
  identity_slots : Int
  reference_bytes : Int
  reference_nodes : Int
  reference_depth : Int
  contract_bytes : Int
  contract_nodes : Int
  contract_depth : Int
  export_limits : @publication_host.PublicationOutputExportLimits
}

///|
pub fn client_serialization_workspace_capacity(
  limits : ClientSerializationWorkspaceLimits,
) -> @execution.ExecutionCapacity? {
  let export_limits = limits.export_limits
  for
    n in [
      limits.generation_bytes,
      limits.generation_nodes,
      limits.generation_depth,
      limits.generation_frames,
      limits.identity_slots,
      limits.reference_bytes,
      limits.reference_nodes,
      limits.reference_depth,
      limits.contract_bytes,
      limits.contract_nodes,
      limits.contract_depth,
      export_limits.max_result_fields,
      export_limits.max_result_mapping_work,
      export_limits.max_result_order_work,
      export_limits.max_result_workspace_entries,
      export_limits.schema.max_fields,
      export_limits.schema.max_bytes,
      export_limits.schema.max_nodes,
      export_limits.schema.max_depth,
    ] {
    if n < 0 {
      return None
    }
  }
  if limits.generation_nodes == 0 ||
    limits.generation_frames == 0 ||
    limits.reference_nodes == 0 ||
    limits.contract_nodes == 0 {
    return None
  }
  // The existing export owner accounts for preparation, reference roots, row
  // cursors and batch buffers. Publication retains both canonical writers.
  guard @local.local_export_retention_capacity({
      max_rows: export_limits.max_rows,
      values: export_limits.values,
      wire: export_limits.payload_wire,
      max_batch_bytes: export_limits.max_batch_bytes,
    })
    is Some(payload) else {
    return None
  }
  guard @local.local_export_retention_capacity({
      max_rows: export_limits.max_rows,
      values: export_limits.values,
      wire: export_limits.logical_wire,
      max_batch_bytes: export_limits.max_batch_bytes,
    })
    is Some(logical) else {
    return None
  }
  // Original byte completion, issued Ref and three private proof bodies remain
  // alive together. Two reference bodies overlap candidate issuance; proof
  // canonical bodies and their encrypted Store transport may overlap cleanup.
  let retained = 8192L +
    8L *
    (
      limits.generation_bytes.to_int64() +
      2L * limits.reference_bytes.to_int64() +
      6L * limits.contract_bytes.to_int64()
    ) +
    256L *
    (
      2L * limits.reference_nodes.to_int64() +
      6L * limits.contract_nodes.to_int64()
    )
  // The source is already held by the prefix provider. These are additional
  // identity/encoder recheck/Result mapping roots, never another input copy.
  let scratch = payload +
    logical +
    256L *
    (
      limits.identity_slots.to_int64() +
      limits.generation_nodes.to_int64() +
      limits.generation_depth.to_int64() +
      limits.generation_frames.to_int64() +
      limits.reference_depth.to_int64() +
      limits.contract_depth.to_int64() +
      export_limits.schema.max_fields.to_int64() +
      export_limits.schema.max_nodes.to_int64() +
      export_limits.schema.max_depth.to_int64() +
      export_limits.max_result_fields.to_int64() +
      export_limits.max_result_workspace_entries.to_int64()
    ) +
    8L * export_limits.schema.max_bytes.to_int64()
  // Each term is a fixed coefficient times a nonnegative Int, so the sum
  // cannot overflow Int64; no saturation or sample-based capacity is used.
  @execution.execution_capacity(retained, retained + scratch)
}

///|
pub fn add_client_serialization_workspace_capacity(
  prefix : @execution.ExecutionCapacity,
  workspace : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  let retained = @execution.execution_capacity_retained_bytes(prefix)
  let execution = @execution.execution_capacity_execution_bytes(prefix)
  let extra_retained = @execution.execution_capacity_retained_bytes(workspace)
  let extra_execution = @execution.execution_capacity_execution_bytes(workspace)
  if retained > 9223372036854775807L - extra_retained ||
    execution > 9223372036854775807L - extra_execution {
    return None
  }
  @execution.execution_capacity(
    retained + extra_retained,
    execution + extra_execution,
  )
}
