///|
test "canonical Timestamp CAST refusal retains the original expression and closed cause" {
  for
    source in [
      "2026-01-02T03:04:05Z", "2026-01-02 03:04:05+00", "2026-01-02T03:04:05.123+00:00",
      "2026-01-02T03:04:05.123000Z", "2001-02-29T03:04:05.123Z",
    ] {
    let original = lowered("\"CAST('" + source + "' AS TIMESTAMP)\"")
    guard evaluate_expression(original, {}, [], {
        remaining: 10000,
        max_frames: 100,
      })
      is Err(issue) else {
      fail("noncanonical Timestamp accepted")
    }
    assert_true(physical_equal(issue.expression, original))
    assert_eq(
      row_failure_diagnostic_cause(Evaluation(0, 0, issue)),
      Some("evaluation.timestamp_canonical_required"),
    )
  }
}

///|
test "canonical Timestamp CAST accepts the same original text under nullable contracts" {
  for source in ["2026-01-02T03:04:05.123Z", "2026-01-02T03:04:05.123456789Z"] {
    for nullable in [false, true] {
      let original = lowered(
        cast_test_expression(
          "{\"literal\":\"" + source + "\"}",
          "{\"type\":\"timestamp\",\"nullable\":" + nullable.to_string() + "}",
        ),
      )
      assert_eq(@lower.expression_contract(original).nullable, nullable)
      assert_true(
        evaluate_expression(original, {}, [], {
          remaining: 10000,
          max_frames: 100,
        })
        is Ok(Captured(@admitted.Timestamp(actual))) &&
        actual == source,
      )
    }
  }
}

///|
test "Timestamp canonical cause does not upgrade generic failure or replace TRY and control behavior" {
  guard run_expr("\"CAST(12 AS TIMESTAMP)\"") is Err(generic) else {
    fail("wrong type accepted")
  }
  assert_eq(
    row_failure_diagnostic_cause(Evaluation(0, 0, generic)),
    Some("evaluation.invalid_operand"),
  )
  assert_true(run_expr("\"try_timestamp('2026-01-02T03:04:05Z')\"") is Ok(Null))
  assert_true(run_expr("\"CAST(NULL AS TIMESTAMP)\"") is Ok(Null))
  let original = lowered("\"CAST('2026-01-02T03:04:05Z' AS TIMESTAMP)\"")
  let workspace = row_workspace(100)
  guard evaluate_expression_with_workspace(
      original,
      {},
      [],
      { remaining: 10, max_frames: 100, },
      workspace,
    )
    is Err(control) else {
    fail("control limit bypassed")
  }
  assert_true(control.kind is ControlLimit)
  assert_eq(row_failure_diagnostic_cause(Evaluation(0, 0, control)), None)
  assert_eq(workspace.live, 0)
}
