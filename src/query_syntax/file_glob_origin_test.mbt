///|
test "file glob source evidence distinguishes escapes with equal decoded values" {
  // Decoded value alone cannot tell wildcard spelling from SQL escape spelling.
  let ordinary = tokenize("'a?.pdf' 'a\\?.pdf' 'a\\u003f.pdf'", limits()).unwrap()
  for index in 0..<3 {
    let token = token_at(ordinary, index).unwrap()
    assert_eq(token.value, Text("a?.pdf"))
    let origin = token.string_origin.unwrap()
    assert_true(!origin.raw)
    assert_eq(origin.backslash, index != 0)
  }
  let raw = tokenize("r'a\\?.pdf' R\"a\\?.pdf\"", limits()).unwrap()
  for index in 0..<2 {
    let token = token_at(raw, index).unwrap()
    assert_eq(token.value, Text("a\\?.pdf"))
    let origin = token.string_origin.unwrap()
    assert_true(origin.raw)
    assert_true(origin.backslash)
  }
}

///|
test "file glob preserves source facts for every adjacent literal chunk" {
  let tokens = tokenize("r'a/' '*.pdf' r'\\?' '\\u0062'", limits()).unwrap()
  let expected = [(true, false), (false, false), (true, true), (false, true)]
  for index, pair in expected {
    let origin = token_at(tokens, index).unwrap().string_origin.unwrap()
    assert_eq((origin.raw, origin.backslash), pair)
  }
  assert_true(token_at(tokens, 4).unwrap().string_origin is None)
}

///|
test "file glob source facts cover triple literals without changing their values" {
  let tokens = tokenize("'''a\\?.pdf''' r'''a\\?.pdf'''", limits()).unwrap()
  assert_eq(token_at(tokens, 0).unwrap().value, Text("a?.pdf"))
  assert_eq(token_at(tokens, 1).unwrap().value, Text("a\\?.pdf"))
  for index in 0..<2 {
    let origin = token_at(tokens, index).unwrap().string_origin.unwrap()
    assert_eq(origin.raw, index == 1)
    assert_true(origin.backslash)
  }
}

///|
test "file glob origin is absent for identifiers and parameters" {
  let tokens = tokenize("plain `quoted\\`name` @p @`escaped\\`p`", limits()).unwrap()
  for index in 0..<token_count(tokens) {
    assert_true(token_at(tokens, index).unwrap().string_origin is None)
  }
}
