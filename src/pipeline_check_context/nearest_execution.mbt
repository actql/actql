///|
pub struct NearestCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  candidates : @pipeline.Target
  queries : @pipeline.Target
  operation : @vector.CheckedNearest
  rule : @vector.NearestObligation
  policy : @policy.Policy
  host_output_rows : @policy.Ceiling?
}

///|
pub(all) enum NearestResource {
  InputAdmissionWork
  PairScoringWork
  RankingWork
  ValueAndTemporaryBytes
  RetainedSearchState
} derive(Eq, Debug)

///|
pub fn nearest_resource_count(check : NearestCheck) -> Int {
  if check.rule is ResolveNearestResources {
    5
  } else {
    0
  }
}

///|
pub fn nearest_resource_at(
  check : NearestCheck,
  index : Int,
) -> NearestResource? {
  guard check.rule is ResolveNearestResources else { return None }
  match index {
    0 => Some(InputAdmissionWork)
    1 => Some(PairScoringWork)
    2 => Some(RankingWork)
    3 => Some(ValueAndTemporaryBytes)
    4 => Some(RetainedSearchState)
    _ => None
  }
}

///|
fn nearest_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.NearestRequirement(rule) else {
    return Ok(None)
  }
  match rule {
    ValidateNearestRoleBindings(_)
    | MatchNearestDimensions
    | AdmitQuantizedVectorComponents
    | ValidateBothUniqueIdentities
    | EvaluateExactNearestScores
    | RestoreSemanticIdentityValues
    | OrderQueriesByIdentity
    | OrderCandidatesByDescendingScoreThenIdentity
    | AssignContiguousOneBasedRanks
    | JournalVectorFieldCompletion(_, _)
    | JournalIdentityFieldCompletion(_, _)
    | ValidateNearestKey(_, _)
    | PreserveSimilarityAuthorityBoundary
    | ResolveNearestResources => ()
    ResolveNearestProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Nearest(queries~, checked=operation) &&
    step.input is Some(candidates) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.nearest_pending_at(operation, site.index) == Some(rule) &&
    @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.input_occurrence_at(step, 0) is Some(left) &&
    @pipeline.input_occurrence_at(step, 1) is Some(right) &&
    left.role == @pipeline.Left &&
    left.target == candidates &&
    right.role == @pipeline.Right &&
    right.target == queries else {
    return Err(ForeignOccurrence(site.step))
  }
  let host_output_rows = if rule is ResolveNearestResources {
    guard @policy.ceiling(policy, "max_relation_output_rows") is Some(limit) else {
      return Ok(None)
    }
    Some(limit)
  } else {
    None
  }
  Ok(
    Some(
      NearestExecution({
        site,
        step,
        candidates,
        queries,
        operation,
        rule,
        policy,
        host_output_rows,
      }),
    ),
  )
}
