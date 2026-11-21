///|
test "exact integer arithmetic signs zero overflow and null remain separate from Number" {
  let integer = (n : Int64) => capture(@admitted.signed64_value(n))
  for
    (a, b, quotient, remainder) in [
      (10L, 3L, 3L, 1L),
      (-10L, 3L, -3L, -1L),
      (10L, -3L, -3L, 1L),
      (-10L, -3L, 3L, -1L),
      (9007199254740993L, 2L, 4503599627370496L, 1L),
    ] {
    assert_true(
      binary(@lower.IntegerDivide, integer(a), integer(b))
      is Ok(Captured(@admitted.Signed64(value))) &&
      value == quotient,
    )
    assert_true(
      binary(@lower.ExactModulo, integer(a), integer(b))
      is Ok(Captured(@admitted.Signed64(value))) &&
      value == remainder,
    )
  }
  let minimum = integer(-9223372036854775807L - 1L)
  assert_true(
    binary(@lower.IntegerDivide, minimum, integer(-1L))
    is Err(ArithmeticFailure),
  )
  assert_true(
    binary(@lower.ExactModulo, minimum, integer(-1L))
    is Ok(Captured(@admitted.Signed64(0L))),
  )
  for operation in [@lower.IntegerDivide, @lower.ExactModulo] {
    assert_true(
      binary(operation, integer(1L), integer(0L)) is Err(ArithmeticFailure),
    )
    assert_true(binary(operation, Null, integer(0L)) is Ok(Null))
    assert_true(binary(operation, integer(1L), Null) is Ok(Null))
    assert_true(
      binary(operation, Number(5.0), integer(2L)) is Err(InvalidOperand),
    )
    assert_true(
      binary(operation, integer(5L), Number(2.0)) is Err(InvalidOperand),
    )
  }
}

///|
test "exact Decimal integer arithmetic keeps bounded scratch roots and demanded failure" {
  let decimal = (text : String, scale : Int) => {
    "{\"cast\":{\"target\":{\"type\":\"decimal\",\"precision\":38,\"scale\":" +
    scale.to_string() +
    "},\"value\":{\"literal\":\"" +
    text +
    "\"}}}"
  }
  let source = "{\"exact_modulo\":[" +
    decimal("-12.50", 2) +
    "," +
    decimal("3.0", 1) +
    "]}"
  let root = lowered(source)
  let workspace = row_workspace(100)
  let logical = text_expression_budget(10000L, 10000L)
  let output = evaluate_expression_retained(
    root,
    {},
    [],
    { remaining: 10000, max_frames: 20, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(
    output.value is Captured(@admitted.Decimal(d)) && d.coefficient == "-50",
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DECIMAL_DIVISION_SLOTS)
  let small = row_workspace(DECIMAL_DIVISION_SLOTS - 1)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: 10000, max_frames: 20, },
      small,
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq(small.live, 0)
  assert_true(
    run_expr(
      "{\"integer_divide\":[" + decimal("1", 0) + "," + decimal("0", 0) + "]}",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  // SQL NULL does not suppress evaluation of a failing original child.
  assert_true(
    run_expr(
      "{\"integer_divide\":[{\"literal\":null}," + decimal("bad", 0) + "]}",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  let pending = start_expression_execution(root, {}, [], 10000, 100, 100).unwrap()
  assert_true(cancel_expression_execution(pending))
  assert_eq(pending.frame.workspace.live, 0)
}

///|
test "exact integer typed literals execute without changing canonical wire or Number admission" {
  for
    (name, expected) in [
      ("exact_modulo", 1L),
      ("integer_divide", 4503599627370496L),
    ] {
    let source = "{\"" +
      name +
      "\":[{\"typed_literal\":{\"type\":\"int64\",\"value\":\"9007199254740993\"}},{\"typed_literal\":{\"type\":\"int64\",\"value\":\"2\"}}]}"
    assert_true(
      run_expr(source) is Ok(Captured(@admitted.Signed64(value))) &&
      value == expected,
    )
  }
  assert_true(
    run_expr(
      "{\"integer_divide\":[{\"cast\":{\"target\":{\"type\":\"int64\"},\"value\":{\"literal\":null}}},{\"typed_literal\":{\"type\":\"int64\",\"value\":\"0\"}}]}",
    )
    is Ok(Null),
  )
}
