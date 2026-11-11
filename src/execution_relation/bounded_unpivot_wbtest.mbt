///|
fn bounded_unpivot_fixture(
  rows : String,
  unused_payload? : Bool = false,
  carried_contract? : String? = None,
  constrain? : (GeneratedSequence) -> GeneratedSequence = generated => generated,
  input_values? : ValueLimits = run_limits().input_values,
  max_rows? : Int = 10,
  max_work? : Int = 10000,
  max_entries? : Int = 100,
  name_bytes? : Int = 10000,
  selected_ceiling? : Int64? = None,
  output_funding? : ((Int64, Int64) -> Result[Unit, WorkspaceGrowthIssue])? = None,
) -> (@bounded.Control, BoundedUnpivotExecution, CompletedOutput) raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan\":{\"type\":\"number\",\"nullable\":true},\"feb\":{\"type\":\"number\",\"nullable\":true}" +
    (if carried_contract is Some(contract) {
      ",\"payload\":" + contract + "}"
    } else if unused_payload {
      ",\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
    } else {
      "}"
    })
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
  )
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let kept = if carried_contract is Some(_) {
    "[\"id\",\"jan\",\"payload\"]"
  } else {
    "[\"id\",\"jan\"]"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"seed\",\"unpivot\":{\"columns\":[\"jan\",\"feb\",\"jan\"],\"keep\":" +
      kept +
      ",\"name_column\":\"metric\",\"value_column\":\"amount\"}}]",
    ),
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
    ["unpivot_0"],
    100000,
    10000,
  ).unwrap()
  let generated = match selected_ceiling {
    Some(ceiling) =>
      constrain_generated_expansion_output(generated, 0, ceiling).unwrap()
    None => generated
  }
  let generated = match output_funding {
    Some(reserve) =>
      bind_generated_workspace_growth(
        generated,
        compute_test_limits(),
        536870912L,
        _ => Ok(()),
        meter_retained_outputs=true,
        reserve_retained=Some(reserve),
      ).unwrap()
    None => generated
  }
  let generated = constrain(generated)
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_unpivot(
    control,
    generated,
    read,
    max_rows,
    input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    name_bytes,
  ).unwrap()
  (control, execution, source)
}

///|
/// Three unpivot_0 scans, three transitions, amount/id/jan/metric,
/// four name pushes and one finish. Logical resource limits are unchanged.
let unpivot_completion_poll_steps : Int = 3 * 9 + 3 + 6 + 2 + 3 + 6 + 4 + 1

///|
test "bounded unpivot enforces the checked expansion ceiling per step" {
  for (ceiling, accepted) in [(3L, true), (2L, false)] {
    let (_, execution, source) = bounded_unpivot_fixture(
      "[{\"id\":1,\"jan\":10,\"feb\":20}]",
      selected_ceiling=Some(ceiling),
    )
    let mut terminal = false
    for _ in 0..<200 {
      if !terminal {
        match advance_bounded_unpivot(execution, 1).unwrap() {
          BoundedUnpivotContinue(..) => ()
          BoundedUnpivotComplete(output, ..) => {
            assert_true(accepted)
            assert_eq(completed_row_count(output), 3)
            terminal = true
          }
          BoundedUnpivotFailed(Rows(RowLimit), ..) => {
            assert_false(accepted)
            terminal = true
          }
          _ => fail("unpivot ended outside its selected output envelope")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_unpivot(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
fn unpivot_unused_payload_rows(count : Int) -> String {
  let numbers = Array::makei(count, index => index.to_string()).join(",")
  "[{\"id\":1,\"jan\":10,\"feb\":20,\"payload\":[" + numbers + "]}]"
}

///|
test "bounded unpivot stops inside an unused nested input value" {
  let (control, execution, source) = bounded_unpivot_fixture(
    unpivot_unused_payload_rows(256),
    unused_payload=true,
    max_work=1000,
    max_entries=1000,
  )
  let mut measuring = false
  for _ in 0..<(50 + unpivot_completion_poll_steps) {
    if !measuring {
      match advance_bounded_unpivot(execution, 1).unwrap() {
        BoundedUnpivotContinue(..) =>
          measuring = bounded_unpivot_measuring_input(execution)
        _ => fail("nested input finished before cancellation")
      }
    }
  }
  assert_true(measuring)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_unpivot(execution, 1).unwrap()
    is BoundedUnpivotStopped(_, ..),
  )
  assert_true(cleanup_bounded_unpivot(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unpivot preserves exact nested input value charges" {
  // Row, three scalar cells, array, and 256 elements: 261 nodes.
  // Four names cost 15 UTF-8 bytes, giving 276 logical work units.
  for
    (nodes, work, accepted) in [
      (261, 276, true),
      (260, 276, false),
      (261, 275, false),
    ] {
    let input_values : ValueLimits = {
      ..run_limits().input_values,
      max_nodes: nodes,
      max_text_bytes: 15,
      max_work: work,
    }
    let (_, execution, source) = bounded_unpivot_fixture(
      unpivot_unused_payload_rows(256),
      unused_payload=true,
      input_values~,
      max_work=1000,
      max_entries=1000,
    )
    let mut terminal = false
    for _ in 0..<1000 {
      if !terminal {
        match advance_bounded_unpivot(execution, 1).unwrap() {
          BoundedUnpivotContinue(..) => ()
          BoundedUnpivotComplete(output, ..) => {
            assert_true(accepted)
            assert_eq(completed_row_count(output), 3)
            terminal = true
          }
          BoundedUnpivotFailed(InputLimit, ..) => {
            assert_false(accepted)
            terminal = true
          }
          _ => fail("nested unpivot ended with another result")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_unpivot(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded unpivot preserves repeated columns and ordered occurrences" {
  let (_, execution, source) = bounded_unpivot_fixture(
    "[{\"id\":1,\"jan\":10,\"feb\":null},{\"id\":2,\"jan\":null,\"feb\":20}]",
  )
  let mut completed : CompletedOutput? = None
  let mut previous_work = 0L
  for _ in 0..<200 {
    if completed is None {
      match advance_bounded_unpivot(execution, 1).unwrap() {
        BoundedUnpivotContinue(work=next, ..) => {
          assert_true(next - previous_work <= 1L)
          previous_work = next
        }
        BoundedUnpivotComplete(output, work=next, ..) => {
          assert_true(next - previous_work <= 1L)
          completed = Some(output)
        }
        _ => fail("bounded unpivot did not complete")
      }
    }
  }
  guard completed is Some(output) else {
    fail("bounded unpivot did not finish")
  }
  assert_eq(completed_row_count(output), 6)
  assert_true(completed_cell(output, 0, 0) is Some(Number(10)))
  assert_true(completed_cell(output, 0, 3) is Some(Text("jan")))
  assert_true(completed_cell(output, 1, 0) is Some(Null))
  assert_true(completed_cell(output, 1, 3) is Some(Text("feb")))
  assert_true(completed_cell(output, 2, 3) is Some(Text("jan")))
  assert_true(completed_cell(output, 4, 0) is Some(Number(20)))
  assert_true(completed_output_available(source))
  assert_true(cleanup_bounded_unpivot(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unpivot cancels after output work without partial completion" {
  let (control, execution, source) = bounded_unpivot_fixture(
    "[{\"id\":1,\"jan\":10,\"feb\":20},{\"id\":2,\"jan\":30,\"feb\":40}]",
  )
  let mut emitted = false
  for _ in 0..<100 {
    if !emitted {
      match advance_bounded_unpivot(execution, 1).unwrap() {
        BoundedUnpivotContinue(progress~, ..) =>
          if progress > 0L {
            emitted = true
          }
        _ => fail("unpivot ended before cancellation")
      }
    }
  }
  assert_true(emitted)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_unpivot(execution, 1).unwrap()
    is BoundedUnpivotStopped(_, ..),
  )
  assert_true(cleanup_bounded_unpivot(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unpivot admits exact empty metadata and rejects one short" {
  // Three input names and ordinals (6), three column labels and ordinals
  // (6), two kept ordinals (2), and four output columns (4) coexist.
  let (_, exact, _) = bounded_unpivot_fixture("[]", max_rows=0, max_entries=18)
  let mut completed = false
  for _ in 0..<(60 + unpivot_completion_poll_steps) {
    if !completed {
      match advance_bounded_unpivot(exact, 1).unwrap() {
        BoundedUnpivotContinue(..) => ()
        BoundedUnpivotComplete(output, ..) => {
          assert_eq(completed_row_count(output), 0)
          completed = true
        }
        _ => fail("exact unpivot metadata was rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_unpivot(exact).unwrap())
  let (_, one_short, _) = bounded_unpivot_fixture(
    "[]",
    max_rows=0,
    max_entries=17,
  )
  let mut failed = false
  for _ in 0..<(60 + unpivot_completion_poll_steps) {
    if !failed {
      match advance_bounded_unpivot(one_short, 1).unwrap() {
        BoundedUnpivotContinue(..) => ()
        BoundedUnpivotFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short unpivot metadata was accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unpivot(one_short).unwrap())
}

///|
test "bounded unpivot admits exact empty control work and rejects one short" {
  // Input fields cost 3 + 8 name bytes, columns 3 + 9, kept fields 2 + 5,
  // and output names 17 bytes: 11 + 12 + 7 + 17 = 47.
  let (_, exact, _) = bounded_unpivot_fixture("[]", max_rows=0, max_work=47)
  let mut completed = false
  for _ in 0..<(60 + unpivot_completion_poll_steps) {
    if !completed {
      match advance_bounded_unpivot(exact, 1).unwrap() {
        BoundedUnpivotContinue(..) => ()
        BoundedUnpivotComplete(_, ..) => completed = true
        _ => fail("exact unpivot control work was rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_unpivot(exact).unwrap())
  let (_, one_short, _) = bounded_unpivot_fixture("[]", max_rows=0, max_work=46)
  let mut failed = false
  for _ in 0..<(60 + unpivot_completion_poll_steps) {
    if !failed {
      match advance_bounded_unpivot(one_short, 1).unwrap() {
        BoundedUnpivotContinue(..) => ()
        BoundedUnpivotFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short unpivot control work was accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unpivot(one_short).unwrap())
}

///|
test "bounded unpivot admits exact nonempty work and workspace" {
  // Metadata costs 47 control units and 18 live slots. One input row,
  // three authored column occurrences, and twelve output cells add
  // 1 + 3 + 12 control units. One four-cell row overlaps metadata.
  for
    (work, entries, success) in [
      (63, 22, true),
      (62, 22, false),
      (63, 21, false),
    ] {
    let (_, execution, source) = bounded_unpivot_fixture(
      "[{\"id\":1,\"jan\":10,\"feb\":20}]",
      max_rows=3,
      max_work=work,
      max_entries=entries,
    )
    let mut accepted = false
    let mut terminal = false
    for _ in 0..<120 {
      if !terminal {
        match advance_bounded_unpivot(execution, 1).unwrap() {
          BoundedUnpivotContinue(..) => ()
          BoundedUnpivotComplete(output, ..) => {
            assert_eq(completed_row_count(output), 3)
            accepted = true
            terminal = true
          }
          BoundedUnpivotFailed(Rows(RowLimit), ..) => terminal = true
          _ => fail("unexpected unpivot resource result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(accepted, success)
    assert_true(cleanup_bounded_unpivot(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded unpivot enforces the output row ceiling incrementally" {
  let (_, execution, source) = bounded_unpivot_fixture(
    "[{\"id\":1,\"jan\":10,\"feb\":20}]",
    max_rows=2,
  )
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_unpivot(execution, 1).unwrap() {
        BoundedUnpivotContinue(..) => ()
        BoundedUnpivotFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("unpivot output ceiling was not enforced")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unpivot(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "unpivot funds original labelled rows before transfer and preserves refusal or close custody" {
  for (refuse, close) in [(false, false), (true, false), (false, true)] {
    let calls = Ref(0)
    let before_transfer = Ref(true)
    let active : Ref[BoundedUnpivotExecution?] = Ref(None)
    let (_, execution, source) = bounded_unpivot_fixture(
      "[{\"id\":1,\"jan\":10,\"feb\":20}]",
      output_funding=Some((retained, execution) => {
        calls.val += 1
        before_transfer.val = before_transfer.val &&
          retained > 0L &&
          execution >= retained &&
          active.val
          .map(value => {
            value.state.checked_row.length() == 4 &&
            value.state.output
            .map(output => {
              output.buffer.rows.length() == value.state.emitted &&
              output.buffer.budget.nodes > 0
            })
            .unwrap_or(false)
          })
          .unwrap_or(false)
        if close {
          active.val
          .bind(value => value.state.output)
          .map(output => cancel_admitted_output(output) |> ignore)
          |> ignore
        }
        if refuse {
          Err(WorkspaceBudgetUnavailable)
        } else {
          Ok(())
        }
      }),
    )
    active.val = Some(execution)
    let mut done = false
    let mut accepted = None
    for _ in 0..<2000 {
      if !done {
        match advance_bounded_unpivot(execution, 1).unwrap() {
          BoundedUnpivotContinue(..) => ()
          BoundedUnpivotComplete(output, ..) => {
            assert_false(refuse || close)
            assert_eq(completed_row_count(output), 3)
            assert_true(completed_cell(output, 0, 0) is Some(Number(10)))
            assert_true(completed_cell(output, 0, 3) is Some(Text("jan")))
            assert_true(completed_cell(output, 1, 3) is Some(Text("feb")))
            assert_true(completed_cell(output, 2, 3) is Some(Text("jan")))
            accepted = Some(output)
            done = true
          }
          BoundedUnpivotFailed(Capture(CaptureLimit), ..) => {
            assert_true(refuse || close)
            assert_true(execution.state.rows.val is None)
            done = true
          }
          _ => fail("unpivot lost its original output funding outcome")
        }
      }
    }
    assert_true(done && calls.val > 0 && before_transfer.val)
    assert_true(cleanup_bounded_unpivot(execution).unwrap())
    if accepted is Some(output) {
      assert_true(completed_output_available(output))
    }
    assert_true(completed_output_available(source))
  }
}

///|
fn unpivot_fixture_column(schema : @schema.Schema, name : String) -> Int {
  for column in 0..<@schema.field_count(schema) {
    if @schema.reference_name(@schema.field_at(schema, column).unwrap().name) ==
      name {
      return column
    }
  }
  -1
}

///|
test "unpivot borrows original text array and object backing through funded transfer and cleanup" {
  for
    (contract, payload) in [
      (
        "{\"type\":\"string\",\"nullable\":false}",
        "\"" + "λ".repeat(80) + "\"",
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2,3]",
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}",
        "{\"x\":[1,2]}",
      ),
    ] {
    for (refuse, close) in [(false, false), (true, false), (false, true)] {
      let calls = Ref(0)
      let before_transfer = Ref(true)
      let active : Ref[BoundedUnpivotExecution?] = Ref(None)
      let (_, execution, source) = bounded_unpivot_fixture(
        "[{\"id\":1,\"jan\":10,\"feb\":20,\"payload\":" + payload + "}]",
        carried_contract=Some(contract),
        max_entries=1000,
        output_funding=Some((retained, execution) => {
          calls.val += 1
          before_transfer.val = before_transfer.val &&
            retained > 0L &&
            execution >= retained &&
            active.val
            .map(value => {
              value.state.checked_row.length() == 5 &&
              value.state.output
              .map(output => {
                output.buffer.rows.length() == value.state.emitted &&
                output.buffer.budget.nodes > 0
              })
              .unwrap_or(false)
            })
            .unwrap_or(false)
          if close {
            active.val
            .bind(value => value.state.output)
            .map(output => cancel_admitted_output(output) |> ignore)
            |> ignore
          }
          if refuse {
            Err(WorkspaceBudgetUnavailable)
          } else {
            Ok(())
          }
        }),
      )
      active.val = Some(execution)
      let source_column = unpivot_fixture_column(
        unpivot_input_schema(execution.state.input),
        "payload",
      )
      let output_column = unpivot_fixture_column(
        execution.state.output_schema,
        "payload",
      )
      let label_column = unpivot_fixture_column(
        execution.state.output_schema,
        "metric",
      )
      assert_true(source_column >= 0 && output_column >= 0 && label_column >= 0)
      let original = unpivot_input_cell(execution.state.input, 0, source_column).unwrap()
      let mut accepted = None
      let mut done = false
      for _ in 0..<10000 {
        if !done {
          match advance_bounded_unpivot(execution, 1).unwrap() {
            BoundedUnpivotContinue(..) => ()
            BoundedUnpivotComplete(output, ..) => {
              assert_false(refuse || close)
              assert_eq(completed_row_count(output), 3)
              for row in 0..<3 {
                match
                  (
                    original,
                    completed_cell(output, row, output_column).unwrap(),
                  ) {
                  (Text(left), Text(right)) => assert_eq(left, right)
                  (Captured(left), Captured(right)) =>
                    assert_true(physical_equal(left, right))
                  _ => fail("unpivot reconstructed its original carried cell")
                }
                assert_true(
                  completed_cell(output, row, label_column) is Some(Text(label)) &&
                  label == (if row == 1 { "feb" } else { "jan" }),
                )
              }
              accepted = Some(output)
              done = true
            }
            BoundedUnpivotFailed(Capture(CaptureLimit), ..) => {
              assert_true(refuse || close)
              assert_true(execution.state.rows.val is None)
              done = true
            }
            _ => fail("borrowed unpivot lost its original transfer outcome")
          }
        }
      }
      assert_true(done && calls.val > 0 && before_transfer.val)
      assert_true(cleanup_bounded_unpivot(execution).unwrap())
      if accepted is Some(output) {
        assert_true(completed_output_available(output))
        match (original, completed_cell(output, 0, output_column).unwrap()) {
          (Text(left), Text(right)) => assert_eq(left, right)
          (Captured(left), Captured(right)) =>
            assert_true(physical_equal(left, right))
          _ => fail("cleanup lost its accepted original backing")
        }
      }
      assert_true(completed_output_available(source))
    }
  }
}
