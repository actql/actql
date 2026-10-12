///|
test "LEFT and RIGHT are permitted as unquoted calls without becoming bare names" {
  for name in ["LEFT", "RIGHT", "left", "right", "`LEFT`", "`RIGHT`"] {
    let expression = parse_expression(name + "('abc',2)", expression_limits()).unwrap()
    assert_true(
      kind(expression, expression_root(expression)) is Call(_, args) &&
      args.length() == 2,
    )
  }
  for source in ["LEFT", "RIGHT", "LEFT+1", "RIGHT.foo()", "SELECT('x')"] {
    assert_true(parse_expression(source, expression_limits()) is Err(_))
  }
  assert_true(parse_expression("`LEFT`", expression_limits()) is Ok(_))
}

///|
test "SQL and Pipe admit LEFT RIGHT nested in projections without weakening join syntax" {
  for
    source in [
      "SELECT LEFT('abc',2) AS prefix, RIGHT('abc',2) AS suffix", "SELECT TRUE AS seed |> SELECT LPAD(LEFT('abc',2),5) AS prefix, RPAD(RIGHT('abc',2),5) AS suffix",
      "SELECT LEFT(a.name,2) AS prefix FROM a LEFT JOIN b ON a.id=b.id", "SELECT RIGHT(b.name,2) AS suffix FROM a RIGHT JOIN b ON a.id=b.id",
    ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
}
