///|
pub(all) enum PoolResource {
  InputAndGroupingWork
  FoldWork
  MemberOrderingWork
  ValueAndTemporaryBytes
  RetainedPoolState
} derive(Eq, Debug)

///|
pub struct PoolCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @vector.CheckedPool
  rule : @vector.PoolObligation
  policy : @policy.Policy
}

///|
pub fn pool_resource_count(check : PoolCheck) -> Int {
  if check.rule is ResolvePoolResources {
    5
  } else {
    0
  }
}

///|
pub fn pool_resource_at(check : PoolCheck, index : Int) -> PoolResource? {
  guard check.rule is ResolvePoolResources else { return None }
  match index {
    0 => Some(InputAndGroupingWork)
    1 => Some(FoldWork)
    2 => Some(MemberOrderingWork)
    3 => Some(ValueAndTemporaryBytes)
    4 => Some(RetainedPoolState)
    _ => None
  }
}

///|
fn pool_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.PoolRequirement(rule) else {
    return Ok(None)
  }
  match rule {
    ValidateDeclaredPoolKey(_)
    | JournalPoolMemberIdentity
    | EncodePoolMemberKeyByScalarLengths
    | OrderPoolMembersByEncodedIdentity
    | AdmitPoolVectorComponents
    | ValidatePoolMemberIdentityGlobally
    | MatchPoolDimensions
    | OrderPoolMembersByIdentity
    | QuantizeBeforeAndAfterPoolFold
    | EvaluateDeterministicPoolFold
    | OrderPoolGroupsByIdentity
    | ValidatePositiveSafeMemberCounts
    | ResolvePoolResources => ()
    ResolvePoolProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Pool(operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.pool_pending_at(operation, site.index) == Some(rule) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0) is Some(edge) &&
    edge.role == @pipeline.Primary &&
    edge.target == input else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(PoolExecution({ site, step, input, operation, rule, policy, })))
}
