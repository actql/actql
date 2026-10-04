///|
pub(all) enum GraphEqualityRule {
  CompareGraphValues
  RequireEqualityResources
} derive(Eq, Debug)

///|
pub struct GraphEqualityCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @graph.CheckedPropertyEquality
  rule : GraphEqualityRule
  policy : @policy.Policy
}

///|
fn graph_equality_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  let rule = match site.requirement {
    @pipeline.PropertyEqualityRequirement(CompareCompleteGraphValues) =>
      CompareGraphValues
    @pipeline.PropertyEqualityRequirement(ResolvePropertyEqualityResources) =>
      RequireEqualityResources
    _ => return Ok(None)
  }
  let pending = match rule {
    CompareGraphValues => @graph.CompareCompleteGraphValues
    RequireEqualityResources => @graph.ResolvePropertyEqualityResources
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphEquality(right~, checked=operation) &&
    step.input is Some(left) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.operation_obligations_property_equality(site.obligations)
    is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.property_equality_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let first = @pipeline.input_occurrence_at(step, 0).unwrap()
  let second = @pipeline.input_occurrence_at(step, 1).unwrap()
  if first.role != @pipeline.Left ||
    first.target != left ||
    second.role != @pipeline.Right ||
    second.target != right {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      GraphEqualityExecution({
        site,
        step,
        left,
        right,
        operation,
        rule,
        policy,
      }),
    ),
  )
}
