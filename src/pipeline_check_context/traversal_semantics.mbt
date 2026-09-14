///|
pub(all) enum TraversalRule {
  AdmitInputGraph
  RespectAuthoredHops
  EvaluateHopConditions
  EmitMinimumDepth
  EnumerateSimplePaths
  DeduplicatePathIdentities
  OrderTraversalRows
} derive(Eq, Debug)

///|
/// Future semantic checks retain the original operation and both input roles.
/// Start membership, selected capacities and bound guards are separate checks.
pub struct TraversalCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  selector_relation : @pipeline.Target?
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
    EvaluateTraversalHopPredicates => EvaluateHopConditions
    EmitMinimumNodeDepth => EmitMinimumDepth
    EnumerateSimplePaths => EnumerateSimplePaths
    DeduplicateExactPaths => DeduplicatePathIdentities
    CanonicalTraversalOrder => OrderTraversalRows
    ResolveTraversalResources
    | ResolveTraversalProfile
    | EnforceTraversalOutputGuard
    | BindTraversalOutputGuard(_) => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation
    is @pipeline.Traverse(selector=selector_relation, checked=operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.traverse_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    (if selector_relation is Some(_) { 2 } else { 1 }) else {
    return Err(ForeignOccurrence(site.step))
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
        operation,
        rule,
      }),
    ),
  )
}
