///|
fn nested_distinct_fixture(
  max_work? : Int = 100000,
  max_entries? : Int = 10000,
  max_frames? : Int = 100,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let schema = "{\"id\":{\"type\":\"object\",\"nullable\":false," +
    "\"fields\":{\"p\":{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"string\",\"nullable\":true}}}}}"
  let row = fn(suffix : String) {
    "{\"id\":{\"p\":[\"" + String::make(256, 'g') + suffix + "\",null]}}"
  }
  let (owner, source) = bounded_append_source(
    "[" + row("a") + "," + row("b") + "," + row("a") + "]",
    schema~,
  )
  let receiver = bounded_binding_rows_receiver(owner, distinct=true)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    max_frames,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
fn nested_distinct_texts(output : CompletedOutput) -> Array[String] raise {
  let texts : Array[String] = []
  for row in 0..<completed_row_count(output) {
    guard completed_cell(output, row, 0)
      is Some(Captured(@admitted.Object(properties))) &&
      @admitted.element_at(properties, 0) is Some(("p", @admitted.Array(items))) &&
      @admitted.element_at(items, 0) is Some(@admitted.Text(text)) &&
      @admitted.element_at(items, 1) is Some(@admitted.Null) else {
      fail("unexpected nested DISTINCT survivor")
    }
    texts.push(text)
  }
  texts
}

///|
test "whole-row DISTINCT yields during nested comparison and preserves logical work" {
  let mut prior : Int? = None
  for quantum in [1, 7] {
    let (_, execution, input) = nested_distinct_fixture()
    let mut output : CompletedOutput? = None
    for _ in 0..<20000 {
      let before = execution.state.control.remaining
      let comparing = execution.state.phase is (SortRows | MarkDistinct)
      let poll = advance_bounded_binding_rows(execution, quantum).unwrap()
      if comparing && quantum == 1 {
        // A merge/adjacency action and one value node may charge together.
        // A recursive walk must never hide its remaining work in that poll.
        assert_true(before - execution.state.control.remaining <= 2)
      }
      match poll {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("nested DISTINCT did not complete")
      }
    }
    guard output is Some(output) else {
      fail("nested DISTINCT exceeded the polling bound")
    }
    assert_eq(nested_distinct_texts(output), [
      String::make(256, 'g') + "a",
      String::make(256, 'g') + "b",
    ])
    let spent = 100000 - execution.state.control.remaining
    if prior is Some(expected) {
      assert_eq(spent, expected)
    }
    prior = Some(spent)
    assert_true(completed_output_matches_inputs(output, [input]))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
test "whole-row DISTINCT retains a nested comparison until confirmed stop and cleanup" {
  for (sorting, text_phase) in [(true, 1), (true, 3), (false, 3)] {
    let (control, execution, input) = nested_distinct_fixture()
    let mut pending : BoundedCompleteTreeComparison? = None
    for _ in 0..<20000 {
      assert_true(
        advance_bounded_binding_rows(execution, 1).unwrap()
        is BoundedBindingRowsContinue(..),
      )
      let phase = if sorting {
        execution.state.phase is SortRows
      } else {
        execution.state.phase is MarkDistinct
      }
      if phase &&
        execution.state.comparison.tree is Some(tree) &&
        tree.frames.last() is Some(TextUnits(_, _, text, _)) &&
        text.phase == text_phase &&
        (text_phase != 3 || text.offset > 0) {
        pending = Some(tree)
        break
      }
    }
    guard pending is Some(tree) else {
      fail("nested DISTINCT comparison boundary was not reached")
    }
    let live = execution.state.workspace.live
    let work = execution.state.control.remaining
    assert_true(live > 0)
    assert_false(tree.closed)
    assert_true(producer_read_available(input))
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
    )
    assert_eq(execution.state.workspace.live, live)
    assert_eq(execution.state.control.remaining, work)
    assert_false(tree.closed)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(tree.closed)
    assert_true(tree.frames.is_empty())
    assert_true(execution.state.comparison.tree is None)
    assert_eq(execution.state.workspace.live, 0)
    assert_eq(execution.state.control.remaining, work)
    assert_true(producer_read_available(input))
  }
}

///|
test "whole-row DISTINCT accounts nested comparison workspace and frame limits" {
  // Four metadata slots, one term, two three-row index arrays, plus a
  // four-slot Object -> Array -> Text comparison cursor: 4 + 1 + 6 + 4 = 15.
  for
    (slots, frames, succeeds) in [(15, 3, true), (14, 3, false), (15, 2, false)] {
    let (_, execution, input) = nested_distinct_fixture(
      max_entries=slots,
      max_frames=frames,
    )
    let mut terminal = false
    for _ in 0..<20000 {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(succeeds)
          assert_eq(completed_row_count(output), 2)
          assert_eq(execution.state.workspace.peak, 15)
          terminal = true
          break
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(succeeds)
          terminal = true
          break
        }
        _ => fail("nested DISTINCT limit had an unrelated outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(execution.state.comparison.tree is None)
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
test "whole-row DISTINCT complete comparator accepts exact work and rejects one short" {
  // Wrapper 1 + Object 1 + two name bytes 2 + Array 1 + Text node 1 +
  // two 257-byte operands 514 + NULL node 1 = 521, independent of quantum.
  for (work, succeeds) in [(521, true), (520, false)] {
    let (engine, execution, input) = nested_distinct_fixture()
    let control : ControlBudget = { remaining: work, max_frames: 3, }
    let workspace = row_workspace(4)
    let orders : Array[ColumnOrder] = [
      { column: 0, descending: false, nulls_first: false, },
    ]
    let mut result : Result[Int?, OrderingIssue] = Ok(None)
    for _ in 0..<2000 {
      result = bounded_row_comparison_step_with(
        execution.state.comparison,
        orders,
        control,
        fn(row, column) { producer_read_cell(input, row, column) },
        0,
        2,
        1,
        complete_values=true,
        workspace=Some(workspace),
      )
      if !(result is Ok(None)) {
        break
      }
    }
    if succeeds {
      assert_true(result is Ok(Some(0)))
      assert_eq(control.remaining, 0)
      assert_eq(workspace.peak, 4)
    } else {
      assert_true(result is Err(Limit))
      assert_true(execution.state.comparison.tree is Some(_))
    }
    assert_true(@bounded.request_cancel(engine))
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
test "public nested DISTINCT fixture reaches a scanning barrier after nine Host quanta" {
  let (engine, execution, input) = nested_distinct_fixture()
  for quantum in 1..<10 {
    guard advance_bounded_binding_rows(execution, 256).unwrap()
      is BoundedBindingRowsContinue(progress~, work~) else {
      fail("public nested DISTINCT barrier must precede completion")
    }
    assert_eq(progress, 0L)
    assert_eq(work, quantum.to_int64() * 256L)
  }
  assert_true(execution.state.phase is SortRows)
  guard execution.state.comparison.tree is Some(tree) &&
    tree.frames.last() is Some(TextUnits(_, _, text, _)) else {
    fail("public nested DISTINCT barrier must retain its comparison")
  }
  assert_eq(text.phase, 3)
  assert_true(text.offset > 0 && text.offset < 257)
  assert_true(@bounded.request_cancel(engine))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}
