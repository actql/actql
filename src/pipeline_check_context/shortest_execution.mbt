///|
pub(all) enum ShortestRule {
  AdmitShortestInput
  RequireEndpoints
  ValidateAllWeights
  FoldCostsWithOverrange
  RejectSelectedOverrange
  SelectSimpleBoundedPaths
  ApplyPathTieBreaks
  OrderOutputRows
} derive(Eq, Debug)

///|
/// Retained semantic obligations, not a shortest-path implementation or receipt.
/// Endpoint selector checks and selected capacity remain separate requirements.
pub struct ShortestCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  source_relation : @pipeline.Target?
  target_relation : @pipeline.Target?
  operation : @graph.CheckedShortest
  rule : ShortestRule
}

///|
fn shortest_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ShortestRequirement(pending) else {
    return Ok(None)
  }
  let rule : ShortestRule = match pending {
    AdmitShortestGraph => AdmitShortestInput
    RequireEndpointMembership => RequireEndpoints
    ValidateAllNonnegativeFiniteWeights => ValidateAllWeights
    FoldPathCostsWithOverrange => FoldCostsWithOverrange
    RejectSelectedOverrangeAtomically => RejectSelectedOverrange
    SelectSimpleHopBoundedPaths => SelectSimpleBoundedPaths
    ApplyCanonicalPathTieBreaks => ApplyPathTieBreaks
    CanonicalShortestOutputOrder => OrderOutputRows
    ResolveShortestResources
    | ResolveShortestProfile
    | EnforceShortestOutputGuard
    | BindShortestOutputGuard(_) => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation
    is @pipeline.Shortest(
      source_selector=source_relation,
      target_selector=target_relation,
      checked=operation
    ) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.shortest_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    1 +
    (if source_relation is Some(_) { 1 } else { 0 }) +
    (if target_relation is Some(_) { 1 } else { 0 }) else {
    return Err(ForeignOccurrence(site.step))
  }
  let primary = @pipeline.input_occurrence_at(step, 0).unwrap()
  if primary.role != @pipeline.Primary || primary.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  let mut index = 1
  for
    (target, role) in [
      (source_relation, @pipeline.Left),
      (target_relation, @pipeline.Right),
    ] {
    if target is Some(target) {
      let edge = @pipeline.input_occurrence_at(step, index).unwrap()
      if edge.role != role || edge.target != target {
        return Err(ForeignOccurrence(site.step))
      }
      index += 1
    }
  }
  Ok(
    Some(
      ShortestExecution({
        site,
        step,
        input,
        source_relation,
        target_relation,
        operation,
        rule,
      }),
    ),
  )
}
