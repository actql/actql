///|
pub(all) enum GraphDiffRule {
  EmitVersion
  AdmitCommonSnapshots
  EmitContractIdentity
  BindSnapshotIdentities
  EmitCompleteRecords
  OrderUniqueActions
  RequireDeltaResources
} derive(Eq, Debug)

///|
pub(all) enum GraphDeltaResource {
  GraphNodes
  GraphEdges
  ActionRecords
  ValueAndTemporaryBytes
  Work
  RetainedState
} derive(Eq, Debug)

///|
/// The retained operation owns the checked common contract and its CID.
/// Snapshot identities remain runtime observations, not source identities.
pub struct GraphDiffCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  base : @pipeline.Target
  target : @pipeline.Target
  operation : @graph.CheckedDiff
  rule : GraphDiffRule
  policy : @policy.Policy
}

///|
pub fn graph_delta_resource_count(check : GraphDiffCheck) -> Int {
  if check.rule == RequireDeltaResources {
    6
  } else {
    0
  }
}

///|
pub fn graph_delta_resource_at(
  check : GraphDiffCheck,
  index : Int,
) -> GraphDeltaResource? {
  if check.rule != RequireDeltaResources {
    return None
  }
  graph_delta_resource(index)
}

///|
fn graph_delta_resource(index : Int) -> GraphDeltaResource? {
  match index {
    0 => Some(GraphNodes)
    1 => Some(GraphEdges)
    2 => Some(ActionRecords)
    3 => Some(ValueAndTemporaryBytes)
    4 => Some(Work)
    5 => Some(RetainedState)
    _ => None
  }
}

///|
fn graph_diff_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.DiffRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    EmitDeltaVersion => EmitVersion
    AdmitSnapshotsUnderCommonContract => AdmitCommonSnapshots
    EmitGraphContractIdentity => EmitContractIdentity
    BindBaseAndTargetIdentities => BindSnapshotIdentities
    EmitCompleteBeforeAfterRecords => EmitCompleteRecords
    SortUniqueActionIdentities => OrderUniqueActions
    ResolveDeltaResources => RequireDeltaResources
    ResolveSgaProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphDiff(right=target, checked=operation) &&
    step.input is Some(base) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.diff_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.role != @pipeline.Left ||
    l.target != base ||
    r.role != @pipeline.Right ||
    r.target != target {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      GraphDiffExecution({ site, step, base, target, operation, rule, policy, }),
    ),
  )
}
