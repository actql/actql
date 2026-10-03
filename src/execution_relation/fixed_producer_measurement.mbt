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
  identity : Ref[Bool]
  mut streamed_rows : Int
  mut streamed_issue : FixedInputGuardIssue?
  mut next_input : Int
  mut scanning_input : Bool
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
  admitted_output_row_count(self.rows)
}

///|
impl IndexedRows for AdmittedGuardRows with fn column_count(self) {
  @schema.field_count(self.rows.schema)
}

///|
impl IndexedRows for AdmittedGuardRows with fn row_width(self, row) {
  if @schema.all_fields_required(self.rows.schema) {
    self.rows.rows[row].length()
  } else {
    self.rows.presence_rows[row].cells.length()
  }
}

///|
impl IndexedRows for AdmittedGuardRows with fn read_cell(self, row, column) {
  capture(
    if @schema.all_fields_required(self.rows.schema) {
      self.rows.rows[row][column]
    } else {
      self.rows.presence_rows[row].cells[column].unwrap()
    },
  )
}

///|
impl IndexedRows for AdmittedGuardRows with fn cell_present(self, row, column) {
  @schema.all_fields_required(self.rows.schema) ||
  self.rows.presence_rows[row].cells[column] is Some(_)
}

///|
pub fn prepare_fixed_producer_measurement(
  inputs : Array[ProducerRead],
  target : @pipeline.Target,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  physical : FixedInputGuardMeasureLimits,
) -> Result[FixedProducerMeasurement, FixedInputGuardIssue] {
  prepare_fixed_producer_measurement_impl(
    inputs, target, max_rows, max_value_bytes, physical, false,
  )
}

///|
pub fn prepare_streamed_fixed_producer_measurement(
  inputs : Array[ProducerRead],
  target : @pipeline.Target,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  physical : FixedInputGuardMeasureLimits,
) -> Result[FixedProducerMeasurement, FixedInputGuardIssue] {
  prepare_fixed_producer_measurement_impl(
    inputs, target, max_rows, max_value_bytes, physical, true,
  )
}

///|
fn prepare_fixed_producer_measurement_impl(
  inputs : Array[ProducerRead],
  target : @pipeline.Target,
  max_rows : Int,
  max_value_bytes : Int,
  physical : FixedInputGuardMeasureLimits,
  streaming : Bool,
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
  let measurement : FixedProducerMeasurement = {
    inputs: inputs.copy(),
    target,
    max_rows,
    max_value_bytes,
    budget,
    initial: physical,
    open: true,
    identity: Ref(false),
    streamed_rows: 0,
    streamed_issue: None,
    next_input: 0,
    scanning_input: false,
  }
  match advance_fixed_producer_input_measurement(measurement) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !streaming && measurement.next_input != inputs.length() {
    return Err(InputRepresentationRequired(measurement.next_input))
  }
  Ok(measurement)
}

///|
pub fn finish_fixed_producer_measurement(
  measurement : FixedProducerMeasurement,
  rows : AdmittedOutputRows,
) -> Result[FixedProducerMeasuredOutput, FixedInputGuardIssue] {
  if !measurement.open ||
    measurement.scanning_input ||
    measurement.next_input != measurement.inputs.length() {
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
  if admitted_output_row_count(rows) > measurement.max_rows {
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
