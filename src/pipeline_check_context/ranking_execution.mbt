///|
pub(all) enum RankingRule {
  AdmitCompleteRankings
  ValidateRankingUniqueness
  ValidateContiguousInputRanks
  AuthenticateRankingScores
  AdmitRankingScoreRanges
  ValidateRankingTieAgreement
  ApplyRankingWindow
  EvaluateRankingScores
  OrderFusedRankings
  AssignFusedRanks
} derive(Eq, Debug)

///|
pub struct RankingCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @vector.CheckedRanking
  rule : RankingRule
  policy : @policy.Policy
}

///|
pub fn ranking_execution_input_count(check : RankingCheck) -> Int {
  @vector.merged_ranking_input_count(check.operation)
}

///|
/// Current first, then authored with occurrences. The checked pipeline owns
/// Sample(index) edges, including repetitions; input shape retains its evidence.
pub fn ranking_execution_input_at(
  check : RankingCheck,
  index : Int,
) -> (@pipeline.InputOccurrence, @vector.RankingShape)? {
  guard @pipeline.input_occurrence_at(check.step, index) is Some(edge) &&
    @vector.merged_ranking_input_at(check.operation, index) is Some(shape) else {
    return None
  }
  Some((edge, shape))
}

///|
fn ranking_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RankingRequirement(pending) else {
    return Ok(None)
  }
  let rule : RankingRule = match pending {
    ValidateCompleteRankingInputs => AdmitCompleteRankings
    ValidateUniqueQueryCandidatePerInput => ValidateRankingUniqueness
    ValidatePositiveSafeContiguousRanks => ValidateContiguousInputRanks
    AuthenticateCapturedScoreDeclarations => AuthenticateRankingScores
    ValidateDeclaredScoreRanges => AdmitRankingScoreRanges
    ValidateBusinessTieAgreement => ValidateRankingTieAgreement
    ApplyRankWindowAfterAdmission => ApplyRankingWindow
    EvaluateRankingPolicyWithFiniteIntermediates => EvaluateRankingScores
    OrderRankingByScoreAndSemanticIdentity => OrderFusedRankings
    AssignFusedContiguousRanks => AssignFusedRanks
    ResolveRankingResources
    | ResolveRankingProfile
    | DeriveOutputScoreEnvelope => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Ranking(operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.merged_ranking_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    @vector.merged_ranking_input_count(operation) &&
    @pipeline.input_occurrence_at(step, 0) is Some(first) &&
    first.role == @pipeline.Sample(0) &&
    first.target == input else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(RankingExecution({ site, step, operation, rule, policy, })))
}
