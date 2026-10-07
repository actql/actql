///|
fn indexed_snapshot_fixture(
  name : String,
  derive_name? : String = "next",
  projection? : Bool = false,
  operation? : String? = None,
  rows? : String? = None,
  nullable? : Bool = false,
  keyed? : Bool = false,
  binding? : Bool = false,
  ordered_binding? : Bool = false,
  work? : Int = 100000,
  entries? : Int = 10000,
) -> BoundedBindingRowsExecution raise {
  let input_rows = rows.unwrap_or("[{\"id\":1,\"" + name + "\":7}]")
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":" +
    nullable.to_string() +
    "}},\"rows\":" +
    input_rows +
    "},\"as\":\"seed\"}" +
    (if keyed {
      ",{\"from\":\"seed\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"keyed\"}]"
    } else {
      "]"
    }),
  )
  let source_sequence = prepared_sequence(source_owner)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    source_sequence,
    [],
    Array::makei(if keyed { 2 } else { 1 }, index => {
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(source_owner), index).unwrap(),
      )
    }),
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(if keyed { 1 } else { 0 }),
  ).unwrap()
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    derive_scalar=!projection,
    derive_name~,
    select=projection,
    select_name=Some(name),
    metadata_operation=operation,
    source_step=if keyed { 1 } else { 0 },
  )
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if ordered_binding {
      [bounded_binding_rows_ordered_context(sequence)]
    } else if projection || (operation is Some(_) && !binding) {
      []
    } else {
      [sequence_fragment_context(sequence, 0, 1L)]
    },
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let read = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  start_bounded_binding_rows(
    @bounded.control(),
    generated,
    read,
    100,
    run_limits().input_values,
    run_limits().output_values,
    work,
    100,
    entries,
    10000,
  ).unwrap()
}

///|
test "indexed expression input preserves NULL missing and wide-row work bounds" {
  let expression = lowered("\"id\"")
  for quantum in [1, 7, 256] {
    for
      (work, slots, success) in [(2L, 2, true), (1L, 2, false), (2L, 1, false)] {
      let logical = text_expression_budget(work, 100L)
      let workspace = row_workspace(slots)
      let input = Array::makei(9, index => {
        if index == 8 {
          ("id", Null)
        } else {
          ("unused" + index.to_string(), Number(9))
        }
      })
      let frame = expression_frame_with_input(
        expression,
        indexed_expression_input(input),
        [],
        { remaining: 4, max_frames: 10, },
        workspace,
        Some(expression_roots(logical, 10)),
      ).unwrap()
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      for _ in 0..<100 {
        for _ in 0..<quantum {
          if result is Ok(None) {
            result = advance_expression_frame(frame)
          }
        }
      }
      if success {
        guard result is Ok(Some(value)) else {
          fail("exact indexed expression")
        }
        assert_true(value.value is Null)
        assert_eq((logical.work, workspace.peak), (2L, 2))
        release_logical_root(logical, value.root.unwrap()).unwrap()
      } else if slots == 1 {
        assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      } else {
        assert_true(
          result
          is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
        )
      }
      assert_eq((logical.live, workspace.live), (0L, 0))
    }
  }
  let frame = expression_frame_with_input(
    expression,
    indexed_expression_input([]),
    [],
    { remaining: 4, max_frames: 10, },
    row_workspace(0),
    None,
  ).unwrap()
  assert_true(
    advance_expression_frame(frame) is Err({ kind: MissingValue, .. }),
  )
}

///|
test "row name cursor preserves exact UTF8 budgets and atomic Value accounting" {
  let name = "x".repeat(63) + "😀" + "é".repeat(65)
  for (limit, success) in [(197, true), (196, false)] {
    let workspace = row_workspace(1)
    let cursor = start_row_name_charge(name, workspace).unwrap()
    let control = { remaining: limit, max_frames: 0, }
    let mut result : Result[Bool, RowIssue] = Ok(false)
    for _ in 0..<300 {
      if result is Ok(false) {
        result = advance_row_name_charge(cursor, Some(control), None)
      }
    }
    if success {
      assert_true(result is Ok(true))
      assert_eq(control.remaining, 0)
    } else {
      assert_true(result is Err(RowLimit))
      assert_eq(control.remaining, 1)
    }
    close_row_name_charge(cursor)
    close_row_name_charge(cursor)
    assert_eq(workspace.live, 0)
    let budget = value_budget({
      max_nodes: 0,
      max_text_bytes: limit,
      max_depth: 0,
      max_work: limit,
    }).unwrap()
    let cursor = start_row_name_charge(name, workspace).unwrap()
    let mut result : Result[Bool, RowIssue] = Ok(false)
    for _ in 0..<300 {
      if result is Ok(false) {
        result = advance_row_name_charge(cursor, None, Some(budget))
      }
    }
    if success {
      assert_true(result is Ok(true))
      assert_eq((budget.text, budget.work), (197, 197))
    } else {
      assert_true(result is Err(RowLimit))
      assert_eq((budget.text, budget.work), (0, 0))
    }
    close_row_name_charge(cursor)
    assert_eq(workspace.live, 0)
  }
  assert_true(start_row_name_charge(name, row_workspace(0)) is None)
}

///|
test "retained row names stop in input snapshot output and capture phases" {
  let name = "x".repeat(256)
  for target in [0, 1, 2, 3] {
    let execution = indexed_snapshot_fixture(name)
    let mut inside = false
    for _ in 0..<6000 {
      if !inside {
        assert_true(
          advance_bounded_binding_rows(execution, 1).unwrap()
          is BoundedBindingRowsContinue(..),
        )
        if execution.state.name_charge is Some(cursor) && cursor.offset == 64 {
          inside = match execution.state.phase {
            ChargeInput => target == 0
            SnapshotRow => target == 1
            BuildOutputRow => target == 2
            ChargeCaptureRow => target == 3
            _ => false
          }
        }
      }
    }
    assert_true(inside)
    let remaining = execution.state.control.remaining
    assert_true(@bounded.request_cancel(execution.state.engine))
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(
      (execution.state.control.remaining, execution.state.workspace.live),
      (remaining, 0),
    )
    assert_true(execution.state.name_charge is None)
    assert_true((execution.state.available)())
  }
}

///|
test "long row snapshot names yield without a whole spelling charge" {
  let execution = indexed_snapshot_fixture("x".repeat(256))
  let mut inside = false
  for _ in 0..<2000 {
    if !inside {
      assert_true(
        advance_bounded_binding_rows(execution, 1).unwrap()
        is BoundedBindingRowsContinue(..),
      )
      inside = execution.state.phase is SnapshotRow &&
        execution.state.column == 1
    }
  }
  assert_true(inside)
  let before = execution.state.control.remaining
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsContinue(..),
  )
  assert_true(
    before - execution.state.control.remaining <= 64,
    msg="snapshot construction must not scan an entire long name in one poll",
  )
  @bounded.request_cancel(execution.state.engine) |> ignore
  advance_bounded_binding_rows(execution, 1) |> ignore
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
}
