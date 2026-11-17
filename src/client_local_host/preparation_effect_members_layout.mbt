///|
// The checked Effect inventory is already retained. Fund only its Host
// selectors, descriptor/member wrappers, routing and Plan demand vectors before
// the original Effect construction borrow exposes that inventory to Node.
// Names/contracts/recipes are borrowed from their existing owners, not copied.
fn installed_effect_member_selection_layout(members : Int) -> (Int64, Int64)? {
  if members < 0 {
    return None
  }
  let n = members.to_int64()
  guard @execution.compose_preparation_representation([
      {
        // Unit/selector/member/owner route and demand carriers. The original
        // descriptor has seven fields; retained member/route views have at
        // most eight. Each method pair has its original context reference.
        record_headers: 6L + 9L * n,
        reference_slots: 12L + 43L * n,
        scalar_words: 4L + 8L * n,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(8L, 8L * n, false),
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      {
        // One descriptor lookup, sort/uniqueness iterators and one demand
        // constructor frame coexist with the retained selection. No rows or
        // physical operations are funded by this definition count.
        record_headers: 12L,
        reference_slots: 39L,
        scalar_words: 12L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(4L, 4L * n, false),
    ])
    is Some(scratch) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(scratch) is Some(s) &&
    @execution.checked_preparation_add_product(r, s, 1L) is Some(e) else {
    return None
  }
  Some((r, e))
}
