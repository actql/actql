///|
fn addition_expression(
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
    "\",\"nullable\":true},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"clock\":\"" +
    seed +
    "\",\"amount\":1}]},\"as\":\"seed\"},{\"derive\":{\"shifted\":{\"date_add\":[{\"field\":\"clock\"},{\"field\":\"amount\"},{\"literal\":\"" +
    unit +
    "\"}]}}}]",
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
test "date_add executes the original checked fixed-unit integer duration" {
  let expression = addition_expression("s")
  let input = Map([
    ("clock", difference_value("timestamp", "1969-12-31T23:59:59.999999999Z")),
    ("amount", Number(1.0)),
  ])
  let workspace = row_workspace(100)
  let result = evaluate_expression_with_workspace(
    expression,
    input,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
  ).unwrap()
  assert_true(
    result is Captured(@admitted.Timestamp("1970-01-01T00:00:00.999999999Z")),
  )
  assert_eq(workspace.live, 0)
}

///|
test "date_add interprets evaluated Number bits exactly rather than decimal spelling" {
  let expression = addition_expression("s")
  for
    (unit, amount, before, after) in [
      (
        "s", 0.125, "1970-01-01T00:00:00.000000001Z", "1970-01-01T00:00:00.125000001Z",
      ),
      (
        "ms", 0.5, "1969-12-31T23:59:59.999999999Z", "1970-01-01T00:00:00.000499999Z",
      ),
      (
        "s", -0.125, "1970-01-01T00:00:00.000000001Z", "1969-12-31T23:59:59.875000001Z",
      ),
      (
        "m", 1.0, "2000-02-29T23:59:59.123456789Z", "2000-03-01T00:00:59.123456789Z",
      ),
      (
        "h", -1.0, "2000-03-01T00:00:59.123456789Z", "2000-02-29T23:00:59.123456789Z",
      ),
      ("d", 1.5, "0000-02-28T12:00:00.000Z", "0000-03-01T00:00:00.000Z"),
      ("ms", 1.0, "1970-01-01T00:00:00.000Z", "1970-01-01T00:00:00.001Z"),
      (
        "s", 0.0, "9999-12-31T23:59:59.999999999Z", "9999-12-31T23:59:59.999999999Z",
      ),
    ] {
    let selected = addition_expression(unit)
    let result = temporal_addition(
      selected,
      unit,
      difference_value("timestamp", before),
      Number(amount),
    ).unwrap()
    assert_true(
      result is Captured(@admitted.Timestamp(actual)) && actual == after,
      msg=unit + before,
    )
  }
  let epoch = difference_value("timestamp", "1970-01-01T00:00:00.000Z")
  // Independent consequences of exact IEEE754 bits, not ideal decimal rationals.
  for amount in [0.1, 1.0e-9, -0.1, 5.0e-324, 1.7976931348623157e308] {
    assert_true(
      temporal_addition(expression, "s", epoch, Number(amount))
      is Err(ArithmeticFailure),
    )
  }
  let evaluated = lowered(
    "\"date_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP), 0.1 + 0.025, 's')\"",
  )
  assert_true(
    evaluate_expression(evaluated, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    }).unwrap()
    is Captured(@admitted.Timestamp("1970-01-01T00:00:00.125Z")),
  )
}

///|
test "date_add preserves Date whole-day domain and calendar overflow refusal" {
  let day = difference_value("date", "2000-02-28")
  let expression = addition_expression("d", domain="date")
  assert_true(
    temporal_addition(expression, "d", day, Number(2.0)).unwrap()
    is Captured(@admitted.Date("2000-03-01")),
  )
  assert_true(
    temporal_addition(expression, "d", day, Number(0.5))
    is Err(ArithmeticFailure),
  )
  assert_true(
    temporal_addition(expression, "s", day, Number(1.0)) is Err(InvalidOperand),
  )
  for
    (before, amount) in [
      ("0000-01-01T00:00:00.000Z", -1.0),
      ("9999-12-31T23:59:59.999999999Z", 1.0),
    ] {
    let expression = addition_expression("ms")
    assert_true(
      temporal_addition(
        expression,
        "ms",
        difference_value("timestamp", before),
        Number(amount),
      )
      is Err(ArithmeticFailure),
    )
  }
  let first = difference_value("timestamp", "0000-01-01T00:00:00.000Z")
  let expression = addition_expression("d")
  assert_true(
    temporal_addition(expression, "d", first, Number(3652424.0)).unwrap()
    is Captured(@admitted.Timestamp("9999-12-31T00:00:00.000Z")),
  )
}

///|
test "date_add retains strict eager NULL demand and ordinary lazy branches" {
  let expression = addition_expression("s")
  assert_true(
    evaluate_expression(
      expression,
      Map([("clock", Null), ("amount", Number(1.0))]),
      [],
      { remaining: 1000, max_frames: 20, },
    ).unwrap()
    is Null,
  )
  assert_true(
    evaluate_expression(expression, Map([("clock", Null)]), [], {
      remaining: 1000,
      max_frames: 20,
    })
    is Err({ kind: MissingValue, .. }),
  )
  let demanded = lowered("\"date_add(CAST(NULL AS TIMESTAMP), 1 / 0, 's')\"")
  assert_true(
    evaluate_expression(demanded, Map([]), [], {
      remaining: 1000,
      max_frames: 20,
    })
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  let lazy_branch = lowered(
    "\"if(FALSE, date_add(CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP), 0.1, 's'), CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP))\"",
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
test "date_add preserves original canonical children and root scratch cancellation" {
  let expression = addition_expression("s")
  let writer = @encode.writer(10000, 100, 20)
  @lower.emit_expression(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"clock\",\"op\":\"field\"},{\"body\":\"amount\",\"op\":\"field\"},{\"body\":\"s\",\"op\":\"literal\"}],\"op\":\"date_add\"}",
  )
  let input = Map([
    ("clock", difference_value("timestamp", "1970-01-01T00:00:00.000000001Z")),
    ("amount", Number(0.125)),
  ])
  let workspace = row_workspace(100)
  let logical = text_expression_budget(1000L, 1000L)
  let output = evaluate_expression_retained(
    expression,
    input,
    [],
    { remaining: 1000, max_frames: 20, },
    workspace,
    logical_work=Some(logical),
  ).unwrap()
  release_logical_root(logical, output.root.unwrap()).unwrap()
  assert_eq((workspace.live, logical.live), (0, 0L))
  assert_true(workspace.peak >= DATE_ADDITION_SLOTS)
  assert_true(
    evaluate_expression_with_workspace(
      expression,
      input,
      [],
      { remaining: 0, max_frames: 20, },
      row_workspace(100),
    )
    is Err({ kind: ControlLimit, .. }),
  )
  assert_true(
    evaluate_expression_with_workspace(
      expression,
      input,
      [],
      { remaining: 1000, max_frames: 20, },
      row_workspace(DATE_ADDITION_SLOTS),
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  let pending = start_expression_execution(expression, input, [], 1000, 20, 100).unwrap()
  assert_true(advance_expression_execution(pending) is Ok(ExpressionContinue))
  assert_true(cancel_expression_execution(pending))
  assert_eq(pending.frame.workspace.live, 0)
}

///|
test "date_add executes on the original typed Relation rows without rewriting timestamps" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"timestamp\",\"nullable\":true},\"amount\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"clock\":\"1969-12-31T23:59:59.999999999Z\",\"amount\":0.125},{\"clock\":\"1970-01-01T00:00:00.001999999Z\",\"amount\":-0.5},{\"clock\":null,\"amount\":1}]},\"as\":\"seed\"},{\"derive\":{\"shifted\":{\"date_add\":[{\"field\":\"clock\"},{\"field\":\"amount\"},{\"literal\":\"s\"}]}},\"as\":\"computed\"}]",
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
  assert_eq(table.names, ["amount", "clock", "shifted"])
  assert_eq(table.rows.length(), 3)
  assert_true(
    table.rows[0][2]
    is Captured(@admitted.Timestamp("1970-01-01T00:00:00.124999999Z")),
  )
  assert_true(
    table.rows[1][2]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.501999999Z")),
  )
  assert_true(table.rows[2][2] is Null)
  assert_true(
    table.rows[0][1]
    is Captured(@admitted.Timestamp("1969-12-31T23:59:59.999999999Z")),
  )
}
