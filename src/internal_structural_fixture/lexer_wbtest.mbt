///|
fn scan_fixture(text : String) -> Array[Token] raise {
  let document = @origin.document(text, 4096).unwrap()
  let limits_budget = budget({
    max_tokens: 100000,
    max_syntax_nodes: 100000,
    max_syntax_depth: 128,
    max_literal_bytes: 1000000,
    max_symbol_count: 10000,
    max_generated_steps: 10000,
    max_generated_fields: 100000,
    max_lowering_work: 10000000,
  }).unwrap()
  let scanner : Scanner = {
    budget: limits_budget,
    text,
    document,
    offset: 0,
    byte_offset: 0,
  }
  let tokens : Array[Token] = []
  while true {
    let token = scanner.next()
    tokens.push(token)
    if token.value == End {
      break
    }
  }
  tokens
}

///|
test "structural lexical tokens preserve names and original byte ranges" {
  let tokens = scan_fixture(
    "\u{feff}-- comment\r\naQl '0.1'; /*x*/ STAGE `日本😀` { DATA a = FROM b |> OP filter; }",
  )
  assert_true(tokens[0].value == Word("aQl"))
  assert_eq(tokens[0].start, 15)
  assert_true(tokens[1].value == Text("0.1"))
  assert_true(tokens[4].value == QuotedName("日本😀"))
  assert_eq(tokens[4].end - tokens[4].start, 12)
  assert_true(tokens[11].value == Pipe)
  assert_true(tokens[12].value == Word("OP"))
}

///|
test "structural strings use the adopted scalar escape subset" {
  let tokens = scan_fixture(
    "'a\\n\\r\\t\\\\\\\'\\u0062\\U0001F600' `a\\`\\\\\\u0062`",
  )
  assert_true(tokens[0].value == Text("a\n\r\t\\'b😀"))
  assert_true(tokens[1].value == QuotedName("a`\\b"))
}

///|
test "invalid escapes, scalars and unterminated tokens fail closed" {
  for
    text in [
      "'\\uD800'", "'\\uDC00'", "'\\U00110000'", "'\\UFFFFFFFF'", "'\\x41'", "'\\u00Q0'",
      "'unterminated", "'line\nbreak'", "``", "`\\n`", "`\\u000A`", "`line\rbreak`",
      "/* unterminated", "\"query string\"", "@param", "|", "é", "'\\uD83D\\uDE00'",
    ] {
    let failed = try {
      ignore(scan_fixture(text))
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=text)
  }
}

///|
test "comments are non-nested and do not consume quoted content" {
  let tokens = scan_fixture("/* outer /* inner */ '/* literal */' -- end")
  assert_true(tokens[0].value == Text("/* literal */"))
  assert_true(tokens[1].value == End)
}
