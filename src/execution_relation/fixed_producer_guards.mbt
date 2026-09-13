///|
priv struct ProducerGuardRows {
  input : ProducerRead
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
  IndexedRows::read_cell(
    self.input.bound.output.table,
    row,
    self.input.columns[column],
  )
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
  if max_rows < 0 ||
    max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !producer_read_available(input) ||
    !physical_equal(
      generated_sequence_owner(original),
      producer_read_receiver(input),
    ) {
    return Err(ForeignInput)
  }
  if producer_read_row_count(input) > max_rows {
    return Err(InputRows)
  }
  let budget : FixedInputGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  match
    measure_input_values(
      ProducerGuardRows::{ input, },
      max_value_bytes,
      InputValues,
      budget,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let generated = match
    constrain_guard_roots(original, max_value_bytes, false, budget) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let completed = match
    execute_fixed_producer_input(generated, input, execution) {
    Ok(value) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard completed_output(completed, target) is Some(output) else {
    return Err(MissingOutput)
  }
  if completed_row_count(output) > max_rows {
    return Err(OutputRows)
  }
  match measure_input_values(output.table, max_value_bytes, Output, budget) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(completed)
  }
}
