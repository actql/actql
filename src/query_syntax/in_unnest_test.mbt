///|
test "IN UNNEST is an array predicate with ordinary precedence and source origins" {
  for
    (text, op) in [
      ("amount IN UNNEST(@xs)", "IN UNNEST"),
      ("amount NOT IN uNnEsT((@xs))", "NOT IN UNNEST"),
    ] {
    let actual = parse_expression(text, expression_limits()).unwrap()
    match kind(actual, expression_root(actual)) {
      Predicate(actual_op, args) => {
        assert_eq(actual_op, op)
        assert_eq(args.length(), 2)
      }
      _ => fail("array membership must not be a scalar list")
    }
    let root = expression_node(actual, expression_root(actual)).unwrap()
    assert_eq(root.start, 0)
    assert_eq(root.end, text.length())
  }
  let actual = parse_expression(
    "amount IN UNNEST(IF(TRUE, @xs, @ys)) AND id > 0",
    expression_limits(),
  ).unwrap()
  assert_true(kind(actual, expression_root(actual)) is Binary("AND", _, _))
}

///|
test "IN UNNEST rejects malformed or quoted invocation without broadening IN lists" {
  for
    text in [
      "x IN UNNEST", "x IN UNNEST()", "x IN UNNEST(@xs, @ys)", "x IN UNNEST @xs",
      "x IN `UNNEST`(@xs)", "x IN UNNEST(@xs", "x IN ()", "x IN UNNEST(@xs) IN (1)",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
  assert_true(
    parse_expression("x IN UNNEST((((@xs))))", {
      ..expression_limits(),
      max_depth: 2,
    })
    is Err(_),
  )
}
