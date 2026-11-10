///|
fn bounded_set_fixture(
  operation? : String = "except",
  duplicates? : String = "all",
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  right_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  left_rows? : String = "[{\"id\":1},{\"id\":2}]",
  right_rows? : String = "[{\"id\":3}]",
  input_nodes? : Int = 1000,
  max_rows? : Int = 3,
  name_bytes? : Int = 1000,
  output_values? : ValueLimits = run_limits().output_values,
  reserve? : ((Int64) -> Result[Unit, WorkspaceGrowthIssue])? = None,
) -> (
  @bounded.Control,
  Result[BoundedSetExecution, BoundedSetIssue],
  Array[ProducerRead],
) raise {
  let (left_owner, left_output) = bounded_append_source(
    left_rows,
    schema=left_schema,
  )
  let (right_owner, right_output) = bounded_append_source(
    right_rows,
    schema=right_schema,
  )
  let left_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(left_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let right_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(right_owner)),
    @pipeline.Step(0),
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
  let generated = match reserve {
    Some(reserve) =>
      bind_generated_workspace_growth(
        generated,
        {
          rows: { ..run_limits(), operation_entries: max_entries, },
          max_work,
          max_frames: 100,
        },
        1048576L,
        reserve,
        meter_retained_outputs=true,
      ).unwrap()
    None => generated
  }
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
    max_rows,
    {
      max_nodes: input_nodes,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    },
    output_values,
    max_work,
    100,
    max_entries,
    name_bytes,
  )
  (control, execution, [left, right])
}

///|
fn drive_bounded_set(execution : BoundedSetExecution) -> BoundedSetPoll {
  for _ in 0..<100000 {
    match advance_bounded_set(execution, 1) {
      Ok(BoundedSetContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) => return BoundedSetFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedSetFailed(InvalidExecution, progress=0L, work=0L)
}

///|
fn bounded_set_ids(output : CompletedOutput) -> Array[String] {
  Array::makei(completed_row_count(output), row => {
    match completed_cell(output, row, 0) {
      Some(Number(value)) => value.to_string()
      Some(Text(value)) => value
      Some(Null) => "null"
      _ => "?"
    }
  })
}

///|
test "bounded set matches the synchronous survivors for every variant" {
  let left = "[{\"id\":1},{\"id\":1},{\"id\":2},{\"id\":3},{\"id\":1}]"
  let right = "[{\"id\":1},{\"id\":3},{\"id\":4}]"
  for
    case in [
      ("except", "all", ["1", "1", "2"]),
      ("intersect", "all", ["1", "3"]),
      ("except", "distinct", ["2"]),
      ("intersect", "distinct", ["1", "3"]),
    ] {
    let (operation, duplicates, expected) = case
    let (_, started, _) = bounded_set_fixture(
      operation~,
      duplicates~,
      left_rows=left,
      right_rows=right,
      max_rows=10,
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    match drive_bounded_set(execution) {
      BoundedSetComplete(output, ..) =>
        assert_eq(bounded_set_ids(output), expected)
      _ => fail("bounded set did not complete")
    }
    assert_true(cleanup_bounded_set(execution).unwrap())
  }
}

///|
test "bounded set compares long text one byte per advance" {
  let schema = "{\"id\":{\"type\":\"string\",\"nullable\":false}}"
  let long = "x".repeat(200)
  let (_, started, _) = bounded_set_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":\"" + long + "a\"},{\"id\":\"" + long + "b\"}]",
    right_rows="[{\"id\":\"" + long + "b\"}]",
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  let mut previous = 0L
  let mut advances = 0
  let result = while true {
    advances += 1
    match advance_bounded_set(execution, 1).unwrap() {
      BoundedSetContinue(work~, ..) => {
        assert_true(work - previous <= 1L)
        previous = work
      }
      BoundedSetComplete(output, ..) => break bounded_set_ids(output)
      _ => fail("bounded text set did not complete")
    }
  } nobreak {
    []
  }
  assert_eq(result, [long + "a"])
  assert_true(advances > 400)
  assert_true(cleanup_bounded_set(execution).unwrap())
}

///|
test "bounded set admits exact work and rejects one unit short" {
  // Input admission for one left row with one number field (7); field id
  // entry and name bytes (3); one left seed coordinate (1); left merge sort
  // copy, end of copy and result (3); empty right sort (2); one keep flag
  // (1); one output row entry and cell (2).
  let exact_work = 19
  let (_, exact, _) = bounded_set_fixture(
    left_rows="[{\"id\":1}]",
    right_rows="[]",
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_set(exact) {
    BoundedSetComplete(output, ..) => assert_eq(bounded_set_ids(output), ["1"])
    _ => fail("exact set work rejected")
  }
  assert_true(cleanup_bounded_set(exact).unwrap())
  let (_, short, _) = bounded_set_fixture(
    left_rows="[{\"id\":1}]",
    right_rows="[]",
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_set(short) {
    BoundedSetFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short set work accepted")
  }
  assert_true(cleanup_bounded_set(short).unwrap())
}

///|
test "bounded set admits exact structural workspace and rejects one short" {
  // One field uses three metadata slots. Two left and one right rows keep
  // three sort coordinates each, two left keep flags, and one output cell:
  // 3 + 6 + 3 + 2 + 1 = 15 simultaneously live slots.
  let (_, exact, _) = bounded_set_fixture(max_entries=15)
  let exact = exact.unwrap()
  match drive_bounded_set(exact) {
    BoundedSetComplete(output, ..) =>
      assert_eq(bounded_set_ids(output), ["1", "2"])
    _ => fail("exact set workspace rejected")
  }
  assert_true(cleanup_bounded_set(exact).unwrap())
  let (_, short, _) = bounded_set_fixture(max_entries=14)
  let short = short.unwrap()
  match drive_bounded_set(short) {
    BoundedSetFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short set workspace accepted")
  }
  assert_true(cleanup_bounded_set(short).unwrap())
}

///|
test "bounded set stops after positive work without publishing" {
  let (control, started, reads) = bounded_set_fixture(
    left_rows="[{\"id\":3},{\"id\":1},{\"id\":2}]",
    right_rows="[{\"id\":2}]",
  )
  let execution = started.unwrap()
  finish_binary_port_fixture(Set(execution)) |> ignore
  for _ in 0..<15 {
    assert_true(
      advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_set(execution, 1).unwrap() is BoundedSetStopped(_, ..),
  )
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded Set requires exact output funding before commit and preserves accepted rows" {
  // One retained row root, one Number cell and two UTF-16 field-name units:
  // 256 + 256 + 16. Both complete-row operators use this same output owner.
  for operation in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      for ceiling in [528L, 527L] {
        let requests : Array[Int64] = []
        let (_, started, inputs) = bounded_set_fixture(
          operation~,
          duplicates~,
          left_rows="[{\"id\":1}]",
          right_rows=if operation == "intersect" {
            "[{\"id\":1}]"
          } else {
            "[]"
          },
          max_work=10000,
          reserve=Some(bytes => {
            requests.push(bytes)
            if bytes <= ceiling {
              Ok(())
            } else {
              Err(WorkspaceBudgetUnavailable)
            }
          }),
        )
        let execution = started.unwrap()
        match drive_bounded_set(execution) {
          BoundedSetComplete(output, ..) => {
            assert_eq(ceiling, 528L)
            assert_eq(bounded_set_ids(output), ["1"])
            assert_true(execution.accepted.val)
            assert_true(cleanup_bounded_set(execution).unwrap())
            assert_eq(bounded_set_ids(output), ["1"])
          }
          BoundedSetFailed(Capture(CaptureLimit), ..) => {
            assert_eq(ceiling, 527L)
            let output = execution.state.output.unwrap()
            assert_true(output.buffer.rows.is_empty())
            assert_true(output.buffer.presence_rows.is_empty())
            assert_eq(output.buffer.budget.retention_funded, 0L)
            assert_true(cleanup_bounded_set(execution).unwrap())
          }
          _ =>
            fail("Set must preserve the actual before-commit funding outcome")
        }
        assert_false(requests.is_empty())
        assert_eq(requests[requests.length() - 1], 528L)
        assert_true(inputs.all(producer_read_available))
        assert_false(bounded_set_cleanup_pending(execution))
      }
    }
  }
}

///|
test "bounded Set cancellation reclaims funded unpublished output and preserves parents" {
  for operation in ["except", "intersect"] {
    let requests : Array[Int64] = []
    let (control, started, inputs) = bounded_set_fixture(
      operation~,
      left_rows="[{\"id\":1},{\"id\":2},{\"id\":3}]",
      right_rows=if operation == "intersect" {
        "[{\"id\":1},{\"id\":2},{\"id\":3}]"
      } else {
        "[]"
      },
      max_work=10000,
      reserve=Some(bytes => {
        requests.push(bytes)
        Ok(())
      }),
    )
    let execution = started.unwrap()
    finish_binary_port_fixture(Set(execution)) |> ignore
    let output = execution.state.output.unwrap()
    let mut funded = false
    for _ in 0..<10000 {
      assert_true(
        advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
      )
      if output.buffer.rows.length() == 1 {
        funded = true
        break
      }
    }
    assert_true(funded)
    // The existing growth owner reserves a 16 KiB page when available;
    // the row consumes only its independently calculated 528-byte charge.
    assert_eq(requests[requests.length() - 1], 16384L)
    assert_eq(output.buffer.budget.retention_funded, 528L)
    assert_false(execution.accepted.val)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_set(execution, 1).unwrap() is BoundedSetStopped(_, ..),
    )
    for _ in 0..<10000 {
      cleanup_bounded_set(execution).unwrap() |> ignore
      if !bounded_set_cleanup_pending(execution) {
        break
      }
    }
    assert_false(bounded_set_cleanup_pending(execution))
    assert_true(execution.state.output is None)
    assert_true(execution.state.rows.val is None)
    assert_true(output.buffer.rows.is_empty())
    assert_true(output.buffer.presence_rows.is_empty())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(inputs.all(producer_read_available))
  }
}
