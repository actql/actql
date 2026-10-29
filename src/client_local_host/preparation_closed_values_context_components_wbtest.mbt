///|
test "empty sourceview component counts real empty containers and distinct attachments" {
  let units = closed_values_empty_sourceview_layout().unwrap()
  assert_true(units.record_headers > 48L)
  assert_true(units.reference_slots > 73L)
  assert_eq(units.owned_utf16_units, 0L)
  assert_eq(units.owned_wire_bytes, 0L)
  assert_true(@execution.preparation_representation_cost(units) is Some(_))
}

///|
test "Unit publication fixed original metadata facts include keys and dependencies" {
  let proof = closed_values_unit_publication_source_facts(false)
  let witness = closed_values_unit_publication_source_facts(true)
  assert_eq(proof.input_bytes, 228)
  assert_eq(proof.node_upper, 7)
  assert_eq(proof.quoted_utf16_units, 168)
  assert_eq(witness.input_bytes, 568)
  assert_eq(witness.node_upper, 15)
  assert_eq(witness.quoted_utf16_units, 466)
  assert_eq(witness.longest_quoted_utf16, 85)
}

///|
test "Unit publication composes generated parsers and writers without row payload copies" {
  let a = closed_values_unit_publication_layout(1).unwrap()
  let b = closed_values_unit_publication_layout(101).unwrap()
  assert_eq(b.payload.owned_utf16_units - a.payload.owned_utf16_units, 1600L)
  assert_true(a.source_admission == b.source_admission)
  assert_true(a.writers == b.writers)
  assert_eq(a.payload.owned_wire_bytes, 796L)
  let combined = @execution.compose_preparation_representation([
    a.payload,
    a.source_admission,
    a.writers,
  ]).unwrap()
  assert_true(
    @execution.preparation_representation_cost(combined).unwrap() >
    @execution.preparation_representation_cost(a.payload).unwrap(),
  )
  assert_true(closed_values_unit_publication_layout(-1) is None)
  assert_true(closed_values_unit_publication_layout(2147483647) is Some(_))
}
