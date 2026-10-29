///|
test "flat Schema constructor retained quantity includes its original Representation tag" {
  assert_eq(
    from_object_construction_extent(1),
    Some({ record_headers: 2L, reference_slots: 3L, scalar_words: 4L, }),
  )
  // Original Schema owns three scalar fields; Flat carries one scalar tag.
  let original = @contract.object_contract(
    [],
    nullable=false,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let schema = from_object(original).unwrap()
  assert_true(physical_equal(as_object(schema).unwrap(), original))
}
