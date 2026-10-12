///|
// A completed comparison's exact two borrows, not another Resource Owner,
// Store/journal authenticator, restoration token or send permission. The
// original installation funds this record, the final-step frame overlap and
// the document/tree/park lifetime BEFORE entering the matched advance API.
struct OriginalCurrentStateMatch[T] {
  mut park : OriginalResourcePark[T]?
  mut document : OriginalCurrentStateDocument?
}

///|
pub enum OriginalCurrentStateMatchPoll[T] {
  CurrentMatchContinue(work~ : Int)
  CurrentMatchComplete(OriginalCurrentStateMatch[T], work~ : Int)
  CurrentMatchFailed(OriginalStateComparisonIssue, work~ : Int)
}

///|
// The old advance still retires its cursor on Complete. Only this actual
// synchronous comparison, never a caller Bool/JSON/poll, issues a matched
// borrow. It allocates nothing on the ordinary comparison entry.
pub fn[T] advance_original_current_state_comparison_with_match(
  value : OriginalCurrentStateComparison[T],
  quantum : Int,
) -> OriginalCurrentStateMatchPoll[T] {
  let park = value.park
  let document = value.document
  match advance_original_current_state_comparison(value, quantum) {
    ComparisonContinue(work~) => CurrentMatchContinue(work~)
    ComparisonFailed(issue, work~) => CurrentMatchFailed(issue, work~)
    ComparisonComplete(work~) =>
      // No callback/await occurs between the last actual census/fence check
      // and this private constructor. The same cursor has now retired itself.
      CurrentMatchComplete({ park, document, }, work~)
  }
}

///|
// A synchronous read-only currentness guard on the same original restriction.
// Matching data is not proof that the Store saved it or the journal committed
// it, nor does this inspection unpark or mutate any resource/quantity usage.
pub fn[T] original_current_state_match_current(
  value : OriginalCurrentStateMatch[T],
  park : OriginalResourcePark[T],
  origin : T,
) -> OriginalCurrentStateMatch[T]? {
  guard value.park is Some(original) &&
    physical_equal(original, park) &&
    value.document is Some(document) &&
    document.source is Some(_) &&
    original_resource_park_current(park, origin) is Some(_) else {
    return None
  }
  Some(value)
}

///|
// Retire only the two borrowed references. This does not retire a shared
// document or unpark/settle its original Owner, and requires no new Infer Allow.
pub fn[T] retire_original_current_state_match(
  value : OriginalCurrentStateMatch[T],
) -> Unit {
  value.park = None
  value.document = None
}
