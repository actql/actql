///|
/// Exact measured material, still not execution-success evidence. In particular
/// demanded expression-root checks must precede completion publication.
struct MeasuredNumericOutput {
  rows : @execution.AdmittedOutputRows
  measurement : @execution.FixedProducerMeasuredOutput
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
) -> Result[MeasuredNumericOutput, PlanIssue] {
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
  let rows = match
    materialize_numeric_output(plan, input, max_work, max_rows, values) {
    Ok(rows) => rows
    Err(issue) => return Err(issue)
  }
  @execution.finish_fixed_producer_measurement(measurement, rows)
  .map(measurement => { rows, measurement, })
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
