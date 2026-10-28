///|
test "typed row constructor retained quantity includes original complete and field variant tags" {
  assert_eq(
    typed_rows_retained_extent(1, 1),
    Some({ record_headers: 8L, reference_slots: 23L, scalar_words: 9L, }),
  )
  // Knowledge three scalar fields + complete Some tag; each retained field
  // owns Presence, contract Some and newly projected Unqualified-name tags.
  let value = @value.primitive(NumberType, nullable=false)
  let original = @value.object_contract(
    [("x", value)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let schema = @row.from_object(original).unwrap()
  let actual = typed_rows(schema)
  assert_true(physical_equal(complete_schema(actual).unwrap(), schema))
  assert_eq(field_count(actual), 1)
}
