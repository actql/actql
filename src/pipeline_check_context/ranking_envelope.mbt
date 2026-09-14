///|
/// Bounds on successful finite outputs, not a new input score declaration.
pub struct RankingScoreEnvelope {
  requirement_index : Int
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @vector.CheckedRanking
  minimum : Double
  maximum : Double
}

///|
// Saturation applies only to conservative bounds. Evaluation still rejects
// every non-finite intermediate and never substitutes a saturated score.
fn finite_ranking_bound(value : Double) -> Double {
  let largest = 1.7976931348623157e308
  if value > largest {
    largest
  } else if value < -largest {
    -largest
  } else if value == 0 {
    0.0
  } else {
    value
  }
}

///|
fn ranking_score_bounds(
  options : @vector.RankingOptions,
  max_work : Int,
) -> Result[((Double, Double), Int), OperationResolutionIndexIssue] {
  if max_work < 1 {
    return Err(BudgetExceeded)
  }
  match @vector.ranking_policy(options) {
    Maximum => {
      let contract = @vector.ranking_score_contract(options).unwrap()
      Ok(
        (
          (
            finite_ranking_bound(contract.minimum),
            finite_ranking_bound(contract.maximum),
          ),
          1,
        ),
      )
    }
    WeightedSum => {
      let contract = @vector.ranking_score_contract(options).unwrap()
      let left = @vector.ranking_weight_at(options, 0).unwrap()
      let right = @vector.ranking_weight_at(options, 1).unwrap()
      let low_left = left * contract.minimum
      let low_right = right * contract.minimum
      let high_left = left * contract.maximum
      let high_right = right * contract.maximum
      // Present on the left, right, or both. Each product and sum uses the
      // same binary64 rounding as score evaluation; absence contributes +0.
      let low = low_left.min(low_right).min(low_left + low_right)
      let high = high_left.max(high_right).max(high_left + high_right)
      Ok(((finite_ranking_bound(low), finite_ranking_bound(high)), 1))
    }
    ReciprocalRank => {
      let count = @vector.ranking_weight_count(options)
      if count > max_work - 1 {
        return Err(BudgetExceeded)
      }
      let denominator = @vector.ranking_rank_constant(options).unwrap() + 1.0
      let mut upper = 0.0
      for i in 0..<count {
        let contribution = @vector.ranking_weight_at(options, i).unwrap() /
          denominator
        upper = finite_ranking_bound(upper + contribution)
      }
      // A candidate can participate only in zero-weight occurrences. Empty
      // output is also compatible; no positive lower score is inferred.
      Ok(((0.0, upper), count + 1))
    }
  }
}

///|
fn ranking_score_envelope(
  site : OperationRequirementSite,
  requirement_index : Int,
  max_work : Int,
) -> Result[(RankingScoreEnvelope?, Int), OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.RankingRequirement(DeriveOutputScoreEnvelope) else {
    return Ok((None, 0))
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Ranking(operation) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.merged_ranking_pending_at(operation, site.index) ==
    Some(DeriveOutputScoreEnvelope) else {
    return Err(ForeignOccurrence(site.step))
  }
  match
    ranking_score_bounds(@vector.merged_ranking_options(operation), max_work) {
    Err(e) => Err(e)
    Ok(((minimum, maximum), work)) =>
      Ok(
        (
          Some({ requirement_index, site, step, operation, minimum, maximum, }),
          work,
        ),
      )
  }
}
