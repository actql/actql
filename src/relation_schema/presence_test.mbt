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
test "wide admitted schemas retain independent presence and qualification facts" {
  let number = @contract.primitive(NumberType, nullable=true)
  for
    (qualified, conditional) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ] {
    let entries = Array::makei(257, index => {
      let name = "column_" + index.to_string()
      let reference = if qualified && index == 256 {
        @relation_schema.Qualified(@relation_schema.Left, name)
      } else {
        @relation_schema.Unqualified(name)
      }
      // A nullable value is still a required column. Only the explicit
      // final conditional declaration may permit absence.
      (
        reference,
        number,
        if conditional && index == 256 {
          @relation_schema.Conditional
        } else {
          @relation_schema.Required
        },
      )
    })
    let schema = @relation_schema.from_presence_fields(
      entries,
      max_fields=257,
      max_name_bytes=10000,
    ).unwrap()
    entries.clear()
    for _ in 0..<3 {
      assert_eq(@relation_schema.all_fields_required(schema), !conditional)
      assert_eq(@relation_schema.has_qualified_fields(schema), qualified)
      assert_eq(@relation_schema.field_count(schema), 257)
    }
    assert_eq(
      @relation_schema.as_object(schema) is Some(_),
      !qualified && !conditional,
    )
    @relation_schema.fields(schema).clear()
    assert_eq(@relation_schema.all_fields_required(schema), !conditional)
    assert_eq(@relation_schema.has_qualified_fields(schema), qualified)
  }
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
