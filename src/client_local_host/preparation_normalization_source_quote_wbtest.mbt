///|
fn source_normalization_quote_data() -> @checked.ParsedCheckDataEstimate {
  {
    collections: {
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    },
    utf16_units: 0L,
    inspection_work: 0L,
    semantic_work: 0L,
  }
}

///|
test "normalization original wrappers and Source path overlap have independent tariff increments" {
  let data = source_normalization_quote_data()
  let base = program_check_data_extent_cost(data).unwrap()
  // One common record/tag: 2H + 5R + 1W = 80 bytes.
  assert_eq(request_normalization_audit_extent_cost(data, 0L), Some(base + 80L))
  // Two Source frames plus one relation upper-bound slot: 20H/15R/17W,
  // and 700 UTF16 units of fixed path/intermediate spelling = 1976B.
  // The independent existing Writer owner supplies its separate constructor.
  let writer_cost = fn(bytes) {
    let writer = @encode.text_writer_construction_inventory(bytes, 1, 1).unwrap()
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    }).unwrap()
  }
  assert_eq(
    request_normalization_audit_extent_cost(data, 1L),
    Some(base + 1976L + writer_cost(2)),
  )
  let named = { ..data, utf16_units: 3L, }
  let base = program_check_data_extent_cost(named).unwrap()
  assert_eq(
    request_normalization_audit_extent_cost(named, 1L),
    Some(base + 2408L + writer_cost(20)),
  )
}

///|
test "normalization Source constructor quotation refuses negative and overflowing counts" {
  let data = source_normalization_quote_data()
  assert_true(request_normalization_audit_extent_cost(data, -1L) is None)
  assert_true(
    request_normalization_audit_extent_cost(data, 9223372036854775807L) is None,
  )
  assert_true(
    request_normalization_audit_extent_cost(
      { ..data, utf16_units: 9223372036854775807L, },
      1L,
    )
    is None,
  )
}
