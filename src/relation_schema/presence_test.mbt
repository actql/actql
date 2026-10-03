///|
test "presence is independent of nullable and the finite field set" {
  let nullable = @contract.primitive(NumberType, nullable=true)
  let nonnullable = @contract.primitive(NumberType, nullable=false)
  let schema = @relation_schema.from_presence_fields(
    [
      (Unqualified("p"), nullable, Conditional),
      (Unqualified("id"), nonnullable, Required),
      (Unqualified("q"), nonnullable, Conditional),
    ],
    max_fields=3,
    max_name_bytes=4,
  ).unwrap()
  assert_true(!@relation_schema.all_fields_required(schema))
  assert_true(!@relation_schema.has_qualified_fields(schema))
  assert_true(@relation_schema.as_object(schema) is None)
  assert_eq(@relation_schema.field_count(schema), 3)
  let id = @relation_schema.lookup_reference(schema, "id").unwrap()
  let p = @relation_schema.lookup_reference(schema, "p").unwrap()
  let q = @relation_schema.lookup_reference(schema, "q").unwrap()
  assert_eq(id.presence, Required)
  assert_true(!id.contract.nullable)
  assert_eq(p.presence, Conditional)
  assert_true(p.contract.nullable)
  assert_eq(q.presence, Conditional)
  assert_true(!q.contract.nullable)
  assert_true(@relation_schema.lookup_reference(schema, "extra") is None)
  @relation_schema.fields(schema).clear()
  assert_eq(@relation_schema.field_count(schema), 3)
}

///|
test "all-required construction retains ordinary object admission and bounds" {
  let number = @contract.primitive(NumberType, nullable=false)
  let schema = @relation_schema.from_presence_fields(
    [(Unqualified("id"), number, Required)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  assert_true(@relation_schema.all_fields_required(schema))
  assert_true(@relation_schema.as_object(schema) is Some(_))
  assert_true(
    @relation_schema.from_presence_fields(
      [
        (Unqualified("id"), number, Required),
        (Unqualified("id"), number, Conditional),
      ],
      max_fields=2,
      max_name_bytes=4,
    )
    is Err(DuplicateField(_)),
  )
  assert_true(
    @relation_schema.from_presence_fields(
      [(Unqualified("p"), number, Conditional)],
      max_fields=0,
      max_name_bytes=1,
    )
    is Err(LimitExceeded),
  )
  assert_true(
    @relation_schema.from_presence_fields(
      [(Qualified(Left, "id"), number, Conditional)],
      max_fields=1,
      max_name_bytes=6,
    )
    is Err(LimitExceeded),
  )
  let qualified = @relation_schema.from_presence_fields(
    [(Qualified(Left, "id"), number, Conditional)],
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  assert_true(@relation_schema.has_qualified_fields(qualified))
}
