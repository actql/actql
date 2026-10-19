///|
test "exact division accepts only representable original scaled coefficient ratios" {
  for
    (left, right, scale, expected) in [
      ("1", "8", 3, "125"),
      ("1", "8", 4, "1250"),
      ("-1", "4", 2, "-25"),
      ("1", "-4", 2, "-25"),
      ("0", "-2", 0, "0"),
      ("1", "CAST('0.80' AS DECIMAL(4,2))", 2, "125"),
      ("9007199254740991", "9007199254740991", 3, "1000"),
    ] {
    let source = "decimal_divide(CAST('" +
      left +
      "' AS DECIMAL(38,0))," +
      right +
      "," +
      scale.to_string() +
      ")"
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == expected &&
      d.precision == 38 &&
      d.scale == scale,
    )
  }
  for (divisor, scale) in [("8", 2), ("3", 2), ("2", 0), ("1", 38), ("0", 2)] {
    assert_true(
      run_expr(
        "\"decimal_divide(CAST('1' AS DECIMAL(1,0))," +
        divisor +
        "," +
        scale.to_string() +
        ")\"",
      )
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
  }
  for right in ["1.5", "9007199254740992"] {
    assert_true(
      run_expr("\"decimal_divide(CAST('1' AS DECIMAL(1,0))," + right + ",3)\"")
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
}

///|
test "exact division NULL still demands original children and retires original roots" {
  for
    source in [
      "decimal_divide(NULL,0,2)", "decimal_divide(NULL,NULL,2)", "decimal_divide(CAST('1' AS DECIMAL(1,0)),NULL,2)",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Null))
  }
  for
    source in [
      "decimal_divide(NULL,1/0,2)", "decimal_divide(CAST('bad' AS DECIMAL(3,0)),NULL,2)",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Err(_))
  }
  assert_true(
    run_expr(
      "\"if(false,decimal_divide(CAST('1' AS DECIMAL(1,0)),3,2),CAST('1.00' AS DECIMAL(38,2)))\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "100",
  )
  let root = lowered("\"decimal_divide(CAST('1' AS DECIMAL(1,0)),8,3)\"")
  let workspace = row_workspace(100)
  let logical = text_expression_budget(10000L, 10000L)
  let output = evaluate_expression_retained(
    root,
    Map(),
    [],
    { remaining: 10000, max_frames: 20, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(
    output.value is Captured(@admitted.Decimal(d)) && d.coefficient == "125",
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DECIMAL_DIVISION_SLOTS)
  let small = row_workspace(10)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      Map(),
      [],
      { remaining: 10000, max_frames: 20, },
      small,
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq(small.live, 0)
  let execution = start_expression_execution(root, Map(), [], 10000, 100, 100).unwrap()
  assert_true(cancel_expression_execution(execution))
  assert_eq(execution.frame.workspace.live, 0)
}

///|
test "exact division normalized source cold admission preserves policy and original children" {
  let original = lowered("\"decimal_divide(CAST('1' AS DECIMAL(1,0)),8,3)\"")
  let writer = @encode.writer(10000, 1000, 100)
  @lower.emit_expression_source(original, writer)
  let saved = @encode.finish(writer)
  assert_true(saved.contains("\"rounding\":\"exact\""))
  let restored = lowered(saved)
  let first = @encode.writer(10000, 1000, 100)
  let second = @encode.writer(10000, 1000, 100)
  @lower.emit_expression(original, first)
  @lower.emit_expression(restored, second)
  assert_eq(@encode.finish(first), @encode.finish(second))
  assert_true(
    evaluate_expression(restored, {}, [], { remaining: 10000, max_frames: 100, })
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "125" &&
    d.scale == 3 &&
    d.precision == 38,
  )
}
