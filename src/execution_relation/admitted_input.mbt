///|
/// Bounded row-layout import of values already admitted under the exact input
/// field contracts. This owns its row containers, not acquisition authority.
struct AdmittedInput {
  owner : @lower.BoundPrepared
  input_index : Int
  schema : @schema.Schema
  max_rows : Int
  budget : ValueBudget
  rows : Array[Array[@admitted.Value]]
  mut open : Bool
}

///|
pub fn prepare_admitted_input(
  owner : @lower.BoundPrepared,
  input_index : Int,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedInput, CaptureIssue] {
  if max_rows < 0 {
    return Err(InvalidCaptureLimits)
  }
  let budget = match value_budget(limits) {
    Ok(budget) => budget
    Err(issue) => return Err(issue)
  }
  let prepared = @lower.bound_preparation(owner)
  guard @lower.input_id(prepared, input_index) is Some(_) &&
    @pipeline.schema_at(@lower.pipeline(prepared), @pipeline.Input(input_index))
    is Some(schema) else {
    return Err(NotRelationInput)
  }
  if @schema.as_object(schema) is None {
    return Err(ScopedInputNotImplemented)
  }
  Ok({ owner, input_index, schema, max_rows, budget, rows: [], open: true, })
}

///|
/// Cancel only an open import; never clear storage already handed to a capture.
pub fn cancel_admitted_input(input : AdmittedInput) -> Bool {
  if !input.open {
    return false
  }
  input.open = false
  input.rows.clear()
  true
}

///|
pub fn append_admitted_input(
  input : AdmittedInput,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CaptureIssue] {
  if !input.open {
    return Err(ClosedCapture)
  }
  let result = append_admitted_row(input, supplied)
  if result is Err(_) {
    cancel_admitted_input(input) |> ignore
  }
  result
}

///|
fn append_admitted_row(
  input : AdmittedInput,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CaptureIssue] {
  let width = @schema.field_count(input.schema)
  if supplied.length() != width {
    return Err(InvalidCheckedRow)
  }
  let budget = input.budget
  if input.rows.length() >= input.max_rows ||
    !charge_node(budget, 1) ||
    width > budget.limits.max_nodes - budget.nodes {
    return Err(CaptureLimit)
  }
  let row = []
  for column in 0..<width {
    let field = @schema.field_at(input.schema, column).unwrap()
    let checked = supplied[column]
    // No re-admission or equality/CID-based substitution. The producer must
    // use the exact schema contracts of this preparation when admitting cells.
    if !physical_equal(field.contract, checked.contract) {
      return Err(ForeignCheckedValue(input.rows.length(), column))
    }
    if !charge_text(budget, @schema.reference_name(field.name)) ||
      !measure(checked.value, 2, budget) {
      return Err(CaptureLimit)
    }
    row.push(checked.value)
  }
  input.rows.push(row)
  Ok(())
}

///|
/// Seal once. Nested immutable values are shared; row containers cannot escape
/// before success. This is supplied input, not completed Compute or observation.
pub fn finish_admitted_input(
  input : AdmittedInput,
) -> Result[CapturedRows, CaptureIssue] {
  if !input.open {
    return Err(ClosedCapture)
  }
  input.open = false
  Ok({
    owner: input.owner,
    origin: SuppliedInput(input.input_index),
    schema: input.schema,
    rows: input.rows,
    usage: {
      nodes: input.budget.nodes,
      text_bytes: input.budget.text,
      work: input.budget.work,
    },
  })
}
