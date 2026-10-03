///|
test "unknown and absent fields are distinct from present untyped fields" {
  let name = @row.Unqualified("x")
  assert_true(lookup(unknown_rows(), name) is Unknown)
  let open = rows(
    [(name, None)],
    field_set=Open,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  assert_true(lookup(open, name) is Present({ contract: None, .. }))
  assert_true(lookup(open, @row.Unqualified("other")) is Unknown)
  assert_true(complete_schema(open) is None)
  let closed = rows(
    [(name, None)],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  assert_true(lookup(closed, name) is Present({ contract: None, .. }))
  assert_true(lookup(closed, @row.Unqualified("other")) is Absent)
  assert_true(complete_schema(closed) is None)
}

///|
test "conditional rows expose only guaranteed fields to ordinary lookup" {
  let number = @value.primitive(NumberType, nullable=false)
  let nullable = @value.primitive(NumberType, nullable=true)
  let schema = @row.from_conditional_fields(
    [
      (@row.Unqualified("id"), number, @row.FieldPresence::Required),
      (@row.Unqualified("p"), nullable, @row.FieldPresence::Conditional),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let records = conditional_rows(schema)
  assert_eq(field_set(records), Closed)
  assert_eq(field_count(records), 2)
  assert_true(complete_schema(records) is None)
  assert_true(conditional_schema(records) is Some(_))
  assert_true(
    lookup(records, @row.Unqualified("id"))
    is Present({ contract: Some(_), .. }),
  )
  assert_true(lookup(records, @row.Unqualified("p")) is Unknown)
  assert_true(lookup(records, @row.Unqualified("absent")) is Absent)
  assert_true(field_at(records, 1).unwrap().contract is None)
  let required = @row.required_projection_schema(schema)
  assert_eq(@row.field_count(required), 1)
  assert_true(complete_schema(typed_rows(required)) is Some(_))
}

///|
test "complete names alone never infer types and open known types never close rows" {
  let number = @value.primitive(NumberType, nullable=false)
  let input = [(@row.Unqualified("x"), Some(number))]
  let open = rows(input, field_set=Open, max_fields=1, max_name_bytes=1).unwrap()
  assert_true(complete_schema(open) is None)
  let closed = rows(input, field_set=Closed, max_fields=1, max_name_bytes=1).unwrap()
  let schema = complete_schema(closed).unwrap()
  assert_eq(@row.field_count(schema), 1)
  assert_true(
    @row.lookup(schema, @row.Unqualified("x"))
    is Some({ shape: @value.Number, .. }),
  )
  assert_eq(field_set(typed_rows(schema)), Closed)
  assert_true(lookup(typed_rows(schema), @row.Unqualified("z")) is Absent)
}

///|
test "empty closed rows are typed but empty open rows remain unknown" {
  let closed = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  assert_eq(@row.field_count(complete_schema(closed).unwrap()), 0)
  assert_eq(field_count(closed), 0)
  assert_true(field_at(closed, 0) is None)
  assert_true(field_at(closed, -1) is None)
  assert_true(complete_schema(unknown_rows()) is None)
}

///|
test "partial field names use exact existing admission and budgets" {
  let qualified = @row.Qualified(Left, "id")
  assert_true(
    rows([(qualified, None)], field_set=Open, max_fields=1, max_name_bytes=6)
    is Err(@row.LimitExceeded),
  )
  let partial = rows(
    [(qualified, None)],
    field_set=Open,
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  assert_true(lookup(partial, qualified) is Present(_))
  assert_true(lookup(partial, @row.Unqualified("left.id")) is Unknown)
  assert_true(
    rows(
      [(@row.Unqualified("left.id"), None)],
      field_set=Open,
      max_fields=1,
      max_name_bytes=7,
    )
    is Err(@row.InvalidField(_, _)),
  )
  assert_true(
    rows(
      [(qualified, None), (qualified, None)],
      field_set=Open,
      max_fields=2,
      max_name_bytes=14,
    )
    is Err(@row.DuplicateField(_)),
  )
  assert_true(
    rows([], field_set=Open, max_fields=-1, max_name_bytes=0)
    is Err(@row.InvalidLimits),
  )
  assert_true(
    rows([(qualified, None)], field_set=Open, max_fields=0, max_name_bytes=7)
    is Err(@row.LimitExceeded),
  )
}

///|
test "field collections are detached and preserve canonical order" {
  let input : Array[(@row.FieldName, @value.Contract?)] = [
    (@row.Unqualified("z"), None),
    (@row.Unqualified("a"), None),
  ]
  let knowledge = rows(input, field_set=Open, max_fields=2, max_name_bytes=2).unwrap()
  input.clear()
  let output = fields(knowledge)
  assert_eq(output[0].name, @row.Unqualified("a"))
  output.clear()
  assert_eq(field_count(knowledge), 2)
  assert_eq(field_at(knowledge, 1).unwrap().name, @row.Unqualified("z"))
}

///|
test "wide incomplete schemas and deep shared child contracts" {
  let input : Array[(@row.FieldName, @value.Contract?)] = []
  for i in 0..<10000 {
    input.push((@row.Unqualified("f" + i.to_string()), None))
  }
  let knowledge = rows(
    input,
    field_set=Open,
    max_fields=10000,
    max_name_bytes=50000,
  ).unwrap()
  assert_eq(field_count(knowledge), 10000)
  for i in 0..<10000 {
    assert_true(
      lookup(knowledge, @row.Unqualified("f" + i.to_string()))
      is Present({ contract: None, .. }),
    )
  }
  let mut child = @value.primitive(NumberType, nullable=false)
  for _ in 0..<10000 {
    child = @value.array_contract(child, nullable=false).unwrap()
  }
  let deep = rows(
    [(@row.Unqualified("deep"), Some(child))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  assert_true(complete_schema(deep) is Some(_))
}

///|
test "closed typed knowledge does not imply row-total presence" {
  let schema = @row.from_presence_fields(
    [
      (
        Unqualified("p"),
        @value.primitive(NumberType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let knowledge = typed_rows(schema)
  assert_eq(field_set(knowledge), Closed)
  let field = field_at(knowledge, 0).unwrap()
  assert_eq(field.presence, @row.Conditional)
  assert_true(field.contract.unwrap().nullable)
  assert_true(!@row.all_fields_required(complete_schema(knowledge).unwrap()))
  assert_true(lookup(knowledge, Unqualified("other")) is Absent)
}
