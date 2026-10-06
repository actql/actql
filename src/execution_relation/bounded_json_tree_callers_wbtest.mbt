///|
fn bounded_json_tree_payload(code : Int) -> String {
  if code == 3 {
    "null"
  } else {
    "{\"p\":[\"" +
    String::make(128, 'g') +
    (if code == 1 { "a" } else { "b" }) +
    "\",null]}"
  }
}

///|
fn bounded_json_tree_literal(code : Int) -> String raise {
  let writer = @encode.writer(1000, 1, 0)
  @encode.string_value(writer, bounded_json_tree_payload(code))
  "{\"typed_literal\":{\"type\":\"json\",\"value\":" +
  @encode.finish(writer) +
  "}}"
}

///|
// Derive JSON from ordinary Values. JSON Values admission is not widened.
fn bounded_json_tree_source(
  values : Array[Int],
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let choose = "{\"if\":[{\"eq\":[{\"field\":\"seed\"},{\"literal\":0}]},{\"literal\":null}," +
    "{\"if\":[{\"eq\":[{\"field\":\"seed\"},{\"literal\":3}]}," +
    bounded_json_tree_literal(3) +
    "," +
    "{\"if\":[{\"eq\":[{\"field\":\"seed\"},{\"literal\":1}]}," +
    bounded_json_tree_literal(1) +
    "," +
    bounded_json_tree_literal(2) +
    "]}]}]}"
  let rows = values
    .map(value => "{\"seed\":" + value.to_string() + "}")
    .join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"seed\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]},\"as\":\"seed\"}," +
    "{\"derive\":{\"id\":" +
    choose +
    "}},{\"select\":[\"id\"]}]",
  )
  let sequence = prepared_sequence(owner)
  let nodes = Array::makei(3, index => {
    @lower.node_id(
      @lower.node_at(@lower.bound_preparation(owner), index).unwrap(),
    )
  })
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 1, values.length().to_int64())],
    nodes,
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(2)).unwrap())
}

///|
fn bounded_json_tree_row(code : Int) -> String {
  if code == 0 {
    "{\"id\":null}"
  } else {
    "{\"id\":{\"$json\":" + bounded_json_tree_payload(code) + "}}"
  }
}

///|
fn bounded_json_tree_rows(output : CompletedOutput) -> Array[String] {
  let rows : Array[String] = []
  for row in 0..<completed_row_count(output) {
    rows.push(completed_output_row_wire(output, row, 1000, 100, 20).unwrap())
  }
  rows
}

///|
fn bounded_json_tree_set_fixture(
  operation : String,
  duplicates : String,
) -> (@bounded.Control, BoundedSetExecution, Array[ProducerRead]) raise {
  let (left_owner, left_output) = bounded_json_tree_source([1, 2, 1, 0, 3])
  let (right_owner, right_output) = bounded_json_tree_source([1, 0])
  let left_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(left_owner)),
    @pipeline.Step(2),
  ).unwrap()
  let right_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(right_owner)),
    @pipeline.Step(2),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"l\",\"" +
      operation +
      "\":{\"with\":\"r\",\"duplicates\":\"" +
      duplicates +
      "\"}}]",
    ),
    [
      ("l", @pipeline.ProducedInput(left_producer)),
      ("r", @pipeline.ProducedInput(right_producer)),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [operation + "_0"],
    10000,
    1000,
  ).unwrap()
  let left = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, left_owner, left_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let right = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 1, right_owner, right_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_set(
    control,
    generated,
    left,
    right,
    8,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    },
    run_limits().output_values,
    100000,
    100,
    1000,
    1000,
  )
  (control, execution.unwrap(), [left, right])
}

///|
fn bounded_json_tree_distinct_fixture(
  values? : Array[Int] = [1, 2, 1, 0, 3, 0, 3],
  max_entries? : Int = 10000,
  max_frames? : Int = 100,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let (owner, source) = bounded_json_tree_source(values)
  let max_work = 100000
  let receiver = bounded_binding_rows_receiver(
    owner,
    source_step=2,
    distinct=true,
  )
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
test "bounded JSON Set retains payload equality and both NULL domains" {
  for
    (operation, duplicates, expected) in [
      ("except", "all", [1, 2, 3]),
      ("except", "distinct", [2, 3]),
      ("intersect", "all", [1, 0]),
      ("intersect", "distinct", [1, 0]),
    ] {
    let mut prior_work : Int? = None
    for quantum in [1, 64] {
      let (_, execution, inputs) = bounded_json_tree_set_fixture(
        operation, duplicates,
      )
      let mut output : CompletedOutput? = None
      let mut saw_tree = false
      for _ in 0..<20000 {
        let before = execution.state.control.remaining
        let comparing = execution.state.phase is (SortLeft | SortRight | Merge)
        let poll = advance_bounded_set(execution, quantum).unwrap()
        if comparing && quantum == 1 {
          assert_true(before - execution.state.control.remaining <= 2)
        }
        if execution.state.comparison.tree is Some(_) {
          saw_tree = true
        }
        match poll {
          BoundedSetContinue(..) => ()
          BoundedSetComplete(value, ..) => {
            output = Some(value)
            break
          }
          _ => fail("JSON Set did not complete")
        }
      }
      guard output is Some(output) else {
        fail("JSON Set exceeded polling bound")
      }
      if quantum == 1 {
        assert_true(saw_tree)
      }
      assert_eq(
        bounded_json_tree_rows(output),
        expected.map(bounded_json_tree_row),
      )
      let spent = 100000 - execution.state.control.remaining
      if prior_work is Some(expected_work) {
        assert_eq(spent, expected_work)
      }
      prior_work = Some(spent)
      assert_true(completed_output_matches_inputs(output, inputs))
      assert_true(cleanup_bounded_set(execution).unwrap())
      assert_false(cleanup_bounded_set(execution).unwrap())
      assert_eq(execution.state.workspace.live, 0)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "bounded JSON DISTINCT retains payloads SQL NULL and JSON null" {
  let mut prior_work : Int? = None
  for quantum in [1, 64] {
    let (_, execution, input) = bounded_json_tree_distinct_fixture()
    let mut output : CompletedOutput? = None
    let mut saw_tree = false
    for _ in 0..<20000 {
      let before = execution.state.control.remaining
      let comparing = execution.state.phase is (SortRows | MarkDistinct)
      let poll = advance_bounded_binding_rows(execution, quantum).unwrap()
      if comparing && quantum == 1 {
        assert_true(before - execution.state.control.remaining <= 2)
      }
      if execution.state.comparison.tree is Some(_) {
        saw_tree = true
      }
      match poll {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("JSON DISTINCT did not complete")
      }
    }
    guard output is Some(output) else {
      fail("JSON DISTINCT exceeded polling bound")
    }
    if quantum == 1 {
      assert_true(saw_tree)
    }
    assert_eq(
      bounded_json_tree_rows(output),
      [1, 2, 0, 3].map(bounded_json_tree_row),
    )
    let spent = 100000 - execution.state.control.remaining
    if prior_work is Some(expected_work) {
      assert_eq(spent, expected_work)
    }
    prior_work = Some(spent)
    assert_true(completed_output_matches_inputs(output, [input]))
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded JSON Set stops inside payload Text without releasing borrowed input" {
  let (control, execution, inputs) = bounded_json_tree_set_fixture(
    "except", "all",
  )
  let mut pending : BoundedCompleteTreeComparison? = None
  for _ in 0..<20000 {
    assert_true(
      advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
    )
    if execution.state.comparison.tree is Some(tree) &&
      tree.frames.last() is Some(TextUnits(_, _, text, _)) &&
      text.phase == 3 &&
      text.offset > 0 {
      pending = Some(tree)
      break
    }
  }
  guard pending is Some(tree) else {
    fail("JSON Set payload comparison was not exposed")
  }
  let live = execution.state.workspace.live
  let work = execution.state.control.remaining
  assert_true(live > 0)
  assert_false(tree.closed)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_set(execution, 1).unwrap()
    is BoundedSetStopped(@bounded.Cancelled, ..),
  )
  assert_eq(
    (execution.state.control.remaining, execution.state.workspace.live),
    (work, live),
  )
  assert_false(tree.closed)
  assert_true(inputs.all(producer_read_available))
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_false(cleanup_bounded_set(execution).unwrap())
  assert_true(tree.closed && tree.frames.is_empty())
  assert_true(execution.state.comparison.tree is None)
  assert_eq(
    (execution.state.control.remaining, execution.state.workspace.live),
    (work, 0),
  )
  assert_true(inputs.all(producer_read_available))
}

///|
test "bounded JSON DISTINCT stops inside payload Text and cleans up once" {
  let (control, execution, input) = bounded_json_tree_distinct_fixture()
  let mut pending : BoundedCompleteTreeComparison? = None
  for _ in 0..<20000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if execution.state.comparison.tree is Some(tree) &&
      tree.frames.last() is Some(TextUnits(_, _, text, _)) &&
      text.phase == 3 &&
      text.offset > 0 {
      pending = Some(tree)
      break
    }
  }
  guard pending is Some(tree) else {
    fail("JSON DISTINCT payload comparison was not exposed")
  }
  let live = execution.state.workspace.live
  let work = execution.state.control.remaining
  assert_true(live > 0)
  assert_false(tree.closed)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq(
    (execution.state.control.remaining, execution.state.workspace.live),
    (work, live),
  )
  assert_false(tree.closed)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(tree.closed && tree.frames.is_empty())
  assert_true(execution.state.comparison.tree is None)
  assert_eq(
    (execution.state.control.remaining, execution.state.workspace.live),
    (work, 0),
  )
  assert_true(producer_read_available(input))
}

///|
test "bounded JSON DISTINCT comparator keeps exact work and cursor limits" {
  // Captured 1 + JsonData 1 + Object 1 + two 'p' bytes 2 + Array 1 +
  // Text node 1 + two 129-byte strings 258 + NULL node 1 = 266.
  // Handle + Object continuation + Array/value + Text/name peak at four.
  for
    (work, slots, frames, succeeds) in [
      (266, 4, 3, true),
      (265, 4, 3, false),
      (266, 3, 3, false),
      (266, 4, 2, false),
    ] {
    let (engine, execution, input) = bounded_json_tree_distinct_fixture()
    let control : ControlBudget = { remaining: work, max_frames: frames, }
    let workspace = row_workspace(slots)
    let orders : Array[ColumnOrder] = [
      { column: 0, descending: false, nulls_first: false, },
    ]
    let mut result : Result[Int?, OrderingIssue] = Ok(None)
    for _ in 0..<2000 {
      let before = control.remaining
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
      assert_true(before - control.remaining <= 1)
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
    let remaining = control.remaining
    assert_true(@bounded.request_cancel(engine))
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq((control.remaining, workspace.live), (remaining, 0))
    assert_true(producer_read_available(input))
  }
}

///|
test "bounded JSON DISTINCT reserves exact whole-row comparison workspace" {
  // Four metadata slots + one term + two three-row indices + four cursor
  // slots = 15. The JsonData marker replaces a frame instead of adding one.
  for
    (slots, frames, succeeds) in [(15, 3, true), (14, 3, false), (15, 2, false)] {
    let (_, execution, input) = bounded_json_tree_distinct_fixture(
      values=[1, 2, 1],
      max_entries=slots,
      max_frames=frames,
    )
    let mut terminal = false
    for _ in 0..<20000 {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(succeeds)
          assert_eq(
            bounded_json_tree_rows(output),
            [1, 2].map(bounded_json_tree_row),
          )
          assert_eq(execution.state.workspace.peak, 15)
          terminal = true
          break
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(succeeds)
          terminal = true
          break
        }
        _ => fail("JSON DISTINCT limit had an unrelated outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(execution.state.comparison.tree is None)
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}
