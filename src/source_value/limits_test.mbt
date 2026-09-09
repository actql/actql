///|
test "raw byte budgets include whitespace BOM and escaped source spelling" {
  for text in [" null ", "\ufeff[]", "\"😀\"", "\"\\u0061\"", "\"\\u0344\""] {
    let bytes = @utf8.encode(text)
    assert_true(parse_json(text, limits(bytes=bytes.length())) is Ok(_))
    assert_true(parse_json_bytes(bytes, limits(bytes=bytes.length())) is Ok(_))
    assert_true(
      parse_json(text, limits(bytes=bytes.length() - 1))
      is Err({ issue: InputLimit, .. }),
    )
    assert_true(
      parse_json_bytes(bytes, limits(bytes=bytes.length() - 1))
      is Err({ issue: InputLimit, .. }),
    )
  }
  // NFC expands this decoded scalar; its normalized size is not the input budget.
  assert_true(parse_json("\"\u0344\"", limits(bytes=4)) is Ok(_))
  assert_true(
    parse_json("", limits(bytes=0)) is Err({ issue: UnexpectedEnd, .. }),
  )
}

///|
test "node budgets count containers and values but not keys" {
  for
    (text, count) in [
      ("null", 1),
      ("{}", 1),
      ("[]", 1),
      ("[1,2]", 3),
      ("{\"a\":[true,null],\"b\":{\"c\":0}}", 6),
    ] {
    assert_true(parse_json(text, limits(nodes=count)) is Ok(_))
    assert_true(
      parse_json(text, limits(nodes=count - 1)) is Err({ issue: NodeLimit, .. }),
    )
  }
  let failure = parse_json("[0,1]", limits(nodes=2))
  assert_true(failure is Err({ issue: NodeLimit, path: Some([Index(1)]), .. }))
}

///|
test "depth is open container count with scalar root zero and empty container one" {
  for
    (text, depth) in [
      ("1", 0),
      ("[]", 1),
      ("[1]", 1),
      ("[[]]", 2),
      ("{\"a\":[{}]}", 3),
    ] {
    assert_true(parse_json(text, limits(depth~)) is Ok(_))
    if depth > 0 {
      assert_true(
        parse_json(text, limits(depth=depth - 1))
        is Err({ issue: DepthLimit, .. }),
      )
    }
  }
  assert_true(
    parse_json("[]", limits(depth=0))
    is Err({ issue: DepthLimit, path: Some([]), .. }),
  )
}

///|
test "parser failures have deterministic local precedence" {
  assert_true(parse_json("?", limits(nodes=0)) is Err({ issue: NodeLimit, .. }))
  assert_true(
    parse_json("[", limits(nodes=0, depth=0)) is Err({ issue: NodeLimit, .. }),
  )
  assert_true(
    parse_json("[", limits(depth=0)) is Err({ issue: DepthLimit, .. }),
  )
  assert_true(
    parse_json("[?]", limits(nodes=1)) is Err({ issue: NodeLimit, .. }),
  )
  assert_true(
    parse_json("{\"a\":1,\"a\":?}", limits(nodes=2))
    is Err({ issue: DuplicateKey("a"), .. }),
  )
  assert_eq(rejected("{\"a\" ?}").issue, ExpectedColon)
  assert_eq(rejected("[1 2]").issue, ExpectedArraySeparator)
  assert_eq(rejected("{\"a\":1 \"b\":2}").issue, ExpectedObjectSeparator)
}
