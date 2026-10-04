///|
/// Runtime resource admission remains bound to the checked Graph occurrence.
pub struct GraphNormalizeCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedNormalize
  policy : @policy.Policy
}

///|
fn graph_normalize_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.NormalizeRequirement(ResolveNormalizeResources) else {
    return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphNormalize(operation) &&
    @pipeline.operation_obligations_graph_normalize(site.obligations)
    is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.normalize_pending_at(operation, site.index) ==
    Some(ResolveNormalizeResources) &&
    step.input is Some(input) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0)
    is Some({ role: @pipeline.Primary, target, }) &&
    target == input else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(GraphNormalizeExecution({ site, step, input, operation, policy, })))
}
