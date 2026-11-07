///|
test "reference reader recipe composes existing Unicode scalar and collection owners" {
  let value = reference_read_construction_inventory(19).unwrap()
  assert_eq(value.retained, {
    record_headers: 4L,
    reference_slots: 3L,
    scalar_words: 0L,
  })
  // One complete ASCII reference has19UTF16 units, decoded names5 and output19.
  // This is a conservative returned envelope, not an actual allocation count.
  assert_eq(value.retained_utf16_units, 38L)
  assert_eq(value.scratch, {
    record_headers: 173L,
    reference_slots: 210L,
    // Sequential ordering/NFC peak: 591 + 27 * 19.
    scalar_words: 1104L,
  })
  // NFC text plus Reference/codec text: 30 * 19 + 44.
  assert_eq(value.scratch_utf16_units, 614L)
}

///|
test "reference reader recipe follows actual text and preserves checked wide quantities" {
  assert_true(reference_read_construction_inventory(-1) is None)
  let empty = reference_read_construction_inventory(0).unwrap()
  let one = reference_read_construction_inventory(1).unwrap()
  assert_eq(one.scratch.record_headers, empty.scratch.record_headers)
  assert_eq(one.scratch.reference_slots, empty.scratch.reference_slots)
  // NFC owns its exact growth; the Reference owner adds only its codec text.
  let nfc0 = @canonical.nfc_lf_construction_extent(0).unwrap()
  let nfc1 = @canonical.nfc_lf_construction_extent(1).unwrap()
  assert_eq(
    one.scratch.scalar_words - empty.scratch.scalar_words,
    nfc1.scalar_words - nfc0.scalar_words,
  )
  assert_eq(
    one.scratch_utf16_units - empty.scratch_utf16_units,
    nfc1.owned_utf16_units - nfc0.owned_utf16_units + 10L,
  )
  // Pure quantity arithmetic: no input String, normalization or sized buffer.
  let widest = reference_read_construction_inventory(2147483647).unwrap()
  assert_eq(widest.retained_utf16_units, 4294967294L)
  assert_eq(widest.scratch_utf16_units, 64424509454L)
}

///|
test "Reference inventory quotation has only fixed original constructor controls" {
  assert_eq(reference_read_inventory_quotation_extent(), {
    record_headers: 38L,
    reference_slots: 8L,
    scalar_words: 85L,
  })
}
