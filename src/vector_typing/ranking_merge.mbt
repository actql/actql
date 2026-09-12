///|
pub type RankingObligation = @evidence.RankingObligation

///|
pub type CheckedRanking = @evidence.CheckedRanking

///|
pub using @evidence {
  check_merge_rankings,
  check_ranking_fusion,
  merged_ranking_output,
  merged_ranking_options,
  merged_ranking_input_count,
  merged_ranking_input_at,
  merged_ranking_usage,
  merged_ranking_pending,
  merged_ranking_pending_count,
  merged_ranking_pending_at,
}
