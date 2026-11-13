///|
/// Immutable receiving-column view of an exactly bound completed producer.
/// This retains upstream ownership without materializing rows or admitting them
/// again. It is not receiving execution admission or a logical budget credit.
struct ProducerRead {
  bound : BoundProducerInput
  schema : @schema.Schema
  columns : Array[Int]
  max_entries : Int
  max_name_bytes : Int
}

///|
pub(all) enum ProducerReadIssue {
  InvalidLimits
  Limit
  ForeignReceiver
  InvalidProjection
  ProducerUnavailable
  ForeignRepresentation
}

///|
/// Admit another verified representation of this exact completed result while
/// retaining the receiving port, projection and binding identity. This does not
/// reserve conversion resources or replace a selected DAG input: the Host must
/// separately admit that transition before dispatch. A lost original copy need
/// not remain available, but its logical-use restrictions still apply.
pub fn rebind_producer_representation(
  input : ProducerRead,
  output : CompletedOutput,
) -> Result[ProducerRead, ProducerReadIssue] {
  let original = input.bound.output.completion
  if !physical_equal(
      original.result_identity,
      output.completion.result_identity,
    ) ||
    input.bound.output.target != output.target {
    return Err(ForeignRepresentation)
  }
  if !completion_is_live(original) || !completed_output_available(output) {
    return Err(ProducerUnavailable)
  }
  // Keep the logical restriction, not the old completion/store. A replacement
  // representation must not retain the previous physical buffer through this
  // callback after all other readers release it.
  let original_live = original.live
  let constrained = restrict_completed_output(output, fn() {
    match original_live {
      None => true
      Some(check) => check()
    }
  })
  // Physical column positions belong to a representation, not the logical
  // result. Re-project using the original bounded metadata admission limits.
  prepare_producer_read(
    input.bound.receiver,
    { ..input.bound, output: constrained, },
    input.max_entries,
    input.max_name_bytes,
  )
}

///|
/// Drain the same cursor for callers that explicitly use synchronous metadata
/// preparation. Bounded chain handoffs retain it between advances.
pub fn prepare_producer_read(
  receiver : @lower.BoundPrepared,
  bound : BoundProducerInput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ProducerRead, ProducerReadIssue] {
  let cursor = match
    start_prepare_producer_read(receiver, bound, max_entries, max_name_bytes) {
    Ok(cursor) => cursor
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_prepare_producer_read(cursor) {
      Ok(Some(read)) => return Ok(read)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Err(InvalidLimits)
}

///|
pub fn producer_read_receiver(value : ProducerRead) -> @lower.BoundPrepared {
  value.bound.receiver
}

///|
/// Exact receiving port retained by successful producer binding.
pub fn producer_read_input_index(value : ProducerRead) -> Int {
  value.bound.input_index
}

///|
/// Compare exact receiving use-site evidence. Equal values, schemas, producer
/// occurrences, or input indexes cannot substitute for the binding retained by
/// the common graph.
pub fn producer_read_same_binding(
  left : ProducerRead,
  right : ProducerRead,
) -> Bool {
  physical_equal(left.bound.identity, right.bound.identity) &&
  physical_equal(left.bound.receiver, right.bound.receiver) &&
  left.bound.input_index == right.bound.input_index
}

///|
/// Recheck external completion provenance before a new import/execution starts.
/// Immutable cell access alone is not permission to start another computation.
pub fn producer_read_available(value : ProducerRead) -> Bool {
  completed_output_available(value.bound.output)
}

///|
pub fn producer_read_has_cell_access(value : ProducerRead) -> Bool {
  completed_has_cell_access(value.bound.output)
}

///|
/// Borrow the live completion at this exact checked Model input. The selected
/// Local chain keeps producer custody; mapping and Model cleanup cannot close
/// it. No arbitrary completed output or structurally equal owner is accepted.
pub fn infer_completed_producer_input(
  owner : @lower.BoundPrepared,
  step : Int,
  read : ProducerRead,
) -> CompletedOutput? {
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_infer_input_target(node) is Some(target) &&
    producer_read_matches_operation_input(read, owner, step, 0) &&
    completed_output_matches_port(read.bound.output, owner, target) else {
    return None
  }
  Some(read.bound.output)
}

///|
/// Compare immutable receiving-port identity after completion. Admission of
/// new work still requires producer_read_matches_operation_input below.
fn producer_read_binding_matches_operation_input(
  value : ProducerRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  if !physical_equal(value.bound.receiver, receiver) {
    return false
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, edge_index) is Some(target) else {
    return false
  }
  match target {
    @pipeline.Input(index) =>
      value.bound.consumer_step is None && value.bound.input_index == index
    @pipeline.Step(_) =>
      value.bound.consumer_step == Some(consumer_step) &&
      value.bound.input_index == edge_index &&
      value.bound.output.target == target
  }
}

///|
/// Match an exact checked operation edge, including an internal Relation step.
/// A new use must also retain current producer availability.
pub fn producer_read_matches_operation_input(
  value : ProducerRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  producer_read_available(value) &&
  producer_read_binding_matches_operation_input(
    value, receiver, consumer_step, edge_index,
  )
}

///|
pub fn producer_read_schema(value : ProducerRead) -> @schema.Schema {
  value.schema
}

///|
pub fn producer_read_row_count(value : ProducerRead) -> Int {
  completed_row_count(value.bound.output)
}

///|
pub fn producer_read_cell(
  value : ProducerRead,
  row : Int,
  column : Int,
) -> Value? {
  guard producer_read_available(value) else { return None }
  guard @schema.field_at(value.schema, column) is Some(field) &&
    field.presence == @schema.Required else {
    return None
  }
  guard value.columns.get(column) is Some(source) else { return None }
  completed_cell(value.bound.output, row, source)
}

///|
/// Preserve an admitted immutable cell only when the selected physical
/// representation still owns that evidence. A RowTable may contain computed
/// values and must use the ordinary checked-value path instead.
fn producer_read_admitted_cell(
  value : ProducerRead,
  row : Int,
  column : Int,
) -> @admitted.Value? {
  guard producer_read_available(value) &&
    value.columns.get(column) is Some(source) &&
    value.bound.output.table is Some(AdmittedTable(table)) &&
    table.rows.get(row) is Some(cells) else {
    return None
  }
  cells.get(source)
}

///|
/// Re-establish a checked immutable cell for a Carrier bridge. The source
/// completion and receiving schema remain exact; validation is bounded and
/// performs no coercion or wire round trip.
pub fn producer_read_checked_cell(
  value : ProducerRead,
  row : Int,
  column : Int,
  limits : @admitted.Limits,
) -> @admitted.CheckedValue? {
  guard @schema.field_at(value.schema, column) is Some(field) &&
    producer_read_cell(value, row, column) is Some(cell) else {
    return None
  }
  let admitted = match cell {
    Null => Some(@admitted.null_value())
    Number(number) => @admitted.number_value(number)
    Boolean(boolean) => Some(@admitted.boolean_value(boolean))
    Text(text) => @admitted.text_value(text, limits.max_text_bytes)
    Captured(captured) => Some(captured)
  }
  guard admitted is Some(admitted) else { return None }
  @admitted.recheck_runtime_value(admitted, field.contract, limits)
}

///|
/// Observe physical presence through the original receiving-column projection.
/// Unavailability and invalid coordinates are never an absent cell or SQL NULL.
pub fn producer_read_cell_present(
  value : ProducerRead,
  row : Int,
  column : Int,
) -> Result[Bool, RelationPresenceIssue] {
  if !producer_read_available(value) {
    return Err(Unavailable)
  }
  guard @schema.field_at(value.schema, column) is Some(field) &&
    value.columns.get(column) is Some(source) else {
    return Err(InvalidLayout)
  }
  if value.bound.output.table is Some(PresenceTable(_)) {
    match completed_presence_cell(value.bound.output, row, source) {
      Err(issue) => Err(issue)
      Ok(Present(_)) => Ok(true)
      Ok(Absent) =>
        if field.presence == @schema.Required {
          Err(RequiredFieldMissing(column))
        } else {
          Ok(false)
        }
    }
  } else if completed_cell(value.bound.output, row, source) is Some(_) {
    Ok(true)
  } else {
    Err(InvalidLayout)
  }
}

///|
fn producer_read_present_runtime_cell(
  value : ProducerRead,
  row : Int,
  column : Int,
) -> Value? {
  guard producer_read_cell_present(value, row, column) is Ok(true) &&
    value.columns.get(column) is Some(source) else {
    return None
  }
  if value.bound.output.table is Some(PresenceTable(_)) {
    match completed_presence_cell(value.bound.output, row, source) {
      Ok(Present(cell)) => Some(Captured(cell))
      _ => None
    }
  } else {
    completed_cell(value.bound.output, row, source)
  }
}

///|
/// Stage receiving-column validation without scanning a cell during setup.
/// The caller retains this read and checks availability before every advance;
/// only a completed admission can be passed to the downstream contract.
pub fn start_producer_read_cell_recheck(
  value : ProducerRead,
  row : Int,
  column : Int,
  limits : @admitted.Limits,
) -> @admitted.RecheckCursor? {
  guard @schema.field_at(value.schema, column) is Some(field) &&
    producer_read_present_runtime_cell(value, row, column) is Some(cell) else {
    return None
  }
  start_ordered_output_value_recheck(cell, field.contract, limits)
}

///|
/// Execute an owned completed input through ordinary producer admission. No
/// source lookup, row materialization or accounting exemption is introduced.
pub fn execute_fixed_producer_input(
  sequence : GeneratedSequence,
  input : ProducerRead,
  limits : SequenceExecutionLimits,
) -> Result[CompletedSequence, SequenceRunIssue] {
  execute_fixed_producer_inputs(sequence, [input], limits)
}

///|
/// Inputs are in checked receiving-port order. Shared backing data may occur at
/// distinct ports; a binding for one port cannot stand in for another port.
pub fn execute_fixed_producer_inputs(
  sequence : GeneratedSequence,
  inputs : Array[ProducerRead],
  limits : SequenceExecutionLimits,
) -> Result[CompletedSequence, SequenceRunIssue] {
  let owner = generated_sequence_owner(sequence)
  let count = @lower.preparation_input_count(@lower.bound_preparation(owner))
  if inputs.length() != count {
    return Err(InputSet)
  }
  for index in 0..<count {
    let input = inputs[index]
    if !physical_equal(owner, input.bound.receiver) {
      return Err(InputOwnership)
    }
    if input.bound.input_index != index {
      return Err(InputSet)
    }
  }
  if sequence.selected_steps is Some([_]) && inputs is [input] {
    return match execute_selected_relation_step(sequence, input, limits) {
      Ok((output, _)) => Ok(output.completion)
      Err((issue, _)) => Err(issue)
    }
  }
  execute_generated_sequence(
    sequence,
    [],
    limits,
    produced=inputs.map(input => input.bound),
  )
}

///|
/// Existing bound producer only; callers still validate the receiving Run and
/// operation. No completed output, binding or independent lifetime is issued.
pub fn producer_read_original_output(value : ProducerRead) -> CompletedOutput? {
  if producer_read_available(value) {
    Some(value.bound.output)
  } else {
    None
  }
}
