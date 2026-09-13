///|
pub(all) enum IntervalExecutionRule {
  AdmitAllIntervalEndpoints
  AdmitSafeIntegerClocks
  PreserveIntervalOccurrenceOrder
} derive(Eq, Debug)

///|
/// Future checks over both captured operands. A missing total-order witness is
/// unknown, not permission to invent one from physical input enumeration.
pub struct IntervalExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @join.CheckedIntervalJoin
  left_time : @join.TemporalOperand
  right_time : @join.TemporalOperand
  timestamp : Bool
  output_order : @pipeline.LogicalOrder?
  rule : IntervalExecutionRule
}

///|
fn interval_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.IntervalJoinRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateIntervalEndpoints => AdmitAllIntervalEndpoints
    ValidateSafeIntegerClocks => AdmitSafeIntegerClocks
    PreserveRowOrder => PreserveIntervalOccurrenceOrder
    _ => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.IntervalJoin(right~, checked=operation) &&
    step.input is Some(left) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @join.interval_pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.target != left ||
    l.role != @pipeline.Left ||
    r.target != right ||
    r.role != @pipeline.Right {
    return Err(ForeignOccurrence(site.step))
  }
  let timestamp = @join.interval_uses_timestamps(operation)
  if rule == AdmitSafeIntegerClocks && timestamp {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      IntervalExecution({
        site,
        step,
        left,
        right,
        operation,
        left_time: @join.interval_operand(operation, @schema.Left),
        right_time: @join.interval_operand(operation, @schema.Right),
        timestamp,
        // The derived witness already retains only applicable producer dependencies;
        // semi/anti do not acquire an unrelated right-side order requirement here.
        output_order: @pipeline.logical_order(
          site.pipeline,
          @pipeline.Step(site.step),
        ),
        rule,
      }),
    ),
  )
}
