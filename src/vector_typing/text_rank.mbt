///|
pub type Tokenizer = @evidence.Tokenizer

///|
pub type TextRankSide = @evidence.TextRankSide

///|
pub type TextRankRoles = @evidence.TextRankRoles

///|
pub type TextRankOptions = @evidence.TextRankOptions

///|
pub type TextRankObligation = @evidence.TextRankObligation

///|
pub type CheckedTextRank = @evidence.CheckedTextRank

///|
pub using @evidence {
  read_text_rank_options,
  check_text_rank,
  check_text_rank_inputs,
  text_rank_source,
  text_rank_queries,
  text_rank_roles,
  text_rank_tokenizer,
  text_rank_bm25,
  text_rank_k,
  text_rank_options_usage,
  text_rank_options,
  text_rank_output,
  text_rank_input,
  text_rank_usage,
  text_rank_profile,
  text_rank_pending,
  text_rank_pending_count,
  text_rank_pending_at,
}
