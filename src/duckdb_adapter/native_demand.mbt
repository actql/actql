///|
pub(all) enum NativeDemandIssue {
  InvalidState
  InvalidLimits
  InvalidLayout
  InvalidResultCount
  Operand(Int, Bool, NativeValueIssue)
  Predicate(NativeValueIssue)
}

///|
/// Exact measurements for the compiled single eager comparison. RHS bytes are
/// per occurrence (repeated rows times); no RHS is demanded for an empty scan.
pub(all) struct NativeDemandUsage {
  rows : Int
  field_bytes : Int64
  rhs_bytes : Int?
  true_rows : Int
  false_rows : Int
  null_rows : Int
  predicate_bytes : Int64
  physical_work : Int
  physical_bytes : Int
  physical_nodes : Int
}

///|
/// A live receiving-owned measurement, not execution attestation or capture.
/// The trusted issuer must also bind actual SQL, read view, attempt and retention.
struct NativeDemandMeasurement {
  owner : NativeReceiving
  usage : NativeDemandUsage
}

///|
fn measure_demand_scalar(
  budget : NativeValueBudget,
  value : @admitted.Value?,
) -> Result[Int, NativeValueIssue] {
  if budget.work == 0 {
    return Err(MeasurementWork)
  }
  budget.work -= 1
  let usage = try {
    let writer = @encode.measuring_writer(
      budget.bytes,
      budget.nodes,
      budget.depth,
    )
    match value {
      Some(value) => @admitted.emit_wire_value(value, writer)
      None => @encode.null_value(writer)
    }
    @encode.finish_measurement_usage(writer)
  } catch {
    issue => return Err(Measurement(issue))
  }
  budget.bytes -= usage.0
  budget.nodes -= usage.1
  if usage.0 > budget.guards.max_value_bytes {
    return Err(ValueBytes)
  }
  Ok(usage.0)
}

///|
/// Measure retained operands without rerunning the predicate. In this restricted
/// compiler, SQL WHERE returns exactly true rows, and NULL comparison results
/// are determined by operand nullness. False rows are the remaining occurrences.
/// These are exact identities, not selectivity estimates. Count consistency
/// alone cannot attest that a provider actually executed the owned SQL.
pub fn measure_native_demand(
  receiving : NativeReceiving,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[NativeDemandMeasurement, NativeDemandIssue] {
  let result = measure_native_demand_impl(receiving, physical)
  if result is Err(_) {
    abort_native_receiving(receiving)
  }
  result
}

///|
fn measure_native_demand_impl(
  receiving : NativeReceiving,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[NativeDemandMeasurement, NativeDemandIssue] {
  guard receiving.phase is Received &&
    receiving.validation is Some(validation) &&
    receiving.native is Some(native) else {
    return Err(InvalidState)
  }
  if physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let query = receiving.scan.query
  let column = receiving.scan.predicate_column
  let rhs = match query.parameter.value {
    Admitted(value) => Some(value)
    Null => None
    _ => return Err(InvalidLayout)
  }
  let budget : NativeValueBudget = {
    guards: receiving.measurement.guards,
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let mut row = 0
  let mut field_bytes = 0L
  let mut rhs_bytes = None
  let mut null_rows = 0
  for batch in receiving.validation_batches {
    for offset in 0..<batch.rows {
      guard physical_batch_cell(batch, offset, column) is Some(cell) else {
        return Err(InvalidLayout)
      }
      let bytes = match measure_demand_scalar(budget, Some(cell.value)) {
        Ok(bytes) => bytes
        Err(issue) => return Err(Operand(row, false, issue))
      }
      field_bytes += bytes.to_int64()
      // The bound immutable value is identical for every demanded occurrence.
      // Measure once at first demand, not during preparation or on empty input.
      if rhs_bytes is None {
        rhs_bytes = Some(
          match measure_demand_scalar(budget, rhs) {
            Ok(bytes) => bytes
            Err(issue) => return Err(Operand(row, true, issue))
          },
        )
      }
      if cell.value is @admitted.Null ||
        rhs is None ||
        rhs is Some(@admitted.Null) {
        null_rows += 1
      }
      row += 1
    }
  }
  if row != validation.rows {
    return Err(InvalidLayout)
  }
  if native.rows > row - null_rows {
    return Err(InvalidResultCount)
  }
  let true_rows = native.rows
  let false_rows = row - null_rows - true_rows
  let max_predicate_bytes = if false_rows > 0 {
    5
  } else if row > 0 {
    4
  } else {
    0
  }
  if max_predicate_bytes > budget.guards.max_value_bytes {
    return Err(Predicate(ValueBytes))
  }
  Ok({
    owner: receiving,
    usage: {
      rows: row,
      field_bytes,
      rhs_bytes,
      true_rows,
      false_rows,
      null_rows,
      predicate_bytes: (true_rows.to_int64() + null_rows.to_int64()) * 4L +
      false_rows.to_int64() * 5L,
      physical_work: physical.max_work - budget.work,
      physical_bytes: physical.max_bytes - budget.bytes,
      physical_nodes: physical.max_nodes - budget.nodes,
    },
  })
}

///|
pub fn native_demand_matches(
  value : NativeDemandMeasurement,
  receiving : NativeReceiving,
) -> Bool {
  physical_equal(value.owner, receiving) && receiving.phase is Received
}

///|
pub fn native_demand_usage(
  value : NativeDemandMeasurement,
) -> NativeDemandUsage {
  value.usage
}
