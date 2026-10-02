///|
test "GoogleSQL raw and triple quoted forms preserve independent decoded values" {
  // Authored from the selected lexical profile, not from the decoder output.
  let cases = [
    ("r'\\n'", "\\n"),
    ("R\"\\u0041\"", "\\u0041"),
    ("r'a\\'b'", "a\\'b"),
    ("r'\\\\'", "\\\\"),
    ("'''it's \"here\"'''", "it's \"here\""),
    ("\"\"\"one\nline\"\"\"", "one\nline"),
    ("'''a\rb\r\nc\nd'''", "a\nb\nc\nd"),
    ("'''\\r\\n'''", "\r\n"),
    ("r'''\\n\nnext'''", "\\n\nnext"),
    ("r'''a\\\r\nb'''", "a\\\r\nb"),
    ("R\"\"\"a\rb\r\nc\"\"\"", "a\nb\nc"),
    ("'''e\u0301'''", "e\u0301"),
    ("'''a''b'c'''", "a''b'c"),
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
test "separated query chunks concatenate values without extending raw mode" {
  let cases = [
    ("'a' \"b\"", "ab"),
    ("r'\\n' /* only the first chunk is raw */ '\\n'", "\\n\n"),
    ("'''a''' -- join\n r\"b\"", "ab"),
    ("'' \"\" ''''''", ""),
    ("r'日' /*c*/ \"😀\"", "日😀"),
  ]
  for (source, expected) in cases {
    let expression = parse_expression(source, expression_limits()).unwrap()
    assert_eq(
      kind(expression, expression_root(expression)),
      StringLiteral(expected),
    )
  }
  let expression = parse_expression(
    "r'日' /*c*/ \"😀\"",
    expression_limits(),
  ).unwrap()
  let node = expression_node(expression, expression_root(expression)).unwrap()
  assert_eq(node.start, 0)
  assert_eq(node.end, 19)
}

///|
test "literal forms reject unterminated delimiters and invalid concatenation" {
  for
    source in [
      "r'odd\\'", "'''unfinished''", "\"\"\"unfinished\"\"", "'a''b'", "r'a'r'b'",
      "'''a'''\"b\"", "`a` `b`", "b'bytes'", "rb'bytes'", "'a' b'b'", "r'raw\nline'",
      "r'raw\\\nline'", "'''bad\\\nline'''",
    ] {
    assert_true(
      parse_expression(source, expression_limits()) is Err(_),
      msg=source,
    )
  }
}

///|
test "literal chunk decoding remains bounded and annotations retain their profile" {
  for source in ["r'\\n日'", "'''a\r\n😀'''", "r'''\\r'''", "'日' \"😀\""] {
    let tokens = tokenize(source, limits()).unwrap()
    let bytes = usage(tokens, LiteralBytes)
    let work = usage(tokens, Work)
    assert_true(
      tokenize(source, { ..limits(), max_literal_bytes: bytes, max_work: work, })
      is Ok(_),
    )
    assert_true(
      tokenize(source, { ..limits(), max_literal_bytes: bytes - 1, })
      is Err({ issue: Limit(LiteralBytes), .. }),
    )
    assert_true(
      tokenize(source, { ..limits(), max_work: work - 1, })
      is Err({ issue: Limit(Work), .. }),
    )
  }
  for source in ["r\"field\"", "\"\"\"field\"\"\""] {
    let tokens = tokenize(source, limits()).unwrap()
    assert_true(!token_at(tokens, 0).unwrap().annotation_compatible)
  }
}
