///|
pub enum PivotExecutionRule {
  PartitionPivot
  EvaluatePivot
  ValidatePivotResult
  CaptureNumericObservations(PivotNumericDemand)
}

///|
pub struct PivotExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  pivot : @relation.CheckedPivot
  rule : PivotExecutionRule
}

///|
fn pivot_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending.kind {
    @relation.PivotPartitioning => PartitionPivot
    @relation.AggregateDemand => EvaluatePivot
    @relation.AggregateEnvelope => ValidatePivotResult
    _ => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  guard step.operation is @pipeline.Unary(operation) &&
    @relation.pivot(operation) is Some(pivot) else {
    return Ok(None)
  }
  guard step.input is Some(input) &&
    site.group == 0 &&
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
  Ok(Some(PivotExecution({ site, step, input, operation, pivot, rule, })))
}
