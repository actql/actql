///|
/// Attempt-local access to an already selected common reduction. The callback
/// does not select a member and cannot turn a missing slot into local fallback.
struct NumericAggregateExecution {
  reduce : (Int, String, Int, Array[Double], Int, Int) -> Result[
    @numeric.Outcome,
    @numeric.ReductionIssue,
  ]?
}

///|
/// Install one trusted execution callback. Authority still belongs to the
/// common managed attempt that created the callback and accepts its capture.
pub fn numeric_aggregate_execution(
  reduce : (Int, String, Int, Array[Double], Int, Int) -> Result[
    @numeric.Outcome,
    @numeric.ReductionIssue,
  ]?,
) -> NumericAggregateExecution {
  { reduce, }
}

///|
fn run_numeric_aggregate(
  execution : NumericAggregateExecution,
  step : Int,
  name : String,
  occurrence : Int,
  contributors : Array[Double],
  expected_count : Int,
  max_work : Int,
) -> Result[@numeric.Outcome, @numeric.ReductionIssue]? {
  (execution.reduce)(
    step, name, occurrence, contributors, expected_count, max_work,
  )
}
