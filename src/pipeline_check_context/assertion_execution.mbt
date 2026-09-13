///|
pub struct RowAssertionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
}

///|
fn assertion_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  // Consumption is a separate static planning condition, not a runtime check.
  guard pending.kind is @relation.AtomicRowAssertion else { return Ok(None) }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.operation is @pipeline.Unary(operation) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @relation.operation(operation) != @relation.AssertRows ||
    @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @pipeline.input_occurrence_count(step) != 1 {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(RowAssertion({ site, step, input, operation, })))
}
