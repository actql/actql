///|
pub(all) enum NativeDemandIssue {
  InvalidState
  InvalidLimits
  InvalidLayout
  InvalidResultCount
  InputRepresentationRequired
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
priv struct ComparisonDemand {
  mut rows : Int
  mut field_bytes : Int64
  mut rhs_bytes : Int?
  mut null_rows : Int
}

///|
fn accumulate_comparison_demand(
  state : ComparisonDemand,
  budget : NativeValueBudget,
  value : ParameterValue,
  rhs : ParameterValue,
) -> Result[Unit, NativeDemandIssue] {
  let bytes = match measure_demand_scalar(budget, value) {
    Ok(bytes) => bytes
    Err(issue) => return Err(Operand(state.rows, false, issue))
  }
  state.field_bytes += bytes.to_int64()
  if state.rhs_bytes is None {
    state.rhs_bytes = Some(
      match measure_demand_scalar(budget, rhs) {
        Ok(bytes) => bytes
        Err(issue) => return Err(Operand(state.rows, true, issue))
      },
    )
  }
  if value is Null ||
    value is Admitted(@admitted.Null) ||
    rhs is Null ||
    rhs is Admitted(@admitted.Null) {
    state.null_rows += 1
  }
  state.rows += 1
  Ok(())
}

///|
/// Canonical per-value facts of one complete operand column.
priv struct ComparisonDemandFacts {
  rows : Int
  bytes : Int
  nodes : Int
  null_rows : Int
  value_bytes_bound : Int
  depth : Int
}

///|
/// The exact result of `accumulate_comparison_demand` over every operand of
/// `facts` in order, applied to a fresh `state`: one work unit per operand plus
/// one for the RHS (measured once, after operands only when rows exist), the
/// same bytes and nodes, and the same null rule. Returns `false` without any
/// change whenever some step of that fold could fail, because only the ordered
/// fold can locate the first failing operand.
fn apply_comparison_demand_facts(
  state : ComparisonDemand,
  budget : NativeValueBudget,
  facts : ComparisonDemandFacts,
  rhs : ParameterValue,
) -> Bool {
  guard state.rows == 0 &&
    state.field_bytes == 0L &&
    state.rhs_bytes is None &&
    state.null_rows == 0 &&
    facts.rows >= 0 &&
    facts.bytes >= 0 &&
    facts.nodes >= 0 &&
    facts.null_rows >= 0 &&
    facts.null_rows <= facts.rows else {
    return false
  }
  if facts.rows == 0 {
    // The ordered fold measures nothing and demands no RHS for no operands.
    return true
  }
  if facts.value_bytes_bound > budget.guards.max_value_bytes ||
    facts.depth > budget.depth ||
    facts.rows >= budget.work ||
    facts.bytes > budget.bytes ||
    facts.nodes > budget.nodes {
    return false
  }
  let remaining : NativeValueBudget = {
    guards: budget.guards,
    work: budget.work - facts.rows,
    bytes: budget.bytes - facts.bytes,
    nodes: budget.nodes - facts.nodes,
    depth: budget.depth,
  }
  guard measure_demand_scalar(remaining, rhs) is Ok(rhs_bytes) else {
    return false
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  state.rows = facts.rows
  state.field_bytes = facts.bytes.to_int64()
  state.rhs_bytes = Some(rhs_bytes)
  state.null_rows = if rhs is Null || rhs is Admitted(@admitted.Null) {
    facts.rows
  } else {
    facts.null_rows
  }
  true
}

///|
fn finish_comparison_demand(
  state : ComparisonDemand,
  true_rows : Int,
  budget : NativeValueBudget,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[NativeDemandUsage, NativeDemandIssue] {
  if true_rows < 0 || true_rows > state.rows - state.null_rows {
    return Err(InvalidResultCount)
  }
  let false_rows = state.rows - state.null_rows - true_rows
  let max_predicate_bytes = if false_rows > 0 {
    5
  } else if state.rows > 0 {
    4
  } else {
    0
  }
  if max_predicate_bytes > budget.guards.max_value_bytes {
    return Err(Predicate(ValueBytes))
  }
  Ok({
    rows: state.rows,
    field_bytes: state.field_bytes,
    rhs_bytes: state.rhs_bytes,
    true_rows,
    false_rows,
    null_rows: state.null_rows,
    predicate_bytes: (true_rows.to_int64() + state.null_rows.to_int64()) * 4L +
    false_rows.to_int64() * 5L,
    physical_work: physical.max_work - budget.work,
    physical_bytes: physical.max_bytes - budget.bytes,
    physical_nodes: physical.max_nodes - budget.nodes,
  })
}

///|
fn measure_demand_scalar(
  budget : NativeValueBudget,
  value : ParameterValue,
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
      Admitted(value) => @admitted.emit_wire_value(value, writer)
      Null => @encode.null_value(writer)
      ScalarNumber(value) => @encode.number_value(writer, value)
      ScalarBoolean(value) => @encode.bool_value(writer, value)
      ScalarText(value) => @encode.string_value(writer, value)
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
  if receiving.validation_stream is Some(stream) {
    if physical.max_work != stream.demand_limits.max_work ||
      physical.max_bytes != stream.demand_limits.max_bytes ||
      physical.max_nodes != stream.demand_limits.max_nodes ||
      physical.max_depth != stream.demand_limits.max_depth {
      return Err(InvalidLimits)
    }
    if stream.demand_issue is Some(issue) {
      return Err(issue)
    }
    if stream.demand.rows != validation.rows {
      return Err(InvalidLayout)
    }
    return finish_comparison_demand(
      stream.demand,
      native.rows,
      stream.demand_budget,
      physical,
    ).map(usage => NativeDemandMeasurement::{ owner: receiving, usage, })
  }
  let query = receiving.scan.query
  let column = receiving.scan.predicate_column
  let rhs = match query.parameter.value {
    Admitted(value) => Admitted(value)
    Null => Null
    _ => return Err(InvalidLayout)
  }
  let budget : NativeValueBudget = {
    guards: receiving.measurement.guards,
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let state : ComparisonDemand = {
    rows: 0,
    field_bytes: 0L,
    rhs_bytes: None,
    null_rows: 0,
  }
  for batch in receiving.validation_batches {
    for offset in 0..<batch.rows {
      guard physical_batch_cell(batch, offset, column) is Some(cell) else {
        return Err(InvalidLayout)
      }
      match
        accumulate_comparison_demand(state, budget, Admitted(cell.value), rhs) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  if state.rows != validation.rows {
    return Err(InvalidLayout)
  }
  finish_comparison_demand(state, native.rows, budget, physical).map(usage => NativeDemandMeasurement::{
    owner: receiving,
    usage,
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
