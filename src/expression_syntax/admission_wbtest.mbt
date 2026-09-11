///|
fn test_limits() -> Limits {
  {
    max_nodes: 1000000,
    max_depth: 40000,
    max_text_bytes: 10000000,
    max_tokens: 200000,
    tree: {
      max_nodes: 500000,
      max_depth: 40000,
      max_string_bytes: 2000000,
      max_total_string_bytes: 10000000,
    },
  }
}

///|
fn source_cursor(source : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      source,
      { max_input_bytes: 10000000, max_nodes: 500000, max_depth: 40000, },
      source_path="test.aql",
    ).unwrap(),
    test_limits().tree,
  ).unwrap()
}

///|
fn text_cursor(text : String) -> @decode.Cursor {
  let span = @decode.cursor_span(source_cursor("null"))
  @decode.admit({ value: @source.String(text), span, }, test_limits().tree).unwrap()
}

///|
fn assert_cursor(left : @decode.Cursor, right : @decode.Cursor) -> Unit raise {
  let pending = [(left, right)]
  while pending.pop() is Some((left, right)) {
    match (@decode.view(left), @decode.view(right)) {
      (@decode.NullValue, @decode.NullValue) => ()
      (@decode.BoolValue(a), @decode.BoolValue(b)) => assert_eq(a, b)
      (@decode.NumberValue(a), @decode.NumberValue(b)) =>
        assert_eq(a.reinterpret_as_uint64(), b.reinterpret_as_uint64())
      (@decode.TextValue(a), @decode.TextValue(b)) => assert_eq(a, b)
      (@decode.ArrayValue(a), @decode.ArrayValue(b)) => {
        assert_eq(a.length(), b.length())
        for i, child in a {
          pending.push((child, b[i]))
        }
      }
      (@decode.ObjectValue(a), @decode.ObjectValue(b)) => {
        let names = @decode.object_field_names(left).unwrap()
        assert_eq(
          names.length(),
          @decode.object_field_names(right).unwrap().length(),
        )
        for name in names {
          pending.push(
            (@decode.lookup(a, name).unwrap(), @decode.lookup(b, name).unwrap()),
          )
        }
      }
      _ => fail("different expression tree")
    }
  }
}

///|
fn assert_tree(source : String, expected : String) -> Unit raise {
  let parsed = admit(source_cursor(source), test_limits())
  assert_true(parsed is Ok(_), msg=source)
  assert_cursor(tree(parsed.unwrap()), source_cursor(expected))
  let roundtrip = admit(
    source_cursor(source_text(parsed.unwrap())),
    test_limits(),
  ).unwrap()
  assert_cursor(tree(roundtrip), tree(parsed.unwrap()))
}

///|
test "mixed expressions normalize aliases without folding or reassociation" {
  assert_tree(
    (
      #|{"add":["$x + 1",{"to_decimal":{"value":{"field":"left.cost"},"precision":8,"scale":2}}]}
    ),
    (
      #|{"add":[{"add":[{"$param":"x"},{"literal":1}]},{"cast":{"value":{"join_field":{"side":"left","name":"cost"}},"target":{"type":"decimal","precision":8,"scale":2}}}]}
    ),
  )
  assert_tree(
    (
      #|{"field":"right.address.city"}
    ),
    (
      #|{"property":{"value":{"join_field":{"side":"right","name":"address"}},"name":"city"}}
    ),
  )
  for kind in ["number", "string", "boolean", "timestamp"] {
    assert_tree(
      "{\"to_" + kind + "\":{\"literal\":null}}",
      "{\"cast\":{\"value\":{\"literal\":null},\"target\":{\"type\":\"" +
      kind +
      "\"}}}",
    )
  }
}

///|
test "template references separate ordinary fields from qualified fields" {
  let expression = admit(
    source_cursor(
      "{\"template\":\"{name} {left.amount} {right.amount} {{left.hidden}}\"}",
    ),
    test_limits(),
  ).unwrap()
  assert_eq(field_references(expression).map(r => r.name), ["name"])
  assert_eq(relation_references(expression).map(r => r.name), [
    "name", "left.amount", "right.amount",
  ])
  let detached = relation_references(expression)
  detached.clear()
  assert_eq(relation_references(expression).length(), 3)
}

///|
test "whole-field aliases normalize independently of lexical quotation" {
  for side in ["left", "right"] {
    let expected = source_cursor(
      "{\"join_field\":{\"side\":\"" + side + "\",\"name\":\"id\"}}",
    )
    let structured = source_cursor("{\"field\":\"" + side + ".id\"}")
    for
      input in [
        text_cursor(side + ".id"),
        text_cursor("\"" + side + ".id\""),
        structured,
        expected,
      ] {
      let expression = admit(input, test_limits()).unwrap()
      assert_cursor(tree(expression), expected)
      assert_cursor(
        tree(admit(tree(expression), test_limits()).unwrap()),
        expected,
      )
    }
    let property = source_cursor(
      "{\"property\":{\"value\":{\"field\":\"" + side + "\"},\"name\":\"id\"}}",
    )
    let expression = admit(text_cursor("\"" + side + "\".id"), test_limits()).unwrap()
    assert_cursor(tree(expression), property)
    assert_cursor(
      tree(admit(tree(expression), test_limits()).unwrap()),
      property,
    )
  }
  assert_tree(
    (
      #|{"array":["\"left.name\"",{"field":"left.name"},"\"left\".name","\"right.address.city\"","\"right.id\"[0]"]}
    ),
    (
      #|{"array":[{"join_field":{"side":"left","name":"name"}},{"join_field":{"side":"left","name":"name"}},{"property":{"value":{"field":"left"},"name":"name"}},{"property":{"value":{"join_field":{"side":"right","name":"address"}},"name":"city"}},{"subscript":{"value":{"join_field":{"side":"right","name":"id"}},"index":{"literal":0}}}]}
    ),
  )
}

///|
test "quoted alias rewriting consumes work budget and preserves diagnostic origin" {
  let input = text_cursor("\"left.id\"")
  let limits = test_limits()
  let decoded = @text.parse("\"left.id\"", {
    max_input_bytes: 1000,
    max_tokens: 100,
    max_nodes: 100,
    max_depth: 100,
    tree: limits.tree,
  }).unwrap()
  assert_cursor(
    tree(admit(@text.tree(decoded), limits).unwrap()),
    tree(admit(input, limits).unwrap()),
  )
  assert_true(admit(input, { ..limits, max_nodes: 9, }) is Ok(_))
  assert_true(
    admit(input, { ..limits, max_nodes: 8, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  let malformed = source_cursor("{\"array\":[\"\\\"right.\\\"\"]}")
  let issue = match admit(malformed, limits) {
    Err(issue) => issue
    _ => fail("expected invalid alias")
  }
  assert_eq(issue.kind, InvalidName("right."))
  assert_eq(issue.path, [@source.Key("array"), @source.Index(0)])
  assert_eq(issue.range, Some({ start: 0, end: 8, }))
  assert_eq(issue.span.source_path, "test.aql")
}

///|
test "literals and templates are opaque except immediate IN parameter holes" {
  let source =
    #|{"array":[{"literal":{"$param":"hidden","expr":"$also_hidden","items":[{"$param":"nested"}]}},{"template":"hello {name} $opaque"},{"in":["$left",{"literal":[1,null,{"$param":"item"}]}]},"$repeat + $repeat",{"$param":"tail"}]}
  let expression = admit(source_cursor(source), test_limits()).unwrap()
  let refs = parameter_references(expression)
  assert_eq(refs.map(r => r.name), ["left", "item", "repeat", "repeat", "tail"])
  assert_eq(location_path(refs[0].location), [
    @source.Key("array"),
    @source.Index(2),
    @source.Key("in"),
    @source.Index(0),
  ])
  assert_eq(refs[0].location.range, Some({ start: 0, end: 5, }))
  assert_eq(location_path(refs[1].location), [
    @source.Key("array"),
    @source.Index(2),
    @source.Key("in"),
    @source.Index(1),
    @source.Key("literal"),
    @source.Index(2),
  ])
  assert_eq(refs[1].location.range, None)
  assert_eq(refs[2].location.range, Some({ start: 0, end: 7, }))
  assert_eq(refs[3].location.range, Some({ start: 10, end: 17, }))
  location_path(refs[0].location).clear()
  refs.clear()
  assert_eq(parameter_references(expression).length(), 5)
  assert_eq(
    location_path(parameter_references(expression)[0].location).length(),
    4,
  )
}

///|
test "closed forms reject malformed arguments and never discover arbitrary data" {
  for
    source in [
      "{}",
      "[]",
      "null",
      "true",
      "1",
      (
        #|{"field":"x","literal":1}
      ),
      (
        #|{"unknown":{"literal":1}}
      ),
      (
        #|{"$param":"bad-name"}
      ),
      (
        #|{"cast":{"value":"x","target":{"type":"number","nullable":false}}}
      ),
      (
        #|{"to_decimal":{"value":"x","precision":1,"scale":2}}
      ),
      (
        #|{"property":{"value":"x","name":"a.b"}}
      ),
      (
        #|{"subscript":{"value":"x","index":"0","extra":true}}
      ),
      (
        #|{"object":{}}
      ),
      (
        #|{"object":{"__cid":"x"}}
      ),
      (
        #|{"empty_array":{"items":{"type":"decimal","nullable":false,"precision":1,"scale":2}}}
      ),
      (
        #|{"in":["x",{"literal":[{"$param":"x","extra":0}]}]}
      ),
      (
        #|{"in":["x",{"literal":[[1]]}]}
      ),
      (
        #|{"in":["x","[1,2]"]}
      ),
      (
        #|{"like":["x",{"concat":[{"literal":"a"},{"literal":"%"}]}]}
      ),
      (
        #|{"eq":["x","NULL"]}
      ),
      (
        #|{"case":{"when":[]}}
      ),
      (
        #|{"case":{"when":[{"when":"x"}]}}
      ),
      (
        #|{"regex_match":{"value":"x","pattern":"pattern","flags":"i"}}
      ),
      (
        #|{"date_add":["x","1",{"literal":"weeks"}]}
      ),
      (
        #|{"template":"unclosed {name"}
      ),
      (
        #|{"template":"{}"}
      ),
      (
        #|{"template":"{nested {name}}"}
      ),
    ] {
    assert_true(
      admit(source_cursor(source), test_limits()) is Err(_),
      msg=source,
    )
  }
}

///|
test "syntax does not preempt type checking or evaluation" {
  for
    source in [
      (
        #|{"if":[{"literal":12},{"literal":null},{"literal":false}]}
      ),
      (
        #|{"object":{"line\nname":"missing"}}
      ),
      (
        #|{"empty_array":{"items":{"type":"object","nullable":false,"fields":{}}}}
      ),
      (
        #|{"subscript":{"value":{"array":[]},"index":{"literal":-0.5}}}
      ),
      (
        #|{"substring":{"value":"x","start":"-3","length":"-1"}}
      ),
      (
        #|{"cast":{"value":{"literal":null},"target":{"type":"number"}}}
      ),
      (
        #|{"is_distinct_from":[{"literal":null},{"literal":null}]}
      ),
      (
        #|{"template":"{{literal}} {name}"}
      ),
      (
        #|{"in":["x",{"literal":[]}]}
      ),
      (
        #|{"regex_match":{"value":"x","pattern":{"$param":"p"},"flags":"z"}}
      ),
    ] {
    assert_true(
      admit(source_cursor(source), test_limits()) is Ok(_),
      msg=source,
    )
  }
}

///|
test "limits apply cumulatively to all embedded strings and retained output" {
  let root = source_cursor("{\"array\":[\"$a\",\"$b\"]}")
  let limits = test_limits()
  assert_true(admit(root, { ..limits, max_tokens: 2, }) is Ok(_))
  assert_true(
    admit(root, { ..limits, max_tokens: 1, }) is Err({ kind: Text(_), .. }),
  )
  // Pure structured literal: one object + one scalar, seven UTF-8 key bytes.
  let literal = source_cursor("{\"literal\":null}")
  let exact : Limits = {
    max_nodes: 2,
    max_depth: 1,
    max_text_bytes: 7,
    max_tokens: 0,
    tree: {
      max_nodes: 2,
      max_depth: 1,
      max_string_bytes: 7,
      max_total_string_bytes: 7,
    },
  }
  assert_true(admit(literal, exact) is Ok(_))
  assert_true(
    admit(literal, { ..exact, max_nodes: 1, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    admit(literal, { ..exact, max_depth: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    admit(literal, { ..exact, max_text_bytes: 6, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    admit(literal, { ..exact, tree: { ..exact.tree, max_nodes: 1, }, })
    is Err(_),
  )
  for cap = 0; cap < 40; cap = cap + 1 {
    let result = admit(root, { ..limits, max_nodes: cap, })
    if result is Ok(_) {
      assert_true(admit(root, { ..limits, max_nodes: cap + 1, }) is Ok(_))
    }
  }
  assert_true(
    admit(root, { ..limits, max_nodes: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
}

///|
test "diagnostics retain the source slot and decoded string coordinates" {
  let root = source_cursor("{\"array\":[\"$x +\"]}")
  let issue = match admit(root, test_limits()) {
    Err(issue) => issue
    _ => fail("expected rejection")
  }
  assert_eq(issue.path, [@source.Key("array"), @source.Index(0)])
  assert_eq(issue.range, Some({ start: 4, end: 4, }))
  assert_eq(issue.span.source_path, "test.aql")
  assert_eq(issue.span.start_byte, 10)
  let structured = source_cursor(
    "{\"cast\":{\"value\":\"x\",\"target\":{\"type\":\"number\",\"extra\":1}}}",
  )
  let issue = match admit(structured, test_limits()) {
    Err(issue) => issue
    _ => fail("expected rejection")
  }
  assert_eq(issue.kind, Decode(@decode.UnknownField))
  assert_eq(issue.path, [
    @source.Key("cast"),
    @source.Key("target"),
    @source.Key("extra"),
  ])
  assert_eq(issue.range, None)
  let input = source_cursor("{\"object\":{\"name\":{\"literal\":null}}}")
  let expression = admit(input, test_limits()).unwrap()
  let body = @decode.lookup(
    @decode.open_object(tree(expression)).unwrap(),
    "object",
  ).unwrap()
  let field = @decode.lookup(@decode.open_object(body).unwrap(), "name").unwrap()
  assert_eq(@decode.cursor_key_span(tree(expression)), None)
  assert_eq(@decode.cursor_key_span(field).unwrap().start_byte, 11)
  assert_eq(@decode.cursor_key_span(field).unwrap().end_byte, 17)
}

///|
test "deep structured and mixed expressions are nonrecursive" {
  let source = "{\"not\":".repeat(10000) + "\"TRUE\"" + "}".repeat(10000)
  assert_true(admit(source_cursor(source), test_limits()) is Ok(_))
  let source = "{\"literal\":" +
    "[".repeat(10000) +
    "null" +
    "]".repeat(10000) +
    "}"
  assert_true(admit(source_cursor(source), test_limits()) is Ok(_))
}

///|
test "all textual families retain their canonical structured forms" {
  for
    source in [
      "x", "$x", "NULL", "-x", "NOT x", "x IS NULL", "x IS NOT NULL", "x IS TRUE",
      "x IS FALSE", "x IS UNKNOWN", "x + y", "x - y", "x * y", "x / y", "x % y",
      "x = y", "x <> y", "x < y", "x <= y", "x > y", "x >= y", "x IN (1, $p, NULL)",
      "x NOT IN $p", "x LIKE $p", "x IS DISTINCT FROM NULL", "nullif(x,y)", "x AND y",
      "x OR y", "concat_strict(x,y)", "coalesce(x,NULL)", "if(x,y,z)", "x BETWEEN NULL AND y",
      "CASE WHEN x THEN y ELSE NULL END", "len(x)", "sqrt(x)", "floor(x)", "lower(x)",
      "upper(x)", "trim(x)", "contains(x,y)", "safe_div(x,y)", "replace(x,y,z)",
      "concat(x,y)", "date_trunc('ms',x)", "date_add(x,1,'s')", "date_diff(x,y,'d')",
      "try_decimal(x,38,2)", "quantize(x,8,2,'half_even')", "decimal_divide(x,y,8,2,'floor')",
      "split_part(x,$d,0)", "substring(x,-1,0)", "utf8_truncate(x,-1)", "try_number(x)",
      "nfkc(x)", "case_fold(x)", "parse_timestamp(x,$p)", "try_timestamp(x,$p)",
      "format_timestamp(x,$p)", "regex_match(x,$p,'i')", "regex_extract(x,$p,1,'m')",
      "regex_replace(x,$p,y,'s')", "vector_score(x,y,'dot')", "vector_concat(x,y)",
      "[]", "[x,y]", "left.x", "x.name", "x[-1]", "CAST(NULL AS DECIMAL(8,2))",
    ] {
    let parsed = @text.parse(source, {
      max_input_bytes: 10000,
      max_tokens: 10000,
      max_nodes: 10000,
      max_depth: 10000,
      tree: test_limits().tree,
    }).unwrap()
    let from_text = admit(text_cursor(source), test_limits())
    let from_structure = admit(@text.tree(parsed), test_limits())
    assert_true(from_text is Ok(_), msg=source)
    assert_true(from_structure is Ok(_), msg=source)
    assert_cursor(tree(from_text.unwrap()), @text.tree(parsed))
    assert_cursor(tree(from_structure.unwrap()), @text.tree(parsed))
  }
}

///|
test "raw owned literals are validated without repairing their values" {
  let span = @decode.cursor_span(source_cursor("null"))
  for
    value in [
      @source.String("e\u{301}"),
      @source.String("x\r\n"),
      @source.Number(-0.0),
      @source.Number(0.0 / 0.0),
      @source.Number(1.0 / 0.0),
    ] {
    let raw : @source.Node = {
      value: @source.Object([
        { key: "literal", key_span: span, value: { value, span, }, },
      ]),
      span,
    }
    let cursor = @decode.admit(raw, test_limits().tree).unwrap()
    assert_true(admit(cursor, test_limits()) is Err(_))
  }
}

///|
test "repeated fragments cannot reset parser node or text budgets" {
  let limits = test_limits()
  // Each $x fragment allocates two parser nodes and visits those two again.
  // array object + array + two slots consume four further nodes.
  let pair = source_cursor("{\"array\":[\"$x\",\"$x\"]}")
  assert_true(
    admit(pair, { ..limits, max_nodes: 12, max_text_bytes: 23, max_tokens: 2, })
    is Ok(_),
  )
  assert_true(admit(pair, { ..limits, max_nodes: 11, }) is Err(_))
  assert_true(admit(pair, { ..limits, max_text_bytes: 22, }) is Err(_))
  let wide = "{\"array\":[" + "\"$x\",".repeat(9999) + "\"$x\"]}"
  assert_true(admit(source_cursor(wide), limits) is Ok(_))
}
