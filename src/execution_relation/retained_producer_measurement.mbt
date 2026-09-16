///|
/// Preserve receiving-port order and one physical measurement budget across
/// memory inputs, retained scans, and the eventual output.
fn advance_fixed_producer_input_measurement(
  measurement : FixedProducerMeasurement,
) -> Result[Unit, FixedInputGuardIssue] {
  while measurement.next_input < measurement.inputs.length() {
    let input = measurement.inputs[measurement.next_input]
    if !producer_read_available(input) {
      measurement.open = false
      return Err(ForeignInput)
    }
    guard input.bound.output.table is Some(table) else { return Ok(()) }
    match
      measure_input_values(
        ProducerGuardRows::{ input, table, },
        measurement.max_value_bytes,
        InputValues,
        measurement.budget,
      ) {
      Err(issue) => {
        measurement.open = false
        return Err(issue)
      }
      Ok(_) => ()
    }
    measurement.next_input += 1
  }
  Ok(())
}

///|
pub fn fixed_producer_inputs_measured(
  measurement : FixedProducerMeasurement,
) -> Bool {
  measurement.open &&
  !measurement.scanning_input &&
  measurement.next_input == measurement.inputs.length() &&
  measurement.inputs.all(input => producer_read_available(input))
}

///|
pub fn attach_retained_producer_measurement(
  measurement : FixedProducerMeasurement,
  scan : RetainedProducerScan,
) -> Result[Unit, FixedInputGuardIssue] {
  if !measurement.open ||
    measurement.scanning_input ||
    !scan.open ||
    scan.stream.rows != 0 ||
    scan.measurement is Some(_) ||
    !(measurement.inputs.get(measurement.next_input) is Some(input) &&
    physical_equal(input, scan.input)) ||
    !producer_read_available(scan.input) {
    return Err(ForeignInput)
  }
  measurement.scanning_input = true
  scan.measurement = Some(measurement)
  Ok(())
}

///|
fn measure_retained_producer_scan_row(
  scan : RetainedProducerScan,
  values : Array[@admitted.CheckedValue],
) -> Unit {
  guard scan.measurement is Some(measurement) && scan.guard_issue is None else {
    return
  }
  if !measurement.open {
    scan.guard_issue = Some(ForeignInput)
    return
  }
  match
    measure_input_values(
      SingleAdmittedGuardRow::{ values: values.map(value => value.value), },
      measurement.max_value_bytes,
      InputValues,
      measurement.budget,
    ) {
    Ok(_) => ()
    Err(issue) =>
      scan.guard_issue = Some(
        match issue {
          Measurement(phase, _, column, detail) =>
            Measurement(phase, scan.stream.rows - 1, column, detail)
          ValueBytes(phase, _, column) =>
            ValueBytes(phase, scan.stream.rows - 1, column)
          _ => issue
        },
      )
  }
}

///|
fn finish_retained_producer_scan_measurement(
  scan : RetainedProducerScan,
) -> Result[Unit, FixedInputGuardIssue] {
  guard scan.measurement is Some(measurement) else { return Ok(()) }
  if !measurement.open || !measurement.scanning_input {
    return Err(ForeignInput)
  }
  if scan.guard_issue is Some(issue) {
    measurement.open = false
    return Err(issue)
  }
  measurement.scanning_input = false
  measurement.next_input += 1
  advance_fixed_producer_input_measurement(measurement)
}
