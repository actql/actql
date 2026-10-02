///|
pub(all) enum GraphObligation {
  ValidateGraphRecords
  RejectRuntimeColumnCollisions
  RestoreSemanticIdentityNames
  ResolveGraphProjectionResources
} derive(Eq, Debug)

///|
pub fn graph_pending(v : CheckedProjection) -> Array[GraphObligation] {
  let out = []
  graph_pending_each(v, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn graph_pending_each(
  v : CheckedProjection,
  emit : (GraphObligation) -> Unit,
) -> Unit {
  if v.operation == NodeRows || v.operation == EdgeRows {
    emit(ValidateGraphRecords)
    emit(RejectRuntimeColumnCollisions)
    emit(RestoreSemanticIdentityNames)
    emit(ResolveGraphProjectionResources)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn graph_pending_count(v : CheckedProjection) -> Int {
  let mut count = 0
  graph_pending_each(v, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn graph_pending_at(v : CheckedProjection, index : Int) -> GraphObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  graph_pending_each(v, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
fn graph_projection(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedProjection, Issue] {
  // Endpoint-tuple projections cannot represent definition-scoped keys or
  // independent edge identities. Never infer a homogeneous schema from a
  // keyed Graph; MATCH is the admitted definition-selected projection.
  if input is @carrier.GraphValue(graph) &&
    @carrier.graph_property_definition(graph) is Some(_) {
    return Err(issue(source, UnsupportedGraphProfile))
  }
  let (properties, identity, names) = match input {
    @carrier.GraphValue(g) =>
      (
        if operation == NodeRows {
          @carrier.graph_node_properties(g)
        } else {
          @carrier.graph_edge_properties(g)
        },
        Some(@carrier.graph_identity(g)),
        @carrier.graph_names(g),
      )
    _ => (@carrier.unknown_rows(), None, None)
  }
  let fields : Array[(@row.FieldName, @value.Contract?)] = []
  if operation == NodeRows {
    fields.push((Unqualified("id"), identity))
  } else {
    fields.push((Unqualified("src"), identity))
    fields.push((Unqualified("dst"), identity))
    fields.push(
      (Unqualified("rel"), Some(@value.primitive(StringType, nullable=true))),
    )
  }
  if names is Some(names) {
    let (node, src, dst, rel) = @carrier.graph_row_fields(names)
    if operation == NodeRows {
      if node != Unqualified("id") {
        fields.push((node, identity))
      }
    } else {
      if src != Unqualified("src") {
        fields.push((src, identity))
      }
      if dst != Unqualified("dst") {
        fields.push((dst, identity))
      }
      if rel is Some(rel) && rel != Unqualified("rel") {
        fields.push((rel, Some(@value.primitive(StringType, nullable=true))))
      }
    }
  }
  let count = @carrier.field_count(properties)
  if fields.length() > limits.max_work - 1 ||
    count > limits.max_work - 1 - fields.length() {
    return Err(issue(source, BudgetExceeded))
  }
  for i in 0..<count {
    let f = @carrier.field_at(properties, i).unwrap()
    fields.push((f.name, f.contract))
  }
  let mut remaining = limits.max_text_bytes
  for (name, _) in fields {
    match @scalar.admit_utf8_length(@row.reference_name(name), remaining) {
      Ok(n) => remaining -= n
      Err(_) => return Err(issue(source, BudgetExceeded))
    }
  }
  let records = match
    @carrier.rows(
      fields,
      field_set=@carrier.field_set(properties),
      max_fields=fields.length(),
      max_name_bytes=limits.max_text_bytes,
    ) {
    Ok(rows) => rows
    Err(@row.DuplicateField(name)) =>
      return Err(issue(source, OutputCollision(name)))
    Err(_) => return Err(issue(source, BudgetExceeded))
  }
  Ok({
    operation,
    source,
    input,
    output: @carrier.relation(records),
    usage: {
      work: fields.length() + 1,
      nodes: 1,
      text_bytes: limits.max_text_bytes - remaining,
    },
  })
}
