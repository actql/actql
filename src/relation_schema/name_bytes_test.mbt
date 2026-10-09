///|
test "schema name bytes include original qualified prefixes without rescanning" {
  let name = "x".repeat(128) + "😀é"
  let flat = make([(@relation_schema.Unqualified(name), number())])
  assert_eq(@relation_schema.field_reference_name_bytes(flat), 134)
  let scoped = make([
    (@relation_schema.Qualified(@relation_schema.Right, name), number()),
    (@relation_schema.Qualified(@relation_schema.Left, name), number()),
  ])
  assert_eq(
    @relation_schema.field_reference_name_bytes(scoped),
    134 * 2 + 5 + 6,
  )
  assert_eq(
    @relation_schema.field_reference_name_at(scoped, 0),
    Some("left." + name),
  )
  assert_eq(
    @relation_schema.field_reference_name_at(scoped, 1),
    Some("right." + name),
  )
  assert_eq(@relation_schema.field_reference_name_bytes(make([])), 0)
}
