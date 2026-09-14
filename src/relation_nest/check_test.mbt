///|
test "nest parameter guards remain unbound and do not create order evidence" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":5},\"maybe\":{\"type\":\"number\",\"nullable\":true},\"text\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 100,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  for name in ["cap", "maybe", "text"] {
    let body = cursor(
      "{\"with\":\"c\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"],\"max_items\":{\"$param\":\"" +
      name +
      "\"}}",
    )
    let result = @relation_nest.check(
      body,
      schema(),
      schema(),
      Some(declarations),
      limits(),
    )
    if name == "text" {
      assert_eq(result.unwrap_err().kind, InvalidGuard)
    } else {
      let value = result.unwrap()
      assert_eq(@relation_nest.item_guard(value), Some(Parameter(name)))
      assert_true(
        indexed_obligation_copy(
          @relation_nest.pending_validations(value),
          @relation_nest.pending_validation_count(value),
          i => @relation_nest.pending_validation_at(value, i),
          (a, b) => a == b,
        ).contains(BindGuard(name)),
      )
      assert_true(
        indexed_obligation_copy(
          @relation_nest.pending_validations(value),
          @relation_nest.pending_validation_count(value),
          i => @relation_nest.pending_validation_at(value, i),
          (a, b) => a == b,
        ).contains(ResolveTotalOrder),
      )
      assert_true(@relation_nest.order(value) is None)
    }
  }
}

///|
test "nest traverses deep payload contracts without recursion and charges added depth" {
  let mut item = @contract.primitive(NumberType, nullable=false)
  for _ in 0..<10000 {
    item = @contract.array_contract(item, nullable=false, max_items=None).unwrap()
  }
  let child = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (@schema.Unqualified("payload"), item),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let body = cursor(
    "{\"with\":\"c\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"payload\"]}",
  )
  assert_true(
    @relation_nest.check(body, schema(), child, None, limits()) is Ok(_),
  )
  assert_eq(
    @relation_nest.check(body, schema(), child, None, {
      ..limits(),
      max_depth: 10001,
    }).unwrap_err().kind,
    BudgetExceeded,
  )
}

///|
test "nest wide repeated correlations and output aliases are budgeted and detached" {
  let on = Array::make(10000, "{\"left\":\"id\",\"right\":\"id\"}").join(",")
  let body = cursor(
    "{\"with\":\"c\",\"on\":[" +
    on +
    "],\"into\":\"items\",\"fields\":[{\"z\":\"id\"},{\"a\":\"id\"}],\"order_by\":[{\"id\":\"asc\"},{\"id\":\"desc\"}]}",
  )
  let v = @relation_nest.check(body, schema(), schema(), None, limits()).unwrap()
  assert_eq(@relation_nest.keys(v).length(), 10000)
  assert_eq(@relation_nest.key_count(v), 10000)
  for i in 0..<10000 {
    let pair = @relation_nest.key_at(v, i).unwrap()
    assert_eq(pair.left, @schema.Unqualified("id"))
    assert_eq(pair.right, @schema.Unqualified("id"))
    assert_true(physical_equal(pair, @relation_nest.key_at(v, i).unwrap()))
  }
  for i in [-1, 10000, 2147483647] {
    assert_true(@relation_nest.key_at(v, i) is None)
  }
  let detached_keys = @relation_nest.keys(v)
  let last = @relation_nest.key_at(v, 9999).unwrap()
  detached_keys.clear()
  assert_eq(@relation_nest.key_count(v), 10000)
  assert_true(physical_equal(last, @relation_nest.key_at(v, 9999).unwrap()))
  let projection = @relation_nest.projection(v)
  projection[0] = projection[1]
  assert_eq(@relation_nest.projection(v)[0].output, "z")
  let terms = @relation_nest.order(v).unwrap()
  ignore(terms.pop())
  assert_eq(@relation_nest.order(v).unwrap().length(), 2)
  assert_true(@relation_nest.usage(v).work < 200000)
}

///|
fn limits() -> @relation_nest.Limits {
  {
    max_work: 2000000,
    max_text_bytes: 2000000,
    max_nodes: 100000,
    max_depth: 30000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 2000000,
      max_nodes: 100000,
      max_depth: 30000,
    }).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 30000,
      max_string_bytes: 2000000,
      max_total_string_bytes: 2000000,
    },
  ).unwrap()
}

///|
fn schema() -> @schema.Schema {
  @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Qualified(Right, "amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "nest retains repeated correlation and flat nullable child projection" {
  let body = cursor(
    "{\"with\":\"child\",\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"right.amount\"},\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"max_items\":3}",
  )
  let v = @relation_nest.check(body, schema(), schema(), None, limits()).unwrap()
  assert_eq(@relation_nest.keys(v).length(), 2)
  assert_eq(@relation_nest.projection(v)[0].output, "amount")
  assert_eq(@relation_nest.item_guard(v), Some(Literal(3L)))
  assert_true(@relation_nest.order(v) is Some(_))
  let output = @relation_nest.output_schema(v)
  assert_eq(@schema.field_count(output), 3)
  assert_true(
    @schema.lookup(output, Qualified(Right, "amount")).unwrap().nullable,
  )
  let array = @schema.lookup(output, Unqualified("items")).unwrap()
  assert_true(!array.nullable)
  match array.shape {
    @contract.Array(item, max_items~) => {
      assert_eq(max_items, None)
      assert_true(!item.nullable)
      match item.shape {
        @contract.Object(fields) =>
          assert_true(@contract.field_at(fields, 0).unwrap().contract.nullable)
        _ => fail("expected object")
      }
    }
    _ => fail("expected array")
  }
  let keys = @relation_nest.keys(v)
  ignore(keys.pop())
  assert_eq(@relation_nest.keys(v).length(), 2)
  let u = @relation_nest.usage(v)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
  }
  assert_true(
    @relation_nest.check(body, schema(), schema(), None, exact) is Ok(_),
  )
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
    ] {
    assert_true(
      @relation_nest.check(body, schema(), schema(), None, l) is Err(_),
    )
  }
}

///|
test "nest rejects nonflat payload names and empty closed syntax" {
  for
    tail in [
      "\"fields\":[]", "\"fields\":[\"right.amount\"]", "\"fields\":[\"id\",\"id\"]",
      "\"fields\":[{\"from\":\"id\",\"to\":\"x\"}]", "\"fields\":[\"id\"],\"order_by\":[]",
      "\"fields\":[\"id\"],\"max_items\":0", "\"fields\":[\"id\"],\"extra\":true",
    ] {
    let body = cursor(
      "{\"with\":\"c\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\"," +
      tail +
      "}",
    )
    assert_true(
      @relation_nest.check(body, schema(), schema(), None, limits()) is Err(_),
    )
  }
}
