///|
/// Checked cells represented by one JSON leaf. Text bytes keep their separate
/// admitted envelope. Nested/opaque domains need their own recursive proof.
fn client_local_json_leaf_schema(schema : @schema.Schema) -> Bool {
  let count = @schema.field_count(schema)
  if count > client_local_schema_proof_work() {
    return false
  }
  for index in 0..<count {
    guard @schema.field_at(schema, index) is Some(field) else { return false }
    if !@execution.json_leaf_representation_contract(
        @schema.field_contract(field),
      ) {
      return false
    }
  }
  true
}

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
  // The SAME closed proof issuers enforce these bounds before writing or
  // admitting their bodies. Preserve every lower caller limit. The unrelated
  // generic contract codec can accept larger bodies but does not allocate them
  // in this Content constructor or its encrypted three-proof holding path.
  let (proof_bytes, proof_nodes, proof_depth) = @publication_host.client_serialization_evidence_codec_bounds()
  let contract_bytes = Int::min(limits.contract_bytes, proof_bytes)
  let contract_nodes = Int::min(limits.contract_nodes, proof_nodes)
  let contract_depth = Int::min(limits.contract_depth, proof_depth)
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
      { unit: CanonicalWireBytes, count: contract_bytes.to_int64(), copies: 6, },
      {
        unit: ValueNodeSlots,
        count: limits.reference_nodes.to_int64(),
        copies: 2,
      },
      { unit: ValueNodeSlots, count: contract_nodes.to_int64(), copies: 6, },
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
      { unit: CursorRootSlots, count: contract_depth.to_int64(), copies: 1, },
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

///|
/// Same checked Content input shape only. This does not bound a different
/// prefix, admit bytes, issue a Scope, or replace the original row guard.
/// A negative result leaves recursive/opaque cells on the general profile.
/// The direct Int projection creates no Option/tuple carrier at the JS ABI.
pub fn client_serialization_json_leaf_field_count(
  component : @publication_host.ClientSerializationPlanGraph,
) -> Int {
  let schema = @pipeline.serialization_input_schema(
    @lower.serialization_checked(component.barrier),
  )
  if !client_local_json_leaf_schema(schema) {
    return -1
  }
  @schema.field_count(schema)
}

///|
/// A fact of the SAME checked serialization input, not its one-row output.
/// Unknown/external input preserves the existing installed producer ceiling.
pub fn client_serialization_input_row_bound(
  component : @publication_host.ClientSerializationPlanGraph,
) -> Int? {
  let prepared = @lower.bound_preparation(
    @lower.serialization_owner(component.barrier),
  )
  guard component.step == @lower.serialization_step(component.barrier) &&
    @lower.node_at(prepared, component.step) is Some(node) &&
    @lower.node_input_count(node) == 1 &&
    @lower.node_input_target(node, 0) is Some(@pipeline.Step(input)) else {
    return None
  }
  @lower.prepared_closed_row_bound(
    prepared,
    client_local_schema_proof_work(),
    target_step=Some(input),
  ).map(bound => bound.0)
}

///|
/// DATA demand of the same checked input. Preserve every caller ceiling and
/// the complete input schema, including fields not selected for byte output.
/// This neither reserves capacity nor authorizes generation or publication.
fn client_serialization_output_limits(
  component : @publication_host.ClientSerializationPlanGraph,
  generation_rows : Int,
  limits : ClientSerializationWorkspaceLimits,
) -> ClientSerializationWorkspaceLimits? {
  if generation_rows < 0 ||
    limits.generation_bytes < 0 ||
    limits.identity_slots < 0 {
    return None
  }
  let output = limits.export_limits
  let rows = Int::min(
    Int::min(output.max_rows, component.max_rows),
    generation_rows,
  )
  let bytes = Int::min(limits.generation_bytes, component.max_bytes)
  if rows < 0 || bytes < 0 {
    return None
  }
  let fields = client_serialization_json_leaf_field_count(component)
  if fields < 0 {
    return Some({ ..limits, generation_bytes: bytes, })
  }
  let n = rows.to_int64()
  let f = fields.to_int64()
  guard @execution.checked_preparation_add_product(1L, f, 2L)
    is Some(value_fields) &&
    @execution.checked_preparation_add_product(1L, value_fields, n)
    is Some(value_nodes) &&
    @execution.checked_preparation_add_product(1L, f + 1L, n)
    is Some(wire_nodes) &&
    @execution.checked_preparation_add_product(wire_nodes, 3L, 1L)
    is Some(logical_nodes) &&
    value_nodes <= 2147483647L &&
    logical_nodes <= 2147483647L else {
    return None
  }
  let value_nodes = Int::min(output.values.max_nodes, value_nodes.to_int())
  let wire_nodes = Int::min(output.payload_wire.max_nodes, wire_nodes.to_int())
  let logical_nodes = Int::min(
    output.logical_wire.max_nodes,
    logical_nodes.to_int(),
  )
  let columns = Int::min(output.payload_wire.max_columns, fields)
  guard @execution.checked_preparation_add_product(
      0L,
      wire_nodes.to_int64(),
      2L,
    )
    is Some(slots) &&
    @execution.checked_preparation_add_product(
      slots,
      logical_nodes.to_int64(),
      1L,
    )
    is Some(slots) &&
    @execution.checked_preparation_add_product(slots, columns.to_int64(), 8L)
    is Some(slots) &&
    @execution.checked_preparation_add_product(
      slots,
      output.values.max_depth.to_int64(),
      2L,
    )
    is Some(slots) &&
    @execution.checked_preparation_add_product(slots, 4L, 1L) is Some(slots) &&
    slots <= 2147483647L else {
    return None
  }
  Some({
    ..limits,
    generation_bytes: bytes,
    identity_slots: Int::min(limits.identity_slots, slots.to_int()),
    export_limits: {
      ..output,
      max_rows: rows,
      values: { ..output.values, max_nodes: value_nodes, },
      payload_wire: {
        ..output.payload_wire,
        max_nodes: wire_nodes,
        max_columns: columns,
      },
      logical_wire: {
        ..output.logical_wire,
        max_nodes: logical_nodes,
        max_columns: Int::min(output.logical_wire.max_columns, fields),
      },
    },
  })
}
