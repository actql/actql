///|
/// Explicitly supplied data, not Connector acquisition. Reuses Value admission
/// under the exact input schema selected from this owner. This validates data
/// shape only, not key/order/capacity evidence or a Program's permission to run.
pub fn capture_input(
  owner : @lower.BoundPrepared,
  input_index : Int,
  supplied : Array[@decode.Cursor],
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
  guard @lower.input_id(prepared, input_index) is Some(_) else {
    return Err(NotRelationInput)
  }
  guard @pipeline.schema_at(
      @lower.pipeline(prepared),
      @pipeline.Input(input_index),
    )
    is Some(schema) else {
    return Err(NotRelationInput)
  }
  guard @schema.as_object(schema) is Some(contract) else {
    // No lossy flattening of qualified fields. The scoped row carrier requires
    // its own input representation before this entry can support it.
    return Err(ScopedInputNotImplemented)
  }
  if supplied.length() > max_rows || supplied.length() > limits.max_nodes {
    return Err(CaptureLimit)
  }
  let rows : Array[Array[@admitted.Value]] = []
  for index = 0; index < supplied.length(); index = index + 1 {
    let available_work = limits.max_work - budget.work
    let checked = match
      @admitted.admit(contract, supplied[index], {
        max_nodes: Int::min(limits.max_nodes - budget.nodes, available_work),
        max_text_bytes: Int::min(
          limits.max_text_bytes - budget.text,
          available_work,
        ),
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) => return Err(InputValue(index, e))
    }
    if !measure(checked.value, 1, budget) {
      return Err(CaptureLimit)
    }
    guard checked.value is @admitted.Object(fields) else {
      return Err(InvalidCheckedRow)
    }
    let width = @schema.field_count(schema)
    if @admitted.element_count(fields) != width {
      return Err(InvalidCheckedRow)
    }
    let row : Array[@admitted.Value] = []
    for column = 0; column < width; column = column + 1 {
      let (name, value) = @admitted.element_at(fields, column).unwrap()
      let expected = @schema.field_at(schema, column).unwrap()
      if name != @schema.reference_name(expected.name) {
        return Err(InvalidCheckedRow)
      }
      row.push(value)
    }
    rows.push(row)
  }
  Ok({
    owner,
    origin: SuppliedInput(input_index),
    schema,
    rows,
    usage: { nodes: budget.nodes, text_bytes: budget.text, work: budget.work, },
  })
}
