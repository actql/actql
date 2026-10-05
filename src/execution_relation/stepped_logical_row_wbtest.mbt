///|
fn logical_text_row_budget(work : Int64, live : Int64) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: 1L,
      max_value_bytes: 4110L,
      max_live_value_bytes: live,
      max_work: work,
    },
    4110,
    2,
    1,
  ).unwrap()
}

///|
test "stepped logical row walks nested cells without copying their elements" {
  // 65 scalar occurrences: [1,...,1] is 131 bytes. The outer row adds
  // twelve bytes; object + key bytes + array + scalar nodes cost 74 work.
  let value = logical_literal("[" + Array::make(65, "1").join(",") + "]")
  for work in [74L, 73L] {
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 143L,
        max_live_value_bytes: 143L,
        max_work: work,
      },
      143,
      67,
      3,
    ).unwrap()
    let workspace = row_workspace(13)
    let cursor = start_stepped_logical_row(
      budget,
      ["payload"],
      [value],
      workspace,
    ).unwrap()
    let mut result : Result[LogicalRoot?, RowIssue] = Ok(None)
    let mut polls = 0
    for _ in 0..<1000 {
      if result is Ok(None) {
        result = advance_stepped_logical_row(cursor)
        polls += 1
      }
    }
    if work == 74L {
      guard result is Ok(Some(root)) else {
        if result is Err(LogicalRows(issue)) {
          debug_inspect(issue, content="completed nested row")
        }
        fail("nested exact allowance")
      }
      assert_eq((budget.work, budget.live), (74L, 143L))
      assert_true(polls > 65)
      assert_true(workspace.peak <= 13)
      release_logical_root(budget, root).unwrap()
    } else {
      assert_true(result is Err(LogicalRows(ValueMeasure(LogicalWorkLimit))))
      assert_eq(budget.work, 73L)
    }
    assert_eq((budget.live, workspace.live), (0L, 0))
  }
}

///|
test "stepped logical row keeps independent work live bytes and workspace bounds" {
  // {"payload":"<4096 ASCII units>"}: 4110 bytes; object node,
  // seven key bytes, one Text node and 4096 Text bytes: 4105 work.
  // Two row/writer handles plus eight cell handles, one pending wire frame
  // and one pre-reserved successor frame coexist at the peak: twelve slots.
  for
    (work, live, workspace_limit, failure) in [
      (4105L, 4110L, 12, 0),
      (4104L, 4110L, 12, 1),
      (4105L, 4109L, 12, 2),
      (4105L, 4110L, 11, 3),
    ] {
    let budget = logical_text_row_budget(work, live)
    let workspace = row_workspace(workspace_limit)
    let cursor = start_stepped_logical_row(
      budget,
      ["payload"],
      [Text(String::make(4096, 'g'))],
      workspace,
    ).unwrap()
    let mut result : Result[LogicalRoot?, RowIssue] = Ok(None)
    let mut polls = 0
    for _ in 0..<400 {
      if result is Ok(None) {
        let before = budget.work
        result = advance_stepped_logical_row(cursor)
        assert_true(budget.work - before <= 64L)
        polls += 1
      }
    }
    match failure {
      0 => {
        guard result is Ok(Some(root)) else { fail("exact row allowance") }
        assert_eq((budget.work, budget.live), (4105L, 4110L))
        assert_eq(workspace.peak, 12)
        assert_true(polls > 100)
        release_logical_root(budget, root).unwrap()
      }
      1 => {
        assert_true(result is Err(LogicalRows(ValueMeasure(LogicalWorkLimit))))
        assert_eq(budget.work, 4104L)
      }
      2 => assert_true(result is Err(LogicalRows(LiveValueLimit)))
      _ => assert_true(result is Err(RowLimit))
    }
    let charged = budget.work
    close_stepped_logical_row(cursor)
    close_stepped_logical_row(cursor)
    assert_eq((workspace.live, budget.live), (0, 0L))
    assert_eq(budget.work, charged)
    assert_true(advance_stepped_logical_row(cursor) is Err(InvalidRows))
  }
}

///|
test "stepped logical row closes traversal and wire without issuing a root" {
  for during_wire in [false, true] {
    let budget = logical_text_row_budget(4105L, 4110L)
    let workspace = row_workspace(20)
    let text = String::make(4096, 'g')
    let row = [Text(text)]
    let cursor = start_stepped_logical_row(budget, ["payload"], row, workspace).unwrap()
    let mut reached = false
    for _ in 0..<400 {
      if !reached {
        assert_true(advance_stepped_logical_row(cursor).unwrap() is None)
        reached = if during_wire {
          cursor.wire is Some(wire) &&
          wire.cursor is TextWire(_) &&
          @encode.writer_progress(cursor.writer).0 > 12
        } else {
          cursor.measure is Some(measure) &&
          measure.text is Some((_, index)) &&
          index > 0
        }
      }
    }
    assert_true(reached)
    assert_eq(budget.live, 0L)
    assert_true(budget.work > 8L)
    let work = budget.work
    close_stepped_logical_row(cursor)
    close_stepped_logical_row(cursor)
    assert_eq((budget.work, budget.live, workspace.live), (work, 0L, 0))
    assert_true(row[0] is Text(value) && value == text)
    assert_true(
      try {
        @encode.finish_measurement(cursor.writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      },
    )
  }
}

///|
test "analytic logical roots yield within input and output Text retention" {
  for stop_at in [-1, 0, 1] {
    let owner = aggregate_output_text_owner(
      "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
    )
    let input = aggregate_output_text_input(owner)
    let budget = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: 100000L,
        max_live_value_bytes: 200000L,
        max_work: 200000L,
      },
      100000,
      100,
      10,
    ).unwrap()
    let scope = expression_roots(budget, 100)
    let workspace = row_workspace(10000)
    let control = { remaining: 100000, max_frames: 100, }
    let accepted : Array[Array[Value]] = []
    let state = start_analytic_evaluation(
      @lower.kernel_analytic(row_kernel(owner, 0)).unwrap(),
      input,
      1,
      control,
      row_output(),
      workspace,
      Some(scope),
      [],
      None,
      run_limits().input_values,
      None,
      0,
      (row, _) => {
        accepted.push(row)
        Ok(())
      },
    )
    let mut done = false
    let mut reached = false
    let mut input_steps = 0
    let mut output_steps = 0
    for _ in 0..<20000 {
      if !done && !reached {
        match advance_analytic_evaluation(state).unwrap() {
          Some(_) => done = true
          None => ()
        }
        if state.input_logical is Some(cursor) &&
          cursor.measure is Some(measure) &&
          measure.text is Some((_, index)) &&
          index > 0 {
          input_steps += 1
          reached = stop_at == 0
        }
        if state.output_logical is Some(cursor) &&
          cursor.measure is Some(measure) &&
          measure.text is Some((_, index)) &&
          index > 0 {
          output_steps += 1
          reached = stop_at == 1
        }
      }
    }
    if stop_at < 0 {
      assert_true(done)
      assert_true(input_steps > 1 && output_steps > 1)
      assert_eq(accepted.length(), 1)
      assert_eq(accepted[0].length(), 5)
      assert_true(accepted[0][0] is Number(7))
      assert_true(
        accepted[0][1] is Text(text) && text == String::make(4096, 'g'),
      )
      assert_true(accepted[0][2] is Number(1))
      assert_true(accepted[0][3] is Number(1))
      assert_true(accepted[0][4] is Text("open"))
    } else {
      assert_true(reached && !done)
      assert_eq(accepted.length(), 0)
      let cursor = if stop_at == 0 {
        // The input has no root until measurement completes.
        assert_eq(budget.live, 0L)
        state.input_logical.unwrap().writer
      } else {
        assert_true(budget.live > 0L)
        state.output_logical.unwrap().writer
      }
      let work = budget.work
      let slots = workspace.live
      close_analytic_evaluation(state)
      close_analytic_evaluation(state)
      assert_true(workspace.live < slots)
      assert_eq(budget.work, work)
      assert_true(state.input_logical is None && state.output_logical is None)
      assert_true(advance_analytic_evaluation(state) is Err(InvalidRows))
      assert_true(
        try {
          @encode.finish_measurement(cursor) |> ignore
          false
        } catch {
          @encode.ClosedWriter => true
          _ => false
        },
      )
      assert_true(
        IndexedRows::read_cell(input, 0, 1) is Text(text) &&
        text.length() == 4096,
      )
    }
    cleanup_expression_roots(scope)
    assert_eq(budget.live, 0L)
  }
}
