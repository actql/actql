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
  if inventory.original_count != @strategy.graph_task_count(graph) ||
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
  let f = fields.to_int64()
  let p = ports.to_int64()
  let b = bindings.to_int64()
  // One task-output identity plus every named Result occurrence, not task count.
  let i = result_count.to_int64() + 1L
  // Per-port schema traversal, names/columns, copied binding identities and refs.
  let bridge_slots = p * (3L * f + 2L * b + 8L)
  // Input copies/bindings plus identity records, references, permits, issuers,
  // closure roots and their overlapping arrays (at most 64 slots per identity).
  let completion_slots = 4L * p + 2L * b + 64L * i + 16L
  // Export summaries/order/schema/result views; row indices and merge scratch.
  let export_slots = 24L * f +
    2L * max_rows.to_int64() +
    order_terms.to_int64() +
    64L
  // Prepared inputs, receiving bridges/import refs, identity/finalization arrays.
  let dispatch_slots = 8L * p + 8L * i + 64L
  // Scalar contract spellings fit 96 bytes per field; escaped names need at
  // most six bytes per original UTF-8 byte. Fund the retained schema text too.
  let schema_bytes = 6L * names.to_int64() + 96L * f + 2L
  let retained = (
      bridge_slots + completion_slots + export_slots + dispatch_slots
    ) *
    256L +
    schema_bytes * 8L +
    client_local_cleanup_retained_bytes()
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
  let slots = 24L * envelope.fields.to_int64() +
    2L * max_rows.to_int64() +
    envelope.order_terms.to_int64() +
    64L
  let bytes = slots * 256L +
    8L * schema_bytes.to_int64() +
    client_local_cleanup_retained_bytes()
  if bytes < 0L || bytes > client_local_retained_byte_ceiling() {
    None
  } else {
    Some(bytes)
  }
}
