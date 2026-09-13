///|
pub(all) enum AppendRowsRule {
  AdmitBothInputs
  PreserveLeftThenRight
} derive(Eq, Debug)

///|
/// Exact operand occurrences, not a proof that either input has been acquired
/// or admitted. Input order evidence is retained without inventing total order.
pub struct AppendRowsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @append.CheckedAppend
  rule : AppendRowsRule
  left_order : @pipeline.LogicalOrder?
  right_order : @pipeline.LogicalOrder?
}

///|
fn append_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  let rule = match site.requirement {
    @pipeline.AppendRequirement(ValidateInputRows) => AdmitBothInputs
    @pipeline.AppendRequirement(PreserveLeftThenRightOrder) =>
      PreserveLeftThenRight
    _ => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Append(right~, checked=operation) &&
    step.input is Some(left) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @pipeline.input_occurrence_count(step) != 2 {
    return Err(ForeignOccurrence(site.step))
  }
  let first = @pipeline.input_occurrence_at(step, 0).unwrap()
  let second = @pipeline.input_occurrence_at(step, 1).unwrap()
  if first.target != left ||
    second.target != right ||
    first.role != @pipeline.Left ||
    second.role != @pipeline.Right {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      AppendRows({
        site,
        step,
        left,
        right,
        operation,
        rule,
        left_order: @pipeline.logical_order(site.pipeline, left),
        right_order: @pipeline.logical_order(site.pipeline, right),
      }),
    ),
  )
}
