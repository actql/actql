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
  mut rows : Array[Array[@admitted.Value]]
  mut presence_rows : Array[AdmittedRelationRow]
  mut open : Bool
  mut reading : Bool
  mut reclaiming : Bool
  mut deferred_reclamation : Bool
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
      reclaiming: false,
      deferred_reclamation: false,
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
  if !input.open && !input.reclaiming {
    return false
  }
  // Preserve the existing synchronous API's immediate logical cancellation.
  // Bounded kernels must use sliced reclamation, not this convenience API.
  input.open = false
  input.rows.clear()
  input.presence_rows.clear()
  input.rows = []
  input.presence_rows = []
  input.reclaiming = false
  true
}

///|
fn revoke_admitted_buffer(input : AdmittedRowBuffer) -> Unit {
  if input.deferred_reclamation {
    input.open = false
    input.reclaiming = true
  } else {
    cancel_admitted_buffer(input) |> ignore
  }
}

///|
/// Remove only private row-container references. Immutable cell payloads can
/// be shared with inputs; neither those values nor sealed output are mutated.
/// Overwrite before pop because non-JS arrays retain references in unused slots.
fn advance_admitted_buffer_reclamation(
  input : AdmittedRowBuffer,
  quantum : Int,
) -> Bool {
  if !input.open && !input.reclaiming {
    return true
  }
  if quantum <= 0 {
    return false
  }
  input.open = false
  input.reclaiming = true
  for _ in 0..<quantum {
    if input.rows.last() is Some(row) {
      if row.is_empty() {
        input.rows[input.rows.length() - 1] = []
        input.rows.pop() |> ignore
      } else {
        row[row.length() - 1] = @admitted.null_value()
        row.pop() |> ignore
      }
    } else if input.presence_rows.last() is Some(row) {
      if row.cells.is_empty() {
        input.presence_rows[input.presence_rows.length() - 1] = {
          ..row,
          cells: [],
        }
        input.presence_rows.pop() |> ignore
      } else {
        row.cells[row.cells.length() - 1] = None
        row.cells.pop() |> ignore
      }
    } else {
      break
    }
  }
  if !input.rows.is_empty() || !input.presence_rows.is_empty() {
    return false
  }
  // Empty logical arrays still own backing storage on Native/Wasm. Detach it
  // after every original row and cell reference has been individually removed.
  input.rows = []
  input.presence_rows = []
  input.reclaiming = false
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
    revoke_admitted_buffer(input)
    return Err(ConditionalInputRequiresPresence)
  }
  input.reading = true
  let result = append_admitted_row(input, width, read)
  input.reading = false
  if result is Err(_) {
    revoke_admitted_buffer(input)
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
  if !physical_equal(input.schema, source) || !input.open || input.reading {
    return Err(InvalidCheckedRow)
  }
  let width = @schema.field_count(input.schema)
  if values.length() != width {
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
    let value = values[column]
    if !charge_text(budget, @schema.reference_name(field.name)) ||
      !measure(value, 2, budget) {
      return Err(CaptureLimit)
    }
    row.push(value)
  }
  if !fund_output_retention(budget, budget.nodes, budget.text) || !input.open {
    return Err(CaptureLimit)
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
  // Reference measurement can revoke this buffer through its Host callback.
  // A retired row must not request more funding before its commit is refused.
  if !input.open {
    return Err(ClosedCapture)
  }
  if !fund_output_retention(budget, budget.nodes, budget.text) || !input.open {
    return Err(CaptureLimit)
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
/// Seal the same unpublished input in an explicitly supplied original-row
/// order. Validate the complete permutation before touching either buffer;
/// immutable Values, original owner, schema, presence and consumed work stay
/// unchanged. The caller backs the two outer arrays and validation bitmap
/// before entry. No row admission, authorization or logical hashing is repeated.
pub fn finish_ordered_admitted_input(
  input : AdmittedInput,
  order : Array[Int],
) -> Result[CapturedRows, CaptureIssue] {
  let buffer = input.buffer
  if !buffer.open || buffer.reading {
    return Err(ClosedCapture)
  }
  let present = !buffer.presence_rows.is_empty()
  let count = if present {
    buffer.presence_rows.length()
  } else {
    buffer.rows.length()
  }
  if order.length() != count {
    return Err(InvalidCheckedRow)
  }
  let seen = Array::make(count, false)
  for index in order {
    if index < 0 || index >= count || seen[index] {
      return Err(InvalidCheckedRow)
    }
    seen[index] = true
  }
  if present {
    buffer.presence_rows = order.map(index => buffer.presence_rows[index])
  } else {
    buffer.rows = order.map(index => buffer.rows[index])
  }
  finish_admitted_input(input)
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
  if @schema.all_fields_required(buffer.schema) ||
    !physical_equal(buffer.schema, row.schema) {
    revoke_admitted_buffer(buffer)
    return Err(InvalidCheckedRow)
  }
  if buffer.presence_rows.length() >= buffer.max_rows {
    revoke_admitted_buffer(buffer)
    return Err(CaptureLimit)
  }
  let budget = buffer.budget
  let copied = match
    copy_relation_row(row, {
      max_nodes: budget.limits.max_nodes - budget.nodes,
      max_text_bytes: budget.limits.max_text_bytes - budget.text,
      max_work: remaining_value_work(budget),
      max_depth: budget.limits.max_depth,
    }) {
    Ok(copied) => copied
    Err(_) => {
      revoke_admitted_buffer(buffer)
      return Err(CaptureLimit)
    }
  }
  budget.nodes += copied.usage.nodes
  budget.text += copied.usage.text_bytes
  budget.work += copied.usage.work
  if !fund_output_retention(budget, budget.nodes, budget.text) || !buffer.open {
    return Err(CaptureLimit)
  }
  buffer.presence_rows.push(copied)
  Ok(())
}
