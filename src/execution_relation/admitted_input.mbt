///|
/// Bounded row-layout import of values already admitted under the exact input
/// field contracts. This owns its row containers, not acquisition authority.
struct AdmittedInput {
  owner : @lower.BoundPrepared
  input_index : Int
  buffer : AdmittedRowBuffer
}

///|
priv struct AdmittedRowBuffer {
  schema : @schema.Schema
  max_rows : Int
  budget : ValueBudget
  rows : Array[Array[@admitted.Value]]
  presence_rows : Array[AdmittedRelationRow]
  mut open : Bool
  mut reading : Bool
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
    @lower.preparation_input_schema(prepared, input_index) is Some(schema) else {
    return Err(NotRelationInput)
  }
  if @schema.has_qualified_fields(schema) {
    return Err(ScopedInputNotImplemented)
  }
  Ok({
    owner,
    input_index,
    buffer: {
      schema,
      max_rows,
      budget,
      rows: [],
      presence_rows: [],
      open: true,
      reading: false,
    },
  })
}

///|
/// Cancel only an open import; never clear storage already handed to a capture.
pub fn cancel_admitted_input(input : AdmittedInput) -> Bool {
  cancel_admitted_buffer(input.buffer)
}

///|
fn cancel_admitted_buffer(input : AdmittedRowBuffer) -> Bool {
  if !input.open {
    return false
  }
  input.open = false
  input.rows.clear()
  input.presence_rows.clear()
  true
}

///|
pub fn append_admitted_input(
  input : AdmittedInput,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer(input.buffer, supplied)
}

///|
fn append_admitted_buffer(
  input : AdmittedRowBuffer,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer_cells(input, supplied.length(), column => {
    supplied.get(column)
  })
}

///|
fn append_admitted_buffer_cells(
  input : AdmittedRowBuffer,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, CaptureIssue] {
  if !input.open || input.reading {
    return Err(ClosedCapture)
  }
  if !@schema.all_fields_required(input.schema) {
    cancel_admitted_buffer(input) |> ignore
    return Err(ConditionalInputRequiresPresence)
  }
  input.reading = true
  let result = append_admitted_row(input, width, read)
  input.reading = false
  if result is Err(_) {
    cancel_admitted_buffer(input) |> ignore
  }
  result
}

///|
/// Preserve already-admitted immutable values only when their complete source
/// schema is the exact destination schema. This is a finite representation
/// preservation rule, not a general way to attach contracts to raw values.
fn append_admitted_buffer_values(
  input : AdmittedRowBuffer,
  source : @schema.Schema,
  values : Array[@admitted.Value],
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer_values_read(input, source, values.length(), index => {
    values.get(index)
  })
}

///|
fn append_admitted_buffer_values_read(
  input : AdmittedRowBuffer,
  source : @schema.Schema,
  width : Int,
  read : (Int) -> @admitted.Value?,
) -> Result[Unit, CaptureIssue] {
  if !physical_equal(input.schema, source) || !input.open || input.reading {
    return Err(InvalidCheckedRow)
  }
  if width != @schema.field_count(input.schema) {
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
    guard read(column) is Some(value) else { return Err(InvalidCheckedRow) }
    if !charge_text(budget, @schema.reference_name(field.name)) ||
      !measure(value, 2, budget) {
      return Err(CaptureLimit)
    }
    row.push(value)
  }
  input.rows.push(row)
  Ok(())
}

///|
fn append_admitted_row(
  input : AdmittedRowBuffer,
  supplied_width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, CaptureIssue] {
  let width = @schema.field_count(input.schema)
  if supplied_width != width {
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
    guard read(column) is Some(checked) else { return Err(InvalidCheckedRow) }
    if !input.open {
      return Err(ClosedCapture)
    }
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
  let buffer = input.buffer
  if !buffer.open || buffer.reading {
    return Err(ClosedCapture)
  }
  buffer.open = false
  Ok({
    owner: input.owner,
    origin: SuppliedInput(input.input_index),
    schema: buffer.schema,
    rows: buffer.rows,
    presence_rows: buffer.presence_rows,
    usage: {
      nodes: buffer.budget.nodes,
      text_bytes: buffer.budget.text,
      work: buffer.budget.work,
    },
  })
}

///|
/// Import immutable presence-bearing rows only under the exact prepared input
/// schema. Cumulative resource limits and cancellation stay with this buffer.
pub fn append_admitted_input_presence(
  input : AdmittedInput,
  row : AdmittedRelationRow,
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer_presence(input.buffer, row)
}

///|
fn append_admitted_buffer_presence(
  buffer : AdmittedRowBuffer,
  row : AdmittedRelationRow,
) -> Result[Unit, CaptureIssue] {
  if !buffer.open || buffer.reading {
    return Err(ClosedCapture)
  }
  if !physical_equal(buffer.schema, row.schema) {
    cancel_admitted_buffer(buffer) |> ignore
    return Err(InvalidCheckedRow)
  }
  if @schema.all_fields_required(buffer.schema) {
    let result = append_admitted_buffer_values_read(
      buffer,
      row.schema,
      @schema.field_count(row.schema),
      column => row.cells.get(column).bind(cell => cell),
    )
    if result is Err(_) {
      cancel_admitted_buffer(buffer) |> ignore
    }
    return result
  }
  if buffer.presence_rows.length() >= buffer.max_rows {
    cancel_admitted_buffer(buffer) |> ignore
    return Err(CaptureLimit)
  }
  let budget = buffer.budget
  let copied = match
    copy_relation_row(row, {
      max_nodes: budget.limits.max_nodes - budget.nodes,
      max_text_bytes: budget.limits.max_text_bytes - budget.text,
      max_work: budget.limits.max_work - budget.work,
      max_depth: budget.limits.max_depth,
    }) {
    Ok(copied) => copied
    Err(_) => {
      cancel_admitted_buffer(buffer) |> ignore
      return Err(CaptureLimit)
    }
  }
  budget.nodes += copied.usage.nodes
  budget.text += copied.usage.text_bytes
  budget.work += copied.usage.work
  buffer.presence_rows.push(copied)
  Ok(())
}
