///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 30000, },
      source_path="append.aql",
    ).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 30000,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
}

///|
fn limits() -> @relation_append.Limits {
  {
    max_work: 2000000,
    max_text_bytes: 2000000,
    max_nodes: 100000,
    max_depth: 30000,
  }
}

///|
fn row(fields : String) -> @schema.Schema {
  @schema.from_object(
    @contract.read_checked(
      cursor(
        "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
        fields +
        "}",
      ),
      { max_nodes: 100000, max_depth: 30000, max_text_bytes: 1000000, },
    ).unwrap(),
  ).unwrap()
}

///|
fn run(
  left : @schema.Schema,
  right : @schema.Schema,
) -> @relation_append.CheckedAppend {
  @relation_append.check(cursor("{\"with\":\"right\"}"), left, right, limits()).unwrap()
}

///|
fn corpus_case(
  body : String,
  left : String,
  right : String,
  output : String?,
  issue : String?,
) -> Unit raise {
  match @relation_append.check(cursor(body), row(left), row(right), limits()) {
    Ok(v) => {
      assert_true(issue is None)
      assert_true(
        @contract.type_equal(
          @schema.as_object(@relation_append.output_schema(v)).unwrap(),
          @schema.as_object(row(output.unwrap())).unwrap(),
          10000,
        ),
      )
    }
    Err(e) => {
      assert_true(output is None)
      let label = match e.kind {
        MissingField(_, _) => "MissingField"
        IncompatibleContracts(_, _) => "IncompatibleContracts"
        InvalidBody => "InvalidBody"
        InvalidName(_) => "InvalidName"
        _ => "unexpected"
      }
      assert_eq(Some(label), issue)
    }
  }
}

///|
test "append joins recursive nullable and size contracts rather than root nullability only" {
  let left = row(
    "{\"x\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"s\":{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":3,\"max_utf8_bytes\":6}}}}}",
  )
  let right = row(
    "{\"x\":{\"type\":\"array\",\"nullable\":true,\"max_items\":4,\"items\":{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"s\":{\"type\":\"string\",\"nullable\":true,\"min_length\":1,\"max_codepoints\":8}}}}}",
  )
  let expected = row(
    "{\"x\":{\"type\":\"array\",\"nullable\":true,\"max_items\":4,\"items\":{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"s\":{\"type\":\"string\",\"nullable\":true,\"min_length\":1,\"max_codepoints\":8}}}}}",
  )
  for value in [run(left, right), run(right, left)] {
    assert_true(
      @contract.type_equal(
        @schema.as_object(@relation_append.output_schema(value)).unwrap(),
        @schema.as_object(expected).unwrap(),
        100,
      ),
    )
    assert_eq(@relation_append.with_name(value), "right")
  }
}

///|
test "append retains both operands empty schemas qualification and detached alignment" {
  let empty = row("{}")
  let result = run(empty, empty)
  assert_eq(@schema.field_count(@relation_append.output_schema(result)), 0)
  assert_true(@relation_append.alignment(result).is_empty())
  assert_eq(@relation_append.pending_validations(result).length(), 4)
  let fields = [
    (
      @schema.Qualified(Right, "id"),
      @contract.primitive(NumberType, nullable=true),
    ),
    (
      @schema.Qualified(Left, "id"),
      @contract.primitive(NumberType, nullable=false),
    ),
  ]
  let schema = @schema.from_fields(fields, max_fields=2, max_name_bytes=100).unwrap()
  let result = run(schema, schema)
  fields.clear()
  assert_eq(@schema.field_count(@relation_append.output_schema(result)), 2)
  assert_true(@schema.as_object(@relation_append.output_schema(result)) is None)
  let alignment = @relation_append.alignment(result)
  assert_eq(alignment[0].field, @schema.Qualified(Left, "id"))
  assert_eq(alignment[1].right_index, 1)
  alignment.clear()
  assert_eq(@relation_append.alignment(result).length(), 2)
  assert_eq(@schema.field_count(@relation_append.input_schema(result, Left)), 2)
  let flat = row("{\"id\":{\"type\":\"number\",\"nullable\":false}}")
  assert_true(
    @relation_append.check(cursor("{\"with\":\"r\"}"), schema, flat, limits())
    is Err({ kind: MissingField(Right, @schema.Qualified(Left, "id")), .. }),
  )
}

///|
test "append retains nested mismatch coordinates without fabricating contract source spans" {
  let left = row(
    "{\"x\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"v\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":4,\"scale\":2}}}}}",
  )
  let right = row(
    "{\"x\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"v\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":5,\"scale\":2}}}}}",
  )
  let body = cursor("{\"with\":\"r\"}")
  let issue = @relation_append.check(body, left, right, limits()).unwrap_err()
  assert_eq(
    issue.kind,
    IncompatibleContracts(@schema.Unqualified("x"), [Item, Field("v")]),
  )
  assert_eq(issue.path, [@source.Key("with")])
  assert_eq(
    issue.span,
    @decode.cursor_span(
      @decode.lookup(@decode.open_object(body).unwrap(), "with").unwrap(),
    ),
  )
}

///|
test "append recursively rejects incompatible domains and never fills missing fields" {
  for
    (a, b) in [
      ("\"type\":\"number\"", "\"type\":\"string\""),
      (
        "\"type\":\"decimal\",\"precision\":4,\"scale\":2", "\"type\":\"decimal\",\"precision\":4,\"scale\":1",
      ),
      (
        "\"type\":\"vector\",\"element_type\":\"f32\",\"dimensions\":2", "\"type\":\"vector\",\"element_type\":\"f32\",\"dimensions\":3",
      ),
      (
        "\"type\":\"resource_ref\",\"resource_kind\":\"A\"", "\"type\":\"resource_ref\",\"resource_kind\":\"B\"",
      ),
    ] {
    let left = row("{\"x\":{" + a + ",\"nullable\":false}}")
    let right = row("{\"x\":{" + b + ",\"nullable\":true}}")
    assert_true(
      @relation_append.check(cursor("{\"with\":\"r\"}"), left, right, limits())
      is Err({ kind: IncompatibleContracts(@schema.Unqualified("x"), []), .. }),
    )
  }
  let left = row(
    "{\"x\":{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"a\"}}",
  )
  let right = row(
    "{\"x\":{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"b\"}}",
  )
  let result = run(left, right)
  assert_true(
    @schema.lookup(@relation_append.output_schema(result), Unqualified("x")).unwrap().shape
    is @contract.ArtifactRef(media_type=None),
  )
  assert_true(
    @relation_append.check(
      cursor("{\"with\":\"r\"}"),
      row("{}"),
      right,
      limits(),
    )
    is Err({ kind: MissingField(Left, @schema.Unqualified("x")), .. }),
  )
  assert_true(
    @relation_append.check(
      cursor("{\"with\":\"r\"}"),
      left,
      row("{}"),
      limits(),
    )
    is Err({ kind: MissingField(Right, @schema.Unqualified("x")), .. }),
  )
}

///|
test "append closed body and cumulative budget boundaries" {
  let left = row("{\"x\":{\"type\":\"string\",\"nullable\":false}}")
  for
    text in [
      "{}", "null", "[]", "{\"with\":null}", "{\"with\":1}", "{\"with\":\"\"}", "{\"with\":\"r\",\"left\":\"l\"}",
      "{\"with\":\"r\",\"schema\":\"union\"}",
    ] {
    assert_true(
      @relation_append.check(cursor(text), left, left, limits()) is Err(_),
    )
  }
  let body = cursor("{\"with\":\"r\"}")
  let result = @relation_append.check(body, left, left, limits()).unwrap()
  let u = @relation_append.usage(result)
  let exact : @relation_append.Limits = {
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
    max_depth: 1,
  }
  assert_true(@relation_append.check(body, left, left, exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_append.check(body, left, left, l)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  assert_true(
    @relation_append.check(body, left, left, { ..exact, max_work: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
}

///|
test "append is iterative for deep contracts and bounded for wide field alignment" {
  let mut a = @contract.primitive(NumberType, nullable=false)
  let mut b = @contract.primitive(NumberType, nullable=true)
  for _ in 0..<10000 {
    a = @contract.array_contract(a, nullable=false).unwrap()
    b = @contract.array_contract(b, nullable=false).unwrap()
  }
  let left = @schema.from_fields(
    [(@schema.Unqualified("x"), a)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let right = @schema.from_fields(
    [(@schema.Unqualified("x"), b)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let result = run(left, right)
  assert_true(
    @contract.type_equal(
      @schema.lookup(@relation_append.output_schema(result), Unqualified("x")).unwrap(),
      b,
      10001,
    ),
  )
  let body = cursor("{\"with\":\"r\"}")
  assert_true(
    @relation_append.check(body, left, right, { ..limits(), max_depth: 100, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  let fields = Array::makei(5000, i => {
    (
      @schema.Unqualified("f" + i.to_string()),
      @contract.primitive(NumberType, nullable=false),
    )
  })
  let wide = @schema.from_fields(fields, max_fields=5000, max_name_bytes=100000).unwrap()
  let result = @relation_append.check(body, wide, wide, {
    ..limits(),
    max_work: 60000,
  }).unwrap()
  assert_eq(@relation_append.alignment(result).length(), 5000)
}
