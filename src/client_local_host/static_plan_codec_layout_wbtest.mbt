///|
fn static_plan_codec_test_validator() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 7L,
    reference_slots: 11L,
    scalar_words: 13L,
    owned_utf16_units: 17L,
    owned_wire_bytes: 19L,
  }
}

///|
test "static plan artifact codec composes original parser and mandatory validator owners" {
  let geometry = (104968, 5000, 12)
  let validator = static_plan_codec_test_validator()
  let value = client_static_plan_codec_layout(
    geometry, validator, 17L, 101L, 13L,
  ).unwrap()
  let parse = program_artifact_parse_layout(geometry).unwrap()
  assert_true(value.retained.record_headers >= parse.value.record_headers)
  assert_true(
    value.retained.owned_utf16_units >=
    parse.value.owned_utf16_units + geometry.0.to_int64(),
  )
  assert_true(
    value.scratch.record_headers >=
    parse.temporary.record_headers + validator.record_headers,
  )
  assert_true(
    value.scratch.owned_wire_bytes >=
    parse.temporary.owned_wire_bytes + validator.owned_wire_bytes,
  )
  assert_eq(value.reference_array_slots, 12L + 3L * 5000L)
  assert_eq(value.map_bucket_slots, 8192L)
  assert_eq(value.scalar_array_items, 64L)
  assert_eq(value.builder_utf16_bound, 104968L)
  assert_true(
    @execution.preparation_representation_cost(value.retained) is Some(_),
  )
  assert_true(
    @execution.preparation_representation_cost(value.scratch) is Some(_),
  )
}

///|
test "static plan artifact geometry refuses invalid inputs instead of omitting a component" {
  let validator = static_plan_codec_test_validator()
  for shape in [(0, 2, 1), (1, 0, 1), (10, 2, 0)] {
    assert_true(
      client_static_plan_codec_layout(shape, validator, 0L, 0L, 0L) is None,
    )
  }
  assert_true(
    client_static_plan_codec_layout(
      (100, 10, 2),
      { ..validator, record_headers: -1L, },
      0L,
      0L,
      0L,
    )
    is None,
  )
  assert_true(
    client_static_plan_codec_layout((100, 10, 2), validator, -1L, 0L, 0L)
    is None,
  )
  let more = client_static_plan_codec_layout(
    (100, 10, 2),
    validator,
    1000L,
    1000L,
    2000L,
  ).unwrap()
  assert_eq(more.string_utf16_units, 1000L)
  assert_eq(more.reference_array_slots, 1000L)
  assert_eq(more.scalar_array_items, 2000L)
}

///|
test "unique item canonical emission includes traversal without a second parse" {
  let shape = (400, 25, 4)
  let value = client_static_plan_canonical_emission_layout(shape).unwrap()
  let writer = @encode.text_writer_construction_inventory(
    shape.0,
    shape.1,
    shape.2,
  ).unwrap()
  let emitter = compilation_canonical_emitter_layout(shape.2).unwrap()
  assert_eq(
    value.record_headers,
    writer.record_headers + emitter.record_headers,
  )
  assert_eq(value.owned_utf16_units, writer.owned_utf16_units)
  assert_eq(value.owned_wire_bytes, 0L)
}

///|
test "static plan helper placement follows pinned collection boundaries" {
  assert_eq(client_static_plan_map_bucket_slots(0), Some(8L))
  assert_eq(client_static_plan_map_bucket_slots(6), Some(8L))
  assert_eq(client_static_plan_map_bucket_slots(7), Some(16L))
  assert_eq(client_static_plan_map_bucket_slots(-1), None)
  assert_true(
    client_static_plan_array_sort_layout(0) ==
    closed_values_sort_scratch_layout(1),
  )
  assert_true(
    client_static_plan_array_sort_layout(17) ==
    closed_values_sort_scratch_layout(17),
  )
  assert_true(client_static_plan_array_sort_layout(-1) is None)
}
