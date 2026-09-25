///|
fn bounded_watermark_fixture(
  rows : String,
  threshold : String,
  policy : String,
  max_work? : Int = 100000,
  max_entries? : Int = 1000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"time\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
  )
  let source = completed_output(
    execute_generated_sequence(
      prepare_generated_sequence(
        registered_relation_contracts(),
        prepared_sequence(source_owner),
        [],
        ["values_0"],
        100000,
        10000,
      ).unwrap(),
      [],
      compute_test_limits(),
    ).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"seed\",\"watermark_rows\":{\"time\":\"time\",\"late_policy\":\"" +
      policy +
      "\"," +
      threshold +
      "}}]",
    ),
    [("seed", @pipeline.ProducedInput(producer))],
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
      max_work: 10000,
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
    ["watermark_0"],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows(
    control,
    generated,
    read,
    100,
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, active, read)
}

///|
test "bounded watermark preserves fixed and prefix decisions" {
  let rows = "[{\"id\":1,\"time\":100},{\"id\":2,\"time\":80},{\"id\":3,\"time\":95}]"
  for
    (threshold, policy, ids, late) in [
      ("\"watermark_ms\":90", "mark", [1.0, 2.0, 3.0], [false, true, false]),
      ("\"max_skew\":10", "drop", [1.0, 3.0], [false, false]),
    ] {
    let (_, active, read) = bounded_watermark_fixture(rows, threshold, policy)
    let mut completed : CompletedOutput? = None
    for _ in 0..<1000 {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          completed = Some(output)
          break
        }
        BoundedBindingRowsFailed(_, ..) => fail("bounded watermark failed")
        BoundedBindingRowsStopped(_, ..) => fail("bounded watermark stopped")
      }
    }
    guard completed is Some(output) else { fail("watermark did not complete") }
    assert_eq(completed_row_count(output), ids.length())
    for index in 0..<ids.length() {
      assert_true(
        completed_cell(output, index, 0) is Some(Number(id)) && id == ids[index],
      )
      assert_true(completed_cell(output, index, 4) is Some(Number(90.0)))
      assert_true(
        completed_cell(output, index, 3) is Some(Boolean(flag)) &&
        flag == late[index],
      )
      assert_true(
        completed_cell(output, index, 2) is Some(Text(decision)) &&
        decision == (if late[index] { "mark" } else { "keep" }),
      )
    }
    assert_true(producer_read_available(read))
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
  }
}

///|
fn bounded_watermark_reaches_terminal(
  threshold : String,
  policy : String,
  max_work : Int,
  max_entries : Int,
) -> Bool raise {
  let (_, active, read) = bounded_watermark_fixture(
    "[{\"id\":1,\"time\":100},{\"id\":2,\"time\":80}," +
    "{\"id\":3,\"time\":95}]",
    threshold,
    policy,
    max_work~,
    max_entries~,
  )
  let mut succeeded = false
  let mut terminal = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(active, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(_, ..) => {
        succeeded = true
        terminal = true
        break
      }
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        terminal = true
        break
      }
      _ => fail("unexpected watermark boundary result")
    }
  }
  assert_true(terminal)
  assert_true(producer_read_available(read))
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  succeeded
}

///|
test "bounded watermark admits exact work and workspace limits" {
  for
    (threshold, policy, exact_work) in [
      ("\"watermark_ms\":90", "mark", 162),
      ("\"max_skew\":10", "drop", 111),
    ] {
    assert_true(
      bounded_watermark_reaches_terminal(threshold, policy, exact_work, 27),
    )
    assert_false(
      bounded_watermark_reaches_terminal(threshold, policy, exact_work - 1, 27),
    )
    assert_false(
      bounded_watermark_reaches_terminal(threshold, policy, exact_work, 26),
    )
  }
}

///|
test "bounded watermark stops after output work without completion" {
  let (control, active, read) = bounded_watermark_fixture(
    "[{\"id\":1,\"time\":100},{\"id\":2,\"time\":80},{\"id\":3,\"time\":95}]", "\"watermark_ms\":90",
    "mark",
  )
  let mut emitted = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(active, 1).unwrap() {
      BoundedBindingRowsContinue(progress~, ..) =>
        if progress > 0L {
          emitted = true
          break
        }
      _ => fail("watermark finished before cancellation")
    }
  }
  assert_true(emitted)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(active, 1)
    is Ok(BoundedBindingRowsStopped(_, ..)),
  )
  assert_true(producer_read_available(read))
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
}
