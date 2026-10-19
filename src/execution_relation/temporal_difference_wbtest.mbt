///|
fn difference_value(domain : String, text : String) -> Value {
  admitted_scalar(
    "{\"type\":\"" + domain + "\",\"nullable\":false}",
    "\"" + text + "\"",
  )
}

///|
fn difference_expression(
  unit : String,
  domain? : String = "timestamp",
) -> @lower.Expression {
  let start = if domain == "date" {
    "1970-01-01"
  } else {
    "1970-01-01T00:00:00.000Z"
  }
  let raw = "[{\"values\":{\"schema\":{\"finish\":{\"type\":\"" +
    domain +
    "\",\"nullable\":true},\"begin\":{\"type\":\"" +
    domain +
    "\",\"nullable\":true}},\"rows\":[{\"finish\":\"" +
    start +
    "\",\"begin\":\"" +
    start +
    "\"}]},\"as\":\"seed\"},{\"derive\":{\"difference\":{\"date_diff\":[{\"field\":\"finish\"},{\"field\":\"begin\"},{\"literal\":\"" +
    unit +
    "\"}]}}}]"
  @lower.lower_expression(bound_pipeline(raw), 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }).unwrap()
}

///|
test "date_diff uses exact fixed-unit quotients at nanosecond and negative boundaries" {
  let epoch = difference_value("timestamp", "1970-01-01T00:00:00.000Z")
  for
    (text, unit, expected) in [
      ("1970-01-01T00:00:00.000000001Z", "ms", 0.0),
      ("1969-12-31T23:59:59.999999999Z", "ms", 0.0),
      ("1970-01-01T00:00:00.001000001Z", "ms", 1.0),
      ("1969-12-31T23:59:59.998999999Z", "ms", -1.0),
      ("1970-01-01T00:00:00.123404Z", "ms", 123.0),
      ("1969-12-31T23:59:59.876596Z", "ms", -123.0),
      ("1970-01-01T00:00:01.000Z", "s", 1.0),
      ("1969-12-31T23:59:59.000000001Z", "s", 0.0),
      ("1969-12-31T23:59:00.000000001Z", "m", 0.0),
      ("1969-12-31T23:58:59.999999999Z", "m", -1.0),
      ("1970-01-01T01:00:00.000Z", "h", 1.0),
      ("1969-12-31T23:00:00.000000001Z", "h", 0.0),
      ("1970-01-02T00:00:00.000Z", "d", 1.0),
      ("1969-12-31T00:00:00.000000001Z", "d", 0.0),
    ] {
    let value = difference_value("timestamp", text)
    let expr = difference_expression(unit)
    let input = Map([("finish", value), ("begin", epoch)])
    assert_true(
      evaluate_expression(expr, input, [], { remaining: 1000, max_frames: 10, }).unwrap()
      is Number(actual) &&
      actual == expected,
      msg=text + unit,
    )
    assert_true(
      temporal_difference(unit, epoch, value).unwrap() is Number(actual) &&
      actual == -expected,
    )
  }
}

///|
test "date_diff preserves the full calendar range and whole-day Date domain" {
  let first = difference_value("timestamp", "0001-01-01T00:00:00.000Z")
  let last = difference_value("timestamp", "9999-12-31T23:59:59.999999999Z")
  assert_true(
    temporal_difference("ms", last, first).unwrap() is Number(315537897599999.0),
  )
  assert_true(
    temporal_difference("ms", first, last).unwrap()
    is Number(-315537897599999.0),
  )
  let leap = difference_value("date", "2000-03-01")
  let previous = difference_value("date", "2000-02-28")
  let expr = difference_expression("d", domain="date")
  assert_true(
    evaluate_expression(
      expr,
      Map([("finish", leap), ("begin", previous)]),
      [],
      { remaining: 1000, max_frames: 10, },
    ).unwrap()
    is Number(2.0),
  )
  assert_true(temporal_difference("ms", leap, previous) is Err(InvalidOperand))
  assert_true(temporal_difference("d", leap, first) is Err(InvalidOperand))
  assert_true(temporal_difference("month", last, first) is Err(InvalidOperand))
}

///|
test "date_diff evaluates demanded failures before NULL and preserves lazy branches" {
  let epoch = difference_value("timestamp", "1970-01-01T00:00:00.000Z")
  let expr = difference_expression("ms")
  assert_true(
    evaluate_expression(expr, Map([("finish", Null), ("begin", epoch)]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Null,
  )
  guard evaluate_expression(expr, Map([("finish", Null)]), [], {
      remaining: 1000,
      max_frames: 10,
    })
    is Err(issue) else {
    fail("NULL must not hide a missing demanded peer")
  }
  assert_true(issue.kind is MissingValue)
  assert_true(
    run_expr(
      "\"if(FALSE, date_diff(CAST(NULL AS TIMESTAMP), CAST(NULL AS TIMESTAMP), 'ms'), 7)\"",
    ).unwrap()
    is Number(7.0),
  )
}

///|
test "date_diff retains all original child nodes in the canonical fragment" {
  let expr = difference_expression("ms")
  assert_eq(@lower.expression_view_entries(expr), 3)
  let writer = @encode.writer(10000, 100, 20)
  @lower.emit_expression(expr, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"finish\",\"op\":\"field\"},{\"body\":\"begin\",\"op\":\"field\"},{\"body\":\"ms\",\"op\":\"literal\"}],\"op\":\"date_diff\"}",
  )
}

///|
test "date_diff charges original operand bytes and releases exact eager-frame slots" {
  let expr = difference_expression("ms")
  let epoch = difference_value("timestamp", "1970-01-01T00:00:00.000Z")
  let input = Map([("finish", epoch), ("begin", epoch)])
  let workspace = row_workspace(10)
  assert_true(
    evaluate_expression_with_workspace(
      expr,
      input,
      [],
      { remaining: 72, max_frames: 1, },
      workspace,
    ).unwrap()
    is Number(0.0),
  )
  assert_eq(workspace.live, 0)
  assert_eq(workspace.peak, 10)
  assert_true(
    evaluate_expression_with_workspace(
      expr,
      input,
      [],
      { remaining: 71, max_frames: 1, },
      row_workspace(10),
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_true(
    evaluate_expression_with_workspace(
      expr,
      input,
      [],
      { remaining: 1000, max_frames: 1, },
      row_workspace(9),
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  let logical = text_expression_budget(1000L, 1000L)
  let workspace = row_workspace(30)
  let output = evaluate_expression_retained(
    expr,
    input,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  assert_true(output.value is Number(0.0))
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((logical.live, workspace.live), (0L, 0))
}

///|
test "date_diff executes on the original typed Relation rows without rewriting timestamps" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"finish\":{\"type\":\"timestamp\",\"nullable\":true},\"begin\":{\"type\":\"timestamp\",\"nullable\":false}},\"rows\":[{\"finish\":\"1969-12-31T23:59:59.999999999Z\",\"begin\":\"1970-01-01T00:00:00.000Z\"},{\"finish\":\"1970-01-01T00:00:00.001999999Z\",\"begin\":\"1970-01-01T00:00:00.000Z\"},{\"finish\":null,\"begin\":\"1970-01-01T00:00:00.000Z\"}]},\"as\":\"seed\"},{\"derive\":{\"difference\":{\"date_diff\":[{\"field\":\"finish\"},{\"field\":\"begin\"},{\"literal\":\"ms\"}]}},\"as\":\"computed\"}]",
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
  assert_eq(table.names, ["begin", "finish", "difference"])
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][2] is Number(0.0))
  assert_true(table.rows[1][2] is Number(1.0))
  assert_true(table.rows[2][2] is Null)
  assert_true(
    table.rows[0][1]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999999999Z")),
  )
}
