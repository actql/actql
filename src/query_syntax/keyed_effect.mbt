///|
// Operator words are structural at the existing Effect boundary, not a new
// globally reserved identifier set.
fn keyed_effect_word(token : Token) -> Bool {
  keyword(token, "UPDATE") ||
  keyword(token, "UPSERT") ||
  keyword(token, "DELETE")
}
