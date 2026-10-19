///|
fn quantize_original_expression(
  mode? : String = "half_even",
) -> @lower.Expression raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":6,\"scale\":3}},\"rows\":[{\"amount\":\"1.235\"}]},\"as\":\"seed\"},{\"derive\":{\"rounded\":{\"quantize\":{\"value\":{\"field\":\"amount\"},\"precision\":4,\"scale\":2,\"rounding\":\"" +
    mode +
    "\"}}}}]",
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
    Err(_) => fail("original checked quantize refused")
  }
}

///|
test "quantize executes original exact Decimal coefficient and explicit rounding" {
  let expr = quantize_original_expression()
  let value = capture(@admitted.decimal_from_coefficient("1235", 6, 3).unwrap())
  assert_true(
    evaluate_expression(expr, Map([("amount", value)]), [], {
      remaining: 10000,
      max_frames: 20,
    })
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "124" &&
    d.precision == 4 &&
    d.scale == 2,
  )
}

///|
test "quantize preserves exact signed ties and directed modes" {
  for
    (mode, positive, negative) in [
      ("half_even", "124", "-124"),
      ("half_up", "124", "-124"),
      ("toward_zero", "123", "-123"),
      ("floor", "123", "-124"),
      ("ceiling", "124", "-123"),
    ] {
    let expr = quantize_original_expression(mode~)
    for (input, expected) in [("1235", positive), ("-1235", negative)] {
      let value = capture(
        @admitted.decimal_from_coefficient(input, 6, 3).unwrap(),
      )
      let workspace = row_workspace(100)
      assert_true(
        evaluate_expression_with_workspace(
          expr,
          Map([("amount", value)]),
          [],
          { remaining: 10000, max_frames: 20, },
          workspace,
        )
        is Ok(Captured(@admitted.Decimal(d))) &&
        d.coefficient == expected,
      )
      assert_eq(workspace.live, 0)
    }
  }
  for
    (source, expected) in [
      ("1.225", "122"),
      ("-1.225", "-122"),
      ("1.224", "122"),
      ("1.226", "123"),
      ("-0.001", "0"),
    ] {
    assert_true(
      run_expr(
        "\"quantize(CAST('" + source + "' AS DECIMAL(6,3)),4,2,'half_even')\"",
      )
      is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == expected,
    )
  }
  assert_true(
    run_expr("\"quantize(CAST('1.2' AS DECIMAL(6,1)),6,3,'floor')\"")
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "1200",
  )
}

///|
test "quantize preserves overflow child failure NULL and resource refusal" {
  assert_true(
    run_expr("\"quantize(CAST('99.995' AS DECIMAL(6,3)),4,2,'half_up')\"")
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr("\"quantize(CAST('bad' AS DECIMAL(6,3)),4,2,'half_up')\"")
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr("\"quantize(CAST(NULL AS DECIMAL(6,3)),4,2,'half_up')\"")
    is Ok(Null),
  )
  let expr = quantize_original_expression()
  let input = Map([
    (
      "amount",
      capture(@admitted.decimal_from_coefficient("1235", 6, 3).unwrap()),
    ),
  ])
  for limit in [0, 1, 10] {
    let workspace = row_workspace(100)
    assert_true(
      evaluate_expression_with_workspace(
        expr,
        input,
        [],
        { remaining: limit, max_frames: 20, },
        workspace,
      )
      is Err({ kind: ControlLimit, .. }),
    )
    assert_eq(workspace.live, 0)
  }
  let workspace = row_workspace(10)
  assert_true(
    evaluate_expression_with_workspace(
      expr,
      input,
      [],
      { remaining: 10000, max_frames: 20, },
      workspace,
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq(workspace.live, 0)
}

///|
test "quantize keeps full precision tiny fractions and cancellation custody" {
  assert_true(
    run_expr(
      "\"quantize(CAST('99999999999999999999999999999999999999' AS DECIMAL(38,0)),38,0,'half_even')\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "99999999999999999999999999999999999999",
  )
  for
    (source, mode, expected) in [
      ("0.00000000000000000000000000000000000001", "ceiling", "1"),
      ("-0.00000000000000000000000000000000000001", "floor", "-1"),
      ("0.00000000000000000000000000000000000001", "half_up", "0"),
    ] {
    assert_true(
      run_expr(
        "\"quantize(CAST('" +
        source +
        "' AS DECIMAL(38,38)),1,0,'" +
        mode +
        "')\"",
      )
      is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == expected,
    )
  }
  assert_true(run_expr("\"quantize(NULL,4,2,'half_even')\"") is Ok(Null))
  assert_true(
    run_expr(
      "\"if(false, quantize(CAST('bad' AS DECIMAL(6,3)),4,2,'half_up'), CAST('1.00' AS DECIMAL(4,2)))\"",
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "100",
  )
  let root = quantize_original_expression()
  let input = Map([
    (
      "amount",
      capture(@admitted.decimal_from_coefficient("1235", 6, 3).unwrap()),
    ),
  ])
  for stop = 0; stop < 4; stop = stop + 1 {
    let execution = start_expression_execution(root, input, [], 10000, 100, 100).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      assert_true(
        advance_expression_execution(execution) is Ok(ExpressionContinue),
      )
    }
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(
      input.get("amount") is Some(Captured(@admitted.Decimal(d))) &&
      d.coefficient == "1235",
    )
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}

///|
test "quantize original Relation rows retain exact Decimal and NULL results" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"nullable\":true,\"precision\":6,\"scale\":3}},\"rows\":[{\"amount\":\"1.235\"},{\"amount\":null}]},\"as\":\"seed\"},{\"derive\":{\"rounded\":{\"quantize\":{\"value\":{\"field\":\"amount\"},\"precision\":4,\"scale\":2,\"rounding\":\"half_even\"}}},\"as\":\"computed\"}]",
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
      { ..run_limits(), max_rows: 2, },
      { remaining: 100000, max_frames: 100, },
      fragments=Some([sequence_fragment_context(sequence, 1, 2L)]),
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
  assert_eq(table.names, ["amount", "rounded"])
  assert_eq(table.rows.length(), 2)
  assert_true(
    table.rows[0][0] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "1235" &&
    d.precision == 6 &&
    d.scale == 3,
  )
  assert_true(
    table.rows[0][1] is Captured(@admitted.Decimal(d)) &&
    d.coefficient == "124" &&
    d.precision == 4 &&
    d.scale == 2,
  )
  assert_true(table.rows[1][0] is Null && table.rows[1][1] is Null)
}

///|
test "quantize original logical roots and scratch have separate retirement" {
  let expr = quantize_original_expression()
  let input = Map([
    (
      "amount",
      capture(@admitted.decimal_from_coefficient("1235", 6, 3).unwrap()),
    ),
  ])
  let workspace = row_workspace(100)
  let logical = text_expression_budget(10000L, 10000L)
  let output = evaluate_expression_retained(
    expr,
    input,
    [],
    { remaining: 10000, max_frames: 20, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(
    output.value is Captured(@admitted.Decimal(d)) && d.coefficient == "124",
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DECIMAL_QUANTIZE_SLOTS)
}
