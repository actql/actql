///|
fn decimal_division_original_expression() -> @lower.Expression raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":6,\"scale\":2}},\"rows\":[{\"amount\":\"12.50\"}]},\"as\":\"seed\"},{\"derive\":{\"quotient\":{\"decimal_divide\":{\"left\":{\"field\":\"amount\"},\"right\":{\"literal\":2},\"precision\":6,\"scale\":2,\"rounding\":\"half_even\"}}}}]",
  )
  match
    @lower.lower_expression(owner, 1, 0, {
      max_nodes: 100,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    }) {
    Ok(expr) => expr
    Err({ kind: @lower.ExpressionNotImplemented(tag), .. }) =>
      fail("ExpressionNotImplemented: " + tag)
    Err(_) => fail("original checked Decimal division refused")
  }
}

///|
test "decimal_divide executes original exact Decimal and safe integer operands" {
  let expr = decimal_division_original_expression()
  let value = capture(@admitted.decimal_from_coefficient("1250", 6, 2).unwrap())
  assert_true(
    evaluate_expression(expr, Map([("amount", value)]), [], {
      remaining: 10000,
      max_frames: 20,
    })
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "625" &&
    d.precision == 6 &&
    d.scale == 2,
  )
}

///|
test "decimal_divide preserves exact signed ties and divisor scales" {
  for
    (mode, positive, negative) in [
      ("half_even", "12", "-12"),
      ("half_up", "13", "-13"),
      ("toward_zero", "12", "-12"),
      ("floor", "12", "-13"),
      ("ceiling", "13", "-12"),
    ] {
    for
      (left, right, expected) in [
        ("1.00", "8", positive),
        ("-1.00", "8", negative),
        ("1.00", "-8", negative),
        ("-1.00", "-8", positive),
      ] {
      assert_true(
        run_expr(
          "\"decimal_divide(CAST('" +
          left +
          "' AS DECIMAL(6,2))," +
          right +
          ",6,2,'" +
          mode +
          "')\"",
        )
        is Ok(Captured(@admitted.Decimal(d))) &&
        d.coefficient == expected &&
        d.scale == 2,
      )
    }
  }
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('1.00' AS DECIMAL(6,2)),CAST('0.80' AS DECIMAL(4,2)),6,2,'half_even')\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "125",
  )
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('9007199254740991.00' AS DECIMAL(18,2)),9007199254740991,4,2,'half_even')\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "100",
  )
  assert_true(
    run_expr("\"decimal_divide(CAST('0' AS DECIMAL(1,0)),-2,4,2,'floor')\"")
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "0",
  )
}

///|
test "decimal_divide refuses zero fractional unsafe and overflowing results without swallowing children" {
  for divisor in ["0"] {
    assert_true(
      run_expr(
        "\"decimal_divide(CAST('1' AS DECIMAL(1,0))," +
        divisor +
        ",4,2,'half_even')\"",
      )
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
  }
  let zero_root = lowered(
    "\"decimal_divide(CAST('1' AS DECIMAL(1,0)),id,4,2,'half_even')\"",
  )
  for value in [0.0, -0.0] {
    assert_true(
      evaluate_expression(zero_root, Map([("id", Number(value))]), [], {
        remaining: 10000,
        max_frames: 20,
      })
      is Err({ kind: Scalar(ArithmeticFailure), .. }),
    )
  }
  for divisor in ["1.5", "9007199254740992"] {
    assert_true(
      run_expr(
        "\"decimal_divide(CAST('1' AS DECIMAL(1,0))," +
        divisor +
        ",4,2,'half_even')\"",
      )
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
  assert_true(
    run_expr("\"decimal_divide(CAST('bad' AS DECIMAL(6,2)),0,4,2,'floor')\"")
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr("\"decimal_divide(CAST(NULL AS DECIMAL(6,2)),1/0,4,2,'floor')\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('99.99' AS DECIMAL(4,2)),0.1,4,2,'floor')\"",
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('99.99' AS DECIMAL(4,2)),CAST('0.1' AS DECIMAL(1,1)),4,2,'floor')\"",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr(
      "\"if(false, decimal_divide(CAST('1' AS DECIMAL(1,0)),0,4,2,'floor'),CAST('1' AS DECIMAL(4,2)))\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "100",
  )
}

///|
test "decimal_divide bounds extreme ratios control scratch and cancellation" {
  let tiny = "0.00000000000000000000000000000000000001"
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('" +
      tiny +
      "' AS DECIMAL(38,38)),CAST('" +
      tiny +
      "' AS DECIMAL(38,38)),1,0,'half_even')\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "1",
  )
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('" +
      tiny +
      "' AS DECIMAL(38,38)),2,1,0,'ceiling')\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "1",
  )
  assert_true(
    run_expr(
      "\"decimal_divide(CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)),CAST('" +
      tiny +
      "' AS DECIMAL(38,38)),38,38,'half_even')\"",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  let root = decimal_division_original_expression()
  let input = Map([
    (
      "amount",
      capture(@admitted.decimal_from_coefficient("1250", 6, 2).unwrap()),
    ),
  ])
  let workspace = row_workspace(100)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      input,
      [],
      { remaining: 1000, max_frames: 20, },
      workspace,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(workspace.live, 0)
  let small = row_workspace(10)
  assert_true(
    evaluate_expression_with_workspace(
      root,
      input,
      [],
      { remaining: 10000, max_frames: 20, },
      small,
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq(small.live, 0)
  for stop = 0; stop < 7; stop = stop + 1 {
    let execution = start_expression_execution(root, input, [], 10000, 100, 100).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      match advance_expression_execution(execution) {
        Ok(ExpressionContinue) => ()
        Ok(ExpressionComplete(value)) => {
          assert_true(
            value is Captured(@admitted.Decimal(d)) && d.coefficient == "625",
          )
          break
        }
        Err(_) => fail("original division failed before cancellation")
      }
    }
    assert_true(cancel_expression_execution(execution))
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(
      input.get("amount") is Some(Captured(@admitted.Decimal(d))) &&
      d.coefficient == "1250",
    )
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}

///|
test "decimal_divide NULL retains strict child demand and original target" {
  for
    text in [
      "decimal_divide(NULL,2,4,2,'half_even')", "decimal_divide(CAST('1' AS DECIMAL(6,2)),NULL,4,2,'half_even')",
      "decimal_divide(NULL,NULL,4,2,'half_even')", "decimal_divide(NULL,0,4,2,'half_even')",
    ] {
    assert_true(run_expr("\"" + text + "\"") is Ok(Null))
  }
  assert_true(
    run_expr("\"decimal_divide(NULL,1/0,4,2,'half_even')\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
}

///|
test "decimal_divide original Relation rows preserve both operands and nullable quotient" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"nullable\":true,\"precision\":6,\"scale\":2},\"divisor\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"amount\":\"12.50\",\"divisor\":2},{\"amount\":null,\"divisor\":0},{\"amount\":\"1.00\",\"divisor\":null}]},\"as\":\"seed\"},{\"derive\":{\"quotient\":{\"decimal_divide\":{\"left\":{\"field\":\"amount\"},\"right\":{\"field\":\"divisor\"},\"precision\":6,\"scale\":2,\"rounding\":\"half_even\"}}},\"as\":\"computed\"}]",
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
  assert_eq(table.names, ["amount", "divisor", "quotient"])
  assert_eq(table.rows.length(), 3)
  assert_true(
    table.rows[0][0] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "1250",
  )
  assert_true(table.rows[0][1] is Number(2.0))
  assert_true(
    table.rows[0][2] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "625" &&
    d.precision == 6 &&
    d.scale == 2,
  )
  assert_true(table.rows[1][0] is Null && table.rows[1][2] is Null)
  assert_true(table.rows[2][1] is Null && table.rows[2][2] is Null)
}

///|
test "decimal_divide original binary roots retire separately from scratch" {
  let root = decimal_division_original_expression()
  let input = Map([
    (
      "amount",
      capture(@admitted.decimal_from_coefficient("1250", 6, 2).unwrap()),
    ),
  ])
  let workspace = row_workspace(100)
  let logical = text_expression_budget(10000L, 10000L)
  let output = evaluate_expression_retained(
    root,
    input,
    [],
    { remaining: 10000, max_frames: 20, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(
    output.value is Captured(@admitted.Decimal(d)) && d.coefficient == "625",
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DECIMAL_DIVISION_SLOTS)
}
