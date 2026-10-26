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
  @execution.execution_capacity_inventory(
    [
      // Existing installed owner-control allowance, already denominated in
      // bytes. This is not a node tariff or a measured object size.
      { unit: QuotedBytes, count: 8192L, copies: 1, },
      {
        unit: CanonicalWireBytes,
        count: limits.generation_bytes.to_int64(),
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        count: limits.reference_bytes.to_int64(),
        copies: 2,
      },
      {
        unit: CanonicalWireBytes,
        count: limits.contract_bytes.to_int64(),
        copies: 6,
      },
      {
        unit: ValueNodeSlots,
        count: limits.reference_nodes.to_int64(),
        copies: 2,
      },
      {
        unit: ValueNodeSlots,
        count: limits.contract_nodes.to_int64(),
        copies: 6,
      },
    ],
    [
      // Payload and logical writers coexist with additional roots, not a
      // second input body. Every root occurrence stays a separate instance.
      { unit: QuotedBytes, count: payload, copies: 1, },
      { unit: QuotedBytes, count: logical, copies: 1, },
      {
        unit: CursorRootSlots,
        count: limits.identity_slots.to_int64(),
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: limits.generation_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: limits.generation_depth.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: limits.generation_frames.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: limits.reference_depth.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: limits.contract_depth.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: export_limits.schema.max_fields.to_int64(),
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: export_limits.schema.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: export_limits.schema.max_depth.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: export_limits.max_result_fields.to_int64(),
        copies: 1,
      },
      {
        unit: CursorRootSlots,
        count: export_limits.max_result_workspace_entries.to_int64(),
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        count: export_limits.schema.max_bytes.to_int64(),
        copies: 1,
      },
    ],
    @execution.RetainedAlongsideExecution,
  )
}
