///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 2000000,
      max_nodes: 1000000,
      max_depth: 30000,
    }).unwrap(),
    {
      max_nodes: 1000000,
      max_depth: 30000,
      max_string_bytes: 2000000,
      max_total_string_bytes: 2000000,
    },
  ).unwrap()
}

///|
fn limits() -> @relation_values.Limits {
  {
    max_rows: 100000,
    max_work: 10000000,
    max_nodes: 1000000,
    max_text_bytes: 2000000,
    max_depth: 30000,
  }
}

///|
fn body(
  rows : String,
  field? : String = "{\"type\":\"number\",\"nullable\":false}",
) -> @decode.Cursor {
  cursor("{\"schema\":{\"x\":" + field + "},\"rows\":" + rows + "}")
}

///|
test "finite values retain empty schema evidence and every repeated row" {
  let empty = @relation_values.check(body("[]"), None, limits()).unwrap()
  assert_eq(@relation_values.row_count(empty), 0)
  assert_eq(@schema.field_count(@relation_values.output_schema(empty)), 1)
  let values = @relation_values.check(
    body("[{\"x\":1},{\"x\":{\"literal\":1}},{\"x\":2}]"),
    None,
    limits(),
  ).unwrap()
  assert_eq(@relation_values.row_count(values), 3)
  for (i, expected) in [(0, 1.0), (1, 1.0), (2, 2.0)] {
    let row = @relation_values.row_at(values, i).unwrap()
    match @relation_values.cell_at(row, 0).unwrap() {
      Literal(v, ..) =>
        assert_true(v.value is @value.Number(n) && n == expected)
      _ => fail("expected literal")
    }
    let detached = @relation_values.cells(row)
    detached.clear()
    assert_true(@relation_values.cell_at(row, 0) is Some(_))
    assert_true(@relation_values.cell_at(row, -1) is None)
    assert_true(@relation_values.cell_at(row, 1) is None)
  }
  assert_true(@relation_values.row_at(values, 3) is None)
  assert_true(@relation_values.row_at(values, -1) is None)
}

///|
test "values require exact rows and preserve nullable cells without omission" {
  let text = "{\"type\":\"string\",\"nullable\":true}"
  assert_true(
    @relation_values.check(body("[{\"x\":null}]", field=text), None, limits())
    is Ok(_),
  )
  for rows in ["[{}]", "[{\"x\":null,\"y\":1}]", "[null]", "{}"] {
    assert_true(
      @relation_values.check(body(rows, field=text), None, limits()) is Err(_),
    )
  }
  assert_true(
    @relation_values.check(
      cursor("{\"schema\":{},\"rows\":[]}"),
      None,
      limits(),
    )
    is Err({ kind: EmptySchema, .. }),
  )
  let invalid = @relation_values.check(body("[{\"x\":null}]"), None, limits()).unwrap_err()
  assert_eq(invalid.kind, Value(UnexpectedNull))
  assert_eq(invalid.path, [Key("rows"), Index(0), Key("x")])
}

///|
test "values literal quoting is one level and nested parameter shapes are opaque" {
  let field = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"$param\":{\"type\":\"string\",\"nullable\":false}}}"
  let p = @relation_values.check(
    body("[{\"x\":{\"literal\":{\"$param\":\"business\"}}}]", field~),
    None,
    limits(),
  ).unwrap()
  match
    @relation_values.cell_at(@relation_values.row_at(p, 0).unwrap(), 0).unwrap() {
    Literal(v, ..) =>
      match v.value {
        @value.Object(fields) => {
          assert_eq(@value.element_at(fields, 0).unwrap().0, "$param")
          assert_true(
            @value.element_at(fields, 0).unwrap().1 is @value.Text("business"),
          )
        }
        _ => fail("expected object")
      }
    _ => fail("expected literal")
  }
  assert_eq(
    indexed_obligation_copy(
      @relation_values.pending_validations(p),
      @relation_values.pending_validation_count(p),
      i => @relation_values.pending_validation_at(p, i),
      (a, b) => a == b,
    ),
    [ResolvePublicationResources],
  )
  let unquoted = @relation_values.check(
    body("[{\"x\":{\"$param\":\"business\"}}]", field~),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(unquoted.kind, UnknownParameter("business"))
}

///|
test "decimal values use exact scale strings and report nested literal failures" {
  let field = "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}"
  let p = @relation_values.check(
    body("[{\"x\":\"19.90\"}]", field~),
    None,
    limits(),
  ).unwrap()
  match
    @relation_values.cell_at(@relation_values.row_at(p, 0).unwrap(), 0).unwrap() {
    Literal(v, ..) =>
      match v.value {
        @value.Decimal(d) => assert_eq(d.coefficient, "1990")
        _ => fail("decimal")
      }
    _ => fail("literal")
  }
  for rows in ["[{\"x\":19.9}]", "[{\"x\":\"19.9\"}]"] {
    assert_true(
      @relation_values.check(body(rows, field~), None, limits()) is Err(_),
    )
  }
  let field = "{\"type\":\"array\",\"items\":{\"type\":\"number\",\"nullable\":false},\"nullable\":false}"
  let e = @relation_values.check(
    body("[{\"x\":{\"literal\":[1,\"wrong\"]}}]", field~),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(e.kind, Value(WrongType))
  assert_eq(e.path, [Key("rows"), Index(0), Key("x"), Key("literal"), Index(1)])
}

///|
test "constructor restrictions apply to complete schemas including empty rows" {
  for
    field in [
      "{\"type\":\"json\",\"nullable\":false}", "{\"type\":\"artifact_ref\",\"nullable\":true}",
      "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"resource_ref\",\"resource_kind\":\"Customer\",\"nullable\":false}}",
    ] {
    assert_true(
      @relation_values.check(body("[]", field~), None, limits())
      is Err({ kind: ForbiddenValueType, .. }),
    )
  }
}

///|
test "values charge literal traversal and schema reading against one budget" {
  let s = body("[{\"x\":1},{\"x\":2}]")
  let p = @relation_values.check(s, None, limits()).unwrap()
  let used = @relation_values.usage(p)
  let exact : @relation_values.Limits = {
    ..limits(),
    max_rows: 2,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(@relation_values.check(s, None, exact) is Ok(_))
  for
    small in [
      { ..exact, max_rows: 1, },
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_values.check(s, None, small)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "whole parameter cells require declared compatible types and retain repetitions" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"default\":7},\"s\":{\"type\":\"string\"},\"a\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let p = @relation_values.check(
    body("[{\"x\":{\"$param\":\"n\"}},{\"x\":{\"$param\":\"n\"}}]"),
    Some(params),
    limits(),
  ).unwrap()
  assert_eq(
    indexed_obligation_copy(
      @relation_values.pending_validations(p),
      @relation_values.pending_validation_count(p),
      i => @relation_values.pending_validation_at(p, i),
      (a, b) => a == b,
    ),
    [ResolvePublicationResources, BindCell("n"), BindCell("n")],
  )
  assert_true(
    @relation_values.cell_at(@relation_values.row_at(p, 0).unwrap(), 0)
    is Some(Parameter("n", ..)),
  )
  for
    (name, expected) in [
      ("", @relation_values.InvalidParameterName("")),
      ("bad.name", InvalidParameterName("bad.name")),
      ("missing", UnknownParameter("missing")),
      ("s", IncompatibleParameter("s")),
    ] {
    let e = @relation_values.check(
      body("[{\"x\":{\"$param\":\"" + name + "\"}}]"),
      Some(params),
      limits(),
    ).unwrap_err()
    assert_eq(e.kind, expected)
    assert_eq(e.path, [Key("rows"), Index(0), Key("x"), Key("$param")])
  }
  let array_type = "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}"
  assert_true(
    @relation_values.check(
      body("[{\"x\":{\"$param\":\"a\"}}]", field=array_type),
      Some(params),
      limits(),
    )
    is Ok(_),
  )
}

///|
test "literal reserved roots and nested business holes are not recursively expanded" {
  let field = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"literal\":{\"type\":\"number\",\"nullable\":false}}}"
  assert_true(
    @relation_values.check(
      body("[{\"x\":{\"literal\":{\"literal\":1}}}]", field~),
      None,
      limits(),
    )
    is Ok(_),
  )
  let field = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"business\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"$param\":{\"type\":\"string\",\"nullable\":false}}}}}"
  let p = @relation_values.check(
    body("[{\"x\":{\"business\":{\"$param\":\"not_a_binding\"}}}]", field~),
    None,
    limits(),
  ).unwrap()
  assert_eq(
    indexed_obligation_copy(
      @relation_values.pending_validations(p),
      @relation_values.pending_validation_count(p),
      i => @relation_values.pending_validation_at(p, i),
      (a, b) => a == b,
    ),
    [ResolvePublicationResources],
  )
}

///|
test "deep declared arrays and literals use iterative traversal" {
  let depth = 3000
  let field = "{\"type\":\"array\",\"nullable\":false,\"items\":".repeat(depth) +
    "{\"type\":\"number\",\"nullable\":false}" +
    "}".repeat(depth)
  let rows = "[{\"x\":" + "[".repeat(depth) + "1" + "]".repeat(depth) + "}]"
  let p = @relation_values.check(body(rows, field~), None, limits()).unwrap()
  assert_eq(@relation_values.row_count(p), 1)
  let row = @relation_values.row_at(p, 0).unwrap()
  let mut value = match @relation_values.cell_at(row, 0).unwrap() {
    Literal(v, ..) => v.value
    _ => abort("literal")
  }
  for _ in 0..<depth {
    value = match value {
      @value.Array(xs) => @value.element_at(xs, 0).unwrap()
      _ => abort("array")
    }
  }
  assert_true(value is @value.Number(1.0))
}
