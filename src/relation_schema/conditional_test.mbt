///|
test "finite presence keeps missing distinct from nullable value types" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let schema = @relation_schema.from_conditional_fields(
    [
      (Unqualified("p"), nullable, FieldPresence::Conditional),
      (Unqualified("id"), number, FieldPresence::Required),
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
  assert_eq(
    @relation_schema.conditional_field_presence(field),
    FieldPresence::Conditional,
  )
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
    @relation_schema.from_conditional_fields(
      [(Unqualified("id"), number, FieldPresence::Required)],
      max_fields=0,
      max_name_bytes=2,
    )
    is Err(LimitExceeded),
  )
  assert_true(
    @relation_schema.from_conditional_fields(
      [(Unqualified("id"), number, FieldPresence::Required)],
      max_fields=-1,
      max_name_bytes=2,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    @relation_schema.from_conditional_fields(
      [
        (Unqualified("id"), number, FieldPresence::Required),
        (Unqualified("id"), number, FieldPresence::Conditional),
      ],
      max_fields=2,
      max_name_bytes=4,
    )
    is Err(DuplicateField(_)),
  )
  assert_true(
    @relation_schema.from_conditional_fields(
      [(Unqualified("__actql_bad"), number, FieldPresence::Conditional)],
      max_fields=1,
      max_name_bytes=20,
    )
    is Err(InvalidField(_, _)),
  )
}

///|
test "definition presence distinguishes missing property from nullable null" {
  let id = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let (schema, work) = @relation_schema.from_definition_fields(
    [
      [(Unqualified("id"), id), (Unqualified("p"), nullable)],
      [(Unqualified("id"), id)],
    ],
    max_definitions=2,
    max_fields=2,
    max_name_bytes=3,
    max_contract_work=6,
  ).unwrap()
  assert_eq(work, 6)
  assert_true(
    @relation_schema.presence_lookup(schema, Unqualified("id"))
    is AlwaysPresent(_),
  )
  assert_true(
    @relation_schema.presence_lookup(schema, Unqualified("p"))
    is ConditionallyPresent(_),
  )
  assert_eq(
    @relation_schema.field_count(
      @relation_schema.required_projection_schema(schema),
    ),
    1,
  )
  assert_true(
    @relation_schema.from_definition_fields(
      [
        [(Unqualified("id"), id), (Unqualified("p"), nullable)],
        [(Unqualified("id"), id)],
      ],
      max_definitions=2,
      max_fields=2,
      max_name_bytes=3,
      max_contract_work=5,
    )
    is Err(DefinitionLimit),
  )
}

///|
test "definition presence rejects incompatible and colliding declarations" {
  let number = @contract.primitive(NumberType, nullable=false)
  let string = @contract.primitive(StringType, nullable=false)
  assert_true(
    @relation_schema.from_definition_fields(
      [[(Unqualified("p"), number)], [(Unqualified("p"), string)]],
      max_definitions=2,
      max_fields=1,
      max_name_bytes=1,
      max_contract_work=5,
    )
    is Err(IncompatibleDeclaration(Unqualified("p"))),
  )
  assert_true(
    @relation_schema.from_definition_fields(
      [[(Unqualified("id"), number)], [(Unqualified("p"), number)]],
      max_definitions=2,
      max_fields=1,
      max_name_bytes=2,
      max_contract_work=4,
    )
    is Err(DefinitionLimit),
  )
  assert_true(
    @relation_schema.from_definition_fields(
      [[(Unqualified("id"), number), (Unqualified("id"), number)]],
      max_definitions=1,
      max_fields=2,
      max_name_bytes=4,
      max_contract_work=3,
    )
    is Err(DefinitionSchema(DuplicateField(Unqualified("id")))),
  )
}
