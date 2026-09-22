///|
fn interval_join_test_kernel(
  kind : String,
  mode : String,
  timestamp? : Bool = false,
  options? : String = "",
) -> (@lower.BoundPrepared, @lower.PreparedIntervalJoin) raise {
  let domain = if timestamp { "timestamp" } else { "number" }
  let value = if timestamp { "\"2000-01-01T00:00:00.000Z\"" } else { "1" }
  let schema = "{\"key\":{\"type\":\"number\",\"nullable\":true}," +
    "\"start\":{\"type\":\"" +
    domain +
    "\",\"nullable\":false},\"end\":{\"type\":\"" +
    domain +
    "\",\"nullable\":false},\"time\":{\"type\":\"" +
    domain +
    "\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}}"
  let temporal = if mode == "overlap" {
    "\"left\":{\"start\":\"start\",\"end\":\"end\"}," +
    "\"right\":{\"start\":\"start\",\"end\":\"end\"}"
  } else {
    "\"left\":{\"time\":\"time\"}," +
    "\"right\":{\"start\":\"start\",\"end\":\"end\"}"
  }
  let select = if kind == "semi" || kind == "anti" {
    "{\"left_value\":\"left.value\"}"
  } else {
    "{\"left_value\":\"left.value\",\"right_value\":\"right.value\"}"
  }
  let row = "{\"key\":1,\"start\":" +
    value +
    ",\"end\":" +
    value +
    ",\"time\":" +
    value +
    ",\"value\":1}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    row +
    "]},\"as\":\"l\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    row +
    "]},\"as\":\"r\"},{\"from\":\"l\",\"interval_join\":{\"with\":\"r\",\"kind\":\"" +
    kind +
    "\",\"mode\":\"" +
    mode +
    "\",\"on\":[{\"left\":\"key\",\"right\":\"key\"},{\"left\":\"key\",\"right\":\"key\"}]," +
    temporal +
    ",\"select\":" +
    select +
    options +
    "}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.IntervalJoinStep(kernel)) else {
    fail("interval join kernel")
  }
  (owner, kernel)
}

///|
fn interval_numeric_left(
  owner : @lower.BoundPrepared,
  kernel : @lower.PreparedIntervalJoin,
) -> CompletedTable {
  RowTable({
    owner,
    id: @lower.interval_join_input(kernel, true),
    names: ["key", "start", "end", "time", "value"],
    rows: [
      [Number(1), Number(0), Number(5), Number(2), Number(10)],
      [Number(2), Number(5), Number(8), Number(7), Number(11)],
      [Null, Number(0), Number(3), Number(1), Number(12)],
    ],
  })
}

///|
fn interval_numeric_right(
  owner : @lower.BoundPrepared,
  kernel : @lower.PreparedIntervalJoin,
) -> CompletedTable {
  RowTable({
    owner,
    id: @lower.interval_join_input(kernel, false),
    names: ["key", "start", "end", "time", "value"],
    rows: [
      [Number(1), Number(0), Number(3), Number(1), Number(20)],
      [Number(1), Number(2), Number(4), Number(2), Number(21)],
      [Number(2), Number(8), Number(9), Number(8), Number(22)],
      [Null, Number(0), Number(3), Number(1), Number(23)],
    ],
  })
}

///|
fn interval_rows(kind : String, mode : String) -> Result[Table, RowIssue] raise {
  let (owner, kernel) = interval_join_test_kernel(kind, mode)
  evaluate_interval_join_rows(
    kernel,
    interval_numeric_left(owner, kernel),
    interval_numeric_right(owner, kernel),
    20,
    12L,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  )
}

///|
test "interval join passes the common kernel budget sweep" {
  let (owner, kernel) = interval_join_test_kernel("inner", "point_in_interval")
  let left = interval_numeric_left(owner, kernel)
  let right = interval_numeric_right(owner, kernel)
  assert_kernel_budget_sweep("interval_join", (control, workspace) => {
    evaluate_interval_join_rows(
      kernel,
      left,
      right,
      20,
      12L,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
  })
}

///|
fn interval_generated() -> GeneratedSequence raise {
  let schema = "{\"key\":{\"type\":\"number\",\"nullable\":true}," +
    "\"start\":{\"type\":\"number\",\"nullable\":false}," +
    "\"end\":{\"type\":\"number\",\"nullable\":false}," +
    "\"time\":{\"type\":\"number\",\"nullable\":false}," +
    "\"value\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"key\":1,\"start\":0,\"end\":5,\"time\":2,\"value\":10},{\"key\":2,\"start\":5,\"end\":8,\"time\":7,\"value\":11},{\"key\":null,\"start\":0,\"end\":3,\"time\":1,\"value\":12}]},\"as\":\"l\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"key\":1,\"start\":0,\"end\":3,\"time\":1,\"value\":20},{\"key\":1,\"start\":2,\"end\":4,\"time\":2,\"value\":21},{\"key\":2,\"start\":8,\"end\":9,\"time\":8,\"value\":22},{\"key\":null,\"start\":0,\"end\":3,\"time\":1,\"value\":23}]},\"as\":\"r\"},{\"from\":\"l\",\"interval_join\":{\"with\":\"r\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"select\":{\"left_value\":\"left.value\",\"right_value\":\"right.value\"}}}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["interval_join_2"],
    100000,
    10000,
  ).unwrap()
}

///|
test "sequence driver requires selected interval search evidence" {
  let generated = interval_generated()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], limits)
    is Err(Rows(2, InvalidRowLimits)),
  )
  let exact = constrain_generated_interval_search(generated, 2, 12L).unwrap()
  let exact = constrain_generated_join_output(exact, 2, 2L).unwrap()
  let completed = execute_generated_sequence(exact, [], limits).unwrap()
  let output = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_true(
    join_numeric_rows_equal(output.rows, [
      [Number(10), Number(20)],
      [Number(10), Number(21)],
    ]),
  )
  let short = constrain_generated_interval_search(generated, 2, 11L).unwrap()
  assert_true(
    execute_generated_sequence(short, [], limits) is Err(Rows(2, RowLimit)),
  )
}

///|
test "interval join preserves left-major matches and all admitted kinds" {
  for mode in ["point_in_interval", "overlap"] {
    let inner = interval_rows("inner", mode).unwrap()
    assert_eq(inner.names, ["left_value", "right_value"])
    assert_true(
      join_numeric_rows_equal(inner.rows, [
        [Number(10), Number(20)],
        [Number(10), Number(21)],
      ]),
    )
    let left = interval_rows("left", mode).unwrap()
    assert_true(
      join_numeric_rows_equal(left.rows, [
        [Number(10), Number(20)],
        [Number(10), Number(21)],
        [Number(11), Null],
        [Number(12), Null],
      ]),
    )
    let semi = interval_rows("semi", mode).unwrap()
    assert_true(join_numeric_rows_equal(semi.rows, [[Number(10)]]))
    let anti = interval_rows("anti", mode).unwrap()
    assert_true(
      join_numeric_rows_equal(anti.rows, [[Number(11)], [Number(12)]]),
    )
  }
}

///|
test "interval join enforces search and output ceilings independently" {
  let (owner, kernel) = interval_join_test_kernel(
    "inner",
    "point_in_interval",
    options=",\"max_output_rows\":1",
  )
  assert_true(
    evaluate_interval_join_rows(
      kernel,
      interval_numeric_left(owner, kernel),
      interval_numeric_right(owner, kernel),
      20,
      11L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
  assert_true(
    evaluate_interval_join_rows(
      kernel,
      interval_numeric_left(owner, kernel),
      interval_numeric_right(owner, kernel),
      20,
      12L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
}

///|
test "interval join admits workspace before each retained output" {
  let (owner, kernel) = interval_join_test_kernel("inner", "point_in_interval")
  let exact = row_workspace(27)
  let result = evaluate_interval_join_rows(
    kernel,
    interval_numeric_left(owner, kernel),
    interval_numeric_right(owner, kernel),
    20,
    12L,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    exact,
  ).unwrap()
  assert_eq(result.rows.length(), 2)
  assert_eq((exact.live, exact.peak), (8, 27))
  let short = row_workspace(26)
  assert_true(
    evaluate_interval_join_rows(
      kernel,
      interval_numeric_left(owner, kernel),
      interval_numeric_right(owner, kernel),
      20,
      12L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      short,
    )
    is Err(RowLimit),
  )
  assert_eq(short.live, 0)
}

///|
test "interval join validates every endpoint before matching" {
  let (owner, kernel) = interval_join_test_kernel("inner", "point_in_interval")
  let invalid = RowTable({
    owner,
    id: @lower.interval_join_input(kernel, false),
    names: ["key", "start", "end", "time", "value"],
    rows: [[Number(99), Number(5), Number(5), Number(5), Number(20)]],
  })
  assert_true(
    evaluate_interval_join_rows(
      kernel,
      interval_numeric_left(owner, kernel),
      invalid,
      20,
      3L,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    )
    is Err(InvalidRows),
  )
}

///|
fn interval_timestamp(text : String) -> Value {
  let contract = @contract.primitive(TimestampType, nullable=false)
  capture(
    @admitted.admit(contract, input_cursor("\"" + text + "\""), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: text.length(),
    }).unwrap().value,
  )
}

///|
test "interval join uses exact canonical timestamp boundaries" {
  let (owner, kernel) = interval_join_test_kernel(
    "inner",
    "point_in_interval",
    timestamp=true,
  )
  let left = RowTable({
    owner,
    id: @lower.interval_join_input(kernel, true),
    names: ["key", "start", "end", "time", "value"],
    rows: [
      [
        Number(1),
        interval_timestamp("2000-01-01T00:00:00.000Z"),
        interval_timestamp("2000-01-01T00:00:00.003Z"),
        interval_timestamp("2000-01-01T00:00:00.002Z"),
        Number(10),
      ],
    ],
  })
  let right = RowTable({
    owner,
    id: @lower.interval_join_input(kernel, false),
    names: ["key", "start", "end", "time", "value"],
    rows: [
      [
        Number(1),
        interval_timestamp("2000-01-01T00:00:00.001Z"),
        interval_timestamp("2000-01-01T00:00:00.002Z"),
        interval_timestamp("2000-01-01T00:00:00.001Z"),
        Number(20),
      ],
    ],
  })
  let result = evaluate_interval_join_rows(
    kernel,
    left,
    right,
    2,
    1L,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(result.rows.length(), 0)
}

///|
test "interval search yields and observes cancellation between pairs" {
  let control = @bounded.control()
  let emitted : Array[(Int, Int?)] = []
  let search = start_interval_search(
    control,
    2,
    3,
    @join.Inner,
    false,
    [1L, 2L],
    [],
    [0L, 0L, 0L],
    [3L, 3L, 3L],
    fn(_, _) { Ok(true) },
    fn(left, right) {
      emitted.push((left, right))
      Ok(())
    },
  )
  assert_true(
    advance_interval_search(search, 1)
    is Ok(IntervalSearchContinue(progress=1L, work=1L)),
  )
  assert_eq(emitted, [(0, Some(0))])
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_interval_search(search, 1)
    is Ok(IntervalSearchStopped(@bounded.Cancelled, progress=1L, work=1L)),
  )
  assert_eq(emitted, [(0, Some(0))])
  assert_true(@bounded.session_stopped(search.session))
  assert_true(@bounded.cleanup(search.session).unwrap_or(false))
}

///|
test "interval search resumes left unmatched output without a retry" {
  let emitted : Array[(Int, Int?)] = []
  let search = start_interval_search(
    @bounded.control(),
    2,
    1,
    @join.Left,
    false,
    [1L, 10L],
    [],
    [0L],
    [5L],
    fn(_, _) { Ok(true) },
    fn(left, right) {
      emitted.push((left, right))
      Ok(())
    },
  )
  let mut complete = false
  while !complete {
    match advance_interval_search(search, 1).unwrap() {
      IntervalSearchContinue(_) => ()
      IntervalSearchComplete(progress~, work~) => {
        assert_eq((progress, work), (4L, 4L))
        complete = true
      }
      IntervalSearchFailed(_, ..) => fail("interval search failed")
      IntervalSearchStopped(_, ..) => fail("interval search stopped")
    }
  }
  assert_eq(emitted, [(0, Some(0)), (1, None)])
  assert_true(cleanup_interval_search(search))
}
