///|
test "scalar snapshot retains decoded keys and canonical rows across source retirement" {
  let a = scalar_snapshot_layout(1, 2, 100000).unwrap()
  let b = scalar_snapshot_layout(2, 4, 100000).unwrap()
  assert_true(a.retained.owned_utf16_units == 200000L)
  assert_true(b.retained.owned_utf16_units == 400000L)
  assert_true(
    @execution.preparation_representation_cost(b.retained).unwrap() >
    @execution.preparation_representation_cost(a.retained).unwrap(),
  )
  assert_true(
    @execution.preparation_representation_cost(a.temporary).unwrap() > 0L,
  )
  println(
    "snapshot100k R=\{@execution.preparation_representation_cost(a.retained).unwrap()} E=\{@execution.preparation_representation_cost(a.temporary).unwrap()}",
  )
}

///|
test "scalar snapshot empty rows Unicode-name scratch and overflow are bounded" {
  let empty = scalar_snapshot_layout(1, 9, 0).unwrap()
  assert_eq(empty.retained.owned_utf16_units, 0L)
  let a = scalar_snapshot_name_normalization_layout(3).unwrap()
  let b = scalar_snapshot_name_normalization_layout(9).unwrap()
  assert_true(
    @execution.preparation_representation_cost(b).unwrap() >
    @execution.preparation_representation_cost(a).unwrap(),
  )
  assert_true(scalar_snapshot_layout(-1, 0, 0) is None)
  assert_true(scalar_snapshot_layout(1, 2147483647, 1) is None)
  assert_true(scalar_snapshot_layout(1, 2, 2147483647) is None)
}

///|
test "scalar snapshot actual indexed cursor admission fits canonical retained bound" {
  let wire = "[{\"é\":null,\"𝄞\":true},{\"é\":1,\"𝄞\":false}]"
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 1000,
    max_nodes: 7,
    max_depth: 2,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 7,
    max_depth: 2,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  let admission = @identity.start_cursor_admission(
    cursor,
    7,
    2,
    1000,
    1000,
    data_keys=true,
  ).unwrap()
  let mut value : @identity.CanonicalValue? = None
  for _ in 0..<1000 {
    match @identity.advance_cursor_admission(admission) {
      @identity.CursorAdmissionContinue => ()
      @identity.CursorAdmissionComplete(v, _, _) => {
        value = Some(v)
        break
      }
      _ => fail("unexpected cursor admission refusal")
    }
  }
  let v = value.unwrap()
  let actual = @identity.representation_extent(v, 7, 2, 1000).unwrap()
  assert_eq(actual.nodes, 7L)
  let containers = actual.arrays + actual.objects
  let measured : @execution.PreparationRepresentationUnits = {
    record_headers: actual.nodes + 3L * containers + 4L,
    reference_slots: actual.nodes +
    2L * containers +
    actual.array_backing_slots +
    actual.object_backing_slots +
    8L,
    scalar_words: actual.nodes + 2L * containers,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let quote = scalar_snapshot_layout(2, 6, 2).unwrap()
  assert_true(
    @execution.preparation_representation_cost(quote.retained).unwrap() >=
    @execution.preparation_representation_cost(measured).unwrap(),
  )
  let writer = @encode.writer(1000, 7, 2)
  @identity.emit_value(v, writer)
  assert_eq(@encode.finish(writer), wire)
}

///|
test "scalar snapshot consumes canonical construction units without repricing" {
  for units in [0, 1, 3, 9, 65536] {
    let extent = @canonical.nfc_lf_construction_extent(units).unwrap()
    let actual = scalar_snapshot_name_normalization_layout(units).unwrap()
    assert_eq(actual.record_headers, extent.record_headers)
    assert_eq(actual.reference_slots, extent.reference_slots)
    assert_eq(actual.scalar_words, extent.scalar_words)
    assert_eq(actual.owned_utf16_units, extent.owned_utf16_units)
    assert_eq(actual.owned_wire_bytes, 0L)
    // Same independent Local slots and controls; the pinned recursive UTF16
    // proof refines only the five retained text/builder overlaps.
    assert_eq(actual.record_headers, 100L)
    assert_eq(actual.reference_slots, 123L)
    assert_eq(actual.scalar_words, 528L + 35L * units.to_int64())
    assert_eq(actual.owned_utf16_units, 20L * units.to_int64() + 2L)
  }
  assert_true(scalar_snapshot_name_normalization_layout(-1) is None)
}

///|
test "JSON leaf snapshot retains Unicode Text and prices original escaped wire" {
  // Independent UTF-8 inventory: two label keys10, Tokyo6, then e+accent3,
  // quote1, LF1, NUL1 and a supplementary scalar4 = 26 bytes, 19 UTF-16 units.
  let wire = "[{\"label\":\"東京\"},{\"label\":\"é\\\"\\n\\u0000𝄞\"}]"
  let quote = scalar_snapshot_layout(1, 5, 2, total_text_bytes=Some(26)).unwrap()
  assert_eq(quote.retained.owned_utf16_units, 26L)
  let numeric = scalar_snapshot_layout(1, 5, 2).unwrap()
  assert_eq(quote.retained.record_headers, numeric.retained.record_headers + 2L)
  assert_true(
    @execution.preparation_representation_cost(quote.temporary).unwrap() >
    @execution.preparation_representation_cost(numeric.temporary).unwrap(),
  )
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 1000,
    max_nodes: 5,
    max_depth: 2,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 5,
    max_depth: 2,
    max_string_bytes: 26,
    max_total_string_bytes: 26,
  }).unwrap()
  let admission = @identity.start_cursor_admission(
    cursor,
    5,
    2,
    26,
    26,
    data_keys=true,
  ).unwrap()
  let mut value : @identity.CanonicalValue? = None
  for _ in 0..<1000 {
    match @identity.advance_cursor_admission(admission) {
      @identity.CursorAdmissionContinue => ()
      @identity.CursorAdmissionComplete(v, _, _) => {
        value = Some(v)
        break
      }
      _ => fail("original Unicode Text cursor admission")
    }
  }
  let actual = @identity.representation_extent(value.unwrap(), 5, 2, 26).unwrap()
  let containers = actual.arrays + actual.objects
  let measured : @execution.PreparationRepresentationUnits = {
    record_headers: actual.nodes + 3L * containers + 4L + 4L,
    reference_slots: actual.nodes +
    2L * containers +
    actual.array_backing_slots +
    actual.object_backing_slots +
    8L,
    scalar_words: actual.nodes + 2L * containers,
    owned_utf16_units: 19L,
    owned_wire_bytes: 0L,
  }
  assert_true(
    @execution.preparation_representation_cost(quote.retained).unwrap() >=
    @execution.preparation_representation_cost(measured).unwrap(),
  )
  let writer = @encode.writer(1000, 5, 2)
  @identity.emit_value(value.unwrap(), writer)
  assert_eq(@encode.finish(writer), wire)
}

///|
test "JSON leaf snapshot preserves numeric wire bounds and empty invalid overflow guards" {
  for (fields, names, rows) in [(0, 0, 0), (1, 2, 2), (100, 500, 1000)] {
    // Independent pre-existing numeric specialization, not a second product
    // calculator or acceptance fallback.
    let expected = 30L +
      rows.to_int64() * (3L + 6L * names.to_int64() + 29L * fields.to_int64())
    assert_eq(
      client_local_scalar_wire_byte_bound(fields, names, rows),
      Some(expected.to_int()),
    )
  }
  let empty = scalar_snapshot_layout(1, 5, 0, total_text_bytes=Some(500000)).unwrap()
  assert_eq(empty.retained.owned_utf16_units, 0L)
  assert_true(
    scalar_snapshot_layout(1, 5, 0, total_text_bytes=Some(-1)) is None,
  )
  assert_true(
    scalar_snapshot_layout(1, 5, 1, total_text_bytes=Some(2147483647)) is None,
  )
  assert_true(client_local_json_leaf_wire_byte_bound(1, 1, 357913931L) is None)
}
