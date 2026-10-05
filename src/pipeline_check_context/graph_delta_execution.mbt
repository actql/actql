///|
pub(all) enum GraphDeltaRule {
  AdmitGraphOperands
  RequireDeltaResources
  EnforceDeltaRows
  RequireExactlyOneDeltaRow
  AdmitCompleteDeltaActions
  CheckExactBaseBeforeTarget
} derive(Eq, Debug)

///|
/// A future runtime check, not a receipt that Graphs or ordinary JSON have
/// passed admission. Both operands retain their exact ordered use sites;
/// equal contents, CIDs, or targets do not make occurrences interchangeable.
pub struct GraphDeltaCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @graph.CheckedDelta
  rule : GraphDeltaRule
  policy : @policy.Policy
}

///|
fn graph_delta_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.DeltaRequirement(pending) else {
    return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphDelta(right~, checked=operation) &&
    @pipeline.operation_obligations_graph_delta(site.obligations) is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.delta_pending_at(operation, site.index) == Some(pending) &&
    step.input is Some(left) &&
    @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.input_occurrence_at(step, 0)
    is Some({ role: @pipeline.Left, target: l, }) &&
    l == left &&
    @pipeline.input_occurrence_at(step, 1)
    is Some({ role: @pipeline.Right, target: r, }) &&
    r == right else {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = match pending {
    @graph.AdmitDeltaGraphs => AdmitGraphOperands
    @graph.ResolveDeltaResources => RequireDeltaResources
    @graph.EnforceDeltaRelationRows => EnforceDeltaRows
    @graph.AdmitExactlyOneDeltaRow => RequireExactlyOneDeltaRow
    @graph.AdmitDeltaActions => AdmitCompleteDeltaActions
    @graph.VerifyDeltaBaseBeforeTarget => CheckExactBaseBeforeTarget
  }
  Ok(
    Some(
      GraphDeltaExecution({ site, step, left, right, operation, rule, policy, }),
    ),
  )
}
