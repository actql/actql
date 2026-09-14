///|
/// Immutable receiving-column view of an exactly bound completed producer.
/// This retains upstream ownership without materializing rows or admitting them
/// again. It is not receiving execution admission or a logical budget credit.
struct ProducerRead {
  bound : BoundProducerInput
  schema : @schema.Schema
  columns : Array[Int]
}

///|
pub(all) enum ProducerReadIssue {
  InvalidLimits
  Limit
  ForeignReceiver
  InvalidProjection
  ProducerUnavailable
}

///|
pub fn prepare_producer_read(
  receiver : @lower.BoundPrepared,
  bound : BoundProducerInput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ProducerRead, ProducerReadIssue] {
  if !completion_is_live(bound.output.completion) {
    return Err(ProducerUnavailable)
  }
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(receiver, bound.receiver) {
    return Err(ForeignReceiver)
  }
  guard @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(receiver)),
      Input(bound.input_index),
    )
    is Some(schema) else {
    return Err(InvalidProjection)
  }
  let count = @schema.field_count(schema)
  if count > max_entries {
    return Err(Limit)
  }
  let mut remaining = max_entries - count
  let mut bytes = max_name_bytes
  let projection = match bound.projection {
    None => []
    Some(checked) => {
      let size = @schema.field_count(@relation.output_schema(checked))
      if size > remaining {
        return Err(Limit)
      }
      remaining -= size
      @relation.projection(checked)
    }
  }
  let columns = []
  for i in 0..<count {
    let field = @schema.field_at(schema, i).unwrap()
    let mut name = field.name
    if bound.projection is Some(_) {
      let mut found = false
      for selected in projection {
        if remaining == 0 {
          return Err(Limit)
        }
        remaining -= 1
        if selected.output == field.name {
          name = selected.input
          found = true
          break
        }
      }
      if !found {
        return Err(InvalidProjection)
      }
    }
    let reference = @schema.reference_name(name)
    match @scalar.admit_utf8_length(reference, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
    let mut found = None
    for column in 0..<completed_column_count(bound.output) {
      if remaining == 0 {
        return Err(Limit)
      }
      remaining -= 1
      let actual = completed_column_name(bound.output, column).unwrap()
      match @scalar.admit_utf8_length(actual, bytes) {
        Ok(size) => bytes -= size
        Err(_) => return Err(Limit)
      }
      if actual == reference {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) else { return Err(InvalidProjection) }
    columns.push(column)
  }
  Ok({ bound, schema, columns, })
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
/// Recheck external completion provenance before a new import/execution starts.
/// Immutable cell access alone is not permission to start another computation.
pub fn producer_read_available(value : ProducerRead) -> Bool {
  completion_is_live(value.bound.output.completion)
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
  guard value.columns.get(column) is Some(source) else { return None }
  completed_cell(value.bound.output, row, source)
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
  let count = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
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
  execute_generated_sequence(
    sequence,
    [],
    limits,
    produced=inputs.map(input => input.bound),
  )
}
