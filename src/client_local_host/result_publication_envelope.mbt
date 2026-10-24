///|
/// Result metadata is derived from the original checked graph, not successful
/// rows. Repeated order terms and aliases are original occurrences.
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
  if max_rows < 1 || max_rows > 20000 || count < 1 || count > 1024 {
    return None
  }
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
    if width < 0 || width > 100 || terms < 0 || terms > 10000 - order_terms {
      return None
    }
    let input = @results.port_input(port)
    guard @pipeline.schema_at(
        @pipeline.producer_pipeline(input),
        @pipeline.producer_target(input),
      )
      is Some(source_schema) else {
      return None
    }
    let columns = @schema.field_count(source_schema)
    if columns < 0 || columns > 100 {
      return None
    }
    let projected = @results.port_projection_count(port)
    if projected < 0 || projected > 100 {
      return None
    }
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
    fields = Int::max(fields, width)
    order_terms += terms
  }
  Some({
    fields,
    mapping_work,
    order_terms,
    workspace_entries: 2 * max_rows + order_terms,
    // Snapshot admission retains 8 owner entries +3F field tuples +2F sort
    // indices. Its counter is separate from Result view construction.
    publication_workspace_entries: Int::max(
      100,
      Int::max(2 * max_rows + order_terms, 8 + 5 * fields),
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
  if count < 1 || count > 1024 {
    return None
  }
  let mut fields = 0
  let mut names = 0
  for index in 0..<count {
    guard @strategy.graph_result_occurrence(graph, index) is Some(occurrence) else {
      return None
    }
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    guard client_local_scalar_schema_width(schema) is Some(width) else {
      return None
    }
    fields = Int::max(fields, width)
    names = Int::max(names, @schema.field_reference_name_bytes(schema))
  }
  client_local_scalar_wire_byte_bound(fields, names, max_rows)
}
