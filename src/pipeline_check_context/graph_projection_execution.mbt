///|
pub(all) enum GraphProjectionRule {
  AdmitGraphRecords
  RejectColumnCollisions
  RestoreIdentityNames
} derive(Eq, Debug)

///|
/// A future check on the exact Graph input and projection, not admitted data.
pub struct GraphProjectionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @projection.CheckedProjection
  rule : GraphProjectionRule
}

///|
fn graph_projection_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ProjectionRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateGraphRecords => AdmitGraphRecords
    RejectRuntimeColumnCollisions => RejectColumnCollisions
    RestoreSemanticIdentityNames => RestoreIdentityNames
    ResolveGraphProjectionResources => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Projection(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @projection.graph_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(GraphProjection({ site, step, input, operation, rule, })))
}
