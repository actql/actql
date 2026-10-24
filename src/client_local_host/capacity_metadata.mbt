///|
/// Conservative host metadata funding, separate from provider workspace and
/// scalar payload nodes. All arrays below may coexist; no lifetime reuse or
/// identity/port deduplication is assumed. Text budgets remain unchanged.
fn client_local_scalar_metadata_envelope(
  sequences : Array[@execution.GeneratedSequence],
  graph : @strategy.CheckedDAG,
  max_rows : Int,
  result_envelope : ClientLocalResultEnvelope,
) -> (Int64, Int)? {
  if sequences.length() != @strategy.graph_task_count(graph) ||
    sequences.is_empty() ||
    sequences.length() > 32 ||
    max_rows < 1 ||
    max_rows > 20000 {
    return None
  }
  let mut fields = 0
  let mut names = 0
  let mut ports = 0
  let mut bindings = 0
  for sequence in sequences {
    let prepared = @lower.bound_preparation(
      @execution.generated_sequence_owner(sequence),
    )
    let inputs = @lower.preparation_input_count(prepared)
    if inputs > 32 || @lower.node_count(prepared) > 256 {
      return None
    }
    if inputs > bindings {
      bindings = inputs
    }
    if inputs > ports {
      ports = inputs
    }
    for input in 0..<inputs {
      guard @lower.preparation_input_schema(prepared, input) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(width) else {
        return None
      }
      fields = Int::max(fields, width)
      names = Int::max(names, @schema.field_reference_name_bytes(schema))
    }
    for index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared, index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(width) else {
        return None
      }
      fields = Int::max(fields, width)
      names = Int::max(names, @schema.field_reference_name_bytes(schema))
      let count = @lower.node_input_count(node)
      if count > 32 {
        return None
      }
      ports = Int::max(ports, count)
      bindings = Int::max(bindings, count)
    }
  }
  let result_count = @strategy.graph_result_count(graph)
  if result_count > 1024 || names < 0 || names > 1000000 {
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
  if names < 0 || names > 1000000 {
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
    schema_bytes * 8L
  if retained < 0L || retained > 536870912L {
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
  if max_rows < 1 || max_rows > 20000 || schema_bytes < 0 || schema_bytes > 1000000 { return None }
  let slots=24L*envelope.fields.to_int64()+2L*max_rows.to_int64()+envelope.order_terms.to_int64()+64L
  let bytes=slots*256L+8L*schema_bytes.to_int64()
  if bytes < 0L || bytes > 536870912L {None} else {Some(bytes)}
}
