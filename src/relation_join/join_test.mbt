///|
test "guard parameters retain declarations without reading defaults or claiming a bound" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":5},\"nullable\":{\"type\":\"number\",\"nullable\":true},\"text\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 100,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"max_output_rows\":{\"$param\":\"cap\"}}",
  )
  let j = @relation_join.check(body, row(), row(), Some(declarations), limits()).unwrap()
  assert_eq(@relation_join.output_guard(j), Some(Parameter("cap")))
  assert_true(
    indexed_obligation_copy(
      @relation_join.pending_validations(j),
      @relation_join.pending_validation_count(j),
      i => @relation_join.pending_validation_at(j, i),
      (a, b) => a == b,
    ).contains(BindGuard("cap")),
  )
  assert_true(
    indexed_obligation_copy(
      @relation_join.pending_validations(j),
      @relation_join.pending_validation_count(j),
      i => @relation_join.pending_validation_at(j, i),
      (a, b) => a == b,
    ).contains(ResolveOutputLimit),
  )
  for name in ["text", "missing"] {
    let body = cursor(
      "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"max_output_rows\":{\"$param\":\"" +
      name +
      "\"}}",
    )
    assert_true(
      @relation_join.check(body, row(), row(), Some(declarations), limits())
      is Err(_),
    )
  }
  let nullable_body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"max_output_rows\":{\"$param\":\"nullable\"}}",
  )
  let nullable_guard = @relation_join.check(
    nullable_body,
    row(),
    row(),
    Some(declarations),
    limits(),
  ).unwrap()
  assert_true(
    indexed_obligation_copy(
      @relation_join.pending_validations(nullable_guard),
      @relation_join.pending_validation_count(nullable_guard),
      i => @relation_join.pending_validation_at(nullable_guard, i),
      (a, b) => a == b,
    ).contains(BindGuard("nullable")),
  )
}

///|
test "repeated key components with different peers and independent source types are retained" {
  let left = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let right = @schema.from_fields(
    [
      (Unqualified("a"), @contract.primitive(NumberType, nullable=true)),
      (Unqualified("b"), @contract.primitive(NumberType, nullable=false)),
    ],
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"b\"},{\"left\":\"id\",\"right\":\"a\"},{\"left\":\"id\",\"right\":\"b\"}]}",
  )
  let j = @relation_join.check(body, left, right, None, limits()).unwrap()
  assert_eq(@relation_join.keys(j).map(k => k.right), [
    @schema.Unqualified("b"),
    Unqualified("a"),
    Unqualified("b"),
  ])
  assert_eq(@schema.fields(@relation_join.output_schema(j)).map(f => f.name), [
    @schema.Qualified(Left, "id"),
    Qualified(Right, "a"),
    Qualified(Right, "b"),
  ])
}

///|
test "key domains follow KeyComparable including references and unequal decimal domains" {
  for
    (body, allowed) in [
      (
        "{\"type\":\"resource_ref\",\"resource_kind\":\"Customer\",\"nullable\":false}",
        true,
      ),
      ("{\"type\":\"artifact_ref\",\"nullable\":true}", true),
      ("{\"type\":\"date\",\"nullable\":false}", true),
      ("{\"type\":\"timestamp\",\"nullable\":false}", true),
      ("{\"type\":\"boolean\",\"nullable\":false}", true),
      ("{\"type\":\"json\",\"nullable\":false}", false),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
        false,
      ),
      ("{\"type\":\"object\",\"nullable\":false,\"fields\":{}}", false),
      ("{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2}", false),
    ] {
    let c = @contract.read_author(cursor(body), {
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    let schema = @schema.from_fields(
      [(Unqualified("id"), c)],
      max_fields=1,
      max_name_bytes=2,
    ).unwrap()
    let result = @relation_join.check(
      cursor("{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"}"),
      schema,
      schema,
      None,
      limits(),
    )
    assert_eq(result is Ok(_), allowed)
  }
}

///|
test "unselected deep contracts and wide repeated keys consume finite budgets" {
  let mut child = @contract.primitive(NumberType, nullable=false)
  for _ in 0..<10000 {
    child = @contract.array_contract(child, nullable=false).unwrap()
  }
  let schema = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("deep"), child),
    ],
    max_fields=2,
    max_name_bytes=6,
  ).unwrap()
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"id\":\"left.id\"}}",
  )
  assert_true(
    @relation_join.check(body, schema, row(), None, limits()) is Ok(_),
  )
  assert_true(
    @relation_join.check(body, schema, row(), None, {
      ..limits(),
      max_depth: 100,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  let pairs = Array::make(10000, "\"id\"").join(",")
  let wide = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":[" + pairs + "]}",
  )
  let j = @relation_join.check(wide, row(), row(), None, limits()).unwrap()
  assert_eq(@relation_join.keys(j).length(), 10000)
  assert_true(
    @relation_join.check(wide, row(), row(), None, {
      ..limits(),
      max_work: 100,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 2000000,
      max_nodes: 200000,
      max_depth: 20000,
    }).unwrap(),
    {
      max_nodes: 200000,
      max_depth: 20000,
      max_string_bytes: 2000000,
      max_total_string_bytes: 2000000,
    },
  ).unwrap()
}

///|
fn limits() -> @relation_join.Limits {
  {
    max_work: 2000000,
    max_text_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 20000,
  }
}

///|
fn row() -> @schema.Schema {
  @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("value"), @contract.primitive(StringType, nullable=true)),
    ],
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
}

///|
fn checked(kind : String, extra? : String = "") -> @relation_join.CheckedJoin {
  @relation_join.check(
    cursor(
      "{\"with\":\"r\",\"kind\":\"" + kind + "\",\"on\":\"id\"" + extra + "}",
    ),
    row(),
    row(),
    None,
    limits(),
  ).unwrap()
}

///|
test "all join kinds qualify output fields and extend only absent sides" {
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let j = checked(kind)
    let output = @relation_join.output_schema(j)
    assert_eq(
      @schema.lookup(output, Qualified(Left, "id")).unwrap().nullable,
      kind == "full",
    )
    assert_true(@schema.lookup(output, Unqualified("id")) is None)
    assert_true(@schema.as_object(output) is None)
    if kind == "semi" || kind == "anti" {
      assert_eq(@schema.field_count(output), 2)
      assert_true(@schema.lookup(output, Qualified(Right, "id")) is None)
    } else {
      assert_eq(@schema.field_count(output), 4)
      assert_eq(
        @schema.lookup(output, Qualified(Right, "id")).unwrap().nullable,
        kind != "inner",
      )
    }
    assert_eq(@relation_join.null_key(j), NoMatch)
  }
}

///|
test "projection is nonempty canonical and permits multiple aliases of one field" {
  let j = checked(
    "left",
    extra=",\"select\":{\"z\":\"left.id\",\"a\":\"left.id\",\"r\":\"right.id\"}",
  )
  let p = @relation_join.projection(j).unwrap()
  assert_eq(p.map(x => @schema.reference_name(x.output)), ["a", "r", "z"])
  assert_eq(p[0].input, @schema.Qualified(Left, "id"))
  assert_eq(p[2].input, p[0].input)
  assert_true(@schema.as_object(@relation_join.output_schema(j)) is Some(_))
  p.clear()
  assert_eq(@relation_join.projection(j).unwrap().length(), 3)
  for
    body in [
      "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{}}", "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"x\":\"id\"}}",
      "{\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\",\"select\":{\"x\":\"right.id\"}}",
      "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"x.y\":\"left.id\"}}",
    ] {
    assert_true(
      @relation_join.check(cursor(body), row(), row(), None, limits()) is Err(_),
    )
  }
}

///|
test "repeated equality pairs are retained and key comparability is typed" {
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":[\"id\",{\"left\":\"id\",\"right\":\"id\"},\"id\"]}",
  )
  let j = @relation_join.check(body, row(), row(), None, limits()).unwrap()
  assert_eq(@relation_join.keys(j).length(), 3)
  @relation_join.keys(j).clear()
  assert_eq(@relation_join.keys(j).length(), 3)
  let decimal = fn(p, s) {
    @schema.from_fields(
      [
        (
          Unqualified("id"),
          @contract.decimal_contract(p, s, nullable=true).unwrap(),
        ),
      ],
      max_fields=1,
      max_name_bytes=2,
    ).unwrap()
  }
  assert_true(
    @relation_join.check(body, decimal(8, 2), decimal(20, 7), None, limits())
    is Ok(_),
  )
  assert_true(
    @relation_join.check(body, decimal(8, 2), row(), None, limits())
    is Err({ kind: IncomparableKeys("id", "id"), .. }),
  )
  for
    on in [
      "[]", "[[\"id\"]]", "null", "{\"left\":\"id\",\"right\":\"value\"}", "{\"left\":\"id\"}",
    ] {
    assert_true(
      @relation_join.check(
        cursor("{\"with\":\"r\",\"kind\":\"inner\",\"on\":" + on + "}"),
        row(),
        row(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "assertions guards null checks and full identity remain unproven obligations" {
  let j = checked(
    "full",
    extra=",\"cardinality\":\"one_to_one\",\"null_key\":\"fail\",\"max_output_rows\":9007199254740991",
  )
  let pending = indexed_obligation_copy(
    @relation_join.pending_validations(j),
    @relation_join.pending_validation_count(j),
    i => @relation_join.pending_validation_at(j, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(StableIdentity(@schema.Left)))
  assert_true(pending.contains(StableIdentity(@schema.Right)))
  assert_true(pending.contains(ValidateCardinality(OneToOne)))
  assert_true(pending.contains(RejectNullKeys))
  assert_true(pending.contains(ResolveOutputLimit))
  assert_eq(@relation_join.output_guard(j), Some(Literal(9007199254740991L)))
  pending.clear()
  assert_true(
    !indexed_obligation_copy(
      @relation_join.pending_validations(j),
      @relation_join.pending_validation_count(j),
      i => @relation_join.pending_validation_at(j, i),
      (a, b) => a == b,
    ).is_empty(),
  )
  for
    extra in [
      ",\"max_output_rows\":0", ",\"max_output_rows\":1.5", ",\"max_output_rows\":9007199254740992",
      ",\"cardinality\":\"many_to_many\"", ",\"null_key\":null",
    ] {
    assert_true(
      @relation_join.check(
        cursor("{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\"" + extra + "}"),
        row(),
        row(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "join budgets accept exact consumption and reject each smaller allowance" {
  let source = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"on\":[\"id\",\"id\"],\"select\":{\"a\":\"left.id\",\"b\":\"right.id\"}}",
  )
  let j = @relation_join.check(source, row(), row(), None, limits()).unwrap()
  let u = @relation_join.usage(j)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
  }
  assert_true(@relation_join.check(source, row(), row(), None, exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_join.check(source, row(), row(), None, l)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
