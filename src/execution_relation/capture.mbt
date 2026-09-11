///|
/// Immutable captured rows tied to one bound checked owner and exact node.
/// This is input material, not proof of executable-fragment admission.
struct CapturedRows {
  owner : @lower.BoundPrepared
  node_index : Int
  schema : @schema.Schema
  rows : Array[Array[@admitted.Value]]
  usage : ValueUsage
}

///|
pub fn captured_owner(rows : CapturedRows) -> @lower.BoundPrepared {
  rows.owner
}

///|
pub fn captured_node(rows : CapturedRows) -> Int {
  rows.node_index
}

///|
pub fn captured_schema(rows : CapturedRows) -> @schema.Schema {
  rows.schema
}

///|
pub fn captured_row_count(rows : CapturedRows) -> Int {
  rows.rows.length()
}

///|
pub fn captured_cell(
  rows : CapturedRows,
  row : Int,
  column : Int,
) -> @admitted.Value? {
  match rows.rows.get(row) {
    Some(r) => r.get(column)
    None => None
  }
}

///|
pub fn captured_usage(rows : CapturedRows) -> ValueUsage {
  rows.usage
}

///|
pub fn capture_values(
  owner : @lower.BoundPrepared,
  node_index : Int,
  max_rows~ : Int,
  limits : ValueLimits,
) -> Result[CapturedRows, CaptureIssue] {
  if max_rows < 0 {
    return Err(InvalidCaptureLimits)
  }
  let budget = match value_budget(limits) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let prepared = @lower.bound_preparation(owner)
  guard @lower.node_at(prepared, node_index) is Some(node) else {
    return Err(NotValuesNode)
  }
  guard @lower.payload(node) is @lower.Values(values) else {
    return Err(NotValuesNode)
  }
  let count = @values.row_count(values)
  if count > max_rows || count > limits.max_nodes {
    return Err(CaptureLimit)
  }
  let schema = @values.output_schema(values)
  let width = @schema.field_count(schema)
  let rows : Array[Array[@admitted.Value]] = []
  for i = 0; i < count; i = i + 1 {
    if !charge_node(budget, 1) || width > limits.max_nodes - budget.nodes {
      return Err(CaptureLimit)
    }
    let source = @values.row_at(values, i).unwrap()
    let row : Array[@admitted.Value] = []
    for j = 0; j < width; j = j + 1 {
      let field = @schema.field_at(schema, j).unwrap()
      if !charge_text(budget, @schema.reference_name(field.name)) {
        return Err(CaptureLimit)
      }
      guard @values.cell_at(source, j) is Some(cell) else {
        return Err(InvalidCheckedRow)
      }
      let checked = match cell {
        @values.Literal(v, ..) => v
        @values.Parameter(name, ..) =>
          match @lower.parameter_value(owner, name) {
            Some(v) => v
            None => return Err(MissingParameter(name))
          }
      }
      if budget.limits.max_depth < 2 || !measure(checked.value, 2, budget) {
        return Err(CaptureLimit)
      }
      row.push(checked.value)
    }
    rows.push(row)
  }
  Ok({
    owner,
    node_index,
    schema,
    rows,
    usage: { nodes: budget.nodes, text_bytes: budget.text, work: budget.work, },
  })
}
