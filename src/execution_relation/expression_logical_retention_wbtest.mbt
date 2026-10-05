///|
fn borrowed_text_expression(forward? : Bool = false) -> @lower.Expression {
  let body = if forward {
    "{\"coalesce\":[{\"field\":\"payload\"},{\"literal\":null}]}"
  } else {
    "{\"field\":\"payload\"}"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"copy\":" +
    body +
    "}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 20,
    max_literal_nodes: 100,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
fn text_expression_budget(work : Int64, live : Int64) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 4100L,
      max_live_value_bytes: live,
      max_work: work,
    },
    4100,
    10000,
    100,
  ).unwrap()
}

///|
test "borrowed long expression results yield within their logical measurement" {
  for captured in [false, true] {
    let text = String::make(4096, 'g')
    let input = if captured {
      logical_literal("\"" + text + "\"")
    } else {
      Text(text)
    }
    let logical = text_expression_budget(4098L, 4098L)
    let workspace = row_workspace(100)
    let frame = expression_frame(
      borrowed_text_expression(),
      Map([("payload", input)]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut result : EvaluatedValue? = None
    let mut polls = 0
    for _ in 0..<1000 {
      polls += 1
      let before = logical.work
      result = advance_expression_frame(frame).unwrap()
      assert_true(logical.work - before <= 64L)
      if result is Some(_) {
        break
      }
    }
    guard result is Some(result) else { fail("long result did not terminate") }
    assert_eq(object_result_wire(result.value), "\"" + text + "\"")
    assert_true(polls > 100)
    assert_eq((logical.work, logical.live), (4098L, 4098L))
    assert_eq(workspace.live, 0)
    release_logical_root(logical, result.root.unwrap()).unwrap()
    assert_eq(logical.live, 0L)
  }
}

///|
test "expression logical measurement keeps independent exact and one short bounds" {
  // One field entry plus one Text node and 4096 UTF-8 bytes: 4098 work.
  // The root is the 4098-byte quoted Text. Eight fixed cursor handles, one
  // wire frame and its pre-reserved successor require ten workspace slots.
  for
    (work, live, slots, failure) in [
      (4098L, 4098L, 10, 0),
      (4097L, 4098L, 10, 1),
      (4098L, 4097L, 10, 2),
      (4098L, 4098L, 9, 3),
    ] {
    let budget = text_expression_budget(work, live)
    let workspace = row_workspace(slots)
    let frame = expression_frame(
      borrowed_text_expression(),
      Map([("payload", Text(String::make(4096, 'g')))]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(budget, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for _ in 0..<1000 {
      result = advance_expression_frame(frame)
      if !(result is Ok(None)) {
        break
      }
    }
    match failure {
      0 => {
        guard result is Ok(Some(value)) else {
          fail("exact expression boundary")
        }
        assert_eq(
          (budget.work, budget.live, workspace.peak),
          (4098L, 4098L, 10),
        )
        release_logical_root(budget, value.root.unwrap()).unwrap()
      }
      1 =>
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
        )
      2 =>
        assert_true(result is Err({ kind: LogicalValue(LiveValueLimit), .. }))
      3 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      _ => fail("unknown expression boundary")
    }
    let consumed = budget.work
    assert_true(consumed > 0L)
    close_expression_frame(frame)
    assert_eq((budget.work, budget.live, workspace.live), (consumed, 0L, 0))
  }
}

///|
test "expression cancellation releases only measurement custody and retains consumed work" {
  let budget = text_expression_budget(10000L, 10000L)
  let borrowed = retain_logical_value(budget, Number(7)).unwrap()
  let workspace = row_workspace(10)
  let frame = expression_frame(
    borrowed_text_expression(),
    Map([("payload", Text(String::make(4096, 'g')))]),
    [],
    { remaining: 10000, max_frames: 10, },
    workspace,
    Some(expression_roots(budget, 10)),
  ).unwrap()
  for _ in 0..<12 {
    assert_true(advance_expression_frame(frame) is Ok(None))
  }
  assert_true(frame.state is MeasureResult(_, _))
  assert_true(budget.work > 64L && budget.work < 4098L)
  assert_eq(budget.live, 1L)
  assert_true(workspace.live > 0)
  let consumed = budget.work
  close_expression_frame(frame)
  assert_eq((budget.work, budget.live, workspace.live), (consumed, 1L, 0))
  assert_false(borrowed.released)
  close_expression_frame(frame)
  assert_eq((budget.work, budget.live, workspace.live), (consumed, 1L, 0))
  assert_true(
    advance_expression_frame(frame) is Err({ kind: InvalidControlLimits, .. }),
  )
  release_logical_root(budget, borrowed).unwrap()
  assert_eq(budget.live, 0L)
}

///|
test "large forwarded results charge every semantic consumption without remeasurement" {
  // Two entries; the field result, COALESCE operand and forwarded result each
  // consume the same Text weight (4097). A cached proof is not a free result.
  for (work, drain) in [(12293L, false), (12293L, true), (12292L, false)] {
    let budget = text_expression_budget(work, 4098L)
    let workspace = row_workspace(100)
    let frame = expression_frame(
      borrowed_text_expression(forward=true),
      Map([("payload", Text(String::make(4096, 'g')))]),
      [],
      { remaining: 10000, max_frames: 10, },
      workspace,
      Some(expression_roots(budget, 10)),
    ).unwrap()
    let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
    for i in 0..<1000 {
      result = advance_expression_frame(frame, drain=drain && i > 12)
      if !(result is Ok(None)) {
        break
      }
    }
    if work == 12293L {
      guard result is Ok(Some(value)) else { fail("forwarded Text boundary") }
      assert_eq((budget.work, budget.live), (12293L, 4098L))
      assert_eq(
        object_result_wire(value.value),
        "\"" + String::make(4096, 'g') + "\"",
      )
      release_logical_root(budget, value.root.unwrap()).unwrap()
    } else {
      assert_true(
        result
        is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
      )
    }
    assert_eq((budget.live, workspace.live), (0L, 0))
  }
}

///|
test "prepaid expression results reject foreign revoked and unmeasured roots" {
  let budget = test_logical_budget(1000L, 1000L)
  let scope = expression_roots(budget, 10)
  let other = expression_roots(budget, 10)
  let root = track_expression_root(scope, Number(7), true).unwrap()
  let expression = lowered("\"7\"")
  let charged = budget.work
  assert_true(
    expression_event_result(
      Some(scope),
      Number(7),
      Some(root),
      expression,
      prepaid=true,
    )
    is Ok(_),
  )
  assert_eq(budget.work, charged)
  assert_true(
    expression_event_result(
      Some(other),
      Number(7),
      Some(root),
      expression,
      prepaid=true,
    )
    is Err({ kind: LogicalValue(InvalidRootLifetime), .. }),
  )
  root.root.measurement = None
  assert_true(
    expression_event_result(
      Some(scope),
      Number(7),
      Some(root),
      expression,
      prepaid=true,
    )
    is Err({ kind: LogicalValue(InvalidRootLifetime), .. }),
  )
  release_expression_root(root).unwrap()
  assert_true(
    expression_event_result(
      Some(scope),
      Number(7),
      Some(root),
      expression,
      prepaid=true,
    )
    is Err({ kind: LogicalValue(InvalidRootLifetime), .. }),
  )
  assert_eq((budget.work, budget.live), (charged, 0L))
}

///|
test "bounded derivation can stop while a demanded Text result is being measured" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"" + String::make(256, 'g') + "\"}]",
    derive_text=true,
    fragment_rows=1L,
  )
  let logical = execution.state.logical.unwrap()
  let mut reached = false
  for _ in 0..<4000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(LogicalRows(issue)), ..) => {
        debug_inspect(issue, content="unexpected demanded Text logical failure")
        fail("derivation failed before demanded measurement")
      }
      BoundedBindingRowsFailed(_, ..) =>
        fail("derivation failed before demanded measurement")
      _ => fail("derivation completed before demanded measurement")
    }
    if execution.state.binding_execution is Some(bindings) &&
      bindings.active is Some(frame) &&
      frame.state is MeasureResult(_, _) &&
      logical.work > 330L {
      reached = true
      break
    }
  }
  assert_true(reached)
  let consumed = logical.work
  let held = execution.state.workspace.live
  assert_true(held > 0)
  assert_false(execution.state.input_roots[0].root.released)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq((logical.work, execution.state.workspace.live), (consumed, held))
  assert_true(producer_read_available(input))
  assert_true(execution.state.rows.val is None)
  assert_false(execution.accepted.val)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(
    (logical.work, logical.live, execution.state.workspace.live),
    (consumed, 0L, 0),
  )
  assert_true(producer_read_available(input))
}

///|
test "bounded derivation completes an independently expected demanded Text row" {
  // The existing checked fixture's 1000-byte per-value contract covers both
  // retained Text columns. The demanded cell still requires multiple chunks.
  let text = String::make(256, 'g')
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"" + text + "\"}]",
    derive_text=true,
    fragment_rows=1L,
  )
  let mut output : CompletedOutput? = None
  let mut polls = 0
  for _ in 0..<8000 {
    polls += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(completed, ..) => {
        output = Some(completed)
        break
      }
      _ => fail("demanded Text derivation failed")
    }
  }
  guard output is Some(output) else { fail("derivation did not terminate") }
  assert_eq(completed_column_count(output), 3)
  // The admitted row owner stores the checked schema's canonical name order.
  for index, name in ["copy", "id", "tag"] {
    assert_eq(completed_column_name(output, index), Some(name))
  }
  assert_eq(completed_row_count(output), 1)
  assert_eq(
    object_result_wire(completed_cell(output, 0, 0).unwrap()),
    "\"" + text + "\"",
  )
  assert_eq(object_result_wire(completed_cell(output, 0, 1).unwrap()), "1")
  assert_eq(
    object_result_wire(completed_cell(output, 0, 2).unwrap()),
    "\"" + text + "\"",
  )
  assert_true(polls > 50)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "large stepped expression roots preserve acquisition result ceilings" {
  let logical = logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 4100L,
      max_live_value_bytes: 4100L,
      max_work: 4098L,
    },
    4100,
    100,
    100,
    root_result_bytes=Some(4097L),
    all_expression_roots=true,
  ).unwrap()
  let frame = expression_frame(
    borrowed_text_expression(),
    Map([("payload", Text(String::make(4096, 'g')))]),
    [],
    { remaining: 10000, max_frames: 10, },
    row_workspace(10),
    Some(expression_roots(logical, 10)),
  ).unwrap()
  let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
  for _ in 0..<1000 {
    result = advance_expression_frame(frame)
    if !(result is Ok(None)) {
      break
    }
  }
  assert_true(
    result is Err({ kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }),
  )
  assert_eq((logical.work, logical.live, frame.workspace.live), (4098L, 0L, 0))
}
