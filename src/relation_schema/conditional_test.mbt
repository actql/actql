///|
test "finite presence keeps missing distinct from nullable value types" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let schema = @relation_schema.from_presence_fields(
    [
      (Unqualified("p"), nullable, Conditional),
      (Unqualified("id"), number, Required),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  assert_eq(@relation_schema.presence_field_count(schema), 2)
  assert_true(
    @relation_schema.presence_lookup(schema, Unqualified("id"))
    is AlwaysPresent(_),
  )
  assert_true(
    @relation_schema.presence_lookup(schema, Unqualified("p"))
    is ConditionallyPresent(_),
  )
  assert_true(
    @relation_schema.presence_lookup(schema, Unqualified("missing"))
    is AbsentField,
  )
  let field = @relation_schema.presence_field_at(schema, 1).unwrap()
  assert_eq(@relation_schema.presence_field_name(field), Unqualified("p"))
  assert_eq(@relation_schema.field_presence(field), Conditional)
  assert_true(@relation_schema.presence_field_contract(field).nullable)
  let dense = @relation_schema.required_projection_schema(schema)
  assert_eq(@relation_schema.field_count(dense), 1)
  assert_true(@relation_schema.lookup(dense, Unqualified("id")) is Some(_))
  assert_true(@relation_schema.lookup(dense, Unqualified("p")) is None)
}

///|
test "presence fields retain ordinary schema name and type validation" {
  let number = @contract.primitive(NumberType, nullable=false)
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
      [(Unqualified("__actql_bad"), number, Conditional)],
      max_fields=1,
      max_name_bytes=20,
    )
    is Err(InvalidField(_, _)),
  )
}
