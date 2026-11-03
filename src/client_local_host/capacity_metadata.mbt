///|
/// Conservative host metadata funding, separate from provider workspace and
/// scalar payload nodes. All arrays below may coexist; no lifetime reuse or
/// identity/port deduplication is assumed. Text budgets remain unchanged.
fn client_local_scalar_metadata_envelope(
  inventory : ClientLocalSchemaProofInventory,
  graph : @strategy.CheckedDAG,
  max_rows : Int,
  result_envelope : ClientLocalResultEnvelope,
) -> (Int64, Int)? {
  if inventory.carrier_values ||
    inventory.original_count != @strategy.graph_task_count(graph) ||
    max_rows < 1 {
    return None
  }
  let fields = inventory.fields
  let mut names = inventory.names
  let ports = inventory.ports
  let bindings = inventory.bindings
  let result_count = @strategy.graph_result_count(graph)
  if result_count > client_local_schema_proof_work() || names < 0 {
    return None
  }
  let order_terms = result_envelope.order_terms
  for index in 0..<result_count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return None
    }
    let port = @execution.managed_result_occurrence_port(occurrence)
    let schema = @results.port_schema(port)
    guard client_local_scalar_schema_width(schema) is Some(width) &&
      width <= fields else {
      return None
    }
    names = Int::max(names, @schema.field_reference_name_bytes(schema))
  }
  if names < 0 {
    return None
  }
  // Each port owns three field traversals plus its binding and control
  // roots. Keep the products in the common checked fold, not Int arithmetic
  // in this domain inventory. Result occurrences are not task identities.
  let slots : Array[@execution.ExecutionCapacityItem] = [
    { unit: CursorRootSlots, count: fields.to_int64(), copies: ports, },
    { unit: CursorRootSlots, count: fields.to_int64(), copies: ports, },
    { unit: CursorRootSlots, count: fields.to_int64(), copies: ports, },
    { unit: CursorRootSlots, count: bindings.to_int64(), copies: ports, },
    { unit: CursorRootSlots, count: bindings.to_int64(), copies: ports, },
    { unit: CursorRootSlots, count: 8L, copies: ports, },
    // Completion: inputs, bindings and identity/permit/issuer arrays.
    { unit: CursorRootSlots, count: ports.to_int64(), copies: 4, },
    { unit: CursorRootSlots, count: bindings.to_int64(), copies: 2, },
    { unit: CursorRootSlots, count: result_count.to_int64(), copies: 64, },
    { unit: CursorRootSlots, count: 1L, copies: 64, },
    { unit: CursorRootSlots, count: 16L, copies: 1, },
    // Export: summaries, schema, row indices, merge scratch and order terms.
    { unit: CursorRootSlots, count: fields.to_int64(), copies: 24, },
    { unit: CursorRootSlots, count: max_rows.to_int64(), copies: 2, },
    { unit: CursorRootSlots, count: order_terms.to_int64(), copies: 1, },
    { unit: CursorRootSlots, count: 64L, copies: 1, },
    // Dispatch: prepared inputs, bridges and finalization arrays.
    { unit: CursorRootSlots, count: ports.to_int64(), copies: 8, },
    { unit: CursorRootSlots, count: result_count.to_int64(), copies: 8, },
    { unit: CursorRootSlots, count: 1L, copies: 8, },
    { unit: CursorRootSlots, count: 64L, copies: 1, },
    // Escaping can expand each original name byte sixfold; bounded scalar
    // contract spellings use their independent per-field wire allowance.
    { unit: CanonicalWireBytes, count: names.to_int64(), copies: 6, },
    { unit: CanonicalWireBytes, count: fields.to_int64(), copies: 96, },
    { unit: CanonicalWireBytes, count: 2L, copies: 1, },
    {
      unit: QuotedBytes,
      count: client_local_cleanup_retained_bytes(),
      copies: 1,
    },
  ]
  guard @execution.execution_capacity_inventory_bytes(slots) is Some(retained) else {
    return None
  }
  if retained < 0L || retained > client_local_retained_byte_ceiling() {
    None
  } else {
    Some((retained, result_envelope.workspace_entries))
  }
}

///|
/// Non-scalar source-free Results keep their generic wire/value policy, but
/// expanded checked Result views still need an explicit retained allowance.
/// Snapshot preparation borrows table cells and retains field/index metadata;
/// it does not allocate an additional rows-by-fields cell matrix.
fn client_local_result_metadata_retained(
  envelope : ClientLocalResultEnvelope,
  max_rows : Int,
  schema_bytes : Int,
) -> Int64? {
  if max_rows < 1 || schema_bytes < 0 {
    return None
  }
  guard @execution.execution_capacity_inventory_bytes([
      { unit: CursorRootSlots, count: envelope.fields.to_int64(), copies: 24, },
      { unit: CursorRootSlots, count: max_rows.to_int64(), copies: 2, },
      {
        unit: CursorRootSlots,
        count: envelope.order_terms.to_int64(),
        copies: 1,
      },
      { unit: CursorRootSlots, count: 64L, copies: 1, },
      { unit: CanonicalWireBytes, count: schema_bytes.to_int64(), copies: 1, },
      {
        unit: QuotedBytes,
        count: client_local_cleanup_retained_bytes(),
        copies: 1,
      },
    ])
    is Some(bytes) else {
    return None
  }
  if bytes < 0L || bytes > client_local_retained_byte_ceiling() {
    None
  } else {
    Some(bytes)
  }
}
