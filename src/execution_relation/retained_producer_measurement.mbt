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
  scan.column_measurements = Array::make(scan.wire_columns.length(), (0, 0))
  scan.column_nulls = Array::make(scan.wire_columns.length(), 0)
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
      column_usage=scan.column_measurements,
      column_nulls=scan.column_nulls,
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
    scan.column_measurements = []
    scan.column_nulls = []
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
      column_usage: scan.column_measurements,
      column_nulls: scan.column_nulls,
      ceiling: measurement.max_value_bytes,
      depth: measurement.budget.depth,
      work: work - measurement.budget.work,
      bytes: bytes - measurement.budget.bytes,
      nodes: nodes - measurement.budget.nodes,
    })
  }
  // Ownership of successful subtotals moves to the immutable material cache.
  // Do not keep a second per-column buffer in the closed scan.
  scan.column_measurements = []
  scan.column_nulls = []
  measurement.scanning_input = false
  measurement.next_input += 1
  advance_fixed_producer_input_measurement(measurement)
}

///|
// Private Core-issued evidence, owned by a single immutable material generation.
// This is a successful bound, not the exact maximum or a diagnostic position.
priv struct RetainedValueMeasurement {
  columns : Array[Int]
  column_usage : Array[(Int, Int)]
  // Exact null occurrences per measured column, over the same complete rows.
  column_nulls : Array[Int]
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
  if evidence.ceiling > measurement.max_value_bytes ||
    evidence.depth > measurement.budget.depth {
    return None
  }
  if evidence.columns != scan.wire_columns {
    return project_retained_value_measurement(scan, measurement, evidence)
  }
  if evidence.work > measurement.budget.work ||
    evidence.bytes > measurement.budget.bytes ||
    evidence.nodes > measurement.budget.nodes {
    // An insufficient summary is not a violation. Ordinary ordered measurement
    // preserves the exact first failure and partial budget on tighter limits.
    return None
  }
  Some(evidence)
}

///|
/// Closed projection/copy rule over the same material and all of its rows.
/// This transports per-value quantities, not record bytes or a Result CID.
fn project_retained_value_measurement(
  scan : RetainedProducerScan,
  measurement : FixedProducerMeasurement,
  evidence : RetainedValueMeasurement,
) -> RetainedValueMeasurement? {
  let rows = producer_read_row_count(scan.input)
  let budget = measurement.budget
  if rows > budget.work {
    return None
  }
  let mut work = rows
  let mut bytes = 0
  let mut nodes = 0
  let mut remaining = scan.wire.max_order_work
  let column_usage = []
  let column_nulls = []
  for column in scan.wire_columns {
    let mut found = None
    for index, stored in evidence.columns {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      if stored == column {
        found = match
          (evidence.column_usage.get(index), evidence.column_nulls.get(index)) {
          (Some(usage), Some(nulls)) => Some((usage, nulls))
          _ => None
        }
        break
      }
    }
    guard found is Some(((column_bytes, column_nodes), null_rows)) else {
      return None
    }
    if rows > budget.work - work ||
      column_bytes > budget.bytes - bytes ||
      column_nodes > budget.nodes - nodes {
      return None
    }
    work += rows
    bytes += column_bytes
    nodes += column_nodes
    column_usage.push((column_bytes, column_nodes))
    column_nulls.push(null_rows)
  }
  Some({
    columns: scan.wire_columns.copy(),
    column_usage,
    column_nulls,
    ceiling: evidence.ceiling,
    depth: evidence.depth,
    work,
    bytes,
    nodes,
  })
}

///|
/// Canonical per-value facts for one receiving column of a reused retained read.
/// The bound is a successful ceiling over the measured values, not an exact
/// maximum; depth is a conservative admission depth. Not an issuer capability.
pub(all) struct RetainedColumnMeasurement {
  rows : Int
  bytes : Int
  nodes : Int
  null_rows : Int
  value_bytes_bound : Int
  depth : Int
} derive(Eq, Debug)

///|
/// Facts only from the live exact representation this scan is already bound to
/// by its trusted reuse proof: same read, same immutable generation, all rows
/// (a read is a projection/rename/copy and never selects rows), and the stored
/// column that the checked read names. Anything else is `None`, never a guess.
pub fn retained_producer_scan_column_measurement(
  scan : RetainedProducerScan,
  column : Int,
) -> RetainedColumnMeasurement? {
  guard retained_producer_scan_reuse_current(scan) &&
    scan.reuse is Some(reuse) &&
    physical_equal(reuse.input, scan.input) &&
    producer_read_retained_material(scan.input) is Some(material) &&
    physical_equal(material, reuse.material) &&
    material.value_measurement is Some(evidence) &&
    scan.wire_columns.get(column) is Some(stored) else {
    return None
  }
  let rows = producer_read_row_count(scan.input)
  if rows != material.receipt.rows ||
    evidence.column_usage.length() != evidence.columns.length() ||
    evidence.column_nulls.length() != evidence.columns.length() {
    return None
  }
  let mut remaining = scan.wire.max_order_work
  for index, candidate in evidence.columns {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    if candidate == stored {
      let (bytes, nodes) = evidence.column_usage[index]
      let null_rows = evidence.column_nulls[index]
      if null_rows < 0 || null_rows > rows {
        return None
      }
      return Some({
        rows,
        bytes,
        nodes,
        null_rows,
        value_bytes_bound: evidence.ceiling,
        depth: evidence.depth,
      })
    }
  }
  None
}
