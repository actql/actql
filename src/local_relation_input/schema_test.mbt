///|
fn rows(fields : String) -> @schema.Schema {
  let contract = @contract.read_checked(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
      fields +
      "}",
    ),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
  @schema.from_object(contract).unwrap()
}

///|
test "schema agreement retains stronger recursive types without rewriting source" {
  let declaration = read(
    cursor(
      (
        #|{"carrier":"relation","schema":{"text":{"type":"string","nullable":true},"xs":{"type":"array","nullable":false,"items":{"type":"number","nullable":true}}},"expected_columns":["text"]}
      ),
    ),
    caps(),
  ).unwrap()
  let actual = rows(
    (
      #|{"text":{"type":"string","nullable":false,"max_utf8_bytes":8},"xs":{"type":"array","nullable":false,"max_items":2,"items":{"type":"number","nullable":false}}}
    ),
  )
  let checked = check_schema(declaration, actual, caps()).unwrap()
  assert_true(physical_equal(schema_declaration(checked), declaration))
  assert_true(physical_equal(supplied_schema(checked), actual))
  let result = @carrier.complete_schema(
    @carrier.relation_rows(schema_carrier(checked)).unwrap(),
  ).unwrap()
  assert_true(physical_equal(result, actual))
  assert_true(
    @schema.lookup(result, Unqualified("text")).unwrap().shape
    is @contract.Text({ max_utf8_bytes: Some(8L), .. }),
  )
  assert_true(schema_primary_key(checked) is None)
  let original = @carrier.complete_schema(
    @carrier.relation_rows(carrier(declaration)).unwrap(),
  ).unwrap()
  assert_true(@schema.lookup(original, Unqualified("text")).unwrap().nullable)
  assert_true(
    check_schema(
      read(cursor("{\"carrier\":\"relation\",\"schema\":{}}"), caps()).unwrap(),
      actual,
      caps(),
    )
    is Err(TypeMismatch),
  )
  let weak = rows(
    (
      #|{"text":{"type":"string","nullable":true},"xs":{"type":"array","nullable":true,"items":{"type":"number","nullable":true}}}
    ),
  )
  assert_true(check_schema(declaration, weak, caps()) is Err(TypeMismatch))
}

///|
test "closed supplied schemas must satisfy open column and key assertions" {
  let declaration = read(
    cursor(
      "{\"carrier\":\"relation\",\"expected_columns\":[\"name\"],\"primary_key\":[\"id\"]}",
    ),
    caps(),
  ).unwrap()
  let actual = rows(
    "{\"name\":{\"type\":\"string\",\"nullable\":true},\"id\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let checked = check_schema(declaration, actual, caps()).unwrap()
  assert_true(
    @carrier.complete_schema(
      @carrier.relation_rows(carrier(declaration)).unwrap(),
    )
    is None,
  )
  let key = schema_primary_key(checked).unwrap()
  assert_true(!@evidence.key_pending(key).is_empty())
  assert_true(@evidence.key_field_at(key, 0).unwrap().contract is Some(_))
  assert_true(
    check_schema(declaration, rows("{}"), caps())
    is Err(MissingExpectedColumn("name")),
  )
  for
    fields in [
      "{\"name\":{\"type\":\"string\",\"nullable\":true}}", "{\"name\":{\"type\":\"string\",\"nullable\":true},\"id\":{\"type\":\"number\",\"nullable\":true}}",
      "{\"name\":{\"type\":\"string\",\"nullable\":true},\"id\":{\"type\":\"json\",\"nullable\":false}}",
    ] {
    assert_true(
      check_schema(declaration, rows(fields), caps()) is Err(PrimaryKey(_)),
    )
  }
}

///|
test "new schema information checks duplicate order field domains but not totality" {
  let declaration = read(
    cursor(
      "{\"carrier\":\"relation\",\"primary_key\":[\"id\"],\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"time\":\"asc\"}]}}}",
    ),
    caps(),
  ).unwrap()
  let actual = rows(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"time\":{\"type\":\"timestamp\",\"nullable\":false}}",
  )
  let checked = check_schema(declaration, actual, caps()).unwrap()
  assert_true(first_by_order(schema_declaration(checked)) is Some(_))
  for
    fields in [
      "{\"id\":{\"type\":\"number\",\"nullable\":false}}", "{\"id\":{\"type\":\"number\",\"nullable\":false},\"time\":{\"type\":\"json\",\"nullable\":false}}",
    ] {
    assert_true(
      check_schema(declaration, rows(fields), caps())
      is Err(InvalidOrderField("time")),
    )
  }
}

///|
test "schema comparison rejects qualified evidence and observes aggregate limits" {
  let declaration = read(
    cursor(
      "{\"carrier\":\"relation\",\"expected_columns\":[\"id\"],\"primary_key\":[\"id\"]}",
    ),
    caps(),
  ).unwrap()
  let actual = rows("{\"id\":{\"type\":\"number\",\"nullable\":false}}")
  let result = check_schema(declaration, actual, caps()).unwrap()
  let used = schema_usage(result)
  let exact : Limits = {
    max_nodes: used.nodes,
    max_depth: 1,
    max_text_bytes: used.text_bytes,
  }
  assert_true(check_schema(declaration, actual, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_depth: 0, },
      { ..exact, max_nodes: -1, },
    ] {
    assert_true(check_schema(declaration, actual, limits) is Err(_))
  }
  let qualified = @schema.from_fields(
    [
      (
        @schema.Qualified(Left, "id"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=20,
  ).unwrap()
  assert_true(
    check_schema(declaration, qualified, caps()) is Err(NonFlatSchema),
  )
  let mut c = @contract.primitive(NumberType, nullable=false)
  for _ in 0..<3000 {
    c = @contract.array_contract(c, nullable=false).unwrap()
  }
  let deep = @schema.from_fields(
    [(Unqualified("id"), c)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let unknown = read(cursor("\"relation\""), caps()).unwrap()
  assert_true(
    check_schema(unknown, deep, {
      max_nodes: 3002,
      max_depth: 3001,
      max_text_bytes: 2,
    })
    is Ok(_),
  )
  assert_true(
    check_schema(unknown, deep, {
      max_nodes: 3002,
      max_depth: 3000,
      max_text_bytes: 2,
    })
    is Err(BudgetExceeded),
  )
}
