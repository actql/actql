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
test "unix seconds floors admitted timestamps and returns signed64" {
  let expression = original_timestamp_expression(
    "unix_seconds(CAST(text AS TIMESTAMP))",
  )
  for
    (text, expected) in [
      ("1969-12-31T23:59:59.999999999Z", -1L),
      ("1970-01-01T00:00:00.000Z", 0L),
      ("1970-01-01T00:00:01.999999999Z", 1L),
      ("2008-12-25T15:30:00.000Z", 1230219000L),
      ("9999-12-31T23:59:59.999999999Z", 253402300799L),
    ] {
    assert_true(
      evaluate_timestamp(expression, text)
      is Ok(Captured(@admitted.Signed64(actual))) &&
      actual == expected,
      msg=text,
    )
  }
  assert_true(evaluate_timestamp(expression, "invalid") is Err(_))
  let null = original_timestamp_expression("unix_seconds(NULL)")
  assert_true(evaluate_timestamp(null, "unused") is Ok(Null))
  let unselected = original_timestamp_expression(
    "if(TRUE, unix_seconds(NULL), unix_seconds(CAST(text AS TIMESTAMP)))",
  )
  assert_true(evaluate_timestamp(unselected, "invalid") is Ok(Null))
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

///|
test "patterned TRY_TIMESTAMP returns only calendar or spelling failures as NULL" {
  let date = original_timestamp_expression("try_timestamp(text, 'dd/MM/yyyy')")
  assert_true(
    evaluate_timestamp(date, "29/02/2000")
    is Ok(Captured(@admitted.Timestamp("2000-02-29T00:00:00.000Z"))),
  )
  assert_true(
    evaluate_timestamp(date, "29/02/0000")
    is Ok(Captured(@admitted.Timestamp("0000-02-29T00:00:00.000Z"))),
  )
  for
    input in [
      "29/02/1900", "31/04/2026", "00/01/2026", "29/13/2026", "29/02/2000x", "29/02",
      "29-02-2000", "29/x2/2000", "🙂",
    ] {
    assert_true(evaluate_timestamp(date, input) is Ok(Null), msg=input)
  }
  let with_time = original_timestamp_expression(
    "try_timestamp(text, 'yyyy-MM-ddTHH:mm:ss.SSS')",
  )
  assert_true(
    evaluate_timestamp(with_time, "2026-01-02T03:04:05.123")
    is Ok(Captured(@admitted.Timestamp("2026-01-02T03:04:05.123Z"))),
  )
  assert_true(
    evaluate_timestamp(with_time, "2026-01-02T24:00:00.123") is Ok(Null),
  )
  assert_true(
    evaluate_timestamp(date, "x".repeat(65))
    is Err({ kind: TextBounds(InputCeiling), .. }),
  )
  let null = original_timestamp_expression("try_timestamp(NULL, 'yyyy-MM-dd')")
  assert_true(evaluate_timestamp(null, "") is Ok(Null))
  let child = original_timestamp_expression(
    "try_timestamp(CAST(1 / 0 AS STRING), 'yyyy-MM-dd')",
  )
  assert_true(evaluate_timestamp(child, "") is Err(_))
}

///|
test "patterned TRY_TIMESTAMP retires the provisional root for NULL before sizing a timestamp" {
  let expression = original_timestamp_expression(
    "try_timestamp(text, 'yyyy-MM-dd')",
  )
  let logical = text_expression_budget(1000000L, 1000000L)
  let borrowed = retain_logical_value(logical, Number(9)).unwrap()
  let workspace = row_workspace(24)
  let invalid = evaluate_expression_retained(
    expression,
    { "text": Text("2026-02-29") },
    [],
    { remaining: 1000, max_frames: 100, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(invalid.value is Null)
  let result_root = invalid.root.unwrap()
  assert_eq(result_root.bytes, 4L)
  assert_eq((logical.live, workspace.live), (borrowed.bytes + 4L, 0))
  release_logical_root(logical, result_root).unwrap()
  assert_false(borrowed.released)

  assert_true(
    evaluate_expression_with_workspace(
      expression,
      { "text": Text("2024-02-29") },
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      logical_work=Some(logical),
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  assert_eq((logical.live, workspace.live), (borrowed.bytes, 0))
  release_logical_root(logical, borrowed).unwrap()
}

///|
test "patterned timestamp fragments retain original AST identities including TRY_TIMESTAMP" {
  for
    (operation, source, output_bytes) in [
      ("parse_timestamp", "parse_timestamp(text, 'yyyy-MM-dd')", 24.0),
      ("try_timestamp", "try_timestamp(text, 'yyyy-MM-dd')", 24.0),
      (
        "format_timestamp", "format_timestamp(CAST(text AS TIMESTAMP), 'yyyy-MM-dd')",
        10.0,
      ),
    ] {
    let request = original_string_fragment_request(
      expression=source,
      max_pattern_bytes=100,
    )
    let material = prepare_fragment_material(
      request,
      material_demands(),
      registry_limits(),
    ).unwrap()
    assert_eq(material.evaluations.length(), 1)
    let envelope = @identity.object_field(
      material.evaluations[0].value,
      "envelope",
    ).unwrap()
    assert_true(
      @identity.object_field(envelope, "operation")
      is Some(@identity.String(name)) &&
      name == operation,
    )
    assert_true(
      @identity.object_field(envelope, "max_output_bytes")
      is Some(@identity.Number(bytes)) &&
      bytes == output_bytes,
    )
    let recorded = @identity.object_field(envelope, "pattern").unwrap()
    assert_true(
      @identity.object_field(recorded, "max_pattern_bytes")
      is Some(@identity.Number(10.0)),
    )
    let expression = @lower.root_at(
        @lower.fragment_pipeline_roots(
          @lower.fragment_request_pipeline(request),
        ),
        0,
      ).unwrap().expression
    let pattern = @lower.text_bound_timestamp_pattern(
      @lower.expression_text_bound(expression).unwrap(),
    ).unwrap()
    assert_true(
      @identity.object_field(recorded, "ast_cid") is Some(@identity.String(cid)) &&
      cid == @timestamp.cid(pattern),
    )
    let candidate = prepare_fragment_candidate(
      test_fragment_contract(),
      material,
      registry_limits(),
    ).unwrap()
    assert_true(
      check_generated_fragment(candidate, material_demands(), registry_limits())
      is Ok(_),
    )
  }
  let unary = original_string_fragment_request(expression="try_timestamp(text)")
  let material = prepare_fragment_material(
    unary,
    material_demands(),
    registry_limits(),
  ).unwrap()
  assert_eq(material.evaluations.length(), 0)
}
