///|
/// Bounded scalar comparison measurement, without Host/SQL/attempt assembly.
/// Successful measurement is not proof of execution or producer identity.
struct ComparisonMeasurement {
  state : ComparisonDemand
  budget : NativeValueBudget
  physical : @execution.FixedInputGuardMeasureLimits
  rhs : @admitted.Value
  mut open : Bool
}

///|
pub fn prepare_comparison_measurement(
  rhs : @admitted.Value,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[ComparisonMeasurement, NativeDemandIssue] {
  if max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    state: { rows: 0, field_bytes: 0L, rhs_bytes: None, null_rows: 0, },
    budget: {
      guards: { max_value_bytes, max_output_rows: 2147483647, },
      work: physical.max_work,
      bytes: physical.max_bytes,
      nodes: physical.max_nodes,
      depth: physical.max_depth,
    },
    physical,
    rhs,
    open: true,
  })
}

///|
pub fn append_comparison_measurement(
  measurement : ComparisonMeasurement,
  value : @admitted.Value,
) -> Result[Unit, NativeDemandIssue] {
  if !measurement.open || measurement.state.rows == 2147483647 {
    measurement.open = false
    return Err(InvalidState)
  }
  let result = accumulate_comparison_demand(
    measurement.state,
    measurement.budget,
    Admitted(value),
    Admitted(measurement.rhs),
  )
  if result is Err(_) {
    measurement.open = false
  }
  result
}

///|
pub fn finish_comparison_measurement(
  measurement : ComparisonMeasurement,
  true_rows : Int,
) -> Result[NativeDemandUsage, NativeDemandIssue] {
  if !measurement.open {
    return Err(InvalidState)
  }
  measurement.open = false
  finish_comparison_demand(
    measurement.state,
    true_rows,
    measurement.budget,
    measurement.physical,
  )
}
