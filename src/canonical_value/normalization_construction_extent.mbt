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
  // decomposition recursion <=4 (Hangul <=3). Extraction <=U, decomposition
  // and composition <=4U. Scalar-backed array old/new growth is <=3N+12;
  // classes and one sorted run each <=4U, plus the 256 counting-sort offsets.
  // Six wrappers/backings and three growing backing overlaps:15H6R, with
  // 12 wrapper words and three 12-slot growth minima.
  let array_headers = 15L
  let array_refs = 6L
  let array_words = 12L + 36L + 35L * u + 256L
  // NFC output is <=8U UTF16 units. JS retains old/new concat text (and the
  // current character), then at most the two preceding LF-pass Strings.
  // For the pinned UInt16 builder, capacity doubling makes old+new backing
  // <=3*output (or buffer+to_string copy <=3*output). Growth and to_string
  // copy do not coexist: grow returns before to_string. The second LF pass
  // has at most 2*8U preceding text +3*8U backing/output =40U. Its two fixed
  // LF replacement Strings add2. Empty input's one-slot buffers also fit.
  // Builder, text and view records are charged separately from their slots.
  let text_headers = 10L
  let text_refs = 8L
  let text_words = 6L
  let text_units = 40L * u + 2L
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
    max_output_utf16_units: 8L * u,
  })
}
