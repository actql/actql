///|
pub(all) enum GraphExecutionRule {
  AdmitGraphData
  OrderComponentIdentities
  OrderBoundsReport
} derive(Eq, Debug)

///|
/// The retained operation supplies checked options and Carrier contracts.
/// Runtime graph admission and ordering are not completed by this binding.
pub struct GraphExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedGraph
  rule : GraphExecutionRule
}

///|
fn graph_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.GraphRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateGraphData => AdmitGraphData
    ComponentIdentityOrder => OrderComponentIdentities
    BoundsReportOrder => OrderBoundsReport
    ResolveSgaProfile
    | ResolveGraphResources
    | BindPositiveCount(_)
    | BindNonnegativeCount(_)
    | EnforceOutputGuard => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Graph(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(GraphExecution({ site, step, input, operation, rule, })))
}
