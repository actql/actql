///|
/// Exact measured material, still not execution-success evidence.
struct MeasuredNumericOutput {
  rows : @execution.AdmittedOutputRows
  measurement : @execution.FixedProducerMeasuredOutput
  roots : (Int, Int, Int)
  input : @execution.ProducerRead
  mut completed : Bool
}

///|
pub fn measure_numeric_output(
  plan : NumericPlan,
  input : @execution.ProducerRead,
  max_work : Int,
  max_rows : Int,
  max_value_bytes : Int,
  values : @execution.ValueLimits,
  physical : @execution.FixedInputGuardMeasureLimits,
  root_limits~ : @execution.FixedInputGuardMeasureLimits,
) -> Result[MeasuredNumericOutput, PlanIssue] {
  if root_limits.max_work < 0 ||
    root_limits.max_bytes < 0 ||
    root_limits.max_nodes < 0 ||
    root_limits.max_depth < 0 {
    return Err(Limit)
  }
  if !physical_equal(plan.owner, @execution.producer_read_receiver(input)) {
    return Err(Unsupported)
  }
  let measurement = match
    @execution.prepare_fixed_producer_measurement(
      [input],
      Step(1),
      max_rows~,
      max_value_bytes~,
      physical,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Guard(issue))
  }
  let budget : RootBudget = {
    ceiling: max_value_bytes,
    depth: root_limits.max_depth,
    work: root_limits.max_work,
    bytes: root_limits.max_bytes,
    nodes: root_limits.max_nodes,
  }
  let rows = match
    materialize_with_roots(
      plan,
      input,
      max_work,
      max_rows,
      values,
      Some(fn(row, left, right, result) {
        for position, value in [left, right, result] {
          match measure_root(budget, row, position, value) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
        Ok(())
      }),
    ) {
    Ok(rows) => rows
    Err(issue) => return Err(issue)
  }
  @execution.finish_fixed_producer_measurement(measurement, rows)
  .map(measurement => {
    rows,
    measurement,
    input,
    completed: false,
    roots: (
      root_limits.max_work - budget.work,
      root_limits.max_bytes - budget.bytes,
      root_limits.max_nodes - budget.nodes,
    ),
  })
  .map_err(issue => Guard(issue))
}

///|
pub fn measured_numeric_rows(
  value : MeasuredNumericOutput,
) -> @execution.AdmittedOutputRows {
  value.rows
}

///|
pub fn measured_numeric_usage(value : MeasuredNumericOutput) -> (Int, Int, Int) {
  @execution.fixed_producer_measurement_usage(value.measurement)
}

///|
pub fn measured_numeric_root_usage(
  value : MeasuredNumericOutput,
) -> (Int, Int, Int) {
  value.roots
}
