///|
test "public quantize shorthand uses exact existing Decimal half even and target bounds" {
  for
    (input, scale, coefficient) in [
      ("2.345", "2", "234"),
      ("2.355", "2", "236"),
      ("-2.345", "2", "-234"),
      ("-2.355", "2", "-236"),
      ("-0.001", "0", "0"),
      ("1.200", "5", "120000"),
      ("0.000", "38", "0"),
    ] {
    assert_true(
      run_expr(
        "\"quantize(CAST('" + input + "' AS DECIMAL(6,3))," + scale + ")\"",
      )
      is Ok(Captured(@admitted.Decimal(value))) &&
      value.coefficient == coefficient &&
      value.precision == 38 &&
      value.scale.to_string() == scale,
    )
  }
  assert_true(
    run_expr(
      "\"quantize(CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)),1)\"",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "public quantize shorthand retains NULL demanded failure and lazy branch semantics" {
  assert_true(run_expr("\"quantize(NULL,2)\"") is Ok(Null))
  assert_true(
    run_expr("\"quantize(CAST(NULL AS DECIMAL(6,3)),2)\"") is Ok(Null),
  )
  assert_true(
    run_expr("\"quantize(CAST('bad' AS DECIMAL(6,3)),2)\"")
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "\"if(false, quantize(CAST('bad' AS DECIMAL(6,3)),2), CAST('1.00' AS DECIMAL(38,2)))\"",
    )
    is Ok(Captured(@admitted.Decimal(value))) &&
    value.coefficient == "100" &&
    value.precision == 38 &&
    value.scale == 2,
  )
}
