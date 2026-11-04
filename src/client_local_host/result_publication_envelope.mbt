///|
/// Result metadata limits come from the checked graph and row policy. They
/// are not an initial allocation quote. Repeated order terms and aliases are
/// original occurrences; actual row workspace is funded before construction.
priv struct ClientLocalResultEnvelope {
  fields : Int
  mapping_work : Int
  order_terms : Int
  publication_workspace_entries : Int
  workspace_entries : Int
}

///|
fn client_local_result_envelope(
  graph : @strategy.CheckedDAG,
  max_rows : Int,
) -> ClientLocalResultEnvelope? {
  let count = @strategy.graph_result_count(graph)
  if max_rows < 1 || count < 1 || count > client_local_schema_proof_work() {
    return None
  }
  let mut remaining = client_local_schema_proof_work() - count
  let mut mapping_work = 0
  let mut fields = 0
  let mut order_terms = 0
  for index in 0..<count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return None
    }
    let port = @execution.managed_result_occurrence_port(occurrence)
    let width = @schema.field_count(@results.port_schema(port))
    let terms = @results.port_order_term_count(port)
    if width < 0 || width > remaining || terms < 0 || terms > remaining - width {
      return None
    }
    remaining -= width + terms
    let input = @results.port_input(port)
    guard @pipeline.schema_at(
        @pipeline.producer_pipeline(input),
        @pipeline.producer_target(input),
      )
      is Some(source_schema) else {
      return None
    }
    let columns = @schema.field_count(source_schema)
    if columns < 0 || columns > remaining {
      return None
    }
    remaining -= columns
    let projected = @results.port_projection_count(port)
    if projected < 0 || projected > remaining {
      return None
    }
    remaining -= projected
    // Each projected field pays the full projection search, one matched
    // reference and at most C source columns. Each order term pays one
    // reference plus C columns. UTF-16 traversal is separately resumable.
    let mapping = width.to_int64() *
      (projected.to_int64() + 1L + columns.to_int64()) +
      terms.to_int64() * (1L + columns.to_int64())
    if mapping > 2147483647L {
      return None
    }
    mapping_work = Int::max(mapping_work, mapping.to_int())
    fields = Int::max(fields, Int::max(width, columns))
    order_terms += terms
  }
  let row_slots = 2L * max_rows.to_int64() + order_terms.to_int64()
  let field_slots = 8L + 5L * fields.to_int64()
  if field_slots > 2147483647L {
    return None
  }
  // The index representation retains its Int ceiling even when the policy's
  // theoretical row product is larger. Actual construction checks this limit;
  // a two-row result does not allocate the policy maximum in advance.
  let row_slots = Int64::min(row_slots, 2147483647L).to_int()
  Some({
    fields,
    mapping_work,
    order_terms,
    workspace_entries: row_slots,
    // Snapshot admission retains 8 owner entries +3F field tuples +2F sort
    // indices. Its counter is separate from Result view construction.
    publication_workspace_entries: Int::max(
      100,
      Int::max(row_slots, field_slots.to_int()),
    ),
  })
}

///|
/// Publication IO proof from original Result schemas only; intermediate
/// evaluator types do not authorize this independent wire bound.
fn client_local_result_scalar_wire_bytes(
  graph : @strategy.CheckedDAG,
  max_rows : Int,
) -> Int? {
  let count = @strategy.graph_result_count(graph)
  if count < 1 || count > client_local_schema_proof_work() {
    return None
  }
  let mut remaining = client_local_schema_proof_work() - count
  let mut fields = 0
  let mut names = 0
  for index in 0..<count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return None
    }
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    let width = @schema.field_count(schema)
    if width > remaining {
      return None
    }
    remaining -= width
    guard client_local_scalar_schema_width(schema) is Some(width) else {
      return None
    }
    fields = Int::max(fields, width)
    names = Int::max(names, @schema.field_reference_name_bytes(schema))
  }
  client_local_scalar_wire_byte_bound(fields, names, max_rows)
}

///|
/// Measure the exact checked projected Result schemas with the publication
/// encoder itself. This is a work-bounded optimization, not a new acceptance
/// limit: an incomplete proof retains the existing schema allowance. Repeated
/// immutable schema owners reuse a measurement; distinct owners are measured
/// independently even when their eventual content identities coincide.
fn client_local_result_schema_bytes(
  graph : @strategy.CheckedDAG,
  limits : @execution.RelationSchemaIdentityLimits,
  max_work? : Int = client_local_schema_proof_work(),
) -> Int? {
  let count = @strategy.graph_result_count(graph)
  if count < 1 || count > max_work {
    return None
  }
  let mut remaining = max_work - count
  let seen : Array[@schema.Schema] = []
  let mut maximum = 0
  for index in 0..<count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return None
    }
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    let mut found = false
    for previous in seen {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      if physical_equal(previous, schema) {
        found = true
        break
      }
    }
    if found {
      continue
    }
    guard @execution.start_relation_schema_identity(schema, limits)
      is Ok(preparation) else {
      return None
    }
    while true {
      if remaining <= 0 {
        @execution.cancel_relation_schema_identity(preparation) |> ignore
        return None
      }
      match
        @execution.advance_relation_schema_identity(
          preparation,
          Int::min(64, remaining),
        ) {
        Ok((done, used)) => {
          remaining -= used
          if done {
            break
          }
        }
        Err(_) => {
          @execution.cancel_relation_schema_identity(preparation) |> ignore
          return None
        }
      }
    }
    guard @execution.finish_relation_schema_identity(preparation)
      is Ok(identity) else {
      @execution.cancel_relation_schema_identity(preparation) |> ignore
      return None
    }
    let (bytes, _, _) = @execution.relation_schema_usage(identity)
    maximum = Int::max(maximum, bytes)
    seen.push(schema)
  }
  Some(maximum)
}
