///|
test "date_trunc lowers the existing original checked fixed UTC expression" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"timestamp\",\"nullable\":false}},\"rows\":[{\"clock\":\"1969-12-31T23:59:59.999999999Z\"}]},\"as\":\"seed\"},{\"derive\":{\"truncated\":{\"date_trunc\":[{\"literal\":\"ms\"},{\"field\":\"clock\"}]}}}]",
  )
  let result = @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  })
  match result {
    Err({ kind: @lower.ExpressionNotImplemented(tag), .. }) =>
      fail("ExpressionNotImplemented: " + tag)
    Err(_) => fail("original checked temporal expression was refused")
    Ok(_) => ()
  }
}

///|
fn truncation_expression(
  unit : String,
  domain? : String = "timestamp",
) -> @lower.Expression {
  let seed = if domain == "date" {
    "1970-01-01"
  } else {
    "1970-01-01T00:00:00.000Z"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"" +
    domain +
    "\",\"nullable\":true}},\"rows\":[{\"clock\":\"" +
    seed +
    "\"}]},\"as\":\"seed\"},{\"derive\":{\"truncated\":{\"date_trunc\":[{\"literal\":\"" +
    unit +
    "\"},{\"field\":\"clock\"}]}}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }).unwrap()
}

///|
test "date_trunc floors exact UTC instants without binary64 or millisecond loss" {
  for
    (unit, before, after) in [
      ("ms", "1970-01-01T00:00:00.000000001Z", "1970-01-01T00:00:00.000Z"),
      ("ms", "1969-12-31T23:59:59.999999999Z", "1969-12-31T23:59:59.999Z"),
      ("ms", "2026-10-19T01:02:03.123456789Z", "2026-10-19T01:02:03.123Z"),
      ("s", "1969-12-31T23:59:59.999999999Z", "1969-12-31T23:59:59.000Z"),
      ("m", "1969-12-31T23:59:59.999999999Z", "1969-12-31T23:59:00.000Z"),
      ("h", "1969-12-31T23:59:59.999999999Z", "1969-12-31T23:00:00.000Z"),
      ("d", "1969-12-31T23:59:59.999999999Z", "1969-12-31T00:00:00.000Z"),
      ("d", "2000-02-29T23:59:59.999999999Z", "2000-02-29T00:00:00.000Z"),
      ("d", "0000-01-01T00:00:00.000Z", "0000-01-01T00:00:00.000Z"),
      ("d", "9999-12-31T23:59:59.999999999Z", "9999-12-31T00:00:00.000Z"),
    ] {
    let value = difference_value("timestamp", before)
    let expression = truncation_expression(unit)
    let workspace = row_workspace(100)
    let output = evaluate_expression_with_workspace(
      expression,
      Map([("clock", value)]),
      [],
      { remaining: 1000, max_frames: 10, },
      workspace,
    ).unwrap()
    assert_true(
      output is Captured(@admitted.Timestamp(actual)) && actual == after,
      msg=before + unit,
    )
    assert_eq(workspace.live, 0)
  }
}

///|
test "date_trunc retains Date identity NULL unit-first bytes and control refusal" {
  let date = difference_value("date", "2000-02-29")
  let date_expression = truncation_expression("d", domain="date")
  assert_true(
    evaluate_expression(date_expression, Map([("clock", date)]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Captured(@admitted.Date("2000-02-29")),
  )
  assert_true(
    evaluate_expression(date_expression, Map([("clock", Null)]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Null,
  )
  let expression = truncation_expression("ms")
  let writer = @encode.writer(10000, 100, 20)
  @lower.emit_expression(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"ms\",\"op\":\"literal\"},{\"body\":\"clock\",\"op\":\"field\"}],\"op\":\"date_trunc\"}",
  )
  assert_true(
    evaluate_expression(
      expression,
      Map([("clock", difference_value("timestamp", "1970-01-01T00:00:00.000Z"))]),
      [],
      { remaining: 0, max_frames: 10, },
    )
    is Err({ kind: ControlLimit, .. }),
  )
}

///|
test "date_trunc preserves demanded failures typed NULL and enclosing lazy branches" {
  let failing = lowered(
    "\"date_trunc('s', CAST(CAST(1 / 0 AS STRING) AS TIMESTAMP))\"",
  )
  assert_true(
    evaluate_expression(failing, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    })
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  let null_value = lowered("\"date_trunc('s', CAST(NULL AS TIMESTAMP))\"")
  assert_true(
    evaluate_expression(null_value, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    }).unwrap()
    is Null,
  )
  let lazy_branch = lowered(
    "\"if(FALSE, date_trunc('s', CAST(CAST(1 / 0 AS STRING) AS TIMESTAMP)), CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP))\"",
  )
  assert_true(
    evaluate_expression(lazy_branch, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    }).unwrap()
    is Captured(@admitted.Timestamp("1970-01-01T00:00:00.000Z")),
  )
}

///|
test "date_trunc retains original roots and retires only expression logical holdings" {
  let expression = truncation_expression("ms")
  let input = Map([
    ("clock", difference_value("timestamp", "1969-12-31T23:59:59.999999999Z")),
  ])
  let logical = text_expression_budget(1000L, 1000L)
  let workspace = row_workspace(100)
  let output = evaluate_expression_retained(
    expression,
    input,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(
    output.value is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999Z")),
  )
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((logical.live, workspace.live), (0L, 0))
  let pending = start_expression_execution(expression, input, [], 1000, 10, 100).unwrap()
  assert_true(advance_expression_execution(pending) is Ok(ExpressionContinue))
  assert_true(cancel_expression_execution(pending))
  assert_eq(pending.frame.workspace.live, 0)
  assert_true(
    advance_expression_execution(pending)
    is Err({ kind: InvalidControlLimits, .. }),
  )
}

///|
test "date_trunc executes on the original typed Relation rows without rewriting inputs" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"finish\":{\"type\":\"timestamp\",\"nullable\":true},\"begin\":{\"type\":\"timestamp\",\"nullable\":false}},\"rows\":[{\"finish\":\"1969-12-31T23:59:59.999999999Z\",\"begin\":\"1970-01-01T00:00:00.000Z\"},{\"finish\":\"1970-01-01T00:00:00.001999999Z\",\"begin\":\"1970-01-01T00:00:00.000Z\"},{\"finish\":null,\"begin\":\"1970-01-01T00:00:00.000Z\"}]},\"as\":\"seed\"},{\"derive\":{\"truncated\":{\"date_trunc\":[{\"literal\":\"ms\"},{\"field\":\"finish\"}]}},\"as\":\"computed\"}]",
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
  assert_eq(table.names, ["begin", "finish", "truncated"])
  assert_eq(table.rows.length(), 3)
  assert_true(
    table.rows[0][2]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999Z")),
  )
  assert_true(
    table.rows[1][2]
    is Captured(@admitted.Timestamp("1970-01-01T00:00:00.001Z")),
  )
  assert_true(table.rows[2][2] is Null)
  assert_true(
    table.rows[0][1]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999999999Z")),
  )
}
