///|
pub(all) enum GraphObligation {
  ValidateGraphRecords
  RejectRuntimeColumnCollisions
  RestoreSemanticIdentityNames
  ResolveGraphProjectionResources
} derive(Eq, Debug)

///|
pub fn graph_pending(v : CheckedProjection) -> Array[GraphObligation] {
  if v.operation == NodeRows || v.operation == EdgeRows {
    [
      ValidateGraphRecords,
      RejectRuntimeColumnCollisions,
      RestoreSemanticIdentityNames,
      ResolveGraphProjectionResources,
    ]
  } else {
    []
  }
}

///|
fn graph_projection(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedProjection, Issue] {
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
