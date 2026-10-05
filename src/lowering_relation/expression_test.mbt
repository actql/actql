///|
fn expression_limits() -> @lowering_relation.ExpressionLimits {
  {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }
}

///|
fn expression_pipeline(tail : String) -> @lowering_relation.BoundPrepared {
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked(tail), limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn vector_expression_pipeline(
  expression : String,
  admit? : Bool = true,
) -> @lowering_relation.BoundPrepared {
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("left"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
        (
          @schema.Unqualified("right"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=9,
    ).unwrap(),
  )
  let checked = @pipeline.check_carriers(
    cursor("[{\"from\":\"rows\",\"derive\":[{\"score\":" + expression + "}]}]"),
    [("rows", rows)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
    expression_profiles={ text_time: false, veca: admit, },
  ).unwrap()
}

///|
fn expression_wire(expr : @lowering_relation.Expression) -> String raise {
  let writer = @encode.writer(100000, 10000, 1000)
  @lowering_relation.emit_expression(expr, writer)
  @encode.finish(writer)
}

///|
test "deep normalized expression lowering and emission use explicit stacks" {
  let mut expr = "{\"literal\":1}"
  for _i = 0; _i < 512; _i = _i + 1 {
    expr = "{\"negate\":" + expr + "}"
  }
  let p = expression_pipeline(",{\"derive\":{\"v\":" + expr + "}}")
  let lowered = @lowering_relation.lower_expression(p, 1, 0, {
    ..expression_limits(),
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 600,
  }).unwrap()
  let writer = @encode.writer(100000, 10000, 1500)
  @lowering_relation.emit_expression(lowered, writer)
  let wire = @encode.finish(writer)
  let mut expected = "{\"body\":1,\"op\":\"literal\"}"
  for _i = 0; _i < 512; _i = _i + 1 {
    expected = "{\"body\":" + expected + ",\"op\":\"negate\"}"
  }
  assert_eq(wire, expected)
}

///|
test "all basic binary node spellings match the normative expression contract" {
  for
    tag in [
      "add", "subtract", "multiply", "divide", "modulo", "eq", "neq", "lt", "lte",
      "gt", "gte", "nullif",
    ] {
    let p = expression_pipeline(
      ",{\"derive\":{\"v\":{\"" +
      tag +
      "\":[{\"literal\":1},{\"literal\":2}]}}}",
    )
    let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
    assert_eq(
      expression_wire(expr),
      "{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"" +
      tag +
      "\"}",
    )
  }
  for tag in ["not", "is_null", "not_null", "is_true", "is_false", "is_unknown"] {
    let p = expression_pipeline(
      ",{\"derive\":{\"v\":{\"" + tag + "\":{\"literal\":true}}}}",
    )
    let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
    assert_eq(
      expression_wire(expr),
      "{\"body\":{\"body\":true,\"op\":\"literal\"},\"op\":\"" + tag + "\"}",
    )
  }
  let p = expression_pipeline(",{\"derive\":{\"v\":\"-id\"}}")
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"body\":\"id\",\"op\":\"field\"},\"op\":\"negate\"}",
  )
}

///|
test "vector score lowering retains metric and object child paths" {
  let owner = vector_expression_pipeline(
    "{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}}",
  )
  let expr = match
    @lowering_relation.lower_expression(owner, 0, 0, expression_limits()) {
    Ok(value) => value
    Err(issue) => {
      debug_inspect(issue.kind, content="vector score lowering")
      fail("vector score lowering")
    }
  }
  guard @lowering_relation.expression_body(expr)
    is @lowering_relation.VectorScore(@lowering_relation.Dot, left, right) else {
    fail("expected vector score")
  }
  assert_true(
    @lowering_relation.expression_body(left)
    is @lowering_relation.Field("left", @relation.InputField(_)),
  )
  assert_true(
    @lowering_relation.expression_body(right)
    is @lowering_relation.Field("right", @relation.InputField(_)),
  )
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"left\":{\"body\":\"left\",\"op\":\"field\"},\"metric\":\"dot\",\"right\":{\"body\":\"right\",\"op\":\"field\"}},\"op\":\"vector_score\"}",
  )
}

///|
test "vector score lowering requires explicit VecA profile admission" {
  let owner = vector_expression_pipeline(
    "{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}}",
    admit=false,
  )
  guard @lowering_relation.lower_expression(owner, 0, 0, expression_limits())
    is Err(issue) else {
    fail("missing VecA profile was accepted")
  }
  assert_eq(
    issue.kind,
    @lowering_relation.PendingValidation(
      @typing.ProfileAdmission("actql-veca/0.1"),
    ),
  )
}

///|
test "vector concat lowering preserves ordered children and canonical wire" {
  let owner = vector_expression_pipeline(
    "{\"vector_concat\":[{\"field\":\"right\"},{\"field\":\"left\"}]}",
  )
  let expr = @lowering_relation.lower_expression(
    owner,
    0,
    0,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.expression_body(expr)
    is @lowering_relation.VectorConcat(children) else {
    fail("expected vector concat")
  }
  assert_eq(children.length(), 2)
  assert_true(
    @lowering_relation.expression_body(children[0])
    is @lowering_relation.Field("right", @relation.InputField(_)),
  )
  assert_true(
    @lowering_relation.expression_body(children[1])
    is @lowering_relation.Field("left", @relation.InputField(_)),
  )
  assert_eq(
    expression_wire(expr),
    "{\"body\":[{\"body\":\"right\",\"op\":\"field\"},{\"body\":\"left\",\"op\":\"field\"}],\"op\":\"vector_concat\"}",
  )
}

///|
test "fixed expression wire vector retains failed constants inside unselected if branch" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"if\":[{\"literal\":true},{\"literal\":7},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":[{\"body\":true,\"op\":\"literal\"},{\"body\":7,\"op\":\"literal\"},{\"body\":[{\"body\":1,\"op\":\"literal\"},{\"body\":0,\"op\":\"literal\"}],\"op\":\"divide\"}],\"op\":\"if\"}",
  )
}

///|
test "bound parameter becomes a typed literal without author source replacement" {
  let d = declarations()
  let p = @lowering_relation.bind_parameters(
    prepared_with(d, tail=",{\"derive\":{\"v\":{\"$param\":\"amount\"}}}"),
    Some(bound(d)),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(expression_wire(expr), "{\"body\":7,\"op\":\"literal\"}")
  let source = @lowering_relation.expression_source(expr)
  assert_eq(@decode.field_at(source, 0).unwrap().0, "$param")
}

///|
test "typed NULL wire uses checker contract and exact output byte budget" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"add\":[{\"literal\":null},{\"literal\":1}]}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  guard @lowering_relation.expression_body(expr)
    is @lowering_relation.Binary(_, null, _) else {
    fail("expected binary")
  }
  let expected = "{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"}"
  assert_eq(expression_wire(null), expected)
  let exact = @encode.writer(expected.length(), 100, 10)
  @lowering_relation.emit_expression(null, exact)
  assert_eq(@encode.finish(exact), expected)
  let short = @encode.writer(expected.length() - 1, 100, 10)
  let exceeded = try {
    @lowering_relation.emit_expression(null, short)
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(exceeded)
}

///|
test "missing CASE ELSE uses the synthetic checked nullable contract" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":1}}]}}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"else\":{\"body\":{\"contract\":{\"nullable\":true,\"type\":\"number\"}},\"op\":\"typed_null\"},\"when\":[{\"then\":{\"body\":1,\"op\":\"literal\"},\"when\":{\"body\":true,\"op\":\"literal\"}}]},\"op\":\"case\"}",
  )
}

///|
test "literal objects are opaque business data and normalized text expressions retain source range" {
  let p = expression_pipeline(
    ",{\"derive\":{\"data\":{\"literal\":{\"$param\":\"business-name\"}}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":{\"$param\":\"business-name\"},\"op\":\"literal\"}",
  )
  let text = expression_pipeline(",{\"derive\":{\"v\":\"id + 2\"}}")
  let expr = @lowering_relation.lower_expression(
    text,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expr),
    "{\"body\":[{\"body\":\"id\",\"op\":\"field\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"add\"}",
  )
  assert_true(@lowering_relation.expression_location(expr).range is Some(_))
}

///|
test "many expression accessors cannot expose internal child arrays" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"coalesce\":[{\"literal\":1},{\"literal\":2}]}}}",
  )
  let expr = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  let before = expression_wire(expr)
  guard @lowering_relation.expression_body(expr)
    is @lowering_relation.Many(_, children) else {
    fail("expected coalesce")
  }
  children.clear()
  assert_eq(expression_wire(expr), before)
}

///|
test "expression lowering consumes checked conditional null and field annotations" {
  let p = expression_pipeline(
    ",{\"derive\":{\"result\":{\"if\":[{\"gt\":[{\"field\":\"id\"},{\"literal\":0}]},{\"add\":[{\"field\":\"id\"},{\"literal\":2}]},{\"literal\":null}]}}}",
  )
  let result = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  guard @lowering_relation.expression_body(result)
    is @lowering_relation.Conditional(condition, yes, no) else {
    fail("expected if node")
  }
  assert_true(
    @lowering_relation.expression_body(condition)
    is @lowering_relation.Binary(@lowering_relation.Greater, _, _),
  )
  guard @lowering_relation.expression_body(yes)
    is @lowering_relation.Binary(@lowering_relation.Add, left, right) else {
    fail("expected add")
  }
  assert_true(
    @lowering_relation.expression_body(left)
    is @lowering_relation.Field("id", @relation.InputField(_)),
  )
  assert_true(
    @lowering_relation.expression_body(right) is @lowering_relation.Literal(_),
  )
  assert_true(
    @lowering_relation.expression_body(no) is @lowering_relation.TypedNull,
  )
  assert_true(@lowering_relation.expression_contract(no).nullable)
  assert_true(
    @lowering_relation.expression_contract(no).shape is @contract.Number,
  )
}

///|
test "derive array references retain the exact prior slot rather than re-resolving names" {
  let p = expression_pipeline(
    ",{\"derive\":[{\"original\":{\"field\":\"id\"}},{\"id\":{\"literal\":9}},{\"next\":{\"field\":\"id\"}}]}",
  )
  let first = @lowering_relation.lower_expression(p, 1, 0, expression_limits()).unwrap()
  let last = @lowering_relation.lower_expression(p, 1, 2, expression_limits()).unwrap()
  assert_true(
    @lowering_relation.expression_body(first)
    is @lowering_relation.Field("id", @relation.InputField(_)),
  )
  assert_true(
    @lowering_relation.expression_body(last)
    is @lowering_relation.Field("id", @relation.PriorSlot(1)),
  )
}

///|
test "expression budget and unsupported handlers are explicit implementation failures" {
  let p = expression_pipeline(
    ",{\"derive\":{\"v\":{\"add\":[{\"literal\":1},{\"literal\":2}]}}}",
  )
  for
    cap in [
      { ..expression_limits(), max_nodes: 2, },
      { ..expression_limits(), max_work: 1, },
      { ..expression_limits(), max_depth: 0, },
      { ..expression_limits(), max_literal_nodes: 1, },
    ] {
    guard @lowering_relation.lower_expression(p, 1, 0, cap) is Err(issue) else {
      fail("budget not enforced")
    }
    assert_eq(issue.kind, @lowering_relation.ExpressionBudgetExceeded)
  }
  let extra = expression_pipeline(
    ",{\"derive\":{\"v\":{\"between\":[{\"literal\":1},{\"literal\":0},{\"literal\":2}]}}}",
  )
  guard @lowering_relation.lower_expression(extra, 1, 0, expression_limits())
    is Err(issue) else {
    fail("between handler not implemented yet")
  }
  assert_eq(issue.kind, @lowering_relation.ExpressionNotImplemented("between"))
}

///|
test "membership lowers typed scalar holes into one ordered literal array" {
  let d = declarations()
  for tag in ["in", "not_in"] {
    let owner = @lowering_relation.bind_parameters(
      prepared_with(
        d,
        tail=",{\"derive\":{\"v\":{\"" +
          tag +
          "\":[{\"field\":\"id\"},{\"literal\":[{\"$param\":\"amount\"},null,-2,{\"$param\":\"amount\"}]}]}}}",
      ),
      Some(bound(d)),
      max_parameters=1,
      max_name_bytes=6,
    ).unwrap()
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"id\",\"op\":\"field\"},{\"body\":[7,null,-2,7],\"op\":\"literal\"}],\"op\":\"" +
      tag +
      "\"}",
    )
    assert_true(
      @lowering_relation.expression_body(expression)
      is @lowering_relation.Binary(_, _, _),
    )
    for
      cap in [
        { ..expression_limits(), max_nodes: 6, },
        { ..expression_limits(), max_literal_nodes: 4, },
        { ..expression_limits(), max_depth: 1, },
      ] {
      assert_true(
        @lowering_relation.lower_expression(owner, 1, 0, cap)
        is Err({ kind: @lowering_relation.ExpressionBudgetExceeded, .. }),
      )
    }
  }
}
