///|
test "Object constructor retained quantity includes original Shape tag and field-name-byte word" {
  assert_eq(
    object_retained_construction_extent(0, 1),
    Some({ record_headers: 6L, reference_slots: 16L, scalar_words: 5L, }),
  )
  // Contract nullable1W, Shape Object tag1W, Fields name_bytes1W;
  // the pinned growing empty fields Array contributes its own2W.
  let original = object_contract(
    [],
    nullable=false,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(original.shape is Object(_))
  assert_true(!original.nullable)
}
