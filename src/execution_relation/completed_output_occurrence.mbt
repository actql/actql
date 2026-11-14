///|
/// Immutable occurrence DATA only. It contains no rows, use, availability
/// callback or resource custody and does not establish currentness or authority.
struct CompletedOutputOccurrence {
  identity : Ref[Unit]
  target : @pipeline.Target
}

///|
/// Snapshot only immutable fields of the exact completed producer. Callers
/// must retain their own actual input/completion and currentness duties.
pub fn completed_output_original_occurrence(
  output : CompletedOutput,
) -> CompletedOutputOccurrence {
  { identity: output.completion.result_identity, target: output.target, }
}

///|
/// Borrow the original occurrence sealed by the complete ordered conversion.
/// The calling completion owner separately validates the live managed output.
pub fn[T] managed_completed_output_original_occurrence(
  output : ManagedCompletedOutput[T],
) -> CompletedOutputOccurrence? {
  output.material.receipt.completed_projection.map(tuple => {
    let (identity, target) = tuple
    { identity, target, }
  })
}

///|
/// Identity-only comparison, never an availability or authorization check.
pub fn completed_output_occurrence_matches_original(
  occurrence : CompletedOutputOccurrence,
  original : CompletedOutput,
) -> Bool {
  physical_equal(occurrence.identity, original.completion.result_identity) &&
  occurrence.target == original.target
}
