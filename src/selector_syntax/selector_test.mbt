///|
fn limits() -> @expression.Limits {
  {
    max_nodes: 500000,
    max_depth: 30000,
    max_text_bytes: 1000000,
    max_tokens: 100000,
    tree: {
      max_nodes: 500000,
      max_depth: 30000,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000000,
      max_nodes: 500000,
      max_depth: 30000,
    }).unwrap(),
    limits().tree,
  ).unwrap()
}

///|
fn text(value : String) -> @decode.Cursor {
  let span = @decode.cursor_span(cursor("null"))
  @decode.admit({ value: @source.String(value), span, }, limits().tree).unwrap()
}

///|
fn rendered(selector : Selector) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(1000000, 500000, 30000)
  @expression.emit_source(expression(selector), writer)
  @encode.finish(writer)
}

///|
test "selector syntax admits the closed predicate vocabulary in common notation" {
  for
    source in [
      "id = $p", "id <> 1", "id < 1", "id <= 1", "id > 1", "id >= 1", "id IN (1, $p)",
      "id NOT IN (1)", "id BETWEEN 1 AND 3", "name LIKE 'a%'", "contains(name, 'a')",
      "id IS NULL", "id IS NOT NULL", "id = 1 AND (id = 2 OR NOT id = 3)",
    ] {
    let value = admit(text(source), limits(), max_work=1000000).unwrap()
    let encoded = rendered(value)
    let structured = admit(cursor(encoded), limits(), max_work=1000000).unwrap()
    assert_eq(rendered(structured), encoded)
    assert_true(admit(text(source), limits(), max_work=work(value)) is Ok(_))
    assert_true(
      admit(text(source), limits(), max_work=work(value) - 1) is Err(WorkLimit),
    )
  }
  assert_eq(
    rendered(admit(text("id = $p"), limits(), max_work=1000000).unwrap()),
    "{\"eq\":[{\"field\":\"id\"},{\"$param\":\"p\"}]}",
  )
}

///|
test "common expression admission never widens restricted selector operands" {
  for
    source in [
      "TRUE", "flag", "$p", "id IS TRUE", "id IS UNKNOWN", "id IS DISTINCT FROM 1",
      "id + 1 = 2", "len(name) = 1", "lower(name) = 'a'", "regex_match(name, 'a')",
      "if(TRUE, id = 1, id = 2)", "id = CAST($p AS NUMBER)", "left.id = 1", "obj.x = 1",
      "a[0] = 1", "NOT (id = 1 OR amount + 1 > 0)",
    ] {
    assert_true(
      admit(text(source), limits(), max_work=1000000)
      is Err(RestrictedNode(_, _)),
      msg=source,
    )
  }
  assert_true(
    admit(text("id = NULL"), limits(), max_work=1000000) is Err(Expression(_)),
  )
  assert_true(
    admit(text("id = 1"), limits(), max_work=-1) is Err(InvalidLimits),
  )
}

///|
test "opaque literal data and membership holes keep common occurrence semantics" {
  let selector = admit(
    cursor(
      (
        #|{"eq":[{"field":"data"},{"literal":{"$param":"hidden","meta":{"add":[1,2]}}}]}
      ),
    ),
    limits(),
    max_work=1000000,
  ).unwrap()
  let refs = @expression.collect_parameter_occurrences(
    expression(selector),
    max_work=10000,
  ).unwrap()
  assert_eq(@expression.parameter_occurrence_count(refs), 0)
  assert_eq(
    rendered(selector),
    (
      #|{"eq":[{"field":"data"},{"literal":{"$param":"hidden","meta":{"add":[1,2]}}}]}
    ),
  )
  let selector = admit(text("id IN (1, $p, $p)"), limits(), max_work=1000000).unwrap()
  let refs = @expression.collect_parameter_occurrences(
    expression(selector),
    max_work=10000,
  ).unwrap()
  assert_eq(@expression.parameter_occurrence_count(refs), 2)
}

///|
test "restricted traversal preserves nested text diagnostics and is nonrecursive" {
  let source = cursor(
    (
      #|{"and":["id = 1","amount + 1 > 0"]}
    ),
  )
  match admit(source, limits(), max_work=1000000) {
    Err(RestrictedNode(tag, location)) => {
      assert_eq(tag, "add")
      assert_eq(@expression.location_path(location), [
        @source.Key("and"),
        @source.Index(1),
      ])
      assert_true(location.range is Some(_))
    }
    _ => fail("expected restricted arithmetic operand")
  }
  let source = "{\"not\":".repeat(10000) +
    "{\"is_null\":{\"field\":\"id\"}}" +
    "}".repeat(10000)
  let selector = admit(cursor(source), limits(), max_work=1000000).unwrap()
  assert_eq(rendered(selector), source)
}
