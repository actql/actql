///|
test "array constructor owns ordered children and original source ranges" {
  for
    text in [
      "[2, value + 1, 2]", "ARRAY[2, value + 1, 2]", "aRrAy[2, value + 1, 2]",
    ] {
    let expression = parse_expression(text, expression_limits()).unwrap()
    let root = expression_node(expression, expression_root(expression)).unwrap()
    assert_eq(root.start, 0)
    assert_eq(root.end, text.length())
    guard root.kind is ArrayConstructor(items, None) else {
      fail("expected an array constructor rather than a scalar call")
    }
    assert_eq(items.length(), 3)
    assert_eq(kind(expression, items[0]), Number("2"))
    assert_true(kind(expression, items[1]) is Binary("+", _, _))
    assert_eq(kind(expression, items[2]), Number("2"))
    let child = expression_child(expression, expression_root(expression)).unwrap()
    items.clear()
    guard kind(expression, expression_root(expression))
      is ArrayConstructor(retained, None) else {
      fail("observation must preserve the array owner")
    }
    assert_eq(retained.length(), 3)
    guard kind(child, expression_root(child)) is ArrayConstructor(copied, None) else {
      fail("subexpression must preserve its array constructor")
    }
    assert_eq(copied.length(), 3)
    assert_true(kind(child, copied[1]) is Binary("+", _, _))
  }
}

///|
test "array constructors retain common source complexity limits" {
  let expression = parse_expression("[1, 2, 1]", expression_limits()).unwrap()
  assert_eq(expression_node_count(expression), 4)
  assert_true(
    parse_expression("[1, 2, 1]", { ..expression_limits(), max_nodes: 3, })
    is Err(_),
  )
  assert_true(
    parse_expression("[1, 2, 1]", {
      ..expression_limits(),
      max_work: expression_work(expression) - 1,
    })
    is Err(_),
  )
  assert_true(
    parse_expression("[1 + 2]", { ..expression_limits(), max_depth: 2, })
    is Err(_),
  )
}

///|
test "array delimiters reject incomplete and comma-only expressions" {
  for text in ["[", "[1", "[,1]", "[1,]", "[1,,2]", "ARRAY[1)", "[1 2]"] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}

///|
test "typed arrays retain an explicit annotation separate from their children" {
  for
    (text, target) in [
      ("ARRAY<STRING>[]", ArrayElementType::String),
      ("ARRAY<BOOL>[TRUE, FALSE]", ArrayElementType::Boolean),
      ("aRrAy<FLOAT64>[2, 1, 2]", ArrayElementType::Number),
      ("ARRAY<JSON>[JSON 'null']", ArrayElementType::Json),
    ] {
    let expression = parse_expression(text, expression_limits()).unwrap()
    guard kind(expression, expression_root(expression))
      is ArrayConstructor(items, Some(found)) else {
      fail("typed array annotation must not be a scalar CAST")
    }
    assert_eq(found, target)
    assert_true(items.length() <= 3)
  }
  for text in ["ARRAY<STRING[1]", "ARRAY<STRING>", "ARRAY<ARRAY<STRING>>[]"] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}
