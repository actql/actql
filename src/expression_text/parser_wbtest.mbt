///|
fn test_limits() -> Limits {
  {
    max_input_bytes: 2000000,
    max_tokens: 200000,
    max_nodes: 200000,
    max_depth: 30000,
    tree: {
      max_nodes: 200000,
      max_depth: 30000,
      max_string_bytes: 2000000,
      max_total_string_bytes: 4000000,
    },
  }
}

///|
fn accepted(source : String) -> Expression raise {
  match parse(source, test_limits()) {
    Ok(value) => value
    Err(_) => fail("unexpected expression rejection: " + source)
  }
}

///|
fn assert_tree(source : String, expected : String) -> Unit raise {
  let expression = accepted(source)
  let node = @value.parse_json(expected, {
    max_input_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 30000,
  }).unwrap()
  let pending = [(tree(expression), node)]
  while pending.pop() is Some((cursor, node)) {
    match (@decode.view(cursor), node.value) {
      (@decode.NullValue, @value.Null) => ()
      (@decode.BoolValue(left), @value.Bool(right)) => assert_eq(left, right)
      (@decode.NumberValue(left), @value.Number(right)) =>
        assert_eq(left.reinterpret_as_uint64(), right.reinterpret_as_uint64())
      (@decode.TextValue(left), @value.String(right)) => assert_eq(left, right)
      (@decode.ArrayValue(left), @value.Array(right)) => {
        assert_eq(left.length(), right.length())
        for i, child in left {
          pending.push((child, right[i]))
        }
      }
      (@decode.ObjectValue(left), @value.Object(right)) => {
        assert_eq(
          @decode.object_field_names(cursor).unwrap().length(),
          right.length(),
        )
        for field in right {
          // Presence, not non-nullness: {"literal": null} is a valid tree.
          pending.push((@decode.lookup(left, field.key).unwrap(), field.value))
        }
      }
      _ => fail("different structured expression")
    }
  }
}

///|
test "precedence, associativity and grouping" {
  assert_tree(
    "a + b * c - d / e % f", "{\"subtract\":[{\"add\":[{\"field\":\"a\"},{\"multiply\":[{\"field\":\"b\"},{\"field\":\"c\"}]}]},{\"modulo\":[{\"divide\":[{\"field\":\"d\"},{\"field\":\"e\"}]},{\"field\":\"f\"}]}]}",
  )
  assert_tree(
    "a AND b AND c", "{\"and\":[{\"field\":\"a\"},{\"field\":\"b\"},{\"field\":\"c\"}]}",
  )
  assert_tree(
    "(a AND b) AND c", "{\"and\":[{\"and\":[{\"field\":\"a\"},{\"field\":\"b\"}]},{\"field\":\"c\"}]}",
  )
  assert_tree(
    "a OR (b OR c)", "{\"or\":[{\"field\":\"a\"},{\"or\":[{\"field\":\"b\"},{\"field\":\"c\"}]}]}",
  )
  assert_tree(
    "'a' || 'b' || 'c'", "{\"concat_strict\":[{\"literal\":\"a\"},{\"literal\":\"b\"},{\"literal\":\"c\"}]}",
  )
  assert_tree("-((2))", "{\"literal\":-2}")
  assert_tree("- -2", "{\"negate\":{\"literal\":-2}}")
  assert_tree(
    "-(1 + 2)", "{\"negate\":{\"add\":[{\"literal\":1},{\"literal\":2}]}}",
  )
}

///|
test "membership, truth tests and nonassociative families" {
  assert_tree(
    "x NOT BETWEEN 1 AND 2", "{\"not\":{\"between\":[{\"field\":\"x\"},{\"literal\":1},{\"literal\":2}]}}",
  )
  assert_tree(
    "x IS NOT DISTINCT FROM y + 1", "{\"not\":{\"is_distinct_from\":[{\"field\":\"x\"},{\"add\":[{\"field\":\"y\"},{\"literal\":1}]}]}}",
  )
  assert_tree(
    "x IS NOT UNKNOWN", "{\"not\":{\"is_unknown\":{\"field\":\"x\"}}}",
  )
  assert_tree("x IS TRUE", "{\"is_true\":{\"field\":\"x\"}}")
  assert_tree("x IS FALSE", "{\"is_false\":{\"field\":\"x\"}}")
  assert_tree(
    "x NOT LIKE ($p)", "{\"not\":{\"like\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}}",
  )
  for
    source in [
      "x IN (TRUE, NULL) IN (1)", "x LIKE 'a' LIKE 'b'", "x BETWEEN 1 AND 2 BETWEEN 3 AND 4",
      "x IS TRUE IS FALSE", "x = (NULL)", "NULL < x", "x IN $p[0]", "x IN ([])",
      "x IN ([1])", "x IN (- -1)", "x LIKE concat('a','b')",
    ] {
    assert_true(parse(source, test_limits()) is Err(_), msg=source)
  }
  ignore(accepted("(x < y) < z"))
  ignore(accepted("x IN (1) = TRUE IS TRUE"))
}

///|
test "predicate result postfixes require explicit grouping" {
  for
    (source, expected) in [
      ("a IS NULL", "{\"is_null\":{\"field\":\"a\"}}"),
      ("a IS NOT NULL", "{\"not_null\":{\"field\":\"a\"}}"),
      ("a IS TRUE", "{\"is_true\":{\"field\":\"a\"}}"),
      ("a IS NOT TRUE", "{\"not\":{\"is_true\":{\"field\":\"a\"}}}"),
      ("a IS FALSE", "{\"is_false\":{\"field\":\"a\"}}"),
      ("a IS NOT FALSE", "{\"not\":{\"is_false\":{\"field\":\"a\"}}}"),
      ("a IS UNKNOWN", "{\"is_unknown\":{\"field\":\"a\"}}"),
      ("a IS NOT UNKNOWN", "{\"not\":{\"is_unknown\":{\"field\":\"a\"}}}"),
      ("a IN (1)", "{\"in\":[{\"field\":\"a\"},{\"literal\":[1]}]}"),
      ("a NOT IN (1)", "{\"not_in\":[{\"field\":\"a\"},{\"literal\":[1]}]}"),
    ] {
    for suffix in [".foo", "[0]", ".foo[0]"] {
      let issue = parse(source + suffix, test_limits()).unwrap_err()
      assert_eq(issue.kind, Syntax)
      assert_eq(issue.range, {
        start: source.length(),
        end: source.length() + 1,
      })
      // A lower-precedence parent must not adopt the rejected postfix.
      for prefix in ["NOT ", "x AND ", "x OR ", "len("] {
        let end = if prefix == "len(" { ")" } else { "" }
        assert_true(
          parse(prefix + source + suffix + end, test_limits()) is Err(_),
        )
      }
    }
    assert_tree(
      "(" + source + ").foo",
      "{\"property\":{\"value\":" + expected + ",\"name\":\"foo\"}}",
    )
    assert_tree(
      "(" + source + ")[0]",
      "{\"subscript\":{\"value\":" + expected + ",\"index\":{\"literal\":0}}}",
    )
  }
  // Postfixes on a predicate's right operand remain legal and bind there.
  assert_tree(
    "a = b.foo", "{\"eq\":[{\"field\":\"a\"},{\"property\":{\"value\":{\"field\":\"b\"},\"name\":\"foo\"}}]}",
  )
  assert_tree(
    "a IS DISTINCT FROM b[0]", "{\"is_distinct_from\":[{\"field\":\"a\"},{\"subscript\":{\"value\":{\"field\":\"b\"},\"index\":{\"literal\":0}}}]}",
  )
  assert_tree(
    "a BETWEEN b AND c.foo", "{\"between\":[{\"field\":\"a\"},{\"field\":\"b\"},{\"property\":{\"value\":{\"field\":\"c\"},\"name\":\"foo\"}}]}",
  )
  assert_tree(
    "a IS NULL AND b.foo", "{\"and\":[{\"is_null\":{\"field\":\"a\"}},{\"property\":{\"value\":{\"field\":\"b\"},\"name\":\"foo\"}}]}",
  )
}

///|
test "field, join field and postfix access" {
  assert_tree(
    "left.a.b[1 + $i]", "{\"subscript\":{\"value\":{\"property\":{\"value\":{\"join_field\":{\"side\":\"left\",\"name\":\"a\"}},\"name\":\"b\"}},\"index\":{\"add\":[{\"literal\":1},{\"$param\":\"i\"}]}}}",
  )
  assert_tree(
    "\"left\".a", "{\"property\":{\"value\":{\"field\":\"left\"},\"name\":\"a\"}}",
  )
  assert_tree(
    "LEFT.a", "{\"property\":{\"value\":{\"field\":\"LEFT\"},\"name\":\"a\"}}",
  )
  assert_tree(
    "[1, $p, []]", "{\"array\":[{\"literal\":1},{\"$param\":\"p\"},{\"array\":[]}]}",
  )
}

///|
test "searched case and cast mapping" {
  assert_tree(
    "CASE WHEN a THEN b WHEN c THEN d ELSE e END", "{\"case\":{\"when\":[{\"when\":{\"field\":\"a\"},\"then\":{\"field\":\"b\"}},{\"when\":{\"field\":\"c\"},\"then\":{\"field\":\"d\"}}],\"else\":{\"field\":\"e\"}}}",
  )
  assert_tree(
    "CASE WHEN a THEN b END", "{\"case\":{\"when\":[{\"when\":{\"field\":\"a\"},\"then\":{\"field\":\"b\"}}]}}",
  )
  assert_tree(
    "cast(x as DeCiMaL(38, 2))", "{\"cast\":{\"value\":{\"field\":\"x\"},\"target\":{\"type\":\"decimal\",\"precision\":38,\"scale\":2}}}",
  )
  for
    source in [
      "CAST(x AS DECIMAL(1,2))", "CAST(x AS DECIMAL(1.0,0))", "CAST(x AS DECIMAL($p,0))",
      "CAST(x AS DATE)", "CASE END", "CASE WHEN x THEN END", "CASE WHEN x THEN y ELSE z",
    ] {
    assert_true(parse(source, test_limits()) is Err(_), msg=source)
  }
}

///|
test "literal-only function fields and profile-neutral syntax" {
  assert_tree(
    "vector_score(a, b, 'dot')", "{\"vector_score\":{\"left\":{\"field\":\"a\"},\"right\":{\"field\":\"b\"},\"metric\":\"dot\"}}",
  )
  assert_tree(
    "regex_match(x, $pattern, 'im')", "{\"regex_match\":{\"value\":{\"field\":\"x\"},\"pattern\":{\"$param\":\"pattern\"},\"flags\":\"im\"}}",
  )
  assert_tree(
    "date_trunc('d', x)", "{\"date_trunc\":[{\"literal\":\"d\"},{\"field\":\"x\"}]}",
  )
  assert_tree(
    "to_boolean(x)", "{\"cast\":{\"value\":{\"field\":\"x\"},\"target\":{\"type\":\"boolean\"}}}",
  )
  for
    source in [
      "to_decimal(x, 39, 0)", "try_decimal(x, 1, 2)", "quantize(x, 2, 1, 'unknown')",
      "decimal_divide(x,y,1,2,'floor')", "vector_score(a,b,$metric)", "vector_score(a,b,'other')",
      "vector_concat(a)", "date_add(x, 1, $unit)", "date_diff(x,y,'year')", "regex_match(x, 'a', $flags)",
      "try_decimal(x, p, 2)",
    ] {
    assert_true(parse(source, test_limits()) is Err(_), msg=source)
  }
  // Type inference, dynamic operand domains and profile admission are separate.
  for
    source in [
      "nfkc(x)", "case_fold(x)", "sqrt('not a number')", "substring(x, $start, $length)",
      "regex_match(x, $pattern)", "1 AND 2",
    ] {
    ignore(accepted(source))
  }
}

///|
test "SQL-style quoting, normalization and literal opacity" {
  assert_tree("'e\u0301\r\n''$hidden'", "{\"literal\":\"é\\n'$hidden\"}")
  assert_tree("\"e\u0301\rname\"", "{\"field\":\"é\\nname\"}")
  assert_tree("'a\\nb'", "{\"literal\":\"a\\\\nb\"}")
  assert_tree("\"a\"\"b\"", "{\"field\":\"a\\\"b\"}")
  for
    source in [
      "\"\"", "'unterminated", "a != b", "a -- b", "a /*b*/", "a */ b", "a\u00a0+b",
      "a; b", ".5", "1.", "1e+", "1 2",
    ] {
    assert_true(parse(source, test_limits()) is Err(_), msg=source)
  }
}

///|
test "numeric rebasing preserves long significands and exponent cancellation" {
  let overflow = "0." + "0".repeat(65535) + "1e655360"
  assert_true(
    parse(overflow, test_limits())
    is Err({ kind: Lexical(NonfiniteNumber), .. }),
  )
  assert_tree("0." + "0".repeat(65535) + "1e65536", "{\"literal\":1}")
  assert_tree("1" + "0".repeat(65536) + "e-65536", "{\"literal\":1}")
  assert_tree("1e-99999999", "{\"literal\":0}")
  assert_tree("5e-324", "{\"literal\":5e-324}")
  assert_tree("9007199254740993", "{\"literal\":9007199254740992}")
  for source in ["-0", "-(0)", "-1e-99999999", "1e309"] {
    assert_true(parse(source, test_limits()) is Err(_), msg=source)
  }
}

///|
test "ordinary field references retain token ranges and detached storage" {
  let result = accepted("a + a.x + left.id + \"left\".id + len('hidden')")
  assert_eq(field_references(result), [
    { name: "a", range: { start: 0, end: 1, }, },
    { name: "a", range: { start: 4, end: 5, }, },
    { name: "left", range: { start: 20, end: 26, }, },
  ])
  let references = field_references(result)
  references.clear()
  assert_eq(field_references(result).length(), 3)
}

///|
test "decoded scalar ranges and enclosing source are separate" {
  let outer : @value.Span = {
    source_path: "program.aql",
    start_byte: 50,
    end_byte: 100,
    start_line: 4,
    start_column: 2,
    end_line: 7,
    end_column: 3,
  }
  let result = parse(
    "'😀' + $p + '$hidden' + $p",
    test_limits(),
    enclosing_span=outer,
  ).unwrap()
  assert_eq(enclosing_span(result), Some(outer))
  assert_eq(parameter_references(result), [
    { name: "p", range: { start: 6, end: 8, }, },
    { name: "p", range: { start: 23, end: 25, }, },
  ])
  let references = parameter_references(result)
  references.clear()
  assert_eq(parameter_references(result).length(), 2)
  assert_eq(
    parameter_references(accepted("x IN ($p, ($q), '$r')")).map(r => r.name),
    ["p", "q"],
  )
  let error = parse("'😀' + @", test_limits(), enclosing_span=outer).unwrap_err()
  assert_eq(error.range, { start: 6, end: 7, })
  assert_eq(error.enclosing_span, Some(outer))
  assert_eq(@decode.cursor_span(tree(result)).source_path, "<expression>")
  let multiline = accepted("'a\r\nb' + $p")
  assert_eq(parameter_references(multiline)[0].range, { start: 9, end: 11, })
  let span = @decode.cursor_span(tree(multiline))
  assert_eq(
    (span.start_byte, span.end_byte, span.end_line, span.end_column),
    (0, 11, 2, 8),
  )
}

///|
test "malformed UTF-16 is rejected on every target" {
  for unit in [0xd800, 0xdc00] {
    let text = String::from_array([unit.unsafe_to_char(), 'A'])
    assert_true(
      parse(text, test_limits()) is Err({ kind: Lexical(InvalidUnicode), .. }),
    )
  }
}

///|
test "independent lexer, parser-work and owned-tree budgets" {
  let base = test_limits()
  assert_true(
    parse("1", {
      max_input_bytes: 1,
      max_tokens: 1,
      max_nodes: 2,
      max_depth: 1,
      tree: {
        max_nodes: 2,
        max_depth: 1,
        max_string_bytes: 7,
        max_total_string_bytes: 7,
      },
    })
    is Ok(_),
  )
  assert_true(
    parse("1", { ..base, max_input_bytes: 0, })
    is Err({ kind: Lexical(ByteLimit), .. }),
  )
  assert_true(
    parse("1", { ..base, max_tokens: 0, })
    is Err({ kind: Lexical(TokenLimit), .. }),
  )
  assert_true(
    parse("1", { ..base, max_nodes: 1, }) is Err({ kind: CapacityExceeded, .. }),
  )
  assert_true(
    parse("1", { ..base, max_depth: 0, }) is Err({ kind: CapacityExceeded, .. }),
  )
  assert_true(
    parse("(1)", { ..base, max_depth: 1, })
    is Err({ kind: CapacityExceeded, .. }),
  )
  for
    limits in [
      { ..base.tree, max_nodes: 1, },
      { ..base.tree, max_depth: 0, },
      { ..base.tree, max_string_bytes: 6, },
      { ..base.tree, max_total_string_bytes: 6, },
    ] {
    assert_true(
      parse("1", { ..base, tree: limits, })
      is Err({ kind: TreeAdmission(@decode.BudgetExceeded), .. }),
    )
  }
  for
    limits in [
      { ..base, max_input_bytes: -1, },
      { ..base, max_tokens: -1, },
      { ..base, max_nodes: -1, },
      { ..base, max_depth: -1, },
      { ..base, tree: { ..base.tree, max_nodes: -1, }, },
    ] {
    assert_true(parse("1", limits) is Err({ kind: InvalidLimits, .. }))
  }
  assert_true(parse("'😀'", { ..base, max_input_bytes: 6, }) is Ok(_))
  assert_true(parse("'😀'", { ..base, max_input_bytes: 5, }) is Err(_))
}

///|
test "deep grouping, calls, arrays, CASE and prefixes are nonrecursive" {
  for
    source in [
      "(".repeat(10000) + "1" + ")".repeat(10000),
      "len(".repeat(10000) + "x" + ")".repeat(10000),
      "[".repeat(10000) + "1" + "]".repeat(10000),
      "CASE WHEN x THEN ".repeat(3000) + "1" + " END".repeat(3000),
      "NOT ".repeat(10000) + "x",
    ] {
    ignore(accepted(source))
  }
}

///|
test "long operator chains and argument lists do not consume nesting budget" {
  let base = test_limits()
  for
    source in [
      "x OR ".repeat(10000) + "x",
      "1 + ".repeat(10000) + "1",
      "concat(" + "'a',".repeat(10000) + "'b')",
    ] {
    assert_true(parse(source, { ..base, max_depth: 2, }) is Ok(_))
  }
  let expression = accepted("x AND ".repeat(10000) + "x")
  let root = @decode.open_object(tree(expression)).unwrap()
  assert_eq(
    @decode.elements(@decode.required(root, "and").unwrap()).unwrap().length(),
    10001,
  )
}

///|
test "every scalar call uses its fixed positional mapping" {
  for
    name in [
      "len", "sqrt", "floor", "lower", "upper", "trim", "negate", "nfkc", "case_fold",
    ] {
    assert_tree(name + "(x)", "{\"" + name + "\":{\"field\":\"x\"}}")
    assert_true(
      parse(name + "()", test_limits()) is Err({ kind: InvalidArguments, .. }),
    )
    assert_true(
      parse(name + "(x,y)", test_limits())
      is Err({ kind: InvalidArguments, .. }),
    )
  }
  for name in ["contains", "safe_div", "nullif"] {
    assert_tree(
      name + "(x,y)",
      "{\"" + name + "\":[{\"field\":\"x\"},{\"field\":\"y\"}]}",
    )
    assert_true(
      parse(name + "(x)", test_limits()) is Err({ kind: InvalidArguments, .. }),
    )
    assert_true(
      parse(name + "(x,y,z)", test_limits())
      is Err({ kind: InvalidArguments, .. }),
    )
  }
  for name in ["concat", "concat_strict", "coalesce", "vector_concat"] {
    assert_tree(
      name + "(x,y)",
      "{\"" + name + "\":[{\"field\":\"x\"},{\"field\":\"y\"}]}",
    )
  }
  for name in ["replace", "if"] {
    assert_tree(
      name + "(x,y,z)",
      "{\"" +
      name +
      "\":[{\"field\":\"x\"},{\"field\":\"y\"},{\"field\":\"z\"}]}",
    )
  }
  for name in ["number", "string", "boolean", "timestamp"] {
    let expected = "{\"cast\":{\"value\":{\"field\":\"x\"},\"target\":{\"type\":\"" +
      name +
      "\"}}}"
    assert_tree("to_" + name + "(x)", expected)
    assert_tree("CAST(x AS " + name + ")", expected)
  }
  for name in ["date_add", "date_diff"] {
    assert_tree(
      name + "(x,y,'ms')",
      "{\"" +
      name +
      "\":[{\"field\":\"x\"},{\"field\":\"y\"},{\"literal\":\"ms\"}]}",
    )
  }
  for name in ["parse_timestamp", "try_timestamp", "format_timestamp"] {
    assert_tree(
      name + "(x,$pattern)",
      "{\"" +
      name +
      "\":{\"value\":{\"field\":\"x\"},\"pattern\":{\"$param\":\"pattern\"}}}",
    )
    assert_true(
      parse(name + "(x, field_pattern)", test_limits())
      is Err({ kind: InvalidArguments, .. }),
    )
  }
  assert_tree(
    "try_decimal(x,38,0)", "{\"try_decimal\":{\"value\":{\"field\":\"x\"},\"precision\":38,\"scale\":0}}",
  )
  assert_tree(
    "decimal_divide(x,y,18,2,'half_even')", "{\"decimal_divide\":{\"left\":{\"field\":\"x\"},\"right\":{\"field\":\"y\"},\"precision\":18,\"scale\":2,\"rounding\":\"half_even\"}}",
  )
  assert_tree(
    "split_part(x,$delimiter,$index)", "{\"split_part\":{\"value\":{\"field\":\"x\"},\"delimiter\":{\"$param\":\"delimiter\"},\"index\":{\"$param\":\"index\"}}}",
  )
  assert_true(
    parse("split_part(x, delimiter, 1)", test_limits())
    is Err({ kind: InvalidArguments, .. }),
  )
  assert_tree(
    "substring(x,$start,$length)", "{\"substring\":{\"value\":{\"field\":\"x\"},\"start\":{\"$param\":\"start\"},\"length\":{\"$param\":\"length\"}}}",
  )
  assert_tree(
    "utf8_truncate(x,$bytes)", "{\"utf8_truncate\":{\"value\":{\"field\":\"x\"},\"max_bytes\":{\"$param\":\"bytes\"}}}",
  )
  assert_tree("try_number(x)", "{\"try_number\":{\"value\":{\"field\":\"x\"}}}")
  assert_tree(
    "regex_extract(x,'(a)',1)", "{\"regex_extract\":{\"value\":{\"field\":\"x\"},\"pattern\":{\"literal\":\"(a)\"},\"capture\":{\"literal\":1}}}",
  )
  assert_tree(
    "regex_replace(x,$p,'$1','i')", "{\"regex_replace\":{\"value\":{\"field\":\"x\"},\"pattern\":{\"$param\":\"p\"},\"replacement\":{\"literal\":\"$1\"},\"flags\":\"i\"}}",
  )
}

///|
test "stable lexical and syntax diagnostics retain offending token ranges" {
  let cases : Array[(String, IssueKind, Range)] = [
    ("$1", Lexical(ParameterName), { start: 0, end: 1, }),
    ("x -- comment", Lexical(Comment), { start: 2, end: 4, }),
    ("'x", Lexical(UnclosedQuote), { start: 0, end: 2, }),
    ("a +", Syntax, { start: 3, end: 3, }),
    ("a . 1", Syntax, { start: 4, end: 5, }),
    ("eval(x)", UnknownFunction, { start: 0, end: 4, }),
    ("len(x,y)", InvalidArguments, { start: 0, end: 3, }),
    ("-0", InvalidArguments, { start: 0, end: 1, }),
    ("a b", Syntax, { start: 2, end: 3, }),
  ]
  for (source, kind, range) in cases {
    let issue = parse(source, test_limits()).unwrap_err()
    assert_eq(issue.kind, kind)
    assert_eq(issue.range, range)
  }
}
