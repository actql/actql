///|
pub(all) enum ReachRule {
  AdmitInputGraph
  RequireStartMembership
  EmitBoundedMinimumDepth
  OrderReachRows
} derive(Eq, Debug)

///|
/// Runtime checks of the retained reach operation, not evidence of execution.
/// Static expansion, selected capacities and profile admission are separate.
pub struct ReachCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedReach
  rule : ReachRule
}

///|
fn reach_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ReachRequirement(pending) else {
    return Ok(None)
  }
  let rule : ReachRule = match pending {
    AdmitReachGraph => AdmitInputGraph
    RequireReachStartMembership => RequireStartMembership
    BoundedMinimumDepthTraversal => EmitBoundedMinimumDepth
    CanonicalReachOrder => OrderReachRows
    JournalReachExpansion | ResolveReachResources | ResolveReachProfile =>
      return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Reach(operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.reach_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    (if @graph.reach_start(operation) is @graph.SelectedReachStarts(selector) &&
      @graph.selector_form(selector) is @graph.RelationIds(..) {
      2
    } else {
      1
    }) else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.input_occurrence_count(step) == 2 {
    let selector = @pipeline.input_occurrence_at(step, 1).unwrap()
    if selector.role != @pipeline.Right {
      return Err(ForeignOccurrence(site.step))
    }
  }
  Ok(Some(ReachExecution({ site, step, input, operation, rule, })))
}
