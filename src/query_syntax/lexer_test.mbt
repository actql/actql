///|
fn limits() -> LexicalLimits {
  {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
}

///|
fn values(text : String) -> Array[Lexeme] {
  let tokens = tokenize(text, limits()).unwrap()
  Array::makei(token_count(tokens), i => token_at(tokens, i).unwrap().value)
}

///|
test "query token stream is shared by SQL and Pipe without rewriting names" {
  assert_eq(values("SELECT t.x + @p AS y FROM t |> WHERE y>=.5;"), [
    Word("SELECT"),
    Word("t"),
    Symbol(46),
    Word("x"),
    Symbol(43),
    Parameter("p"),
    Word("AS"),
    Word("y"),
    Word("FROM"),
    Word("t"),
    Pipe,
    Word("WHERE"),
    Word("y"),
    Operator(">="),
    Numeric(".5"),
    Symbol(59),
    End,
  ])
  assert_eq(values("a!=b OR a<>b AND a<=b || c"), [
    Word("a"),
    Operator("!="),
    Word("b"),
    Word("OR"),
    Word("a"),
    Operator("<>"),
    Word("b"),
    Word("AND"),
    Word("a"),
    Operator("<="),
    Word("b"),
    Operator("||"),
    Word("c"),
    End,
  ])
}

///|
test "graph delimiters use the bounded shared query token stream" {
  assert_eq(values("MATCH ACYCLIC (a:Account)-[e:LINK]->(b){1,2}"), [
    Word("MATCH"),
    Word("ACYCLIC"),
    Symbol(40),
    Word("a"),
    Symbol(58),
    Word("Account"),
    Symbol(41),
    Symbol(45),
    Symbol(91),
    Word("e"),
    Symbol(58),
    Word("LINK"),
    Symbol(93),
    Symbol(45),
    Operator(">"),
    Symbol(40),
    Word("b"),
    Symbol(41),
    Symbol(123),
    Numeric("1"),
    Symbol(44),
    Numeric("2"),
    Symbol(125),
    End,
  ])
}

///|
test "query numbers keep exact spelling and unary signs are separate" {
  assert_eq(values("-9007199254740992 + 1e-4 / 1. + .5"), [
    Symbol(45),
    Numeric("9007199254740992"),
    Symbol(43),
    Numeric("1e-4"),
    Symbol(47),
    Numeric("1."),
    Symbol(43),
    Numeric(".5"),
    End,
  ])
  for text in ["1e", "1e+", "1e--2", "1.2.3", "2abc", "0x10"] {
    assert_true(tokenize(text, limits()) is Err(_), msg=text)
  }
}

///|
test "query Unicode spans refer to original bytes and CRLF" {
  let tokens = tokenize(
    "\u{feff}-- hi\r\n`日本😀` @x",
    limits(),
    source_path="input.sql",
  ).unwrap()
  let token = token_at(tokens, 0).unwrap()
  assert_eq(token.value, QuotedName("日本😀"))
  assert_eq(token.start, 10)
  assert_eq(token.end, 22)
  let span = @origin.span(token_origin(tokens, 0).unwrap())
  assert_eq(span.start_line, 2)
  assert_eq(span.start_column, 1)
  assert_eq(@origin.end(token_origin(tokens, 0).unwrap()).utf16_column, 7)
  assert_true(token_at(tokens, -1) is None)
  assert_true(token_at(tokens, token_count(tokens)) is None)
}

///|
test "query escapes and comments preserve decoded scalar values" {
  assert_eq(
    values("'a\\n\\r\\t\\\\\\\'\\u0062\\U0001F600' `a\\`b` /* /* */ -- end"),
    [Text("a\n\r\t\\'b😀"), QuotedName("a`b"), End],
  )
  assert_eq(values("\"node\":\"entity_type\""), [
    Text("node"),
    Symbol(58),
    Text("entity_type"),
    End,
  ])
  for
    text in [
      "'\\uD800'", "'\\U00110000'", "'\\x4'", "'raw\nline'", "``", "/* unfinished",
      "@", "$x", "!", "|", "é",
    ] {
    assert_true(tokenize(text, limits()) is Err(_), msg=text)
  }
}

///|
test "query accounting fails before token or decoded storage growth" {
  let source = "a + '😀' -- x"
  let tokens = tokenize(source, limits()).unwrap()
  assert_eq(usage(tokens, Tokens), 4)
  assert_eq(usage(tokens, LiteralBytes), 5)
  let work = usage(tokens, Work)
  assert_true(
    tokenize(source, {
      ..limits(),
      max_tokens: 4,
      max_literal_bytes: 5,
      max_work: work,
    })
    is Ok(_),
  )
  for
    budget in [
      { ..limits(), max_tokens: 3, },
      { ..limits(), max_literal_bytes: 4, },
      { ..limits(), max_work: work - 1, },
    ] {
    assert_true(tokenize(source, budget) is Err(_))
  }
  assert_true(tokenize("", { ..limits(), max_tokens: 0, }) is Err(_))
}

///|
test "query input owner rejects invalid UTF8 and invalid limits" {
  assert_true(tokenize_bytes(b"\xFF", limits()) is Err(_))
  assert_true(tokenize("x", { ..limits(), max_tokens: -1, }) is Err(_))
  assert_true(tokenize("😀", { ..limits(), max_source_bytes: 3, }) is Err(_))
  assert_true(tokenize("'😀'", { ..limits(), max_source_bytes: 6, }) is Ok(_))
}
