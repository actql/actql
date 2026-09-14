///|
pub(all) enum GraphMatchRule {
  AdmitGraph
  SelectExistingIdentities
  FilterEdgeTypes
  EvaluatePredicate
  OrderMatches
  EnforceMatchResources
} derive(Eq, Debug)

///|
pub struct GraphMatchCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedMatch
  rule : GraphMatchRule
  policy : @policy.Policy
  output_rows : @policy.Ceiling
}

///|
pub fn graph_match_resource_count(check : GraphMatchCheck) -> Int {
  if check.rule == EnforceMatchResources {
    3
  } else {
    0
  }
}

///|
pub fn graph_match_resource_at(
  check : GraphMatchCheck,
  index : Int,
) -> GraphComparisonResource? {
  if check.rule != EnforceMatchResources {
    return None
  }
  graph_comparison_resource(index)
}

///|
fn graph_match_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.MatchRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    AdmitMatchGraphData => AdmitGraph
    ValidateSelectedIdentityMembership => SelectExistingIdentities
    FilterSelectedEdgeTypes => FilterEdgeTypes
    EvaluateMatchPredicate => EvaluatePredicate
    CanonicalMatchOrder => OrderMatches
    ResolveMatchResources => EnforceMatchResources
    ResolveMatchProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphMatch(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.match_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  guard @policy.ceiling(policy, "max_relation_output_rows") is Some(output_rows) else {
    return Ok(None)
  }
  Ok(
    Some(
      GraphMatchExecution({
        site,
        step,
        input,
        operation,
        rule,
        policy,
        output_rows,
      }),
    ),
  )
}
