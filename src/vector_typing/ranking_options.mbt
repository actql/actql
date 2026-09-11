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
  ranking_by,
  ranking_by_count,
  ranking_candidate,
  ranking_score,
  ranking_rank,
  ranking_policy,
  ranking_weights,
  ranking_rank_constant,
  ranking_rank_window,
  ranking_score_contract,
  ranking_tie_break,
  ranking_k,
  ranking_options_usage,
}
