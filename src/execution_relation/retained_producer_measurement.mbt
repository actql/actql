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
  scan.measurement_start = Some(
    (
      measurement.budget.work,
      measurement.budget.bytes,
      measurement.budget.nodes,
    ),
  )
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
  if scan.stream.rows == 1 {
    scan.measurement_reuse = reusable_retained_value_measurement(
      scan, measurement,
    )
  }
  if scan.measurement_reuse is Some(_) {
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
  if scan.measurement_reuse is Some(evidence) {
    // The complete exact representation has now been verified. Keep consumer
    // accounting, but do not repeat the canonical value measurement pass.
    measurement.budget.work -= evidence.work
    measurement.budget.bytes -= evidence.bytes
    measurement.budget.nodes -= evidence.nodes
  } else if scan.measurement_start is Some((work, bytes, nodes)) {
    // One bounded slot per physical generation. Publish only after complete
    // identity verification and successful measurement, never from partial rows.
    let material = scan.input.bound.output.representation.unwrap()
    material.value_measurement = Some({
      columns: scan.wire_columns.copy(),
      ceiling: measurement.max_value_bytes,
      depth: measurement.budget.depth,
      work: work - measurement.budget.work,
      bytes: bytes - measurement.budget.bytes,
      nodes: nodes - measurement.budget.nodes,
    })
  }
  measurement.scanning_input = false
  measurement.next_input += 1
  advance_fixed_producer_input_measurement(measurement)
}

///|
// Private Core-issued evidence, owned by a single immutable material generation.
// This is a successful bound, not the exact maximum or a diagnostic position.
priv struct RetainedValueMeasurement {
  columns : Array[Int]
  ceiling : Int
  depth : Int
  work : Int
  bytes : Int
  nodes : Int
}

///|
fn reusable_retained_value_measurement(
  scan : RetainedProducerScan,
  measurement : FixedProducerMeasurement,
) -> RetainedValueMeasurement? {
  guard scan.reuse is Some(reuse) && retained_scan_reuse_available(reuse) else {
    return None
  }
  guard reuse.material.value_measurement is Some(evidence) else { return None }
  if evidence.columns != scan.wire_columns ||
    evidence.ceiling > measurement.max_value_bytes ||
    evidence.depth > measurement.budget.depth ||
    evidence.work > measurement.budget.work ||
    evidence.bytes > measurement.budget.bytes ||
    evidence.nodes > measurement.budget.nodes {
    // An insufficient summary is not a violation. Ordinary ordered measurement
    // preserves the exact first failure and partial budget on tighter limits.
    return None
  }
  Some(evidence)
}
