///|
pub(all) enum GraphResourceScope {
  PreserveGraph
  RelationRows(@policy.Ceiling)
}

///|
/// Existing producer admission and resource prerequisites remain on the input
/// edge. No external-input ceiling is reapplied to an internal Graph here.
pub struct GraphResourcesCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedGraph
  policy : @policy.Policy
  scope : GraphResourceScope
}

///|
fn graph_resources_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.GraphRequirement(ResolveGraphResources) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Graph(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.pending_validation_at(operation, site.index) ==
    Some(@graph.ResolveGraphResources) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  let scope = match @graph.operation(operation) {
    Components => return Ok(None)
    NormalizeGraph => GraphResourceScope::PreserveGraph
    Degree | GraphBounds => {
      guard @policy.ceiling(policy, "max_relation_output_rows") is Some(limit) else {
        return Ok(None)
      }
      GraphResourceScope::RelationRows(limit)
    }
  }
  Ok(Some(GraphResources({ site, step, input, operation, policy, scope, })))
}
