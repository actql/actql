///|
test "original object assembler construction separates borrowed children from names" {
  let q = @value_contract.object_construction_inventory(2, 1).unwrap()
  assert_eq(q.retained, {
    record_headers: 8L,
    reference_slots: 26L,
    scalar_words: 5L,
  })
  assert_eq(q.scratch, {
    record_headers: 147L,
    reference_slots: 187L,
    scalar_words: 636L,
  })
  assert_eq(q.scratch_utf16_units, 22L)
  let child = @value_contract.primitive(NumberType, nullable=false)
  let value = @value_contract.object_contract(
    [("b", child), ("a", child)],
    nullable=false,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  guard value.shape is Object(fields) else { fail("original object") }
  assert_eq(@value_contract.field_count(fields), 2)
  assert_true(
    physical_equal(@value_contract.field_at(fields, 0).unwrap().contract, child),
  )
  assert_true(
    @value_contract.object_contract(
      [("a.b", child)],
      nullable=false,
      max_fields=1,
      max_name_bytes=3,
    )
    is Err(InvalidConstructionName(_)),
  )
  assert_true(@value_contract.object_construction_inventory(-1, 0) is None)
  assert_true(
    @value_contract.object_retained_construction_extent(0, -1) is None,
  )
  let join = @value_contract.relation_construction_inventory(3).unwrap()
  let result = @value_contract.join_nullability(
    child,
    @value_contract.with_nullability(child, true),
    1,
  )
  assert_true(result is Some({ nullable: true, shape: Number, }))
  assert_true(
    join.joined.record_headers > 0L && join.scratch.record_headers > 0L,
  )
  assert_true(@value_contract.relation_construction_inventory(-1) is None)
}
