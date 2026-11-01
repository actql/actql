///|
/// Logical construction inventory of normalize_nfc_lf, including its returned
/// String and refusal path. The original input String is borrowed. These are
/// representation units, not byte prices, an allocator/RSS claim or a grant.
/// The pinned JS concat and non-JS UInt16-buffer recipes have the same bound;
/// their different backing overlaps are justified separately below.
pub(all) struct NormalizationConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  // A retained-output bound, not an additional scratch charge. This lets
  // callers inventory all returned keys without copying the Unicode rule.
  max_output_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Bound the existing Unicode 16 NFC constructor, followed by LF folding.
/// This is not the compatibility/casefold cursor's expansion inventory.
/// One original input is normalized at a time. A caller retaining multiple
/// returned Strings must also retain their cumulative text and references.
pub fn nfc_lf_construction_extent(
  max_input_utf16_units : Int,
) -> NormalizationConstructionExtent? {
  if max_input_utf16_units < 0 {
    return None
  }
  let u = max_input_utf16_units.to_int64()
  // The pinned canonical tables expand one input scalar to <=4 scalars, with
  // recursive expansion derived by the canonical generator (Hangul <=3).
  // Extraction <=U; decomposition and composition <=4U. Scalar-backed array
  // old/new growth is <=3N+12. Keep that complete growth bound even for each
  // preceding array which is no longer growing. order_canonically owns its
  // classes and one sorted run (each <=4U) plus 256 counting-sort offsets;
  // both arrays are private to that synchronous call and cannot escape it.
  // compose_nfc starts only after it returns. Thus ordering has at most
  // (3+5E)U scalar slots and composition (3+6E)U, not their sum. The latter
  // dominates for the same pinned positive expansion E. Every input,
  // decomposed and returned array remains charged through rendering; this
  // does not infer GC, refund a reservation or change the Unicode algorithm.
  // Conservatively keep all six wrappers/backings, three growth overlaps,
  // 12 wrapper words, three 12-slot minima and the sort table in both phases.
  let array_headers = 15L
  let array_refs = 6L
  let array_words = 12L +
    36L +
    (3L + 6L * canonical_decomposition_max_scalar_expansion) * u +
    256L
  // The generated table proves NFC output is <=4U UTF16 units. JS retains
  // old/new concat text (and the current character), then at most the two preceding LF-pass Strings.
  // For the pinned UInt16 builder, capacity doubling makes old+new backing
  // <=3*output (or buffer+to_string copy <=3*output). Growth and to_string
  // copy do not coexist: grow returns before to_string. The second LF pass
  // has <=2*output preceding text +3*output backing/output =5*output.
  // Its two fixed LF replacement Strings add2. Empty input's one-slot buffers also fit.
  // Builder, text and view records are charged separately from their slots.
  let text_headers = 10L
  let text_refs = 8L
  let text_words = 6L
  let text_units = 5L * nfc_lf_retained_output_units(u).unwrap() + 2L
  // Conservative sum of the named quickcheck/extract/decompose/order/compose/
  // render/LF control families, including tagged Result/transition carriers.
  // Fixed VM/allocator frames are backend baseline, not funded by this DATA.
  let control_headers = 75L
  let control_refs = 109L
  let control_words = 218L
  // An Int input keeps every product/addition representable as Int64. The
  // shared representation owner still performs checked byte conversion.
  Some({
    record_headers: array_headers + text_headers + control_headers,
    reference_slots: array_refs + text_refs + control_refs,
    scalar_words: array_words + text_words + control_words,
    owned_utf16_units: text_units,
    max_output_utf16_units: nfc_lf_retained_output_units(u).unwrap(),
  })
}

///|
/// Aggregate returned text uses the SAME canonical output expansion rule as a
/// single normalization. This is a bound on new returned backing, not a second
/// copy of the borrowed original input or physical allocation evidence.
pub fn nfc_lf_retained_output_units(input_utf16_units : Int64) -> Int64? {
  @counts.checked_nonnegative_add_product(
    0L, input_utf16_units, nfc_output_utf16_expansion,
  )
}

///|
let nfc_output_utf16_expansion : Int64 = canonical_decomposition_max_utf16_expansion

///|
/// A caller retaining this same returned output separately removes exactly
/// that output envelope from the constructor peak. All other intermediate
/// Strings, arrays and controls remain here. The output bound is still exposed
/// for correspondence; it is not additional scratch storage.
pub fn nfc_lf_construction_scratch_extent(
  max_input_utf16_units : Int,
) -> NormalizationConstructionExtent? {
  guard nfc_lf_construction_extent(max_input_utf16_units) is Some(value) else {
    return None
  }
  Some({
    ..value,
    record_headers: value.record_headers - 1L,
    owned_utf16_units: value.owned_utf16_units - value.max_output_utf16_units,
  })
}
