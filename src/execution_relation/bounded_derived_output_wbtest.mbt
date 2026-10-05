///|
fn derived_output_limits(presence : Bool) -> ValueLimits {
  // The existing expression fixture admits 1,000 bytes per row value;
  // two 400-byte copies stay within it while spanning multiple scan chunks.
  // Dense row: seven cells, outer object, 25 name bytes, two 400-byte texts.
  // Presence row: id, absent p (one presence node at depth two), z, outer object,
  // four name bytes and the 400-byte text. NULL is not substituted for p.
  let (nodes, bytes) = if presence { (4, 404) } else { (8, 825) }
  {
    max_nodes: nodes,
    max_text_bytes: bytes,
    max_depth: 2,
    max_work: nodes + bytes,
  }
}

///|
fn derived_output_fixture(
  presence : Bool,
  limits : ValueLimits,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  if presence {
    return presence_filter_fixture(
      operations=Some("[{\"derive\":{\"z\":\"'" + "x".repeat(400) + "'\"}}]"),
      wires=Some(["{\"id\":1}"]),
      output_limits=limits,
    )
  }
  let (source_owner, source) = temporal_output_source(
    "[{\"id\":1,\"key\":1,\"clock\":1,\"start\":0,\"end\":5,\"tag\":\"" +
    "x".repeat(400) +
    "\"}]",
  )
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"source\",\"derive\":{\"copy\":\"tag\"}}]"),
    [("source", @pipeline.ProducedInput(producer))],
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
  let owner = @lower.bind_parameters(
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
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 1L)],
    ["derive_0"],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows(
    control,
    generated,
    input,
    1,
    run_limits().input_values,
    limits,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, active, input)
}

///|
fn assert_derived_output(
  output : CompletedOutput,
  presence : Bool,
) -> Unit raise {
  let names = if presence {
    ["id", "p", "z"]
  } else {
    ["clock", "copy", "end", "id", "key", "start", "tag"]
  }
  assert_eq(completed_row_count(output), 1)
  assert_eq(completed_column_count(output), names.length())
  for index, name in names {
    assert_eq(completed_column_name(output, index), Some(name))
    if name == "p" {
      assert_true(completed_presence_cell(output, 0, index) is Ok(Absent))
    } else if name == "z" || name == "copy" || name == "tag" {
      if presence {
        assert_true(
          completed_presence_cell(output, 0, index)
          is Ok(Present(@admitted.Text(text))) &&
          text == "x".repeat(400),
        )
      } else {
        assert_true(
          completed_cell(output, 0, index) is Some(Text(text)) &&
          text == "x".repeat(400),
        )
      }
    } else {
      let expected = if name == "end" {
        5.0
      } else if name == "start" {
        0.0
      } else {
        1.0
      }
      if presence {
        assert_true(
          completed_presence_cell(output, 0, index)
          is Ok(Present(@admitted.Number(number))) &&
          number == expected,
        )
      } else {
        assert_true(
          completed_cell(output, 0, index) is Some(Number(number)) &&
          number == expected,
        )
      }
    }
  }
}

///|
test "derived output recheck yields before dense and presence row publication" {
  for presence in [false, true] {
    let (control, active, input) = derived_output_fixture(
      presence,
      derived_output_limits(presence),
    )
    let mut reached = false
    for _ in 0..<30000 {
      assert_true(
        advance_bounded_binding_rows(active, 1).unwrap()
        is BoundedBindingRowsContinue(..),
      )
      if active.state.output_recheck is Some(_) {
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_true(
      advance_bounded_binding_rows(active, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    assert_true(active.state.output_recheck is Some(_))
    assert_true(producer_read_available(input))
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_binding_rows(active, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(active.state.output_recheck is None)
    assert_eq(active.state.workspace.live, 0)
    assert_true(active.state.rows.val is None)
    assert_true(producer_read_available(input))
  }
}

///|
test "derived output keeps literal exact and one-short occurrence budgets" {
  for presence in [false, true] {
    for short in -1..<3 {
      let exact = derived_output_limits(presence)
      let limits = {
        max_nodes: exact.max_nodes - (if short == 0 { 1 } else { 0 }),
        max_text_bytes: exact.max_text_bytes - (if short == 1 { 1 } else { 0 }),
        max_depth: exact.max_depth,
        max_work: exact.max_work - (if short == 2 { 1 } else { 0 }),
      }
      let (_, active, input) = derived_output_fixture(presence, limits)
      let mut terminal = false
      for _ in 0..<30000 {
        match advance_bounded_binding_rows(active, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(output, ..) => {
            assert_eq(short, -1)
            assert_derived_output(output, presence)
            terminal = true
            break
          }
          BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
            assert_true(short >= 0)
            terminal = true
            break
          }
          BoundedBindingRowsFailed(Capture(CaptureLimit), ..) =>
            fail("capture limit: presence=\{presence}, short=\{short}")
          BoundedBindingRowsFailed(InvalidExecution, ..) =>
            fail("invalid execution: presence=\{presence}, short=\{short}")
          BoundedBindingRowsFailed(
            Capture(ForeignCheckedValue(row, column)),
            ..
          ) =>
            fail(
              "foreign value: presence=\{presence}, short=\{short}, row=\{row}, column=\{column}",
            )
          _ =>
            fail(
              "unexpected derived output budget failure: presence=\{presence}, short=\{short}",
            )
        }
      }
      assert_true(terminal)
      assert_true(cleanup_bounded_binding_rows(active).unwrap())
      assert_eq(active.state.workspace.live, 0)
      assert_true(active.state.output_recheck is None)
      assert_true(producer_read_available(input))
    }
  }
}
