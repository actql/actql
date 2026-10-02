///|
test "GoogleSQL quoted strings decode the same independent values" {
  let cases = [
    ("'abc'", "abc"),
    ("\"abc\"", "abc"),
    ("\"it's\"", "it's"),
    ("'Title: \"Boy\"'", "Title: \"Boy\""),
    ("'\\a\\b\\f\\n\\r\\t\\v'", "\u0007\u0008\u000c\n\r\t\u000b"),
    ("\"\\a\\b\\f\\n\\r\\t\\v\"", "\u0007\u0008\u000c\n\r\t\u000b"),
    ("'\\\\\\?\\\"\\'\\`'", "\\?\"'`"),
    ("\"\\\\\\?\\\"\\'\\`\"", "\\?\"'`"),
    ("'\\101\\x42\\X43\\u65e5\\U0001F600'", "ABC日😀"),
    ("\"\\101\\x42\\X43\\u65e5\\U0001F600\"", "ABC日😀"),
    ("'\\x41B\\1012'", "ABA2"),
    ("'\\000\\377'", "\u0000\u00ff"),
    ("\"tab\there\"", "tab\there"),
    ("'e\u0301'", "e\u0301"),
    ("\"e\\u0301\"", "e\u0301"),
    ("'\\r\\n'", "\r\n"),
  ]
  for (source, expected) in cases {
    let expression = parse_expression(source, expression_limits()).unwrap()
    assert_eq(
      kind(expression, expression_root(expression)),
      StringLiteral(expected),
    )
  }
}

///|
test "GoogleSQL octal escapes stop at 377 in every quoted STRING form" {
  // Independent scalar expectations from the pinned decoder contract, not
  // values produced by the lexer. The upper bound is U+00FF, not U+01FF.
  for quote in ["'", "\"", "'''", "\"\"\""] {
    for (escape, expected) in [("\\000", "\u0000"), ("\\377", "\u00ff")] {
      let source = quote + escape + quote
      let expression = parse_expression(source, expression_limits()).unwrap()
      assert_eq(
        kind(expression, expression_root(expression)),
        StringLiteral(expected),
      )
    }
    for escape in ["\\400", "\\777"] {
      assert_true(
        tokenize(quote + escape + quote, limits())
        is Err({ issue: Lexical(InvalidEscape), .. }),
      )
      // Raw literals retain both the backslash and digits; they do not
      // apply the decoded escape range to their contents.
      let raw = parse_expression(
        "r" + quote + escape + quote,
        expression_limits(),
      ).unwrap()
      assert_eq(kind(raw, expression_root(raw)), StringLiteral(escape))
    }
  }
}

///|
test "GoogleSQL strings are distinct from backtick identifiers and path names" {
  let quoted = parse_expression("`ID`", expression_limits()).unwrap()
  assert_eq(
    kind(quoted, expression_root(quoted)),
    Reference([{ value: "ID", quoted: true, }]),
  )
  let literal = parse_expression("\"ID\"", expression_limits()).unwrap()
  assert_eq(kind(literal, expression_root(literal)), StringLiteral("ID"))
  for source in ["\"memory\".\"main\".\"records\"", "t.\"id\"", "b'bytes'"] {
    assert_true(
      parse_expression(source, expression_limits()) is Err(_),
      msg=source,
    )
  }
}

///|
test "quoted string errors preserve lexical rejection and original spans" {
  for
    source in [
      "'\\x'", "'\\x4'", "'\\xGG'", "'\\12'", "'\\128'", "'\\8'", "'\\uD800'", "\"\\U00110000\"",
      "'\\/'", "\"raw\nline\"", "\"unfinished", "'unfinished\\",
    ] {
    assert_true(tokenize(source, limits()) is Err(_), msg=source)
  }
  let expression = parse_expression(
    "\r\n \"日\\x41😀\"",
    expression_limits(),
    source_path="quoted.sql",
  ).unwrap()
  let node = expression_node(expression, expression_root(expression)).unwrap()
  assert_eq(node.kind, StringLiteral("日A😀"))
  assert_eq(node.start, 3)
  assert_eq(node.end, 16)
  let span = @origin.span(
    expression_origin(expression, expression_root(expression)).unwrap(),
  )
  assert_eq(span.source_path, "quoted.sql")
  assert_eq(span.start_line, 2)
  assert_eq(span.start_column, 2)
}

///|
test "query escapes cannot widen the historical Graph annotation profile" {
  let valid = tokenize("\"field\" \"\\u0069d\"", limits()).unwrap()
  assert_true(token_at(valid, 0).unwrap().annotation_compatible)
  assert_true(token_at(valid, 1).unwrap().annotation_compatible)
  for source in ["\"\\x66ield\"", "\"\\146ield\"", "\"\\?\"", "\"\\a\""] {
    let tokens = tokenize(source, limits()).unwrap()
    assert_true(!token_at(tokens, 0).unwrap().annotation_compatible)
    assert_true(parse_expression(source, expression_limits()) is Ok(_))
  }
  let controls = tokenize("\"tab\there\"", limits()).unwrap()
  assert_true(!token_at(controls, 0).unwrap().annotation_compatible)
}

///|
test "quoted strings charge decoded bytes and every escape step" {
  for source in ["'\\x41日\\U0001F600'", "\"\\101日\\U0001F600\""] {
    let tokens = tokenize(source, limits()).unwrap()
    assert_eq(usage(tokens, LiteralBytes), 8)
    let work = usage(tokens, Work)
    assert_true(
      tokenize(source, { ..limits(), max_literal_bytes: 8, max_work: work, })
      is Ok(_),
    )
    assert_true(
      tokenize(source, { ..limits(), max_literal_bytes: 7, })
      is Err({ issue: Limit(LiteralBytes), .. }),
    )
    assert_true(
      tokenize(source, { ..limits(), max_work: work - 1, })
      is Err({ issue: Limit(Work), .. }),
    )
  }
}
