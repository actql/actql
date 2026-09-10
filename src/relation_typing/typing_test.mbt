///|
fn check_row(
  op : @relation_typing.Operation,
  body : @decode.Cursor,
  row : @contract.Contract,
  parameters : @parameter.Declarations?,
  limits : @relation_typing.Limits,
) -> Result[@relation_typing.CheckedOperation, @relation_typing.Issue] {
  @relation_typing.check(
    op,
    body,
    @schema.from_object(row).unwrap(),
    parameters,
    limits,
  )
}

///|
fn output_row(v : @relation_typing.CheckedOperation) -> @contract.Contract {
  @schema.as_object(@relation_typing.output_schema(v)).unwrap()
}

///|
fn input_row(v : @relation_typing.CheckedOperation) -> @contract.Contract {
  @schema.as_object(@relation_typing.input_schema(v)).unwrap()
}

///|
fn limits() -> @relation_typing.Limits {
  {
    max_work: 20000000,
    max_text_bytes: 20000000,
    max_nodes: 1000000,
    max_depth: 30000,
    max_tokens: 1000000,
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 20000000, max_nodes: 1000000, max_depth: 40000, },
      source_path="relation.aql",
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
fn schema(fields : String) -> @contract.Contract {
  @contract.read_author(
    cursor("{\"type\":\"object\",\"nullable\":false,\"fields\":" + fields + "}"),
    { max_nodes: 1000000, max_depth: 30000, max_text_bytes: 20000000, },
  ).unwrap()
}

///|
fn input() -> @contract.Contract {
  schema(
    "{\"amount\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"string\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":true}}",
  )
}

///|
fn checked(
  op : @relation_typing.Operation,
  body : String,
) -> @relation_typing.CheckedOperation raise {
  match check_row(op, cursor(body), input(), None, limits()) {
    Ok(v) => v
    Err(issue) => fail(@debug.to_string(issue.kind))
  }
}

///|
fn rejected(
  op : @relation_typing.Operation,
  body : String,
  kind : @relation_typing.IssueKind,
) -> Unit raise {
  match check_row(op, cursor(body), input(), None, limits()) {
    Ok(_) => fail("unexpected acceptance")
    Err(issue) => assert_eq(issue.kind, kind)
  }
}

///|
fn field(value : @contract.Contract, name : String) -> @contract.Contract {
  let fields = match value.shape {
    @contract.Object(fields) => fields
    _ => abort("test object")
  }
  for f in @contract.fields(fields) {
    if f.name == name {
      return f.contract
    }
  }
  abort("missing test field")
}

///|
fn corpus_accepted(
  op : @relation_typing.Operation,
  text : String,
  fields : String,
  expected : String,
  order : Array[String]?,
) -> Unit raise {
  let result = check_row(op, cursor(text), schema(fields), None, limits())
  match result {
    Err(issue) => fail(text + ": " + @debug.to_string(issue.kind))
    Ok(value) => {
      assert_true(
        @contract.type_equal(output_row(value), schema(expected), 1000000),
      )
      if order is Some(order) {
        assert_eq(
          @relation_typing.projection(value).map(p => {
            @schema.reference_name(p.output)
          }),
          order,
        )
      }
    }
  }
}

///|
fn corpus_rejected(
  op : @relation_typing.Operation,
  text : String,
  fields : String,
  expected : String,
) -> Unit raise {
  match check_row(op, cursor(text), schema(fields), None, limits()) {
    Ok(_) => fail("unexpected acceptance: " + text)
    Err(issue) => {
      let actual = match issue.kind {
        InvalidAggregate(_) => "InvalidAggregate"
        InvalidAggregateArgument(_) => "InvalidAggregateArgument"
        InvalidAggregateOption(_) => "InvalidAggregateOption"
        ForbiddenAggregateValue => "ForbiddenAggregateValue"
        InvalidOrder => "InvalidOrder"
        IncompatibleColumn(_) => "IncompatibleColumn"
        NotAuthorOrderable(_) => "NotAuthorOrderable"
        NotKeyComparable(_) => "NotKeyComparable"
        InvalidCount => "InvalidCount"
        UnknownParameter(_) => "UnknownParameter"
        ExpectedBoolean => "ExpectedBoolean"
        UnknownField(_) => "UnknownField"
        Expression(@typing.NullTypeUnresolved) => "NullTypeUnresolved"
        EmptyBody => "EmptyBody"
        InvalidBody => "InvalidBody"
        InputCollision(_) => "InputCollision"
        DuplicateOutput(_) => "DuplicateOutput"
        InvalidName(_) => "InvalidName"
        _ => @debug.to_string(issue.kind)
      }
      assert_eq(actual, expected)
    }
  }
}

///|
test "derive map uses only the snapshot and canonical binding order" {
  let result = checked(Derive, "{\"z\":\"amount + 2\",\"a\":\"amount + 1\"}")
  assert_eq(@relation_typing.form(result), DeriveMap)
  assert_eq(@relation_typing.binding_at(result, 0).unwrap().name, Some("a"))
  assert_eq(@relation_typing.binding_at(result, 1).unwrap().name, Some("z"))
  assert_true(field(output_row(result), "amount").shape is @contract.Number)
  assert_eq(
    @relation_typing.references(@relation_typing.binding_at(result, 0).unwrap())[0].target,
    InputField(@schema.Unqualified("amount")),
  )
  rejected(Derive, "{\"amount\":\"amount + 1\"}", InputCollision("amount"))
  rejected(Derive, "{\"a\":\"1\",\"b\":\"a + 1\"}", UnknownField("a"))
}

///|
test "ordered derive records exact value versions and replacement types" {
  let result = checked(
    Derive,
    "[{\"old\":\"amount\"},{\"amount\":\"to_string(amount)\"},{\"copy\":\"amount\"}]",
  )
  assert_eq(@relation_typing.form(result), DeriveArray)
  assert_true(field(output_row(result), "amount").shape is @contract.Text(_))
  assert_true(field(output_row(result), "old").shape is @contract.Number)
  assert_true(field(output_row(result), "copy").shape is @contract.Text(_))
  let first = @relation_typing.binding_at(result, 0).unwrap()
  let second = @relation_typing.binding_at(result, 1).unwrap()
  let third = @relation_typing.binding_at(result, 2).unwrap()
  assert_eq(
    @relation_typing.references(first)[0].target,
    InputField(@schema.Unqualified("amount")),
  )
  assert_eq(
    @relation_typing.references(second)[0].target,
    InputField(@schema.Unqualified("amount")),
  )
  assert_eq(@relation_typing.references(third)[0].target, PriorSlot(1))
  assert_eq(
    @syntax.location_path(
      @relation_typing.references(third)[0].occurrence.location,
    ),
    [@source.Index(2), @source.Key("copy")],
  )
  assert_true(
    @relation_typing.references(third)[0].occurrence.location.range is Some(_),
  )
  rejected(Derive, "[{\"x\":\"y\"},{\"y\":\"1\"}]", UnknownField("y"))
  rejected(Derive, "[{\"x\":\"x\"}]", UnknownField("x"))
  rejected(Derive, "[{\"x\":\"1\"},{\"x\":\"2\"}]", DuplicateOutput("x"))
  let future = checked(Derive, "[{\"x\":\"amount\"},{\"amount\":\"1\"}]")
  assert_eq(
    @relation_typing.references(@relation_typing.binding_at(future, 0).unwrap())[0].target,
    InputField(@schema.Unqualified("amount")),
  )
}

///|
test "field references include templates but exclude opaque data" {
  let result = checked(
    Derive,
    "[{\"x\":\"amount\"},{\"label\":{\"template\":\"{{skip}} {x} {amount} {x}\"}},{\"data\":{\"literal\":{\"field\":\"missing\"}}}]",
  )
  let refs = @relation_typing.references(
    @relation_typing.binding_at(result, 1).unwrap(),
  )
  assert_eq(refs.length(), 3)
  assert_eq(refs[0].target, PriorSlot(0))
  assert_eq(refs[1].target, InputField(@schema.Unqualified("amount")))
  assert_eq(refs[2].target, PriorSlot(0))
  assert_eq(
    @relation_typing.references(@relation_typing.binding_at(result, 2).unwrap()).length(),
    0,
  )
}

///|
test "filter preserves the input schema and pending obligations" {
  let result = checked(Filter, "\"flag\"")
  assert_true(@contract.type_equal(output_row(result), input(), 1000))
  assert_eq(@relation_typing.form(result), Predicate)
  rejected(Filter, "\"amount\"", ExpectedBoolean)
  let result = checked(Filter, "\"regex_match(id, 'x')\"")
  let expr = @relation_typing.binding_at(result, 0).unwrap().expression
  assert_eq(@typing.required_profiles(expr), ["actql-text-time/0.1"])
  assert_true(@typing.pending_validations(expr).length() > 0)
  ignore(checked(Filter, "\"if(FALSE, 1 / 0 > 0, TRUE)\""))
}

///|
test "select retains semantic order and permits distinct aliases of one input" {
  let result = checked(Select, "[{\"z\":\"id\"},\"amount\",{\"a\":\"id\"}]")
  let p = @relation_typing.projection(result)
  assert_eq(p.map(x => @schema.reference_name(x.output)), ["z", "amount", "a"])
  assert_eq(p.map(x => @schema.reference_name(x.input)), ["id", "amount", "id"])
  assert_true(field(output_row(result), "a").shape is @contract.Text(_))
  rejected(Select, "[\"id\",{\"id\":\"amount\"}]", DuplicateOutput("id"))
  rejected(Select, "[\"missing\"]", UnknownField("missing"))
  rejected(Select, "[]", EmptyBody)
  rejected(Select, "{\"x\":\"id\"}", InvalidBody)
  rejected(Select, "[{\"from\":\"id\",\"to\":\"x\"}]", InvalidBody)
  ignore(checked(Select, "[{\"from\":\"id\"},{\"to\":\"amount\"}]"))
}

///|
test "rename and drop expand without sequential rename effects" {
  let result = checked(Rename, "{\"id\":\"amount\",\"amount\":\"id\"}")
  assert_true(field(output_row(result), "id").shape is @contract.Number)
  assert_true(field(output_row(result), "amount").shape is @contract.Text(_))
  rejected(Rename, "{\"id\":\"amount\"}", DuplicateOutput("amount"))
  rejected(Rename, "{\"missing\":\"x\"}", UnknownField("missing"))
  let result = checked(Drop, "[\"id\"]")
  assert_eq(
    @relation_typing.projection(result).map(x => {
      @schema.reference_name(x.output)
    }),
    ["amount", "flag"],
  )
  rejected(Drop, "[\"amount\",\"id\",\"flag\"]", EmptyBody)
  rejected(Drop, "[\"missing\"]", UnknownField("missing"))
}

///|
test "empty derive maps retain schemas and still check input budgets" {
  for input in [input(), schema("{}")] {
    let body = cursor("{}")
    let value = check_row(Derive, body, input, None, limits()).unwrap()
    assert_eq(@relation_typing.operation(value), Derive)
    assert_eq(@relation_typing.form(value), DeriveMap)
    assert_eq(@relation_typing.binding_count(value), 0)
    assert_true(@contract.type_equal(output_row(value), input, 10000))
    let work = @relation_typing.work_used(value)
    assert_true(work > 0)
    assert_true(
      check_row(Derive, body, input, None, { ..limits(), max_work: work, })
      is Ok(_),
    )
    assert_true(
      check_row(Derive, body, input, None, { ..limits(), max_work: work - 1, })
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let invalid = @contract.with_nullability(input(), true)
  assert_true(@schema.from_object(invalid) is Err(InvalidRowContract))
  rejected(Derive, "[]", EmptyBody)
  rejected(Derive, "[{}]", InvalidBody)
}

///|
test "empty rename and drop retain both nonempty and empty input schemas" {
  for
    (op, body) in [
      (@relation_typing.Rename, "{}"),
      (@relation_typing.Drop, "[]"),
    ] {
    for input in [input(), schema("{}")] {
      let value = check_row(op, cursor(body), input, None, limits()).unwrap()
      assert_eq(@relation_typing.operation(value), op)
      assert_true(@contract.type_equal(input_row(value), input, 10000))
      assert_true(@contract.type_equal(output_row(value), input, 10000))
      assert_eq(@relation_typing.binding_count(value), 0)
      let expected = match input.shape {
        @contract.Object(fields) => @contract.fields(fields).map(f => f.name)
        _ => abort("test input object")
      }
      assert_eq(
        @relation_typing.projection(value).map(p => {
          @schema.reference_name(p.output)
        }),
        expected,
      )
      assert_eq(
        @relation_typing.projection(value).map(p => {
          @schema.reference_name(p.input)
        }),
        expected,
      )
    }
  }
  assert_true(
    check_row(Select, cursor("[]"), schema("{}"), None, limits())
    is Err({ kind: EmptyBody, .. }),
  )
}

///|
test "derive rejects malformed slots and preserves lawful data names" {
  rejected(Derive, "[]", EmptyBody)
  rejected(Derive, "[{}]", InvalidBody)
  rejected(Derive, "[{\"x\":\"1\",\"y\":\"2\"}]", InvalidBody)
  rejected(Derive, "{\"x.y\":\"1\"}", InvalidName("x.y"))
  rejected(Derive, "{\"__cid\":\"1\"}", InvalidName("__cid"))
  let result = checked(
    Derive,
    "{\"__proto__\":\"1\",\"7\":\"2\",\"line\\nname\":\"3\"}",
  )
  assert_true(field(output_row(result), "__proto__").shape is @contract.Number)
  rejected(Derive, "[{\"é\":\"1\"},{\"é\":\"2\"}]", DuplicateOutput("é"))
}

///|
test "operation result accessors detach arrays and preserve input evidence" {
  let result = checked(Derive, "[{\"x\":\"amount\"},{\"y\":\"x\"}]")
  let b = @relation_typing.binding_at(result, 1).unwrap()
  let refs = @relation_typing.references(b)
  @syntax.location_path(refs[0].occurrence.location).clear()
  refs.clear()
  assert_eq(@relation_typing.references(b).length(), 1)
  assert_true(
    @syntax.location_path(
      @relation_typing.references(
        @relation_typing.binding_at(result, 1).unwrap(),
      )[0].occurrence.location,
    ).length() >
    0,
  )
  assert_true(@relation_typing.binding_at(result, -1) is None)
  assert_true(@relation_typing.binding_at(result, 2) is None)
  let projected = checked(Select, "[\"id\"]")
  @relation_typing.projection(projected).clear()
  assert_eq(@relation_typing.projection(projected).length(), 1)
}

///|
test "operation work and text budgets are cumulative and exact at reported usage" {
  let body = cursor("[{\"x\":\"amount + 1\"},{\"y\":\"x + 2\"}]")
  let result = check_row(Derive, body, input(), None, limits()).unwrap()
  let work = @relation_typing.work_used(result)
  let text = @relation_typing.text_bytes_used(result)
  assert_true(
    check_row(Derive, body, input(), None, {
      ..limits(),
      max_work: work,
      max_text_bytes: text,
    })
    is Ok(_),
  )
  assert_true(
    check_row(Derive, body, input(), None, { ..limits(), max_work: work - 1, })
    is Err(_),
  )
  assert_true(
    check_row(Derive, body, input(), None, {
      ..limits(),
      max_text_bytes: text - 1,
    })
    is Err(_),
  )
  for bound in [-1, 0, 1] {
    assert_true(
      check_row(Derive, body, input(), None, { ..limits(), max_work: bound, })
      is Err(_),
    )
  }
}

///|
test "long ordered derive chains reuse the visible field map" {
  let entries : Array[String] = []
  for i in 0..<3000 {
    let rhs = if i == 0 { "amount" } else { "x" + (i - 1).to_string() }
    entries.push("{\"x" + i.to_string() + "\":\"" + rhs + "\"}")
  }
  let result = check_row(
    Derive,
    cursor("[" + entries.join(",") + "]"),
    input(),
    None,
    { ..limits(), max_work: 600000, },
  ).unwrap()
  assert_eq(@relation_typing.binding_count(result), 3000)
  assert_eq(
    @relation_typing.references(
      @relation_typing.binding_at(result, 2999).unwrap(),
    )[0].target,
    PriorSlot(2998),
  )
}

///|
test "deep expressions remain nonrecursive inside an operation" {
  let text = "{\"not\":".repeat(10000) +
    "{\"literal\":true}" +
    "}".repeat(10000)
  let result = check_row(Filter, cursor(text), input(), None, limits()).unwrap()
  assert_true(@contract.type_equal(output_row(result), input(), 1000))
}

///|
test "operation composition uses the previous output without dropping derive slots" {
  let derived = checked(
    Derive,
    "[{\"unused\":\"1 / 0\"},{\"total\":\"amount * 2\"}]",
  )
  assert_eq(@relation_typing.binding_count(derived), 2)
  let select = check_row(
    Select,
    cursor("[\"total\"]"),
    output_row(derived),
    None,
    limits(),
  ).unwrap()
  assert_true(field(output_row(select), "total").shape is @contract.Number)
  let later = check_row(
    Derive,
    cursor("{\"old\":\"amount\"}"),
    output_row(select),
    None,
    limits(),
  )
  assert_true(later is Err({ kind: UnknownField("amount"), .. }))
}

///|
test "parameters are declarations and patterns remain pending" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"factor\":{\"type\":\"number\",\"nullable\":true,\"default\":2},\"pattern\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 100,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let result = check_row(
    Derive,
    cursor("{\"total\":\"amount * $factor\"}"),
    input(),
    Some(params),
    limits(),
  ).unwrap()
  assert_true(field(output_row(result), "total").nullable)
  assert_eq(
    @parameter.declaration_count(@relation_typing.parameters(result).unwrap()),
    2,
  )
  let filtered = check_row(
    Filter,
    cursor("\"regex_match(id, $pattern)\""),
    input(),
    Some(params),
    limits(),
  ).unwrap()
  let expr = @relation_typing.binding_at(filtered, 0).unwrap().expression
  assert_true(@typing.pending_validations(expr).length() > 0)
  let unknown = check_row(
    Derive,
    cursor("{\"x\":\"$missing\"}"),
    input(),
    Some(params),
    limits(),
  )
  assert_true(
    unknown
    is Err({ kind: Expression(@typing.UnknownParameter("missing")), .. }),
  )
}

///|
test "syntax budgets cannot reset between slots" {
  let one = cursor("[{\"x\":\"amount + 1\"}]")
  let two = cursor("[{\"x\":\"amount + 1\"},{\"y\":\"amount + 1\"}]")
  let narrow = { ..limits(), max_tokens: 4, }
  assert_true(check_row(Derive, one, input(), None, narrow) is Ok(_))
  assert_true(check_row(Derive, two, input(), None, narrow) is Err(_))
  for bound in [0, 1] {
    assert_true(
      check_row(Derive, one, input(), None, { ..limits(), max_nodes: bound, })
      is Err(_),
    )
  }
}

///|
test "input schema preflight includes fields that projection removes" {
  let mut deep = @contract.primitive(NumberType, nullable=false)
  for _ in 0..<100 {
    deep = @contract.array_contract(deep, nullable=false).unwrap()
  }
  let input = @contract.object_contract(
    [("hidden", deep), ("id", @contract.primitive(StringType, nullable=false))],
    nullable=false,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    check_row(Select, cursor("[\"id\"]"), input, None, {
      ..limits(),
      max_depth: 50,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    @schema.from_object(@contract.with_nullability(input, true))
    is Err(InvalidRowContract),
  )
  assert_true(
    @schema.from_object(@contract.primitive(NumberType, nullable=false))
    is Err(InvalidRowContract),
  )
}

///|
test "wide select uses indexed lookups and retains authored projection order" {
  let fields : Array[(String, @contract.Contract)] = []
  let names : Array[String] = []
  for i in 0..<5000 {
    let name = "f" + i.to_string()
    fields.push((name, @contract.primitive(NumberType, nullable=false)))
    names.push("\"" + name + "\"")
  }
  let input = @contract.object_contract(
    fields,
    nullable=false,
    max_fields=5000,
    max_name_bytes=100000,
  ).unwrap()
  let result = check_row(
    Select,
    cursor("[" + names.join(",") + "]"),
    input,
    None,
    { ..limits(), max_work: 100000, },
  ).unwrap()
  let projection = @relation_typing.projection(result)
  assert_eq(projection.length(), 5000)
  assert_eq(projection[2].output, @schema.Unqualified("f2"))
  assert_eq(projection[4999].output, @schema.Unqualified("f4999"))
}

///|
test "unknown structured field diagnostics retain the nested occurrence" {
  let body = cursor(
    "{\"x\":{\"add\":[{\"field\":\"amount\"},{\"field\":\"missing\"}]}}",
  )
  let x = @decode.lookup(@decode.open_object(body).unwrap(), "x").unwrap()
  let add = @decode.lookup(@decode.open_object(x).unwrap(), "add").unwrap()
  let missing = @decode.elements(add).unwrap()[1]
  match check_row(Derive, body, input(), None, limits()) {
    Ok(_) => fail("unknown field accepted")
    Err(issue) => {
      assert_eq(issue.kind, UnknownField("missing"))
      assert_eq(issue.path, [
        @source.Key("x"),
        @source.Key("add"),
        @source.Index(1),
      ])
      assert_eq(issue.span, @decode.cursor_span(missing))
      assert_eq(issue.range, None)
    }
  }
}

///|
test "unknown fields in mixed text retain scalar spans and scalar-relative ranges" {
  let body = cursor(
    "[{\"x\":{\"add\":[{\"field\":\"amount\"},\"len('\\ud83d\\ude00') + missing\"]}}]",
  )
  let slot = @decode.elements(body).unwrap()[0]
  let x = @decode.lookup(@decode.open_object(slot).unwrap(), "x").unwrap()
  let add = @decode.lookup(@decode.open_object(x).unwrap(), "add").unwrap()
  let text = @decode.elements(add).unwrap()[1]
  match check_row(Derive, body, input(), None, limits()) {
    Ok(_) => fail("unknown field accepted")
    Err(issue) => {
      assert_eq(issue.kind, UnknownField("missing"))
      assert_eq(issue.path, [
        @source.Index(0),
        @source.Key("x"),
        @source.Key("add"),
        @source.Index(1),
      ])
      assert_eq(issue.span, @decode.cursor_span(text))
      assert_eq(issue.range, Some({ start: 11, end: 18, }))
      assert_eq(issue.span.source_path, "relation.aql")
    }
  }
}

///|
test "syntax failures expose their original diagnostic coordinates" {
  let body = cursor("{\"x\":{\"add\":[\"amount\",\"amount +\"]}}")
  match check_row(Derive, body, input(), None, limits()) {
    Ok(_) => fail("invalid syntax accepted")
    Err(issue) => {
      match issue.kind {
        Syntax(inner) => {
          assert_eq(issue.path, inner.path)
          assert_eq(issue.span, inner.span)
          assert_eq(issue.range, inner.range)
        }
        _ => fail("expected syntax issue")
      }
      assert_eq(issue.path, [
        @source.Key("x"),
        @source.Key("add"),
        @source.Index(1),
      ])
      assert_true(issue.range is Some(_))
    }
  }
}
