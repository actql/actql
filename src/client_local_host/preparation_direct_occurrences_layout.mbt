///|
/// Add only this selector's Plan field, retained original/check/coordinate
/// containers and simultaneous construction workspace. The same original
/// graph, requests and query operations are borrowed, never copied.
fn installed_direct_occurrences_layout(captures : Int) -> (Int64, Int64)? {
  if captures < 0 {
    return None
  }
  if captures == 0 {
    guard @execution.preparation_representation_cost({
        record_headers: 0L,
        reference_slots: 1L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(field) else {
      return None
    }
    return Some((field, field))
  }
  let n = captures.to_int64()
  guard @execution.compose_preparation_representation([
      // Owner enum, inventory, Plan Some, each coordinate triple; Plan field.
      {
        record_headers: 3L + n,
        reference_slots: 6L,
        scalar_words: 2L + 3L * n,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(2L, 2L * n, false),
    ])
    is Some(retained) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      // Slot Some/pair for each retained check/coordinate, budget Ref, active
      // Result/Option and query-shape selection carriers. QueryAcquisition's
      // six borrowed references/five scalars and terminal target are included.
      {
        // The private route result also carries Whole/Query DATA until its
        // checked task triple is retained; only one such carrier is live.
        record_headers: 19L + 2L * n,
        reference_slots: 28L + 3L * n,
        scalar_words: 36L + n,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(1L, n, false),
      // Difference between the same two output arrays' pinned append overlap
      // (3 headers, 12+3n slots) and retained bound (2 headers, 8+2n slots).
      {
        record_headers: 2L,
        reference_slots: 8L + 2L * n,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      // Shape's filter/select temporary and Effect's private traversal view
      // with its two empty arrays. No Effect owner is replaced or exposed.
      closed_values_program_arrays(3L, 2L, false),
      // Private view (1H/8R/1W) and its standard sequence/expression limits
      // (2H/1R/10W), used only to read the existing default scalar limit.
      {
        record_headers: 3L,
        reference_slots: 9L,
        scalar_words: 11L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(scratch) &&
    @execution.preparation_representation_cost(retained) is Some(retained_bytes) &&
    @execution.preparation_representation_cost(scratch) is Some(scratch_bytes) &&
    @execution.checked_preparation_add_product(
      retained_bytes, scratch_bytes, 1L,
    )
    is Some(total) else {
    return None
  }
  Some((retained_bytes, total))
}
