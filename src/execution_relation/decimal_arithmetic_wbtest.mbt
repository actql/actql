///|
test "decimal arithmetic executes original checked add subtract multiply contracts" {
  for
    (source, coefficient, precision, scale) in [
      (
        "CAST('12.50' AS DECIMAL(6,2)) + CAST('0.125' AS DECIMAL(4,3))", "12625",
        8, 3,
      ),
      (
        "CAST('12.50' AS DECIMAL(6,2)) - CAST('0.125' AS DECIMAL(4,3))", "12375",
        8, 3,
      ),
      (
        "CAST('-12.50' AS DECIMAL(6,2)) + CAST('0.125' AS DECIMAL(4,3))", "-12375",
        8, 3,
      ),
      (
        "CAST('12.50' AS DECIMAL(6,2)) * CAST('0.125' AS DECIMAL(4,3))", "156250",
        10, 5,
      ),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Captured(@admitted.Decimal(value))) &&
      value.coefficient == coefficient &&
      value.precision == precision &&
      value.scale == scale,
    )
  }
}

///|
test "decimal arithmetic preserves full coefficients zero and precision overflow" {
  for
    (source, coefficient, precision, scale) in [
      (
        "CAST('9007199254740992' AS DECIMAL(16,0)) + CAST('1' AS DECIMAL(1,0))",
        "9007199254740993", 17, 0,
      ),
      (
        "CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)) - CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0))",
        "0", 38, 0,
      ),
      ("CAST('-1.25' AS DECIMAL(3,2)) * CAST('0' AS DECIMAL(1,0))", "0", 4, 2),
    ] {
    assert_true(
      run_expr("\"" + source + "\"") is Ok(Captured(@admitted.Decimal(value))) &&
      value.coefficient == coefficient &&
      value.precision == precision &&
      value.scale == scale,
    )
  }
  for
    source in [
      "CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)) + CAST('1' AS DECIMAL(1,0))",
      "CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)) * CAST('2' AS DECIMAL(1,0))",
      "CAST('1' AS DECIMAL(1,0)) + CAST('0.00000000000000000000000000000000000001' AS DECIMAL(38,38))",
    ] {
    assert_true(
      run_expr("\"" + source + "\"")
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
  }
}

///|
test "decimal arithmetic retains eager null children and separate numeric domains" {
  assert_true(
    run_expr("\"CAST(NULL AS DECIMAL(6,2)) + CAST('1' AS DECIMAL(1,0))\"")
    is Ok(Null),
  )
  assert_true(
    run_expr("\"CAST(NULL AS DECIMAL(6,2)) * CAST('bad' AS DECIMAL(1,0))\"")
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  let decimal = capture(@admitted.decimal_from_coefficient("1", 1, 0).unwrap())
  for operation in [@lower.Add, @lower.Subtract, @lower.Multiply] {
    assert_true(binary(operation, decimal, Number(1.0)) is Err(InvalidOperand))
    assert_true(binary(operation, Number(1.0), decimal) is Err(InvalidOperand))
  }
  assert_true(run_expr("\"2 + 3 * 4\"") is Ok(Number(14.0)))
}

///|
test "decimal arithmetic controls scratch logical roots and cancellation" {
  let root = lowered(
    "\"CAST('12.50' AS DECIMAL(6,2)) + CAST('0.125' AS DECIMAL(4,3))\"",
  )
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
    output.value is Captured(@admitted.Decimal(d)) && d.coefficient == "12625",
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DECIMAL_ARITHMETIC_SLOTS)
  let small = row_workspace(10)
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
  let limited = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: 500, max_frames: 20, },
      limited,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(limited.live, 0)
  for stop = 0; stop < 8; stop = stop + 1 {
    let execution = start_expression_execution(root, {}, [], 10000, 100, 100).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      match advance_expression_execution(execution) {
        Ok(ExpressionContinue) => ()
        Ok(ExpressionComplete(value)) => {
          assert_true(
            value is Captured(@admitted.Decimal(d)) && d.coefficient == "12625",
          )
          break
        }
        Err(_) => fail("original decimal arithmetic failed before cancellation")
      }
    }
    assert_true(cancel_expression_execution(execution))
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
  }
}

///|
test "decimal arithmetic original Relation rows retain operands and nullable exact sum" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"decimal\",\"nullable\":true,\"precision\":6,\"scale\":2},\"b\":{\"type\":\"decimal\",\"nullable\":true,\"precision\":4,\"scale\":3}},\"rows\":[{\"a\":\"12.50\",\"b\":\"0.125\"},{\"a\":null,\"b\":\"0.000\"},{\"a\":\"1.00\",\"b\":null}]},\"as\":\"seed\"},{\"derive\":{\"sum\":{\"add\":[{\"field\":\"a\"},{\"field\":\"b\"}]}},\"as\":\"computed\"}]",
  )
  let sequence = prepared_sequence(owner)
  let completed = match
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      [
        @lower.node_id(
          @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
        ),
      ],
      { ..run_limits(), max_rows: 3, },
      { remaining: 100000, max_frames: 100, },
      fragments=Some([sequence_fragment_context(sequence, 1, 3L)]),
    ) {
    Ok(value) => value
    Err(MissingFragmentContext(i)) => fail("missing fragment " + i.to_string())
    Err(FragmentContext(i, _)) => fail("fragment context " + i.to_string())
    Err(Rows(i, Evaluation(_, _, _))) => fail("row evaluation " + i.to_string())
    Err(Rows(i, _)) => fail("rows " + i.to_string())
    Err(Capture(i, _)) => fail("capture " + i.to_string())
    Err(Store(_)) => fail("store")
    Err(InvalidLimits) => fail("invalid limits")
    Err(InputOwnership) => fail("input ownership")
    Err(InputSet) => fail("input set")
    Err(InputExecutionEvidencePending(i)) =>
      fail("input pending " + i.to_string())
    Err(InputRepresentationRequired(i)) =>
      fail("input representation " + i.to_string())
    Err(InputLimit) => fail("input limit")
    Err(InputKey(i, _)) => fail("input key " + i.to_string())
    Err(InputScore(i, _)) => fail("input score " + i.to_string())
    Err(Wiring(_)) => fail("wiring")
    Err(OrderedContext(i, _)) => fail("ordered " + i.to_string())
    Err(MixedExecutionConfiguration) => fail("mixed execution")
    Err(UnsupportedRowComparison(i, _)) =>
      fail("unsupported comparison " + i.to_string())
  }
  let table = test_row_store(completed).tables[1].unwrap().table
  assert_eq(table.names, ["a", "b", "sum"])
  assert_eq(table.rows.length(), 3)
  assert_true(
    table.rows[0][0] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "1250",
  )
  assert_true(
    table.rows[0][1] is Captured(@admitted.Decimal(d)) && d.coefficient == "125",
  )
  assert_true(
    table.rows[0][2] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "12625" &&
    d.precision == 8 &&
    d.scale == 3,
  )
  assert_true(table.rows[1][0] is Null && table.rows[1][2] is Null)
  assert_true(table.rows[2][1] is Null && table.rows[2][2] is Null)
}
