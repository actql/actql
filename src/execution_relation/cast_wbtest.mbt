///|
fn cast_test_expression(value : String, target : String) -> String {
  "{\"cast\":{\"value\":" + value + ",\"target\":" + target + "}}"
}

///|
test "CAST preserves typed NULL for every admitted target" {
  for target in ["number", "string", "boolean", "timestamp", "decimal(6,2)"] {
    assert_true(run_expr("\"CAST(NULL AS " + target + ")\"") is Ok(Null))
  }
}

///|
test "CAST finite numbers uses the strict grammar and normalizes negative zero" {
  let target = "{\"type\":\"number\"}"
  for (source, expected) in [("12.5", 12.5), ("-1e+2", -100.0), ("-0.0", 0.0)] {
    assert_true(
      run_expr(cast_test_expression("{\"literal\":\"" + source + "\"}", target))
      is Ok(Number(n)) &&
      n == expected,
    )
  }
  for source in [" 1", "1 ", "01", "+1", "0x10", "NaN", "1e999", "-0x"] {
    assert_true(
      run_expr(cast_test_expression("{\"literal\":\"" + source + "\"}", target))
      is Err({ kind: Scalar(InvalidOperand), .. }),
    )
  }
}

///|
test "CAST boolean and timestamp reuse strict admitted scalar contracts" {
  assert_true(
    run_expr(
      cast_test_expression("{\"literal\":\"true\"}", "{\"type\":\"boolean\"}"),
    )
    is Ok(Boolean(true)),
  )
  for source in ["TRUE", " true", "1"] {
    assert_true(
      run_expr(
        cast_test_expression(
          "{\"literal\":\"" + source + "\"}",
          "{\"type\":\"boolean\"}",
        ),
      )
      is Err(_),
    )
  }
  assert_true(
    run_expr(
      cast_test_expression(
        "{\"literal\":\"2026-10-01T00:00:00.000Z\"}", "{\"type\":\"timestamp\"}",
      ),
    )
    is Ok(Captured(@admitted.Timestamp("2026-10-01T00:00:00.000Z"))),
  )
  assert_true(
    run_expr(
      cast_test_expression(
        "{\"literal\":\"2026-10-01T00:00:00+09:00\"}", "{\"type\":\"timestamp\"}",
      ),
    )
    is Err(_),
  )
}

///|
test "CAST decimal is exact and does not round or accept negative zero" {
  let target = "{\"type\":\"decimal\",\"precision\":6,\"scale\":2}"
  for (source, expected) in [("12.3", "1230"), ("-0.01", "-1"), ("0", "0")] {
    assert_true(
      run_expr(cast_test_expression("{\"literal\":\"" + source + "\"}", target))
      is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == expected &&
      d.precision == 6 &&
      d.scale == 2,
    )
  }
  for source in ["-0", "-0.00", "1.000", "1e2", "10000", "+1", "01"] {
    assert_true(
      run_expr(cast_test_expression("{\"literal\":\"" + source + "\"}", target))
      is Err(_),
    )
  }
  assert_true(
    run_expr(cast_test_expression("{\"literal\":1.5}", target)) is Err(_),
  )
  assert_true(
    run_expr(cast_test_expression("{\"literal\":9007199254740992}", target))
    is Err(_),
  )
  let exact = run_expr(
    cast_test_expression(
      "{\"literal\":\"99999999999999999999999999999999999999\"}", "{\"type\":\"decimal\",\"precision\":38,\"scale\":0}",
    ),
  )
  assert_true(
    exact is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "99999999999999999999999999999999999999",
  )
}

///|
test "CAST canonical strings and same-type casts retain ordinary values" {
  for
    (value, expected) in [
      ("true", "true"),
      ("12.5", "12.5"),
      ("\"hello\"", "hello"),
    ] {
    assert_true(
      run_expr(
        cast_test_expression(
          "{\"literal\":" + value + "}",
          "{\"type\":\"string\"}",
        ),
      )
      is Ok(Text(actual)) &&
      actual == expected,
    )
  }
  let decimal = cast_test_expression(
    "{\"literal\":\"1.2\"}", "{\"type\":\"decimal\",\"precision\":6,\"scale\":2}",
  )
  assert_true(
    run_expr(cast_test_expression(decimal, "{\"type\":\"string\"}"))
    is Ok(Text("1.20")),
  )
  assert_true(
    run_expr(
      cast_test_expression(
        decimal, "{\"type\":\"decimal\",\"precision\":6,\"scale\":1}",
      ),
    )
    is Ok(Captured(@admitted.Decimal(d))) &&
    d.coefficient == "12" &&
    d.scale == 1,
  )
}

///|
test "CAST failure remains lazy and variable conversion respects control limits" {
  let invalid = cast_test_expression(
    "{\"literal\":\"bad\"}", "{\"type\":\"number\"}",
  )
  assert_true(
    run_expr("{\"if\":[{\"literal\":false}," + invalid + ",{\"literal\":1}]}")
    is Ok(Number(1.0)),
  )
  assert_true(
    run_expr("{\"if\":[{\"literal\":true}," + invalid + ",{\"literal\":1}]}")
    is Err(_),
  )
  let root = lowered(
    cast_test_expression("{\"literal\":\"12345\"}", "{\"type\":\"number\"}"),
  )
  let workspace : RowWorkspace = { limit: 100, live: 0, peak: 0, }
  assert_true(
    evaluate_expression_with_workspace(
      root,
      {},
      [],
      { remaining: 10, max_frames: 10, },
      workspace,
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_eq(workspace.live, 0)
}

///|
test "CAST cancellation at each frame boundary releases only temporary slots" {
  let root = lowered(
    cast_test_expression("{\"field\":\"id\"}", "{\"type\":\"string\"}"),
  )
  for stop = 0; stop < 4; stop = stop + 1 {
    let input : Map[String, Value] = { "id": Number(12.0) }
    let execution = start_expression_execution(root, input, [], 10000, 100, 100).unwrap()
    for _i = 0; _i < stop; _i = _i + 1 {
      assert_true(
        advance_expression_execution(execution) is Ok(ExpressionContinue),
      )
    }
    assert_true(cancel_expression_execution(execution))
    assert_eq(execution.frame.workspace.live, 0)
    assert_true(input.get("id") is Some(Number(12.0)))
    assert_true(
      advance_expression_execution(execution)
      is Err({ kind: InvalidControlLimits, .. }),
    )
  }
}
