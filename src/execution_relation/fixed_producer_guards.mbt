///|
priv struct ProducerGuardRows {
  input : ProducerRead
  table : CompletedTable
}

///|
impl IndexedRows for ProducerGuardRows with fn row_count(self) {
  producer_read_row_count(self.input)
}

///|
impl IndexedRows for ProducerGuardRows with fn column_count(self) {
  self.input.columns.length()
}

///|
impl IndexedRows for ProducerGuardRows with fn row_width(self, _row) {
  self.input.columns.length()
}

///|
impl IndexedRows for ProducerGuardRows with fn read_cell(self, row, column) {
  IndexedRows::read_cell(self.table, row, self.input.columns[column])
}

///|
/// One cumulative measurement ledger for complete fixed input and retained
/// output. Producer admission remains the ordinary owned driver path. The
/// additional common root ceiling uses the existing evaluator, without replay.
pub fn execute_fixed_producer_guarded(
  original : GeneratedSequence,
  input : ProducerRead,
  target : @pipeline.Target,
  execution : SequenceExecutionLimits,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  physical : FixedInputGuardMeasureLimits,
) -> Result[CompletedSequence, FixedInputGuardIssue] {
  execute_fixed_producers_guarded(
    original,
    [input],
    target,
    execution,
    max_rows~,
    max_value_bytes~,
    physical,
  )
}

///|
/// Enforce the common row ceiling independently for every fixed input and for
/// the output. Value measurement uses one cumulative ledger across all ports,
/// including repeated references to shared data; sharing is not a logical credit.
pub fn execute_fixed_producers_guarded(
  original : GeneratedSequence,
  inputs : Array[ProducerRead],
  target : @pipeline.Target,
  execution : SequenceExecutionLimits,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  physical : FixedInputGuardMeasureLimits,
) -> Result[CompletedSequence, FixedInputGuardIssue] {
  if max_rows < 0 ||
    max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let owner = generated_sequence_owner(original)
  let count = @lower.preparation_input_count(@lower.bound_preparation(owner))
  if inputs.length() != count {
    return Err(ForeignInput)
  }
  if count > physical.max_work {
    return Err(MeasurementWork)
  }
  for index in 0..<count {
    let input = inputs[index]
    if !producer_read_available(input) ||
      !physical_equal(owner, producer_read_receiver(input)) ||
      producer_read_input_index(input) != index {
      return Err(ForeignInput)
    }
    if producer_read_row_count(input) > max_rows {
      return Err(InputRows)
    }
  }
  let budget : FixedInputGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  for index, input in inputs {
    guard input.bound.output.table is Some(table) else {
      return Err(InputRepresentationRequired(index))
    }
    match
      measure_input_values(
        ProducerGuardRows::{ input, table, },
        max_value_bytes,
        InputValues,
        budget,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let generated = match
    constrain_guard_roots(original, max_value_bytes, false, budget) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let completed = match
    execute_fixed_producer_inputs(generated, inputs, execution) {
    Ok(value) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard completed_output(completed, target) is Some(output) else {
    return Err(MissingOutput)
  }
  if completed_row_count(output) > max_rows {
    return Err(OutputRows)
  }
  guard output.table is Some(table) else { return Err(MissingOutput) }
  match measure_input_values(table, max_value_bytes, Output, budget) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(completed)
  }
}
