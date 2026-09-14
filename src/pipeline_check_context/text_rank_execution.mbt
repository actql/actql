///|
pub struct TextRankCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  corpus : @pipeline.Target
  queries : @pipeline.Target
  operation : @vector.CheckedTextRank
  selection : OperationLexicalResolution
  rule : @vector.TextRankObligation
  policy : @policy.Policy
}

///|
fn text_rank_execution_check(
  site : OperationRequirementSite,
  selection : OperationLexicalResolution?,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.TextRankRequirement(rule) else {
    return Ok(None)
  }
  match rule {
    ValidateCompleteTextInputs
    | ValidateGlobalStringIdentities(_)
    | NormalizeAndTokenizeWithPinnedUnicode
    | ComputeStatisticsFromAdmittedCorpusOnly
    | EvaluatePinnedBm25AndCorrectlyRoundedLogarithm
    | FoldTermsInCanonicalOrder
    | RejectNonFiniteTextScores
    | ExcludeZeroScoresAndHandleEmptyInputs
    | OrderTextScoresAndSemanticIdentities
    | AssignContiguousTextRanks => ()
    ResolveTokenizerAndNormalizedTextCeilings
    | ResolveTextRankProfile
    | ResolveStatisticsScoringAndOutputResources => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.TextRank(queries~, checked=operation) &&
    step.input is Some(corpus) &&
    site.group == 0 &&
    selection is Some(selection) &&
    selection.stage == site.stage &&
    selection.producer_visit == site.producer_visit &&
    selection.step == site.step &&
    physical_equal(selection.operation, operation) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.text_rank_pending_at(operation, site.index) == Some(rule) &&
    @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.input_occurrence_at(step, 0) is Some(left) &&
    @pipeline.input_occurrence_at(step, 1) is Some(right) &&
    left.role == @pipeline.Left &&
    left.target == corpus &&
    right.role == @pipeline.Right &&
    right.target == queries else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      TextRankExecution({
        site,
        step,
        corpus,
        queries,
        operation,
        selection,
        rule,
        policy,
      }),
    ),
  )
}
