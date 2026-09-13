///|
pub enum GroupExecutionRule {
  PartitionGroups
  EvaluateAggregate(@relation.CheckedAggregate)
}

///|
pub struct GroupExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  group : @relation.CheckedGroup
  rule : GroupExecutionRule
}

///|
fn group_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  guard pending.kind is @relation.GroupPartitioning ||
    pending.kind is @relation.AggregateDemand else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  // Window groups, pivots and analytic calls have separate execution boundaries.
  guard step.operation is @pipeline.Unary(operation) &&
    @relation.operation(operation) == @relation.Group else {
    return Ok(None)
  }
  guard @relation.group(operation) is Some(group) && step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @pipeline.input_occurrence_count(step) != 1 {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  guard @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return Err(ForeignOccurrence(site.step))
  }
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = if pending.kind is @relation.GroupPartitioning {
    PartitionGroups
  } else {
    guard @relation.aggregate_for_validation(group, site.index) is Some(call) else {
      return Err(ForeignOccurrence(site.step))
    }
    EvaluateAggregate(call)
  }
  Ok(Some(GroupExecution({ site, step, input, operation, group, rule, })))
}
