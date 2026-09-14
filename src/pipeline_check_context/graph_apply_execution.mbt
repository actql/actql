///|
pub(all) enum GraphApplyRule {
  RequireSingleDeltaRow
  AdmitDeltaShapeAndVersion
  MatchGraphContract
  AdmitBaseGraph
  MatchBaseIdentity
  ValidateUniqueOrderedActions
  MatchBeforeRecords
  CheckActionExistence
  ApplyChangesAtomically
  AdmitResultGraph
  MatchTargetIdentity
  PreservePolicyDependencies
  RequireApplicationResources
} derive(Eq, Debug)

///|
pub struct GraphApplyCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  base : @pipeline.Target
  delta : @pipeline.Target
  operation : @graph.CheckedApply
  rule : GraphApplyRule
  policy : @policy.Policy
}

///|
pub fn graph_apply_resource_count(check : GraphApplyCheck) -> Int {
  if check.rule == RequireApplicationResources {
    6
  } else {
    0
  }
}

///|
pub fn graph_apply_resource_at(
  check : GraphApplyCheck,
  index : Int,
) -> GraphDeltaResource? {
  if check.rule != RequireApplicationResources {
    return None
  }
  graph_delta_resource(index)
}

///|
fn graph_apply_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ApplyRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    RequireExactlyOneDeltaRow => RequireSingleDeltaRow
    ValidateDeltaVersionAndClosedShape => AdmitDeltaShapeAndVersion
    MatchPinnedGraphContract => MatchGraphContract
    AdmitBaseUnderPinnedContract => AdmitBaseGraph
    MatchExactBaseIdentity => MatchBaseIdentity
    ValidateOrderedUniqueActions => ValidateUniqueOrderedActions
    ValidateExactBeforeRecords => MatchBeforeRecords
    ValidateAddRemoveUpdateExistence => CheckActionExistence
    ApplyNodeAndEdgeChangesTogether => ApplyChangesAtomically
    ValidateResultEndpointsAndContract => AdmitResultGraph
    MatchExactTargetIdentity => MatchTargetIdentity
    PreserveGraphPolicyDependencies => PreservePolicyDependencies
    ResolveApplyResources => RequireApplicationResources
    ResolveSgaProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphApply(right=delta, checked=operation) &&
    step.input is Some(base) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.apply_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.role != @pipeline.Left ||
    l.target != base ||
    r.role != @pipeline.Right ||
    r.target != delta {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      GraphApplyExecution({ site, step, base, delta, operation, rule, policy, }),
    ),
  )
}
