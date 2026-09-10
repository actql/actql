///|
fn unary(op : @pipeline_typing.CheckedOperation) -> @relation.CheckedOperation {
  match op {
    Unary(v) => v
    _ => abort("expected unary test operation")
  }
}

///|
fn limits() -> @pipeline_typing.Limits {
  {
    max_steps: 20000,
    max_work: 20000000,
    max_text_bytes: 20000000,
    max_nodes: 1000000,
    max_tokens: 1000000,
    max_depth: 30000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 20000000, max_nodes: 1000000, max_depth: 40000, },
      source_path="pipeline.aql",
    ).unwrap(),
    {
      max_nodes: 1000000,
      max_depth: 40000,
      max_string_bytes: 20000000,
      max_total_string_bytes: 20000000,
    },
  ).unwrap()
}

///|
fn row() -> @contract.Contract {
  @contract.object_contract(
    [
      ("amount", @contract.primitive(NumberType, nullable=false)),
      ("id", @contract.primitive(StringType, nullable=false)),
      ("flag", @contract.primitive(BooleanType, nullable=true)),
    ],
    nullable=false,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
}

///|
fn schema() -> @schema.Schema {
  @schema.from_object(row()).unwrap()
}

///|
test "qualified schemas are admitted without implicit current selection" {
  let qualified = @schema.from_fields(
    [(Qualified(Left, "id"), @contract.primitive(StringType, nullable=false))],
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  for
    inputs in [
      [("joined", qualified)],
      [("rows", schema()), ("joined", qualified)],
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor("[]"),
        inputs,
        None,
        Some(cursor("\"joined\"")),
        limits(),
      )
      is Ok(_),
    )
  }
  assert_true(
    @pipeline_typing.check(
      cursor("[]"),
      [("rows", schema()), ("joined", qualified)],
      None,
      Some(cursor("\"rows\"")),
      limits(),
    )
    is Ok(_),
  )
}

///|
fn check(text : String) -> @pipeline_typing.CheckedPipeline raise {
  match
    @pipeline_typing.check(
      cursor(text),
      [("rows", schema())],
      None,
      None,
      limits(),
    ) {
    Ok(v) => v
    Err(e) => fail(@debug.to_string(e.kind))
  }
}

///|
test "linear steps and explicit branches retain exact sources and old schemas" {
  let p = check(
    "[{\"derive\":[{\"amount\":\"to_string(amount)\"}],\"as\":\"text\"},{\"select\":[\"id\"],\"from\":\"rows\"},{\"filter\":\"amount = '1'\",\"from\":\"text\",\"as\":\"result\"}]",
  )
  assert_eq(@pipeline_typing.step_count(p), 3)
  assert_eq(@pipeline_typing.step_at(p, 0).unwrap().input, Input(0))
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().input, Input(0))
  assert_eq(@pipeline_typing.step_at(p, 2).unwrap().input, Step(0))
  assert_eq(@pipeline_typing.current(p), Step(2))
  assert_eq(@pipeline_typing.lookup(p, "rows"), Some(Input(0)))
  assert_eq(@pipeline_typing.lookup(p, "result"), Some(Step(2)))
  assert_eq(@pipeline_typing.lookup(p, "1"), None)
  assert_eq(@pipeline_typing.step_at(p, 1).unwrap().binding_name, None)
  assert_true(@pipeline_typing.step_at(p, -1) is None)
  assert_true(@pipeline_typing.step_at(p, 3) is None)
  let inputs = @pipeline_typing.inputs(p)
  inputs.clear()
  assert_eq(@pipeline_typing.inputs(p).length(), 1)
  assert_true(
    @contract.type_equal(
      @schema.as_object(@pipeline_typing.inputs(p)[0].1).unwrap(),
      row(),
      100,
    ),
  )
  let linear = check(
    "[{\"derive\":{\"tax\":\"amount * 0.1\"}},{\"select\":[\"tax\"]}]",
  )
  assert_eq(@pipeline_typing.step_at(linear, 1).unwrap().input, Step(0))
  assert_eq(
    @relation.projection(
      unary(@pipeline_typing.step_at(linear, 1).unwrap().operation),
    )[0].output,
    @schema.Unqualified("tax"),
  )
}

///|
test "initial selection is explicit or uniquely materialized and never declaration order" {
  let inputs = [("a", schema()), ("b", schema())]
  for source in ["[]", "[{\"derive\":{}}]"] {
    assert_true(
      @pipeline_typing.check(cursor(source), inputs, None, None, limits())
      is Err({ kind: MissingCurrent, .. }),
    )
  }
  let empty = @pipeline_typing.check(
    cursor("[]"),
    inputs,
    None,
    Some(cursor("\"b\"")),
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.current(empty), Input(1))
  let selected = @pipeline_typing.check(
    cursor("[{\"derive\":{},\"from\":\"b\"},{\"drop\":[]}]"),
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.step_at(selected, 0).unwrap().input, Input(1))
  assert_eq(@pipeline_typing.step_at(selected, 1).unwrap().input, Step(0))
  assert_true(
    @pipeline_typing.check(cursor("[]"), [], None, None, limits())
    is Err({ kind: MissingCurrent, .. }),
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[]"),
      inputs,
      None,
      Some(cursor("\"later\"")),
      limits(),
    )
    is Err({ kind: UnknownName("later"), .. }),
  )
}

///|
test "closed envelopes reject unknown operations and unavailable or duplicate names" {
  for
    source in [
      "[{}]", "[null]", "[1]", "[{\"derive\":{},\"drop\":[]}]", "[{\"meta\":{\"x\":1}}]",
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(source),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
  for
    source in [
      "[{\"derive\":{},\"as\":\"rows\"}]", "[{\"derive\":{},\"as\":\"x\"},{\"drop\":[],\"as\":\"x\"}]",
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(source),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err({ kind: DuplicateName(_), .. }),
    )
  }
  for
    source in [
      "[{\"derive\":{},\"from\":\"x\",\"as\":\"x\"}]", "[{\"derive\":{},\"from\":\"x\"},{\"drop\":[],\"as\":\"x\"}]",
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(source),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err({ kind: UnknownName("x"), .. }),
    )
  }
  for
    source in [
      "[{\"values\":[],\"as\":\"v\"}]", "[{\"window_group\":{}}]", "[{\"search_candidates\":{}}]",
    ] {
    assert_true(
      @pipeline_typing.check(cursor(source), [], None, None, limits())
      is Err({ kind: UnsupportedOperation(_), .. }),
    )
  }
  for
    source in [
      "[{\"derive\":{},\"from\":null}]", "[{\"derive\":{},\"as\":null}]",
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(source),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
}

///|
test "metadata is retained and constrained without changing connections or schemas" {
  let p = check(
    "[{\"derive\":{},\"as\":\"x\",\"meta\":{\"custom\":[null,true,{\"actql_note\":42}]}}]",
  )
  let s = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(s.metadata is Some(_))
  assert_eq(@decode.cursor_path(s.metadata.unwrap()), [Index(0), Key("meta")])
  assert_true(
    @contract.type_equal(
      @schema.as_object(@pipeline_typing.output_schema(p)).unwrap(),
      row(),
      100,
    ),
  )
  for meta in ["null", "[]", "{}", "1"] {
    assert_true(
      @pipeline_typing.check(
        cursor("[{\"derive\":{},\"meta\":" + meta + "}]"),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err({ kind: InvalidMetadata, .. }),
    )
  }
  let e = @pipeline_typing.check(
    cursor("[{\"derive\":{},\"meta\":{\"actql_reserved\":1}}]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_true(e.kind is ReservedMetadataKey("actql_reserved"))
  assert_eq(e.path, [Index(0), Key("meta"), Key("actql_reserved")])
}

///|
test "nested and mixed expression diagnostics survive pipeline wrapping" {
  let source = cursor(
    "[{\"derive\":{\"x\":{\"add\":[\"amount\",\"len('😀') + missing\"]}}}]",
  )
  let e = @pipeline_typing.check(
    source,
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_true(e.kind is Operation(UnknownField("missing")))
  assert_eq(e.path, [Index(0), Key("derive"), Key("x"), Key("add"), Index(1)])
  assert_eq(e.span.source_path, "pipeline.aql")
  assert_eq(e.range, Some({ start: 11, end: 18, }))
}

///|
test "budgets cover the whole pipeline including metadata and empty input selection" {
  let source = cursor(
    "[{\"derive\":{\"x\":\"amount + 1\"},\"meta\":{\"x\":[1,2]}},{\"derive\":{\"y\":\"x + 1\"}}]",
  )
  let inputs = [("rows", schema())]
  let p = @pipeline_typing.check(source, inputs, None, None, limits()).unwrap()
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_steps: 2,
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check(source, inputs, None, None, exact) is Ok(_),
  )
  for
    l in [
      { ..exact, max_steps: 1, },
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_tokens: u.tokens - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(@pipeline_typing.check(source, inputs, None, None, l) is Err(_))
  }
  let empty = @pipeline_typing.check(cursor("[]"), inputs, None, None, limits()).unwrap()
  let cost = @pipeline_typing.usage(empty)
  assert_true(cost.work > 0 && cost.text_bytes > 0)
  assert_true(
    @pipeline_typing.check(cursor("[]"), inputs, None, None, {
      ..limits(),
      max_work: cost.work - 1,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  for
    l in [
      { ..limits(), max_steps: -1, },
      { ..limits(), max_work: -1, },
      { ..limits(), max_nodes: -1, },
      { ..limits(), max_text_bytes: -1, },
      { ..limits(), max_tokens: -1, },
      { ..limits(), max_depth: -1, },
    ] {
    assert_true(
      @pipeline_typing.check(cursor("[]"), inputs, None, None, l)
      is Err({ kind: InvalidLimits, .. }),
    )
  }
}

///|
test "unused inputs and parameter declarations are still preflighted" {
  let invalid = @contract.with_nullability(row(), true)
  assert_true(@schema.from_object(invalid) is Err(InvalidRowContract))
  assert_true(
    @pipeline_typing.check(
      cursor("[]"),
      [("a", schema()), ("a", schema())],
      None,
      None,
      limits(),
    )
    is Err({ kind: DuplicateName("a"), .. }),
  )
  assert_true(
    @pipeline_typing.check(cursor("[]"), [("", schema())], None, None, limits())
    is Err({ kind: InvalidName(""), .. }),
  )
  let mut deep = row()
  for _ in 0..<100 {
    deep = @contract.array_contract(deep, nullable=false).unwrap()
  }
  let wide = @contract.object_contract(
    [("deep", deep)],
    nullable=false,
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  assert_true(
    @pipeline_typing.check(
      cursor("[]"),
      [("a", schema()), ("b", @schema.from_object(wide).unwrap())],
      None,
      Some(cursor("\"a\"")),
      { ..limits(), max_depth: 10, },
    )
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "parameter declarations are retained without binding defaults or narrowing nullability" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"p\":{\"type\":\"string\",\"nullable\":true,\"default\":\"(\"}}",
      ),
    ),
    {
      max_parameters: 100,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let source = cursor("[{\"derive\":{\"matched\":\"regex_match(id, $p)\"}}]")
  let supplied = [("rows", schema())]
  let p = @pipeline_typing.check(
    source,
    supplied,
    Some(declarations),
    None,
    limits(),
  ).unwrap()
  supplied.clear()
  assert_eq(@pipeline_typing.inputs(p).length(), 1)
  assert_eq(
    @parameter.declaration_count(@pipeline_typing.parameters(p).unwrap()),
    1,
  )
  let b = @relation.binding_at(
    unary(@pipeline_typing.step_at(p, 0).unwrap().operation),
    0,
  ).unwrap()
  assert_true(@typing.result_type(b.expression).nullable)
  assert_true(
    @typing.pending_validations(b.expression).any(o => {
      o.kind is PatternValidation("regex_match")
    }),
  )
  let empty = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    Some(declarations),
    None,
    limits(),
  ).unwrap()
  let plain = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.usage(empty).work > @pipeline_typing.usage(plain).work,
  )
  assert_true(
    @pipeline_typing.usage(empty).text_bytes >
    @pipeline_typing.usage(plain).text_bytes,
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[]"),
      [("rows", schema())],
      Some(declarations),
      None,
      { ..limits(), max_work: @pipeline_typing.usage(plain).work, },
    )
    is Err(_),
  )
}

///|
test "empty schemas and metadata depth keep their own admission boundaries" {
  let empty = @contract.object_contract(
    [],
    nullable=false,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let p = @pipeline_typing.check(
    cursor("[]"),
    [("empty", @schema.from_object(empty).unwrap())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(@pipeline_typing.current(p), Input(0))
  assert_true(@pipeline_typing.initial_from(p) is None)
  let selected = cursor("\"empty\"")
  let p = @pipeline_typing.check(
    cursor("[]"),
    [("empty", @schema.from_object(empty).unwrap())],
    None,
    Some(selected),
    limits(),
  ).unwrap()
  assert_eq(
    @decode.cursor_span(@pipeline_typing.initial_from(p).unwrap()),
    @decode.cursor_span(selected),
  )
  let body = cursor("[{\"derive\":{},\"meta\":{\"x\":{\"y\":[1]}}}]")
  assert_true(
    @pipeline_typing.check(
      body,
      [("empty", @schema.from_object(empty).unwrap())],
      None,
      None,
      { ..limits(), max_depth: 3, },
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check(
      body,
      [("empty", @schema.from_object(empty).unwrap())],
      None,
      None,
      { ..limits(), max_depth: 2, },
    )
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "unselected branches retain pending expression obligations" {
  let p = check(
    "[{\"derive\":{\"test\":\"if(TRUE, TRUE, regex_match(id, '('))\"}},{\"select\":[\"id\"]}]",
  )
  let op = unary(@pipeline_typing.step_at(p, 0).unwrap().operation)
  let expression = @relation.binding_at(op, 0).unwrap().expression
  assert_true(
    @typing.pending_validations(expression).any(o => {
      o.kind is PatternValidation("regex_match")
    }),
  )
  assert_true(
    @typing.pending_validations(expression).any(o => o.kind is HostEnvelope),
  )
}

///|
test "long linear pipelines preserve references without recursive checking" {
  let parts : Array[String] = []
  for _ in 0..<3000 {
    parts.push("{\"derive\":{}}")
  }
  let p = check("[" + parts.join(",") + "]")
  assert_eq(@pipeline_typing.current(p), Step(2999))
  assert_eq(@pipeline_typing.step_at(p, 2999).unwrap().input, Step(2998))
  assert_true(
    @contract.type_equal(
      @schema.as_object(@pipeline_typing.output_schema(p)).unwrap(),
      row(),
      100,
    ),
  )
}
