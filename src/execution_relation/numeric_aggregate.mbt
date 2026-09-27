///|
/// Attempt-local access to an already selected common reduction. The callback
/// does not select a member and cannot turn a missing slot into local fallback.
struct NumericAggregateExecution {
  reduce : (Int, String, Int, Array[Double], Int, Int) -> Result[
    @numeric.Outcome,
    @numeric.ReductionIssue,
  ]?
  seal : (Int, String, Int) -> Bool
  start : ((Int, String, Int, Array[Double], Int, Int) -> Result[
    NumericAggregateStep,
    @numeric.ReductionIssue,
  ]?)?
}

///|
/// A common-Host-owned occurrence. Closing never publishes a numeric capture.
struct NumericAggregateStep {
  advance : () -> Result[@numeric.Outcome?, @numeric.ReductionIssue]?
  close : () -> Bool
}

///|
pub fn numeric_aggregate_step(
  advance : () -> Result[@numeric.Outcome?, @numeric.ReductionIssue]?,
  close : () -> Bool,
) -> NumericAggregateStep {
  { advance, close, }
}

///|
pub fn numeric_aggregate_execution_with_steps(
  reduce : (Int, String, Int, Array[Double], Int, Int) -> Result[
    @numeric.Outcome,
    @numeric.ReductionIssue,
  ]?,
  seal : (Int, String, Int) -> Bool,
  start : (Int, String, Int, Array[Double], Int, Int) -> Result[
    NumericAggregateStep,
    @numeric.ReductionIssue,
  ]?,
) -> NumericAggregateExecution {
  { reduce, seal, start: Some(start), }
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
  { reduce, seal: fn(_step, _name, _count) { true }, start: None, }
}

///|
/// Install the selected reduction together with its attempt-owned slot seal.
/// Product execution uses this form; the simpler constructor remains useful
/// for evaluator conformance tests that have no common Host attempt.
pub fn numeric_aggregate_execution_with_seal(
  reduce : (Int, String, Int, Array[Double], Int, Int) -> Result[
    @numeric.Outcome,
    @numeric.ReductionIssue,
  ]?,
  seal : (Int, String, Int) -> Bool,
) -> NumericAggregateExecution {
  { reduce, seal, start: None, }
}

///|
/// Close one exact operation-owned slot after the evaluator has completed the
/// occurrence domain. This is separate from task completion because later
/// relational operations may change the task's final row count.
fn seal_numeric_aggregate(
  execution : NumericAggregateExecution,
  step : Int,
  name : String,
  occurrence_count : Int,
) -> Bool {
  (execution.seal)(step, name, occurrence_count)
}
