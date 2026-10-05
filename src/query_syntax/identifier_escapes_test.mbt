///|
test "quoted identifiers decode the pinned GoogleSQL escape repertoire" {
  // Expectations are authored from the pinned decoder, not STRING token output.
  for
    (escaped, decoded) in [
      ("\\a", "\u{7}"),
      ("\\b", "\u{8}"),
      ("\\f", "\u{c}"),
      ("\\n", "\n"),
      ("\\r", "\r"),
      ("\\t", "\t"),
      ("\\v", "\u{b}"),
      ("\\?", "?"),
      ("\\'", "'"),
      ("\\\"", "\""),
      ("\\`", "`"),
      ("\\\\", "\\"),
      ("\\000", "\u{0}"),
      ("\\377", "ÿ"),
      ("\\x41", "A"),
      ("\\XFF", "ÿ"),
      ("\\u0062", "b"),
      ("\\U0001F600", "😀"),
    ] {
    assert_eq(
      values("`a" + escaped + "z`"),
      [QuotedName("a" + decoded + "z"), End],
      msg=escaped,
    )
  }
}

///|
test "quoted identifiers permit physical newlines and retain source spans" {
  let text = "`a\r\nb` `a\nb` `a\\nb`"
  let tokens = tokenize(text, limits(), source_path="identifiers.sql").unwrap()
  for i in 0..<3 {
    assert_eq(token_at(tokens, i).unwrap().value, QuotedName("a\nb"))
  }
  let first = token_at(tokens, 0).unwrap()
  assert_eq(first.start, 0)
  assert_eq(first.end, 6)
  let span = @origin.span(token_origin(tokens, 0).unwrap())
  assert_eq(span.start_line, 1)
  assert_eq(span.end_line, 2)
  assert_eq(span.end_column, 3)
}

///|
test "quoted identifiers retain precise malformed escape refusals" {
  for escaped in ["\\400", "\\777", "\\00", "\\x4", "\\z", "\\\n"] {
    assert_true(
      tokenize("`a" + escaped + "`", limits())
      is Err({ issue: Lexical(InvalidEscape), .. }),
      msg=escaped,
    )
  }
  for escaped in ["\\uD800", "\\U00110000"] {
    assert_true(
      tokenize("`a" + escaped + "`", limits())
      is Err({ issue: Lexical(InvalidScalar), .. }),
      msg=escaped,
    )
  }
  assert_true(
    tokenize("``", limits()) is Err({ issue: Lexical(EmptyIdentifier), .. }),
  )
}

///|
test "quoted identifier decoding retains decoded bytes and work ceilings" {
  let text = "`\\101\\x42\\U0001F600`"
  let tokens = tokenize(text, limits()).unwrap()
  assert_eq(usage(tokens, LiteralBytes), 6)
  let work = usage(tokens, Work)
  assert_true(
    tokenize(text, { ..limits(), max_literal_bytes: 6, max_work: work, })
    is Ok(_),
  )
  assert_true(
    tokenize(text, { ..limits(), max_literal_bytes: 5, })
    is Err({ issue: Limit(LiteralBytes), .. }),
  )
  assert_true(
    tokenize(text, { ..limits(), max_work: work - 1, })
    is Err({ issue: Limit(Work), .. }),
  )
  assert_eq(values("r'\\101'"), [Text("\\101"), End])
}
