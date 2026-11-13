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
/// An input is a terminal Relation output only for an operation-free owner.
/// This does not grant completion authority or expose intermediate inputs of
/// an executable pipeline as completed results.
fn admitted_relation_output_target(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  let prepared = @lower.bound_preparation(owner)
  match target {
    Step(index) => @lower.node_at(prepared, index) is Some(_)
    Input(_) =>
      @lower.node_count(prepared) == 0 &&
      @lower.preparation_output_target(prepared) == Some(target)
  }
}

///|
pub fn prepare_admitted_output(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedOutput, CaptureIssue] {
  guard admitted_relation_output_target(owner, target) &&
    @lower.preparation_schema_at(@lower.bound_preparation(owner), target)
    is Some(schema) else {
    return Err(NotRelationOutput)
  }
  prepare_admitted_output_with_schema(owner, target, schema, max_rows, limits)
}

///|
fn prepare_admitted_output_with_schema(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  schema : @schema.Schema,
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
  guard admitted_relation_output_target(owner, target) else {
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
      reclaiming: false,
      deferred_reclamation: false,
    },
  })
}

///|
pub fn prepare_bounded_admitted_output(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedOutput, CaptureIssue] {
  match prepare_admitted_output(owner, target, max_rows, limits) {
    Err(issue) => Err(issue)
    Ok(output) => {
      output.buffer.deferred_reclamation = true
      Ok(output)
    }
  }
}

///|
fn prepare_bounded_sequence_admitted_output(
  generated : GeneratedSequence,
  target : @pipeline.Target,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedOutput, CaptureIssue] {
  let preparation = generated_completion_preparation(generated)
  guard completion_preparation_schema(preparation, target) is Some(schema) else {
    return Err(NotRelationOutput)
  }
  prepare_admitted_output_with_schema(
    completion_preparation_owner(preparation),
    target,
    schema,
    max_rows,
    limits,
  ).map(output => {
    output.buffer.deferred_reclamation = true
    output.buffer.budget.retention = generated.working
    output
  })
}

///|
fn advance_admitted_output_reclamation(output : AdmittedOutput) -> Bool {
  advance_admitted_buffer_reclamation(output.buffer, 64)
}

///|
/// Only the stopped kernel knows whether its sealed result was accepted.
/// Until acceptance it retains the buffer, including failed completion and
/// a common-session cancellation racing the final kernel response.
pub fn reclaim_bounded_admitted_output(
  output : AdmittedOutput,
  accepted : Bool,
) -> Bool {
  if accepted {
    return true
  }
  if !output.buffer.open && output.buffer.deferred_reclamation {
    output.buffer.reclaiming = true
  }
  advance_admitted_output_reclamation(output)
}

///|
fn reclaim_bounded_admitted_output_counted(
  output : AdmittedOutput,
  accepted : Bool,
) -> (Bool, Int) {
  if accepted {
    return (true, 0)
  }
  if !output.buffer.open && output.buffer.deferred_reclamation {
    output.buffer.reclaiming = true
  }
  advance_admitted_buffer_reclamation_counted(output.buffer, 64)
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
