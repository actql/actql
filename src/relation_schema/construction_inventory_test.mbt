///|
test "original unqualified presence inventory counts each distinct retained schema" {
  let q = @relation_schema.unqualified_presence_construction_inventory(2, 1).unwrap()
  assert_eq(q.retained, {
    record_headers: 17L,
    reference_slots: 55L,
    scalar_words: 13L,
  })
  assert_eq(q.scratch, {
    record_headers: 201L,
    reference_slots: 330L,
    scalar_words: 708L,
  })
  assert_eq(q.scratch_utf16_units, 22L)
  assert_eq(
    @relation_schema.unqualified_presence_retained_extent(2, 2),
    Some({ record_headers: 28L, reference_slots: 86L, scalar_words: 24L, }),
  )
  let a = @contract.primitive(NumberType, nullable=false)
  let fields = @relation_schema.from_presence_fields(
    [
      (@relation_schema.Unqualified("b"), a, @relation_schema.Conditional),
      (@relation_schema.Unqualified("a"), a, @relation_schema.Required),
    ],
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  assert_eq(@relation_schema.field_count(fields), 2)
  assert_true(!@relation_schema.all_fields_required(fields))
  assert_eq(
    @relation_schema.field_presence(
      @relation_schema.field_at(fields, 1).unwrap(),
    ),
    @relation_schema.Conditional,
  )
  assert_true(
    @relation_schema.unqualified_presence_construction_inventory(1, -1) is None,
  )
  assert_true(@relation_schema.from_object_construction_extent(-1) is None)
  assert_true(
    @relation_schema.unqualified_presence_retained_extent(
      2147483647, 2147483647,
    )
    is Some(_),
  )
}
