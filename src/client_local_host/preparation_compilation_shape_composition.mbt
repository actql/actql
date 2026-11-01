///|
/// Componentwise maximum is a conservative envelope of mutually exclusive
/// synchronous constructor scratch phases. Retained child values are composed
/// separately; this function is not permission to drop a live owner's holding.
fn compilation_scratch_max(
  a : @execution.PreparationRepresentationUnits,
  b : @execution.PreparationRepresentationUnits,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
    owned_utf16_units: Int64::max(a.owned_utf16_units, b.owned_utf16_units),
    owned_wire_bytes: Int64::max(a.owned_wire_bytes, b.owned_wire_bytes),
  }
}
