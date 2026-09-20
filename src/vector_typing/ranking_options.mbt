///|
pub type RankingPolicy = @evidence.RankingPolicy

///|
pub type ScoreContract = @evidence.ScoreContract

///|
pub type RankingOptions = @evidence.RankingOptions

///|
pub(all) enum RankingPolicyKind {
  MaximumPolicy
  WeightedSumPolicy
  ReciprocalRankPolicy
} derive(Eq, Debug)

///|
pub fn ranking_policy_kind(value : RankingOptions) -> RankingPolicyKind {
  match @evidence.ranking_policy(value) {
    @evidence.Maximum => MaximumPolicy
    @evidence.WeightedSum => WeightedSumPolicy
    @evidence.ReciprocalRank => ReciprocalRankPolicy
  }
}

///|
pub using @evidence {
  read_ranking_options,
  ranking_source,
  ranking_inputs,
  ranking_input_count,
  ranking_input_at,
  ranking_by,
  ranking_by_count,
  ranking_by_at,
  ranking_candidate,
  ranking_score,
  ranking_rank,
  ranking_policy,
  ranking_weights,
  ranking_weight_count,
  ranking_weight_at,
  ranking_rank_constant,
  ranking_rank_window,
  ranking_score_contract,
  ranking_tie_break,
  ranking_tie_break_count,
  ranking_tie_break_at,
  ranking_k,
  ranking_options_usage,
  score_contract_domain,
  score_contract_normalization,
  score_contract_minimum,
  score_contract_maximum,
}
