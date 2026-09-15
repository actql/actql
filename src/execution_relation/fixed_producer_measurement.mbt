///|
/// One-use measurement session, not execution evidence. The exact fixed input
/// remains owned across backend execution; output measurement uses the same
/// physical ledger and cannot be paired with another consumer or target.
struct FixedProducerMeasurement {
  inputs : Array[ProducerRead]
  target : @pipeline.Target
  max_rows : Int
  max_value_bytes : Int
  budget : FixedInputGuardBudget
  initial : FixedInputGuardMeasureLimits
  mut open : Bool
}

///|
struct FixedProducerMeasuredOutput {
  measurement : FixedProducerMeasurement
  rows : AdmittedOutputRows
}

///|
priv struct AdmittedGuardRows {
  rows : AdmittedOutputRows
}

///|
impl IndexedRows for AdmittedGuardRows with fn row_count(self) {
  self.rows.rows.length()
}

///|
impl IndexedRows for AdmittedGuardRows with fn column_count(self) {
  @schema.field_count(self.rows.schema)
}

///|
impl IndexedRows for AdmittedGuardRows with fn row_width(self, row) {
  self.rows.rows[row].length()
}

///|
impl IndexedRows for AdmittedGuardRows with fn read_cell(self, row, column) {
  capture(self.rows.rows[row][column])
}

///|
pub fn prepare_fixed_producer_measurement(
  inputs : Array[ProducerRead],
  target : @pipeline.Target,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  physical : FixedInputGuardMeasureLimits,
) -> Result[FixedProducerMeasurement, FixedInputGuardIssue] {
  if max_rows < 0 ||
    max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if inputs.is_empty() {
    return Err(ForeignInput)
  }
  let owner = producer_read_receiver(inputs[0])
  let prepared = @lower.bound_preparation(owner)
  if inputs.length() != @lower.preparation_input_count(prepared) {
    return Err(ForeignInput)
  }
  if inputs.length() > physical.max_work {
    return Err(MeasurementWork)
  }
  for index in 0..<inputs.length() {
    let input = inputs[index]
    if !producer_read_available(input) ||
      !physical_equal(producer_read_receiver(input), owner) ||
      producer_read_input_index(input) != index {
      return Err(ForeignInput)
    }
    if producer_read_row_count(input) > max_rows {
      return Err(InputRows)
    }
  }
  guard target is Step(index) &&
    index == @lower.node_count(prepared) - 1 &&
    @lower.preparation_schema_at(prepared, target) is Some(_) else {
    return Err(MissingOutput)
  }
  let budget : FixedInputGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  for input in inputs {
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
  }
  Ok({
    inputs: inputs.copy(),
    target,
    max_rows,
    max_value_bytes,
    budget,
    initial: physical,
    open: true,
  })
}

///|
pub fn finish_fixed_producer_measurement(
  measurement : FixedProducerMeasurement,
  rows : AdmittedOutputRows,
) -> Result[FixedProducerMeasuredOutput, FixedInputGuardIssue] {
  if !measurement.open {
    return Err(ForeignInput)
  }
  measurement.open = false
  let owner = producer_read_receiver(measurement.inputs[0])
  let prepared = @lower.bound_preparation(owner)
  for input in measurement.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInput)
    }
  }
  if !physical_equal(rows.owner, owner) || rows.target != measurement.target {
    return Err(ForeignInput)
  }
  guard @lower.preparation_schema_at(prepared, measurement.target)
    is Some(schema) &&
    physical_equal(schema, rows.schema) else {
    return Err(InvalidLayout)
  }
  if rows.rows.length() > measurement.max_rows {
    return Err(OutputRows)
  }
  match
    measure_input_values(
      AdmittedGuardRows::{ rows, },
      measurement.max_value_bytes,
      Output,
      measurement.budget,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok({ measurement, rows, })
  }
}

///|
pub fn fixed_producer_measurement_matches(
  value : FixedProducerMeasuredOutput,
  inputs : Array[ProducerRead],
  rows : AdmittedOutputRows,
  max_rows : Int,
  max_value_bytes : Int,
) -> Bool {
  if inputs.length() != value.measurement.inputs.length() {
    return false
  }
  for index in 0..<inputs.length() {
    if !physical_equal(value.measurement.inputs[index], inputs[index]) ||
      !producer_read_available(inputs[index]) {
      return false
    }
  }
  physical_equal(value.rows, rows) &&
  value.measurement.max_rows == max_rows &&
  value.measurement.max_value_bytes == max_value_bytes
}

///|
pub fn fixed_producer_measurement_usage(
  value : FixedProducerMeasuredOutput,
) -> (Int, Int, Int) {
  let measurement = value.measurement
  (
    measurement.initial.max_work - measurement.budget.work,
    measurement.initial.max_bytes - measurement.budget.bytes,
    measurement.initial.max_nodes - measurement.budget.nodes,
  )
}
