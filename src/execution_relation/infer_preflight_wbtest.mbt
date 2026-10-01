///|
fn infer_preflight_fixture(
  rows : String,
  mapping? : String = "{\"field\":\"text\"}",
) -> (InferRowInput, CapturedRows) {
  let producer = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"text\":{\"type\":\"string\",\"nullable\":true},\"secret\":{\"type\":\"string\",\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"input\"}]",
  )
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(producer),
    Step(0),
  ).unwrap()
  let input = @carrier.relation(@carrier.typed_rows(schema))
  // The key is conditional. The preparation must validate actual uniqueness.
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), input, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @infer.check(
    input_cursor(
      "{\"contract\":\"model-task:risk-score.v1\",\"key\":\"id\",\"input\":{\"text\":" +
      mapping +
      "}}",
    ),
    input,
    Some(@evidence.singleton_key(key)),
    infer_fixture_tasks(),
    None,
    {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_key_fields: 1,
      max_input_roles: 1,
    },
  ).unwrap()
  let prepared = @lower.prepare_infer_inputs(
    checked,
    None,
    infer_fixture_expression_limits(),
  ).unwrap()
  let rows = capture_values(producer, 0, max_rows=100, {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_work: 100000,
    max_depth: 100,
  }).unwrap()
  (bind_infer_captured_input(prepared, producer, Step(0), rows).unwrap(), rows)
}

///|
fn infer_preflight_limits() -> InferPreparationLimits {
  {
    max_items: 100,
    max_work: 100000,
    max_frames: 100,
    max_workspace_slots: 10000,
    values: { max_nodes: 10000, max_text_bytes: 10000, max_depth: 100, },
    logical: {
      max_input_rows: 100L,
      max_value_bytes: 10000L,
      max_live_value_bytes: 100000L,
      max_work: 100000L,
    },
  }
}

///|
fn infer_preflight_drain(
  value : InferRowsPreparation,
) -> Result[PreparedInferRows, InferPreparationIssue] raise {
  for _ in 0..<100000 {
    match advance_infer_rows_preparation(value, 1) {
      Err(issue) => return Err(issue)
      Ok(InferRowsComplete(rows, ..)) => return Ok(rows)
      Ok(InferRowsContinue(..)) => ()
      Ok(InferRowsStopped(_, ..)) => fail("unexpected cancellation")
    }
  }
  fail("finite preparation did not terminate")
}

///|
test "inference input preparation sorts typed keys and maps only declared roles" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"b","text":"second","secret":"not-egress-b"},{"id":"a","text":"first","secret":"not-egress-a"},{"id":"😀","text":null,"secret":"not-egress-supplementary"},{"id":"","text":"private-use","secret":"not-egress-private"},{"id":"A","text":"uppercase","secret":"not-egress-upper"}]
    ),
  )
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    infer_preflight_limits(),
  ).unwrap()
  let prepared = infer_preflight_drain(execution).unwrap()
  assert_eq(prepared_infer_rows_count(prepared), 5)
  for slot, expected in ["A", "a", "b", "😀", ""] {
    guard prepared_infer_rows_key(prepared, slot, 0) is Some(value) else {
      fail("missing key")
    }
    assert_true(value.value is @admitted.Text(text) && text == expected)
    assert_true(prepared_infer_rows_value(prepared, slot, 1) is None)
  }
  assert_true(
    prepared_infer_rows_value(prepared, 0, 0).unwrap().value
    is @admitted.Text("uppercase"),
  )
  assert_true(
    prepared_infer_rows_value(prepared, 1, 0).unwrap().value
    is @admitted.Text("first"),
  )
  assert_true(
    prepared_infer_rows_value(prepared, 3, 0).unwrap().value is @admitted.Null,
  )
  assert_true(infer_rows_preparation_stopped(execution))
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(prepared_infer_rows_key(prepared, 0, 0) is Some(_))
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_true(prepared_infer_rows_value(prepared, 0, 0) is None)
  assert_eq(captured_row_count(source), 5)
  assert_true(captured_cell(source, 0, 0) is Some(@admitted.Text("b")))
}

///|
test "duplicate inference keys reject before mapping and empty input prepares no slots" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"same","text":"first","secret":"s1"},{"id":"same","text":"second","secret":"s2"}]
    ),
  )
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    infer_preflight_limits(),
  ).unwrap()
  assert_true(infer_preflight_drain(execution) is Err(DuplicateKey(0, 1)))
  assert_eq(execution.state.values.length(), 0)
  assert_eq(execution.state.snapshot.length(), 0)
  assert_true(infer_rows_preparation_stopped(execution))
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_eq(captured_row_count(source), 2)
  let (empty, _) = infer_preflight_fixture("[]")
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    empty,
    infer_preflight_limits(),
  ).unwrap()
  let prepared = infer_preflight_drain(execution).unwrap()
  assert_eq(prepared_infer_rows_count(prepared), 0)
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
}

///|
test "mapped inference inputs have independent exact and one-short preparation bounds" {
  let (input, _) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"}]
    ),
  )
  // Forty-three preparation transitions, twelve snapshot-name bytes, two
  // expression transitions and four field-name bytes cost 61 work units.
  // Source/key metadata and shared sorting peak at nine slots; a three-field
  // snapshot, one detached root, mapped value and row container peak at 13.
  // Shared sort cleanup leaves only one output index per row before mapping.
  let exact = {
    ..infer_preflight_limits(),
    max_work: 61,
    max_workspace_slots: 13,
    values: { max_nodes: 2, max_text_bytes: 7, max_depth: 0, },
  }
  let execution = start_infer_rows_preparation(@bounded.control(), input, exact).unwrap()
  let prepared = infer_preflight_drain(execution).unwrap()
  assert_eq(infer_rows_preparation_usage(execution), (61, 6, 13))
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  for
    (limits, workspace) in [
      ({ ..exact, max_work: 60, }, false),
      ({ ..exact, max_workspace_slots: 12, }, true),
    ] {
    let execution = start_infer_rows_preparation(
      @bounded.control(),
      input,
      limits,
    ).unwrap()
    let result = infer_preflight_drain(execution)
    if workspace {
      assert_true(result is Err(WorkspaceLimit))
    } else {
      assert_true(result is Err(WorkLimit))
    }
    assert_true(cleanup_infer_rows_preparation(execution).unwrap())
    assert_eq(infer_rows_preparation_usage(execution).1, 0)
  }
  assert_true(
    start_infer_rows_preparation(@bounded.control(), input, {
      ..exact,
      max_items: 0,
    })
    is Err(ItemLimit),
  )
}

///|
test "inference preparation cancellation preserves borrowed input and releases scratch" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"}]
    ),
  )
  for phase in [ReadKeys, EvaluateMapping, ValidateMapping, FinishRow] {
    let control = @bounded.control()
    let execution = start_infer_rows_preparation(
      control,
      input,
      infer_preflight_limits(),
    ).unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      let at_phase = match (execution.state.phase, phase) {
        (ReadKeys, ReadKeys)
        | (EvaluateMapping, EvaluateMapping)
        | (ValidateMapping, ValidateMapping)
        | (FinishRow, FinishRow) => true
        _ => false
      }
      if at_phase {
        reached = true
        break
      }
      assert_true(
        advance_infer_rows_preparation(execution, 1).unwrap()
        is InferRowsContinue(..),
      )
    }
    assert_true(reached)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_infer_rows_preparation(execution, 1).unwrap()
      is InferRowsStopped(Cancelled, ..),
    )
    assert_true(infer_rows_preparation_stopped(execution))
    assert_true(cleanup_infer_rows_preparation(execution).unwrap())
    assert_eq(infer_rows_preparation_usage(execution).1, 0)
    assert_true(captured_cell(source, 0, 0) is Some(@admitted.Text("a")))
    assert_true(
      advance_infer_rows_preparation(execution, 1) is Err(Session(Terminal)),
    )
  }
  let control = @bounded.control()
  assert_true(@bounded.request_cancel(control))
  let execution = start_infer_rows_preparation(
    control,
    input,
    infer_preflight_limits(),
  ).unwrap()
  assert_true(
    advance_infer_rows_preparation(execution, 1).unwrap()
    is InferRowsStopped(Cancelled, ..),
  )
  assert_eq(infer_rows_preparation_usage(execution), (0, 0, 0))
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
}

///|
test "inference input binding rejects foreign invocation target and checked schema" {
  let (input, source) = infer_preflight_fixture("[]")
  assert_true(
    bind_infer_captured_input(input.prepared, input.expected, Step(1), source)
    is Err(ForeignInput),
  )
  let foreign = @lower.bind_parameters(
    @lower.bound_preparation(input.expected),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    bind_infer_captured_input(input.prepared, foreign, Step(0), source)
    is Err(ForeignInput),
  )
  let (other, _) = infer_preflight_fixture("[]")
  assert_true(
    bind_infer_captured_input(other.prepared, input.expected, Step(0), source)
    is Err(ForeignInput),
  )
}

///|
test "completed inference input preserves exact completion and current liveness" {
  let (input, _) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"}]
    ),
  )
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(input.expected),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let output = completed_output(completion, Step(0)).unwrap()
  let live = Ref(true)
  let output = restrict_completed_output(output, fn() { live.val })
  let bound = bind_infer_completed_input(
    input.prepared,
    input.expected,
    Step(0),
    output,
  ).unwrap()
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    bound,
    infer_preflight_limits(),
  ).unwrap()
  let prepared = infer_preflight_drain(execution).unwrap()
  assert_true(
    prepared_infer_rows_value(prepared, 0, 0).unwrap().value
    is @admitted.Text("urgent"),
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  live.val = false
  assert_true(prepared_infer_rows_value(prepared, 0, 0) is None)
  assert_true(
    bind_infer_completed_input(input.prepared, input.expected, Step(0), output)
    is Err(InputUnavailable),
  )
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
}

///|
test "null inference key is a barrier admission error not a provider outcome" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"}]
    ),
  )
  // Corrupt only the private test copy, as an untrusted storage adapter could.
  let cells = source.rows[0].copy()
  cells[0] = @admitted.null_value()
  let invalid : CapturedRows = { ..source, rows: [cells], }
  let bound = bind_infer_captured_input(
    input.prepared,
    input.expected,
    Step(0),
    invalid,
  ).unwrap()
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    bound,
    infer_preflight_limits(),
  ).unwrap()
  assert_true(infer_preflight_drain(execution) is Err(InvalidKey(0, 0)))
  assert_eq(execution.state.values.length(), 0)
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_true(captured_cell(source, 0, 0) is Some(@admitted.Text("a")))
}

///|
test "key comparisons yield within long common prefixes without changing order" {
  let prefix = Array::make(1024, "x").join("")
  let (input, _) = infer_preflight_fixture(
    "[{\"id\":\"" +
    prefix +
    "b\",\"text\":\"second\",\"secret\":\"s2\"},{\"id\":\"" +
    prefix +
    "a\",\"text\":\"first\",\"secret\":\"s1\"}]",
  )
  let control = @bounded.control()
  let execution = start_infer_rows_preparation(
    control,
    input,
    infer_preflight_limits(),
  ).unwrap()
  let mut compared = 0
  for _ in 0..<10000 {
    assert_true(
      advance_infer_rows_preparation(execution, 1).unwrap()
      is InferRowsContinue(..),
    )
    if execution.state.comparison is Some(_) {
      compared += 1
      if compared == 20 {
        break
      }
    }
  }
  assert_eq(compared, 20)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_infer_rows_preparation(execution, 1).unwrap()
    is InferRowsStopped(Cancelled, ..),
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    infer_preflight_limits(),
  ).unwrap()
  let rows = infer_preflight_drain(execution).unwrap()
  assert_true(
    prepared_infer_rows_value(rows, 0, 0).unwrap().value
    is @admitted.Text("first"),
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(cleanup_prepared_infer_rows(rows))
}

///|
test "inference mapping shares exact logical work and retained-root budgets" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"},{"id":"b","text":"urgent","secret":"private-b"}]
    ),
  )
  // Each field mapping enters once and produces a value of weight 1+6.
  // Both independently retained result roots encode as eight-byte strings.
  let exact : LogicalLimits = {
    max_input_rows: 2L,
    max_value_bytes: 8L,
    max_live_value_bytes: 16L,
    max_work: 16L,
  }
  let execution = start_infer_rows_preparation(@bounded.control(), input, {
    ..infer_preflight_limits(),
    logical: exact,
  }).unwrap()
  let rows = infer_preflight_drain(execution).unwrap()
  assert_eq(infer_rows_preparation_logical_usage(execution), (16L, 16L, 16L))
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 16L)
  assert_true(cleanup_prepared_infer_rows(rows))
  assert_eq(infer_rows_preparation_logical_usage(execution), (16L, 0L, 16L))
  assert_true(cleanup_prepared_infer_rows(rows))
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  for
    (logical, work_limit) in [
      ({ ..exact, max_work: 15L, }, true),
      ({ ..exact, max_live_value_bytes: 15L, }, false),
    ] {
    let execution = start_infer_rows_preparation(@bounded.control(), input, {
      ..infer_preflight_limits(),
      logical,
    }).unwrap()
    let result = infer_preflight_drain(execution)
    if work_limit {
      assert_true(
        result
        is Err(
          Evaluation(
            1,
            0,
            { kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }
          )
        ),
      )
    } else {
      assert_true(
        result
        is Err(Evaluation(1, 0, { kind: LogicalValue(LiveValueLimit), .. })),
      )
    }
    let charged = infer_rows_preparation_logical_usage(execution).0
    assert_true(cleanup_infer_rows_preparation(execution).unwrap())
    assert_eq(infer_rows_preparation_logical_usage(execution).0, charged)
    assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
    assert_eq(infer_rows_preparation_usage(execution).1, 0)
  }
  assert_true(
    start_infer_rows_preparation(@bounded.control(), input, {
      ..infer_preflight_limits(),
      logical: { ..exact, max_input_rows: 1L, },
    })
    is Err(Logical(InputRowLimit)),
  )
  assert_eq(captured_row_count(source), 2)
}

///|
test "inference object intermediates enforce logical limits and keep cancellation custody" {
  let mapping =
    #|{"property":{"value":{"object":{"a":{"field":"text"},"b":{"field":"secret"}}},"name":"a"}}
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"}]
    ),
    mapping~,
  )
  let limits = infer_preflight_limits()
  let execution = start_infer_rows_preparation(@bounded.control(), input, {
    ..limits,
    // The final scalar fits, but the demanded intermediate object is 30 bytes.
    logical: { ..limits.logical, max_value_bytes: 29L, },
  }).unwrap()
  assert_true(
    infer_preflight_drain(execution)
    is Err(
      Evaluation(
        0,
        0,
        { kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }
      )
    ),
  )
  assert_eq(execution.state.values.length(), 0)
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  let control = @bounded.control()
  let execution = start_infer_rows_preparation(control, input, limits).unwrap()
  let mut reached = false
  for _ in 0..<1000 {
    assert_true(
      advance_infer_rows_preparation(execution, 1).unwrap()
      is InferRowsContinue(..),
    )
    if execution.state.frame is Some(frame) &&
      frame.state is MeasureObject(_, _, _) {
      reached = true
      break
    }
  }
  assert_true(reached)
  assert_true(infer_rows_preparation_logical_usage(execution).1 > 0L)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_infer_rows_preparation(execution, 1).unwrap()
    is InferRowsStopped(Cancelled, ..),
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    limits,
  ).unwrap()
  let rows = infer_preflight_drain(execution).unwrap()
  assert_true(
    prepared_infer_rows_value(rows, 0, 0).unwrap().value
    is @admitted.Text("urgent"),
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(cleanup_prepared_infer_rows(rows))
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  assert_eq(captured_row_count(source), 1)
}
