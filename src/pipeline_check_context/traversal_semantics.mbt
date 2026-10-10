///|
pub(all) enum TraversalRule {
  AdmitInputGraph
  RespectAuthoredHops
  FilterAuthoredLabels
  EnumerateGraphPaths
  DeduplicatePathIdentities
  SelectMinimumEligibleNodeDepth
  OrderTraversalRows
  ShortestRule(@graph.ShortestObligation)
} derive(Eq, Debug)

///|
/// Future semantic checks retain the original operation and both input roles.
/// Start membership, selected capacities and bound guards are separate checks.
pub struct TraversalCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  selector_relation : @pipeline.Target?
  target_selector_relation : @pipeline.Target?
  operation : @graph.CheckedTraverse
  rule : TraversalRule
}

///|
fn traversal_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.TraverseRequirement(pending) else {
    return Ok(None)
  }
  let rule : TraversalRule = match pending {
    AdmitTraversalGraph => TraversalRule::AdmitInputGraph
    RespectTraversalHopBounds => RespectAuthoredHops
    FilterTraversalLabels => FilterAuthoredLabels
    EnumerateGraphPaths => EnumerateGraphPaths
    DeduplicateExactPaths => DeduplicatePathIdentities
    MinimumEligibleNodeDepth => SelectMinimumEligibleNodeDepth
    CanonicalTraversalOrder => OrderTraversalRows
    ResolveTraversalResources
    | ResolveGraphTraversalProfile
    | EnforceTraversalOutputGuard
    | BindTraversalOutputGuard(_) => return Ok(None)
    ShortestRequirement(
      ResolveShortestResources
      | ResolveShortestProfile
      | EnforceShortestOutputGuard
      | BindShortestOutputGuard(_)
    ) => return Ok(None)
    // Retain the authored Shortest duty; TRAIL enumeration cannot discharge it.
    ShortestRequirement(rule) => ShortestRule(rule)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation
    is @pipeline.Traverse(selector=selector_relation, checked=operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.traverse_pending_at(operation, site.index) == Some(pending) else {
    return Err(ForeignOccurrence(site.step))
  }
  let target_relation = @graph.traverse_shortest(operation)
    .map(shortest => {
      @graph.selector_form(@graph.shortest_targets(shortest))
      is @graph.RelationIds(..)
    })
    .unwrap_or(false)
  let count = 1 + (if selector_relation is Some(_) { 1 } else { 0 })
  if @pipeline.input_occurrence_count(step) !=
    count + (if target_relation { 1 } else { 0 }) {
    return Err(ForeignOccurrence(site.step))
  }
  let target_selector_relation = if target_relation {
    let edge = @pipeline.input_occurrence_at(step, count).unwrap()
    if edge.role != @pipeline.Sample(0) {
      return Err(ForeignOccurrence(site.step))
    }
    Some(edge.target)
  } else {
    None
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  if selector_relation is Some(target) {
    let edge = @pipeline.input_occurrence_at(step, 1).unwrap()
    if edge.role != @pipeline.Right || edge.target != target {
      return Err(ForeignOccurrence(site.step))
    }
  }
  Ok(
    Some(
      TraversalExecution({
        site,
        step,
        input,
        selector_relation,
        target_selector_relation,
        operation,
        rule,
      }),
    ),
  )
}
