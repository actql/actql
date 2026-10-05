///|
priv enum ExpansionOutputFixture {
  Values(BoundedValuesExecution)
  Unpivot(BoundedUnpivotExecution)
  Unnest(BoundedUnnestExecution)
  Window(BoundedRowWindowExecution)
}

///|
priv enum ExpansionOutputPoll {
  Continue
  Complete(CompletedOutput)
  Stopped
  OutputLimit
  WorkspaceLimit
}

///|
fn expansion_output_fixture(
  kind : Int,
  output_values : ValueLimits,
  max_entries? : Int = 100,
  input_values? : ValueLimits = run_limits().input_values,
) -> (@bounded.Control, ExpansionOutputFixture, CompletedOutput?) raise {
  let text = "x".repeat(4096)
  let schema = if kind == 1 {
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}}"
  } else if kind == 2 {
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false},\"max_items\":1},\"tag\":{\"type\":\"string\",\"nullable\":false}}"
  } else if kind == 3 {
    "{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}}"
  } else {
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}}"
  }
  let extra = if kind == 1 {
    ",\"jan\":2"
  } else if kind == 2 {
    ",\"items\":[2]"
  } else if kind == 3 {
    ",\"at\":5"
  } else {
    ""
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":1,\"tag\":\"" +
    text +
    "\"" +
    extra +
    "}]},\"as\":\"seed\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let control = @bounded.control()
  if kind == 0 {
    return (
      control,
      Values(
        start_bounded_values(
          control, generated, 1, input_values, output_values, 100000, 100, max_entries,
          10000,
        ).unwrap(),
      ),
      None,
    )
  }
  let source = completed_output(
    execute_generated_sequence(generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let operation = if kind == 1 {
    "\"unpivot\":{\"columns\":[\"jan\"],\"keep\":[\"id\",\"tag\"],\"name_column\":\"metric\",\"value_column\":\"amount\"}"
  } else if kind == 2 {
    "\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":\"position\",\"outer\":true}"
  } else {
    "\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"seed\"," + operation + "}]"),
    [("seed", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
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
      max_work: 100000,
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
    [
      if kind == 1 {
        "unpivot_0"
      } else if kind == 2 {
        "unnest_0"
      } else {
        "window_0"
      },
    ],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let execution = if kind == 1 {
    Unpivot(
      start_bounded_unpivot(
        control,
        generated,
        read,
        1,
        run_limits().input_values,
        output_values,
        100000,
        100,
        max_entries,
        10000,
      ).unwrap(),
    )
  } else if kind == 2 {
    Unnest(
      start_bounded_unnest(
        control,
        generated,
        read,
        1,
        run_limits().input_values,
        output_values,
        100000,
        100,
        max_entries,
        10000,
      ).unwrap(),
    )
  } else {
    Window(
      start_bounded_row_window(
        control,
        generated,
        read,
        1,
        run_limits().input_values,
        output_values,
        100000,
        100,
        max_entries,
        10000,
      ).unwrap(),
    )
  }
  (control, execution, Some(source))
}

///|
fn expansion_output_limits(kind : Int) -> ValueLimits {
  // Hand-derived nodes and UTF-8 occurrences, including outer row and names.
  // Unpivot: four scalar cells plus the "jan" label.
  // Unnest: five cells, with the retained items array and its child.
  // Window: five scalar cells and the two default window boundary names.
  let (nodes, bytes, depth) = match kind {
    0 => (3, 4101, 2)
    1 => (5, 4116, 2)
    2 => (7, 4118, 3)
    _ => (6, 4125, 2)
  }
  {
    max_nodes: nodes,
    max_text_bytes: bytes,
    max_depth: depth,
    max_work: nodes + bytes,
  }
}

///|
fn advance_expansion_output(
  value : ExpansionOutputFixture,
) -> ExpansionOutputPoll raise {
  match value {
    Values(value) =>
      match advance_bounded_values(value, 1).unwrap() {
        BoundedValuesContinue(..) => Continue
        BoundedValuesComplete(output, ..) => Complete(output)
        BoundedValuesStopped(_, ..) => Stopped
        BoundedValuesFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedValuesFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("values failed outside the output boundary")
      }
    Unpivot(value) =>
      match advance_bounded_unpivot(value, 1).unwrap() {
        BoundedUnpivotContinue(..) => Continue
        BoundedUnpivotComplete(output, ..) => Complete(output)
        BoundedUnpivotStopped(_, ..) => Stopped
        BoundedUnpivotFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedUnpivotFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("unpivot failed outside the output boundary")
      }
    Unnest(value) =>
      match advance_bounded_unnest(value, 1).unwrap() {
        BoundedUnnestContinue(..) => Continue
        BoundedUnnestComplete(output, ..) => Complete(output)
        BoundedUnnestStopped(_, ..) => Stopped
        BoundedUnnestFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedUnnestFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("unnest failed outside the output boundary")
      }
    Window(value) =>
      match advance_bounded_row_window(value, 1).unwrap() {
        BoundedRowWindowContinue(..) => Continue
        BoundedRowWindowComplete(output, ..) => Complete(output)
        BoundedRowWindowStopped(_, ..) => Stopped
        BoundedRowWindowFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedRowWindowFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("row_window failed outside the output boundary")
      }
  }
}

///|
fn expansion_output_inside(
  value : ExpansionOutputFixture,
  charging : Bool,
) -> Bool {
  match value {
    Values(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
    Unpivot(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
    Unnest(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
    Window(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
  }
}

///|
fn cleanup_expansion_output(value : ExpansionOutputFixture) -> Unit raise {
  match value {
    Values(value) => {
      assert_true(cleanup_bounded_values(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
    Unpivot(value) => {
      assert_true(cleanup_bounded_unpivot(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
    Unnest(value) => {
      assert_true(cleanup_bounded_unnest(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
    Window(value) => {
      assert_true(cleanup_bounded_row_window(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
  }
}

///|
test "expansion output stops inside recheck and charge without releasing inputs" {
  for kind in 0..<4 {
    for charging in [false, true] {
      let (control, active, source) = expansion_output_fixture(
        kind,
        expansion_output_limits(kind),
      )
      let mut reached = false
      for _ in 0..<30000 {
        assert_true(advance_expansion_output(active) is Continue)
        if expansion_output_inside(active, charging) {
          reached = true
          break
        }
      }
      assert_true(reached)
      if source is Some(source) {
        assert_eq(completed_row_count(source), 1)
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(advance_expansion_output(active) is Stopped)
      cleanup_expansion_output(active)
      if source is Some(source) {
        assert_eq(completed_row_count(source), 1)
      }
    }
  }
}

///|
test "expansion output keeps exact node byte and work limits" {
  for kind in 0..<4 {
    for short in -1..<3 {
      let exact = expansion_output_limits(kind)
      let limits = {
        max_nodes: exact.max_nodes - (if short == 0 { 1 } else { 0 }),
        max_text_bytes: exact.max_text_bytes - (if short == 1 { 1 } else { 0 }),
        max_depth: exact.max_depth,
        max_work: exact.max_work - (if short == 2 { 1 } else { 0 }),
      }
      let (_, active, _) = expansion_output_fixture(kind, limits)
      let mut terminal = false
      for _ in 0..<30000 {
        match advance_expansion_output(active) {
          Continue => ()
          Complete(output) => {
            assert_eq(short, -1)
            assert_eq(completed_row_count(output), 1)
            let expected_names = match kind {
              0 => ["id", "tag"]
              1 => ["amount", "id", "metric", "tag"]
              2 => ["id", "item", "items", "position", "tag"]
              _ => ["at", "id", "tag", "window_end", "window_start"]
            }
            assert_eq(completed_column_count(output), expected_names.length())
            let mut saw_tag = false
            for index in 0..<completed_column_count(output) {
              let name = completed_column_name(output, index).unwrap()
              assert_eq(name, expected_names[index])
              let cell = completed_cell(output, 0, index)
              if name == "tag" {
                assert_true(
                  cell is Some(Text(text)) && text == "x".repeat(4096),
                )
                saw_tag = true
              } else if name == "id" {
                assert_true(cell is Some(Number(1.0)))
              } else if name == "amount" || name == "item" {
                assert_true(cell is Some(Number(2.0)))
              } else if name == "metric" {
                assert_true(cell is Some(Text("jan")))
              } else if name == "position" || name == "window_start" {
                assert_true(cell is Some(Number(0.0)))
              } else if name == "at" {
                assert_true(cell is Some(Number(5.0)))
              } else if name == "window_end" {
                assert_true(cell is Some(Number(10.0)))
              } else if name == "items" {
                assert_true(
                  cell is Some(Captured(@admitted.Array(items))) &&
                  @admitted.element_count(items) == 1 &&
                  @admitted.element_at(items, 0) is Some(@admitted.Number(2.0)),
                )
              }
            }
            assert_true(saw_tag)
            terminal = true
            break
          }
          OutputLimit => {
            assert_true(short >= 0)
            terminal = true
            break
          }
          _ => fail("unexpected output limit cause")
        }
      }
      assert_true(terminal)
      cleanup_expansion_output(active)
    }
  }
}

///|
test "Values input measurement stops and preserves exact logical charges" {
  let (control, active, _) = expansion_output_fixture(
    0,
    expansion_output_limits(0),
  )
  let mut reached = false
  for _ in 0..<100 {
    assert_true(advance_expansion_output(active) is Continue)
    if active is Values(value) && value.state.input_measure is Some(_) {
      reached = true
      break
    }
  }
  assert_true(reached)
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_expansion_output(active) is Stopped)
  cleanup_expansion_output(active)
  if active is Values(value) {
    assert_true(value.state.input_measure is None)
    assert_true(value.state.pending_input is None)
  }
  for short in -1..<3 {
    let exact = expansion_output_limits(0)
    let input_values = {
      max_nodes: exact.max_nodes - (if short == 0 { 1 } else { 0 }),
      max_text_bytes: exact.max_text_bytes - (if short == 1 { 1 } else { 0 }),
      max_depth: exact.max_depth,
      max_work: exact.max_work - (if short == 2 { 1 } else { 0 }),
    }
    let (_, active, _) = expansion_output_fixture(0, exact, input_values~)
    guard active is Values(value) else { fail("expected Values owner") }
    let mut terminal = false
    for _ in 0..<30000 {
      match advance_bounded_values(value, 1).unwrap() {
        BoundedValuesContinue(..) => ()
        BoundedValuesComplete(_, ..) => {
          assert_eq(short, -1)
          terminal = true
          break
        }
        BoundedValuesFailed(InputLimit, ..) => {
          assert_true(short >= 0)
          terminal = true
          break
        }
        _ => fail("unexpected Values input limit cause")
      }
    }
    assert_true(terminal)
    cleanup_expansion_output(active)
  }
}

///|
test "expansion output reserves traversal frames before one-short workspace" {
  // Values: row 2 + cells 2 + frame 1.
  // Unpivot: input 6 + labels 2 + keeps 2 + output ordinals 4 + cells 4 + frame 1.
  // Unnest: input 6 + output ordinals 5 + cells 5 + frame 1.
  // Window: input 6 + output ordinals 5 + membership 1 + cells 5 + frame 1.
  for (kind, slots) in [(0, 5), (1, 19), (2, 17), (3, 18)] {
    for short in [false, true] {
      let (_, active, _) = expansion_output_fixture(
        kind,
        expansion_output_limits(kind),
        max_entries=slots - (if short { 1 } else { 0 }),
      )
      let mut terminal = false
      for _ in 0..<30000 {
        match advance_expansion_output(active) {
          Continue => ()
          Complete(_) => {
            assert_false(short)
            terminal = true
            break
          }
          WorkspaceLimit => {
            assert_true(short)
            terminal = true
            break
          }
          _ => fail("unexpected workspace limit cause")
        }
      }
      assert_true(terminal)
      cleanup_expansion_output(active)
    }
  }
}
