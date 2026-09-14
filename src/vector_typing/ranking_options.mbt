///|
pub type RankingPolicy = @evidence.RankingPolicy

///|
pub type ScoreContract = @evidence.ScoreContract

///|
pub type RankingOptions = @evidence.RankingOptions

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
}
