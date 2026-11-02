///|
test "original known fields retain same contracts with separate schema and knowledge copies" {
  let q = unqualified_rows_construction_inventory(2, 1).unwrap()
  assert_eq(q.retained, {
    record_headers: 28L,
    reference_slots: 85L,
    // Knowledge and projected-field Presence/contract tags stay retained.
    scalar_words: 25L,
  })
  assert_eq(q.scratch, {
    record_headers: 242L,
    reference_slots: 449L,
    scalar_words: 772L,
  })
  assert_eq(q.scratch_utf16_units, 22L)
  assert_eq(
    unqualified_rows_retained_extent(2, 2),
    Some({ record_headers: 44L, reference_slots: 132L, scalar_words: 42L, }),
  )
  let original = @value.primitive(NumberType, nullable=false)
  let knowledge = rows(
    [
      (@row.Unqualified("b"), Some(original)),
      (@row.Unqualified("a"), Some(original)),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  assert_eq(field_count(knowledge), 2)
  assert_true(
    physical_equal(field_at(knowledge, 0).unwrap().contract.unwrap(), original),
  )
  assert_true(complete_schema(knowledge) is Some(_))
  assert_true(typed_rows_construction_inventory(-1) is None)
  assert_true(unqualified_rows_retained_extent(0, -1) is None)
}
