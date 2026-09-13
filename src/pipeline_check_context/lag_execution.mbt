///|
pub struct LagExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  field : @relation.KeyField
  output : String
  offset : @relation.CountValue
  policy : @policy.Policy
}

///|
// Navigation does not establish its own ordering or discharge bound offsets.
// Both static requirements must close in the same owning inventory.
fn lag_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    pending.kind is @relation.ValidateReshapeRows else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    @relation.operation(operation) == @relation.Lag else {
    return Ok(None)
  }
  guard step.input is Some(input) &&
    @relation.lag_navigation(operation) is Some((field, output, offset)) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      LagExecution({
        site,
        step,
        input,
        operation,
        field,
        output,
        offset,
        policy,
      }),
    ),
  )
}
