///|
test "NFC construction rejects negative extents and preserves finite Int bounds" {
  assert_true(nfc_lf_construction_extent(-1) is None)
  let empty = nfc_lf_construction_extent(0).unwrap()
  assert_eq(empty.record_headers, 100L)
  assert_eq(empty.reference_slots, 123L)
  assert_eq(empty.scalar_words, 528L)
  assert_eq(empty.owned_utf16_units, 2L)
  assert_eq(empty.max_output_utf16_units, 0L)
  let largest = nfc_lf_construction_extent(2147483647).unwrap()
  assert_eq(largest.scalar_words, 75161928173L)
  assert_eq(largest.owned_utf16_units, 42949672942L)
  assert_eq(largest.max_output_utf16_units, 8589934588L)
}

///|
test "NFC constructor arrays and text fit the named construction inventory" {
  // Recursive decomposition, reordered leading marks, Hangul, supplementary
  // text, QC=Maybe, and both LF passes exercise distinct original branches.
  for
    text in [
      "", "abc", "\u{1F82}", "\u{0315}\u{0300}a", "\u{AC01}", "𝄞e\u{0301}\r\n\r",
      "é\u{0301}",
    ] {
    let units = text.length().to_int64()
    let quote = nfc_lf_construction_extent(text.length()).unwrap()
    let scalars = scalar_values(text).unwrap()
    let decomposed : Array[Int] = []
    for scalar in scalars {
      append_canonical_decomposition(scalar, decomposed)
    }
    assert_true(scalars.length().to_int64() <= units)
    assert_true(decomposed.length().to_int64() <= 4L * units)
    order_canonically(decomposed)
    let composed = compose_nfc(decomposed)
    assert_true(composed.length().to_int64() <= 4L * units)
    let result = normalize_nfc_lf(text).unwrap()
    assert_true(result.length().to_int64() <= quote.max_output_utf16_units)
    // Returned output alone is not the construction peak. All scalar slots,
    // the fixed sort table, and old/new text must remain separately covered.
    let live_slots = scalars.capacity().to_int64() +
      decomposed.capacity().to_int64() +
      composed.capacity().to_int64()
    assert_true(quote.scalar_words >= live_slots + 256L)
    assert_true(quote.owned_utf16_units >= result.length().to_int64())
  }
  assert_eq(normalize_nfc_lf("e\u{0301}\r\n\r").unwrap(), "é\n\n")
}

///|
test "NFC output quotation follows pinned recursive UTF16 geometry without doubling each scalar" {
  assert_eq(nfc_lf_retained_output_units(64L), Some(256L))
  let profile = nfc_lf_construction_extent(64).unwrap()
  assert_eq(profile.max_output_utf16_units, 256L)
  // Same five named output/builder/LF overlaps and fixed empty buffers.
  assert_eq(profile.owned_utf16_units, 5L * 256L + 2L)
}
