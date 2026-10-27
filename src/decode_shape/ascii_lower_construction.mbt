///|
/// Pinned builtin ASCII-only to_lower constructor, not Unicode case folding.
/// Input backing is borrowed. The output has the SAME UTF-16 extent; targets
/// without an uppercase ASCII letter can return the original String instead.
pub(all) struct AsciiLowerConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  max_output_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn ascii_lower_construction_extent(
  input_utf16_units : Int,
) -> AsciiLowerConstructionExtent? {
  if input_utf16_units < 0 {
    return None
  }
  let u = input_utf16_units.to_int64()
  // Original builder1/1/1, head/tail views2/2/4, iterator/closure4/4/4,
  // optional/scalar outcomes3/2/2, old/new/current Strings3/0/0 and the
  // non-JS fixed backing1/1/1. These alternatives are conservatively co-counted.
  // JS concat keeps <=2U +one current scalar<=2; fixed-copy targets need <=2U.
  // 3U+2 covers both without assigning a byte tariff or invoking either path.
  Some({
    record_headers: 14L,
    reference_slots: 10L,
    scalar_words: 12L,
    owned_utf16_units: 3L * u + 2L,
    max_output_utf16_units: u,
  })
}
