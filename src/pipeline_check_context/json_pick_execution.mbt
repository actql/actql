///|
pub struct JsonPickExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  policy : @policy.Policy
}

///|
fn json_pick_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    pending.kind is @relation.ValidateReshapeRows else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    @relation.operation(operation) == @relation.JsonPick else {
    return Ok(None)
  }
  guard step.input is Some(input) &&
    @relation.json_pick_source(operation) is Some(_) &&
    @relation.json_pick_path_count(operation) > 0 &&
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
  Ok(Some(JsonPickExecution({ site, step, input, operation, policy, })))
}
