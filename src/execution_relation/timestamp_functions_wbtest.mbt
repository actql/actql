///|
fn original_timestamp_expression(expression : String) -> @lower.Expression {
  let request = original_string_fragment_request(
    expression~,
    max_pattern_bytes=100,
  )
  @lower.root_at(
    @lower.fragment_pipeline_roots(@lower.fragment_request_pipeline(request)),
    0,
  ).unwrap().expression
}

///|
fn evaluate_timestamp(
  expression : @lower.Expression,
  text : String,
) -> Result[Value, EvalIssue] {
  evaluate_expression(expression, Map([("text", Text(text))]), [], {
    remaining: 100000,
    max_frames: 100,
  })
}

///|
test "checked timestamp patterns execute original parse and format through the actual expression frame" {
  let date = original_timestamp_expression(
    "parse_timestamp(text, 'yyyy-MM-dd')",
  )
  for
    (input, output) in [
      ("2026-01-02", "2026-01-02T00:00:00.000Z"),
      ("2024-02-29", "2024-02-29T00:00:00.000Z"),
    ] {
    assert_true(
      evaluate_timestamp(date, input)
      is Ok(Captured(@admitted.Timestamp(actual))) &&
      actual == output,
    )
  }
  let full = original_timestamp_expression(
    "parse_timestamp(text, 'yyyy-MM-ddTHH:mm:ss.SSS')",
  )
  assert_true(
    evaluate_timestamp(full, "2026-01-02T03:04:05.123")
    is Ok(Captured(@admitted.Timestamp("2026-01-02T03:04:05.123Z"))),
  )
  let format = original_timestamp_expression(
    "format_timestamp(CAST(text AS TIMESTAMP), 'yyyy/MM/dd HH:mm:ss.SSS')",
  )
  for
    timestamp in ["2026-01-02T03:04:05.123Z", "2026-01-02T03:04:05.123456789Z"] {
    assert_true(
      evaluate_timestamp(format, timestamp)
      is Ok(Text("2026/01/02 03:04:05.123")),
    )
  }
  let year = original_timestamp_expression(
    "format_timestamp(CAST(text AS TIMESTAMP), 'yyyy')",
  )
  assert_true(
    evaluate_timestamp(year, "2026-01-02T03:04:05.123456789Z")
    is Ok(Text("2026")),
  )
}

///|
test "timestamp execution keeps complete value grammar calendar null and lazy demand" {
  let date = original_timestamp_expression(
    "parse_timestamp(text, 'yyyy-MM-dd')",
  )
  for
    text in [
      "2026-02-29", "2026-13-01", "2026-00-02", "2026-01-00", "2026-01-02x", "2026-1-02",
      " 2026-01-02", "2026/01/02",
    ] {
    assert_true(
      evaluate_timestamp(date, text)
      is Err({ kind: Scalar(InvalidOperand), .. }),
      msg=text,
    )
  }
  let null = original_timestamp_expression(
    "parse_timestamp(NULL, 'yyyy-MM-dd')",
  )
  assert_true(evaluate_timestamp(null, "ignored") is Ok(Null))
  let unselected = original_timestamp_expression(
    "if(TRUE, CAST(NULL AS TIMESTAMP), parse_timestamp(text, 'yyyy-MM-dd'))",
  )
  assert_true(evaluate_timestamp(unselected, "invalid") is Ok(Null))
  let format = original_timestamp_expression(
    "format_timestamp(CAST(text AS TIMESTAMP), 'yyyy')",
  )
  for
    text in [
      "2026-01-02T03:04:05Z", "2026-01-02 03:04:05+00:00", "2026-01-02T03:04:05.123+00:00",
    ] {
    assert_true(evaluate_timestamp(format, text) is Err(_), msg=text)
  }
}

///|
test "timestamp cancellation and work refusal release original roots at every continuation phase" {
  for
    operation in [
      "parse_timestamp(text, 'yyyy-MM-dd')", "format_timestamp(CAST(text AS TIMESTAMP), 'yyyy/MM/dd')",
    ] {
    let expression = original_timestamp_expression(operation)
    for scenario in 0..<6 {
      let phase = scenario % 3
      let logical = text_expression_budget(1000000L, 1000000L)
      let borrowed = retain_logical_value(logical, Number(9)).unwrap()
      let workspace = row_workspace(2000)
      let text = if operation.has_prefix("parse") {
        "2026-01-02"
      } else {
        "2026-01-02T03:04:05.123456789Z"
      }
      let frame = expression_frame(
        expression,
        Map([("text", Text(text))]),
        [],
        { remaining: 100000, max_frames: 100, },
        workspace,
        Some(expression_roots(logical, 100)),
      ).unwrap()
      let mut reached = false
      for _ in 0..<10000 {
        let timestamp_poll = frame.state
          is TextFunction({ timestamp: Some(_), .. })
        let before = frame.budget.remaining
        assert_true(advance_expression_frame(frame) is Ok(None))
        // Existing operand CAST admission has its own checked work demand.
        // Bound the newly selected timestamp continuation itself per poll.
        if timestamp_poll {
          assert_true(before - frame.budget.remaining <= 64)
        }
        if frame.state is TextFunction(state) &&
          state.timestamp is Some(timestamp) &&
          (if phase == 0 {
            timestamp.phase == 0 && state.position > 1
          } else if phase == 1 {
            timestamp.phase == 2 && !state.building && state.units > 1
          } else {
            state.building && state.position > 1
          }) {
          reached = true
          break
        }
      }
      assert_true(reached)
      let work = logical.work
      if scenario >= 3 {
        frame.budget.remaining = 0
        assert_true(
          advance_expression_frame(frame) is Err({ kind: ControlLimit, .. }),
        )
      } else {
        close_expression_frame(frame)
      }
      close_expression_frame(frame)
      assert_eq(
        (logical.work, logical.live, workspace.live),
        (work, borrowed.bytes, 0),
      )
      assert_false(borrowed.released)
      release_logical_root(logical, borrowed).unwrap()
    }
  }
}

///|
test "timestamp input policy and workspace refusals preserve cleanup without widening limits" {
  let expression = original_timestamp_expression(
    "parse_timestamp(text, 'yyyy-MM-dd')",
  )
  assert_true(
    evaluate_timestamp(expression, "x".repeat(65))
    is Err({ kind: TextBounds(InputCeiling), .. }),
  )
  let logical = text_expression_budget(1000000L, 1000000L)
  let borrowed = retain_logical_value(logical, Number(9)).unwrap()
  let workspace = row_workspace(24)
  let frame = expression_frame(
    expression,
    Map([("text", Text("2026-01-02"))]),
    [],
    { remaining: 100000, max_frames: 100, },
    workspace,
    Some(expression_roots(logical, 100)),
  ).unwrap()
  let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
  for _ in 0..<10000 {
    result = advance_expression_frame(frame)
    if !(result is Ok(None)) {
      break
    }
  }
  assert_true(result is Err({ kind: WorkspaceLimit, .. }))
  close_expression_frame(frame)
  assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
  release_logical_root(logical, borrowed).unwrap()
}
