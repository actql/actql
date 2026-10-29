///|
test "representation composition preserves distinct bodies references text and wire units" {
  let header : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let references = { ..header, record_headers: 0L, reference_slots: 2L, }
  let encoded = {
    ..header,
    record_headers: 0L,
    owned_utf16_units: 7L,
    owned_wire_bytes: 17L,
  }
  let combined = compose_preparation_representation([
    header, references, encoded,
  ]).unwrap()
  assert_eq(combined.record_headers, 1L)
  assert_eq(combined.reference_slots, 2L)
  assert_eq(combined.owned_utf16_units, 7L)
  assert_eq(combined.owned_wire_bytes, 17L)
  // One body, two borrowed roots, seven UTF16 units and17 encoded bytes.
  assert_eq(preparation_representation_cost(combined), Some(63L))
  // Equal unit DATA is not proof that the two declared bodies alias. The
  // domain must count an original shared body once, not expect this fold to
  // deduplicate objects or issue an ownership/permission receipt.
  let two = compose_preparation_representation([encoded, encoded]).unwrap()
  assert_eq(preparation_representation_cost(two), Some(62L))
  assert_eq(preparation_representation_cost(encoded), Some(31L))
  assert_eq(preparation_representation_cost(header), Some(16L))
  assert_eq(
    preparation_representation_cost(
      compose_preparation_representation([]).unwrap(),
    ),
    Some(0L),
  )
}

///|
test "representation composition cannot cancel invalid extents or overflow across dimensions" {
  let zero : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let positive = {
    record_headers: 10L,
    reference_slots: 10L,
    scalar_words: 10L,
    owned_utf16_units: 10L,
    owned_wire_bytes: 10L,
  }
  for
    invalid in [
      { ..zero, record_headers: -1L, },
      { ..zero, reference_slots: -1L, },
      { ..zero, scalar_words: -1L, },
      { ..zero, owned_utf16_units: -1L, },
      { ..zero, owned_wire_bytes: -1L, },
    ] {
    assert_true(compose_preparation_representation([positive, invalid]) is None)
    assert_true(compose_preparation_representation([invalid, positive]) is None)
  }
  let maximum = { ..zero, owned_wire_bytes: 9223372036854775807L, }
  assert_true(compose_preparation_representation([maximum]) is Some(_))
  assert_true(
    compose_preparation_representation([
      maximum,
      { ..zero, owned_wire_bytes: 1L, },
    ])
    is None,
  )
  // Every field addition fits, but converting the combined units does not.
  assert_true(
    compose_preparation_representation([
      maximum,
      { ..zero, record_headers: 1L, },
    ])
    is None,
  )
}
