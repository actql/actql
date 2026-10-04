///|
/// Provisional physical result import. Owning a checked target is not evidence
/// that it executed. This buffer cannot be used as supplied or producer input.
struct AdmittedOutput {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  buffer : AdmittedRowBuffer
}

///|
/// Immutable result material, deliberately distinct from CompletedOutput and
/// CapturedRows. A successful value import grants no execution/capture authority.
struct AdmittedOutputRows {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  schema : @schema.Schema
  rows : Array[Array[@admitted.Value]]
  presence_rows : Array[AdmittedRelationRow]
  usage : ValueUsage
}

///|
pub fn prepare_admitted_output(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedOutput, CaptureIssue] {
  if max_rows < 0 {
    return Err(InvalidCaptureLimits)
  }
  let budget = match value_budget(limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let prepared = @lower.bound_preparation(owner)
  guard target is Step(index) &&
    @lower.node_at(prepared, index) is Some(_) &&
    @lower.preparation_schema_at(prepared, target) is Some(schema) else {
    return Err(NotRelationOutput)
  }
  if @schema.has_qualified_fields(schema) {
    return Err(ScopedInputNotImplemented)
  }
  Ok({
    owner,
    target,
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
pub fn append_admitted_output(
  output : AdmittedOutput,
  supplied : Array[@admitted.CheckedValue],
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer(output.buffer, supplied)
}

///|
/// Charge surrounding kernel control work against the same finite output
/// budget without including it in the retained value-usage observation.
pub fn admitted_output_charge_control_work(
  output : AdmittedOutput,
  units : Int,
) -> Bool {
  let buffer = output.buffer
  buffer.open &&
  !buffer.reading &&
  charge_external_value_work(buffer.budget, units)
}

///|
/// For retained column/chunk readers: checks capacity before reading any cell
/// and avoids allocating a second temporary row. The callback supplies already
/// checked immutable values; it is not an execution-success verifier.
pub fn append_admitted_output_cells(
  output : AdmittedOutput,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer_cells(output.buffer, width, read)
}

///|
pub fn cancel_admitted_output(output : AdmittedOutput) -> Bool {
  cancel_admitted_buffer(output.buffer)
}

///|
pub fn finish_admitted_output(
  output : AdmittedOutput,
) -> Result[AdmittedOutputRows, CaptureIssue] {
  let buffer = output.buffer
  if !buffer.open || buffer.reading {
    return Err(ClosedCapture)
  }
  buffer.open = false
  Ok({
    owner: output.owner,
    target: output.target,
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
pub fn admitted_output_owner(
  output : AdmittedOutputRows,
) -> @lower.BoundPrepared {
  output.owner
}

///|
pub fn admitted_output_target(output : AdmittedOutputRows) -> @pipeline.Target {
  output.target
}

///|
pub fn admitted_output_schema(output : AdmittedOutputRows) -> @schema.Schema {
  output.schema
}

///|
pub fn admitted_output_row_count(output : AdmittedOutputRows) -> Int {
  if @schema.all_fields_required(output.schema) {
    output.rows.length()
  } else {
    output.presence_rows.length()
  }
}

///|
pub fn admitted_output_cell(
  output : AdmittedOutputRows,
  row : Int,
  column : Int,
) -> @admitted.Value? {
  if !@schema.all_fields_required(output.schema) {
    return match output.presence_rows.get(row) {
      Some(value) => relation_row_required_value(value, column).to_option()
      None => None
    }
  }
  guard output.rows.get(row) is Some(values) else { return None }
  values.get(column)
}

///|
pub fn append_admitted_output_presence(
  output : AdmittedOutput,
  row : AdmittedRelationRow,
) -> Result[Unit, CaptureIssue] {
  append_admitted_buffer_presence(output.buffer, row)
}

///|
pub fn admitted_output_usage(output : AdmittedOutputRows) -> ValueUsage {
  output.usage
}
