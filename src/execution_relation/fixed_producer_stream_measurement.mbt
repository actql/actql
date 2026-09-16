///|
/// Measurements of this exact admitted stream, not transport/Compute evidence.
/// The receipt holds only an opaque identity, never the upstream live handles.
struct FixedProducerStreamMeasuredOutput {
  measurement : FixedProducerMeasurement
  receipt : AdmittedOutputStreamReceipt
}

///|
priv struct SingleAdmittedGuardRow {
  values : Array[@admitted.Value]
}

///|
impl IndexedRows for SingleAdmittedGuardRow with fn row_count(_self) {
  1
}

///|
impl IndexedRows for SingleAdmittedGuardRow with fn column_count(self) {
  self.values.length()
}

///|
impl IndexedRows for SingleAdmittedGuardRow with fn row_width(self, _row) {
  self.values.length()
}

///|
impl IndexedRows for SingleAdmittedGuardRow with fn read_cell(
  self,
  _row,
  column,
) {
  capture(self.values[column])
}

///|
/// Bind the unconsumed measurement to one empty stream before result reception.
/// The same input/output budget is retained; no fresh per-chunk budget is made.
pub fn attach_fixed_producer_stream_measurement(
  measurement : FixedProducerMeasurement,
  stream : AdmittedOutputStream,
) -> Result[Unit, FixedInputGuardIssue] {
  if !measurement.open ||
    measurement.scanning_input ||
    measurement.next_input != measurement.inputs.length() ||
    !stream.open ||
    stream.reading ||
    stream.rows != 0 ||
    stream.measurement is Some(_) ||
    !physical_equal(stream.owner, producer_read_receiver(measurement.inputs[0])) ||
    stream.target != measurement.target {
    return Err(ForeignInput)
  }
  for input in measurement.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInput)
    }
  }
  measurement.open = false
  stream.measurement = Some(measurement)
  Ok(())
}

///|
fn measure_fixed_producer_stream_row(
  measurement : FixedProducerMeasurement,
  values : Array[@admitted.Value],
) -> Unit {
  // Preserve the first measurement failure for the completion phase. Physical
  // decoding/admission must still reject a later invalid chunk before a normal
  // result is exposed; moving the measurement does not authorize early success.
  if measurement.streamed_issue is None {
    match
      measure_input_values(
        SingleAdmittedGuardRow::{ values, },
        measurement.max_value_bytes,
        Output,
        measurement.budget,
      ) {
      Ok(_) => ()
      Err(issue) =>
        measurement.streamed_issue = Some(
          match issue {
            Measurement(phase, _, column, issue) =>
              Measurement(phase, measurement.streamed_rows, column, issue)
            ValueBytes(phase, _, column) =>
              ValueBytes(phase, measurement.streamed_rows, column)
            _ => issue
          },
        )
    }
  }
  measurement.streamed_rows += 1
}

///|
pub fn finish_fixed_producer_stream_measurement(
  measurement : FixedProducerMeasurement,
  receipt : AdmittedOutputStreamReceipt,
) -> Result[FixedProducerStreamMeasuredOutput, FixedInputGuardIssue] {
  guard !measurement.open &&
    !measurement.identity.val &&
    receipt.measurement_identity is Some(identity) &&
    physical_equal(identity, measurement.identity) &&
    physical_equal(receipt.owner, producer_read_receiver(measurement.inputs[0])) &&
    receipt.target == measurement.target &&
    receipt.rows == measurement.streamed_rows else {
    return Err(ForeignInput)
  }
  measurement.identity.val = true
  for input in measurement.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInput)
    }
  }
  if receipt.rows > measurement.max_rows {
    return Err(OutputRows)
  }
  match measurement.streamed_issue {
    Some(issue) => Err(issue)
    None => Ok({ measurement, receipt, })
  }
}

///|
pub fn fixed_producer_stream_measurement_matches(
  value : FixedProducerStreamMeasuredOutput,
  inputs : Array[ProducerRead],
  receipt : AdmittedOutputStreamReceipt,
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
  physical_equal(value.receipt, receipt) &&
  value.measurement.max_rows == max_rows &&
  value.measurement.max_value_bytes == max_value_bytes
}

///|
pub fn fixed_producer_stream_measurement_usage(
  value : FixedProducerStreamMeasuredOutput,
) -> (Int, Int, Int) {
  let measurement = value.measurement
  (
    measurement.initial.max_work - measurement.budget.work,
    measurement.initial.max_bytes - measurement.budget.bytes,
    measurement.initial.max_nodes - measurement.budget.nodes,
  )
}
