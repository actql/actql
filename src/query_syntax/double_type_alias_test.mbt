///|
test "DOUBLE is the same unquoted numeric annotation as FLOAT64" {
  for target in ["FLOAT64", "DOUBLE", "dOuBlE"] {
    let text = "CAST(1.25 AS " + target + ")"
    let expression = parse_expression(text, expression_limits()).unwrap()
    let root = expression_node(expression, expression_root(expression)).unwrap()
    assert_eq(root.start, 0)
    assert_eq(root.end, text.length())
    guard root.kind is Cast(value, CastType::Number) else {
      fail("numeric alias must retain the existing cast target")
    }
    assert_eq(kind(expression, value), Number("1.25"))
    let array = parse_expression("ARRAY<" + target + ">[]", expression_limits()).unwrap()
    guard kind(array, expression_root(array))
      is ArrayConstructor(items, Some(ArrayElementType::Number)) else {
      fail("numeric alias must retain the existing item annotation")
    }
    assert_eq(items.length(), 0)
  }
}

///|
test "numeric type aliases do not admit quoted names or separate FLOAT types" {
  for target in ["`DOUBLE`", "FLOAT", "FLOAT32", "DOUBLEISH"] {
    guard parse_expression("CAST(1 AS " + target + ")", expression_limits())
      is Err(cast_error) else {
      fail("unsupported cast target must remain a syntax refusal")
    }
    guard cast_error.issue is Syntax(reason) else {
      fail("cast refusal must identify a syntax error")
    }
    assert_eq(
      reason,
      if target == "`DOUBLE`" {
        "Expected query cast type"
      } else {
        "Unsupported query cast type"
      },
    )
    guard parse_expression("ARRAY<" + target + ">[1]", expression_limits())
      is Err(array_error) else {
      fail("unsupported array target must remain a syntax refusal")
    }
    guard array_error.issue is Syntax(reason) else {
      fail("array refusal must identify a syntax error")
    }
    assert_eq(
      reason,
      if target == "`DOUBLE`" {
        "Expected ARRAY element type"
      } else {
        "Unsupported ARRAY element type"
      },
    )
  }
}
