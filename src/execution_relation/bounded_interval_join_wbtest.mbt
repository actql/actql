///|
fn bounded_interval_source(
  rows : String,
  text_key? : Bool = false,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let key_type = if text_key { "string" } else { "number" }
  let schema = "{\"key\":{\"type\":\"" +
    key_type +
    "\",\"nullable\":true}," +
    "\"start\":{\"type\":\"number\",\"nullable\":false}," +
    "\"end\":{\"type\":\"number\",\"nullable\":false}," +
    "\"time\":{\"type\":\"number\",\"nullable\":false}," +
    "\"value\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    rows +
    "},\"as\":\"source\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let complete = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(complete, @pipeline.Step(0)).unwrap())
}

///|
fn bounded_interval_fixture_result(
  max_work : Int,
  max_entries? : Int = 10000,
  text_key? : Bool = false,
) -> Result[
  (@bounded.Control, BoundedIntervalJoinExecution, Array[ProducerRead]),
  BoundedIntervalJoinIssue,
] raise {
  let key = fn(value : Int) {
    if text_key {
      "\"" + String::make(256, 'g') + value.to_string() + "\""
    } else {
      value.to_string()
    }
  }
  let (left_owner, left_output) = bounded_interval_source(
    "[{\"key\":" +
    key(1) +
    ",\"start\":0,\"end\":5,\"time\":2,\"value\":10}," +
    "{\"key\":" +
    key(2) +
    ",\"start\":5,\"end\":8,\"time\":7,\"value\":11}]",
    text_key~,
  )
  let (right_owner, right_output) = bounded_interval_source(
    "[{\"key\":" +
    key(1) +
    ",\"start\":0,\"end\":3,\"time\":1,\"value\":20}," +
    "{\"key\":" +
    key(1) +
    ",\"start\":2,\"end\":4,\"time\":2,\"value\":21}]",
    text_key~,
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
      "[{\"from\":\"l\",\"interval_join\":{\"with\":\"r\"," +
      "\"kind\":\"left\",\"mode\":\"point_in_interval\"," +
      "\"on\":[{\"left\":\"key\",\"right\":\"key\"}]," +
      "\"left\":{\"time\":\"time\"}," +
      "\"right\":{\"start\":\"start\",\"end\":\"end\"}," +
      "\"select\":{\"left_value\":\"left.value\"," +
      "\"right_value\":\"right.value\"}}}]",
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
    ["interval_join_0"],
    100000,
    10000,
  ).unwrap()
  let generated = constrain_generated_interval_search(generated, 0, 4L).unwrap()
  let generated = constrain_generated_join_output(generated, 0, 3L).unwrap()
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
  let execution = match
    start_bounded_interval_join(
      control,
      generated,
      left,
      right,
      10,
      run_limits().output_values,
      max_work,
      100,
      max_entries,
      10000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((control, execution, [left, right]))
}

///|
fn bounded_interval_fixture(
  max_work? : Int = 100000,
  max_entries? : Int = 10000,
  text_key? : Bool = false,
) -> (@bounded.Control, BoundedIntervalJoinExecution, Array[ProducerRead]) raise {
  bounded_interval_fixture_result(max_work, max_entries~, text_key~).unwrap()
}

///|
test "interval join yields within long equal and unequal Text keys" {
  let mut prior_work : Int? = None
  for quantum in [1, 7] {
    let (_, execution, inputs) = bounded_interval_fixture(text_key=true)
    let state = execution.state
    let mut output : CompletedOutput? = None
    let mut comparing = 0
    for _ in 0..<10000 {
      let before = state.control.remaining
      let compare_phase = state.phase is CompareKey
      let poll = advance_bounded_interval_join(execution, quantum).unwrap()
      if compare_phase {
        assert_true(before - state.control.remaining <= quantum)
        comparing += 1
      }
      match poll {
        BoundedIntervalJoinContinue(..) => ()
        BoundedIntervalJoinComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("long Text interval join failed")
      }
    }
    assert_true(comparing > 256)
    guard output is Some(output) else { fail("interval join did not finish") }
    assert_eq(completed_row_count(output), 3)
    for
      (row, left, right) in [
        (0, 10.0, Some(20.0)),
        (1, 10.0, Some(21.0)),
        (2, 11.0, None),
      ] {
      assert_true(
        completed_cell(output, row, 0) is Some(Number(value)) && value == left,
      )
      match right {
        Some(expected) =>
          assert_true(
            completed_cell(output, row, 1) is Some(Number(value)) &&
            value == expected,
          )
        None => assert_true(completed_cell(output, row, 1) is Some(Null))
      }
    }
    assert_true(completed_output_matches_inputs(output, inputs))
    let spent = 100000 - state.control.remaining
    if prior_work is Some(prior) {
      assert_eq(spent, prior)
    }
    prior_work = Some(spent)
    assert_true(cleanup_bounded_interval_join(execution).unwrap())
    assert_false(cleanup_bounded_interval_join(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(inputs.all(producer_read_available))
  }
}

///|
test "interval join retains pending Text comparison until confirmed stop" {
  for target in [1, 3] {
    let (control, execution, inputs) = bounded_interval_fixture(text_key=true)
    let state = execution.state
    let mut reached = false
    for _ in 0..<3000 {
      assert_true(
        advance_bounded_interval_join(execution, 1).unwrap()
        is BoundedIntervalJoinContinue(..),
      )
      if state.comparison is Some(cursor) &&
        cursor.phase == target &&
        (if target == 1 { cursor.charge.offset } else { cursor.offset }) > 64 {
        reached = true
        break
      }
    }
    assert_true(reached)
    let held = state.workspace.live
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_true(state.comparison is Some(_))
    assert_eq(state.workspace.live, held)
    assert_true(
      advance_bounded_interval_join(execution, 1).unwrap()
      is BoundedIntervalJoinStopped(@bounded.Cancelled, ..),
    )
    assert_true(state.comparison is Some(_))
    assert_eq(
      (state.workspace.live, state.control.remaining),
      (held, remaining),
    )
    assert_true(state.rows.val is None)
    assert_false(state.accepted.val)
    assert_true(inputs.all(producer_read_available))
    assert_true(cleanup_bounded_interval_join(execution).unwrap())
    assert_false(cleanup_bounded_interval_join(execution).unwrap())
    assert_true(state.comparison is None)
    assert_eq(state.workspace.live, 0)
    assert_eq(state.control.remaining, remaining)
    assert_true(inputs.all(producer_read_available))
  }
}

///|
test "interval Text comparison has fixed control and cursor boundaries" {
  // Isolate the first production key pair after ordinary preparation. Two
  // 257-byte Text operands and the complete-value transition cost 515 units.
  // Four clock entries per side, two key entries and four output mappings
  // hold 14 metadata slots; the pending comparison borrows two more.
  // These are comparison boundaries, not the complete Run budget.
  for (work, slots, failure) in [(515, 16, 0), (514, 16, 1), (515, 15, 2)] {
    let (control, execution, inputs) = bounded_interval_fixture(
      text_key=true,
      max_entries=slots,
    )
    let state = execution.state
    while !(state.phase is CompareKey) {
      assert_true(
        advance_bounded_interval_join(execution, 1).unwrap()
        is BoundedIntervalJoinContinue(..),
      )
    }
    state.control.remaining = work
    let a = producer_read_cell(inputs[0], 0, state.keys[0].0).unwrap()
    let b = producer_read_cell(inputs[1], 0, state.keys[0].1).unwrap()
    let mut result : Result[Int?, RowIssue] = Ok(None)
    for _ in 0..<2000 {
      result = bounded_interval_compare_key(state, a, b)
      if !(result is Ok(None)) {
        break
      }
    }
    if failure == 0 {
      assert_true(result is Ok(Some(0)))
      assert_eq(state.control.remaining, 0)
      assert_eq(state.workspace.peak, 16)
      assert_eq(state.workspace.live, 14)
      assert_true(state.comparison is None)
    } else {
      assert_true(result is Err(RowLimit))
    }
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_interval_join(execution, 1).unwrap()
      is BoundedIntervalJoinStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_interval_join(execution).unwrap())
    assert_false(cleanup_bounded_interval_join(execution).unwrap())
    assert_true(state.comparison is None)
    assert_eq(state.workspace.live, 0)
    assert_eq(state.control.remaining, remaining)
    assert_true(inputs.all(producer_read_available))
  }
}

///|
test "interval long Text preserves whole-operation exact work and workspace" {
  // The existing 132-unit scalar fixture has four one-unit key comparisons.
  // Replacing each with 1 + 257 + 257 adds 4 * 514: exact work is 2188.
  // Pending comparisons peak at 14 + 2 slots, below the existing output
  // peak of 18. Neither limit is inferred from a successful execution.
  for
    (work, slots, success) in [
      (2188, 18, true),
      (2187, 18, false),
      (2188, 17, false),
    ] {
    for quantum in [1, 7] {
      let (_, execution, inputs) = bounded_interval_fixture(
        max_work=work,
        max_entries=slots,
        text_key=true,
      )
      let mut terminal : BoundedIntervalJoinPoll? = None
      for _ in 0..<10000 {
        match advance_bounded_interval_join(execution, quantum).unwrap() {
          BoundedIntervalJoinContinue(..) => ()
          value => {
            terminal = Some(value)
            break
          }
        }
      }
      if success {
        assert_true(terminal is Some(BoundedIntervalJoinComplete(_, ..)))
        assert_eq(execution.state.control.remaining, 0)
        assert_eq(execution.state.workspace.peak, 18)
      } else {
        assert_true(
          terminal is Some(BoundedIntervalJoinFailed(Rows(RowLimit), ..)),
        )
        assert_true(execution.state.rows.val is None)
        assert_false(execution.state.accepted.val)
      }
      assert_true(cleanup_bounded_interval_join(execution).unwrap())
      assert_false(cleanup_bounded_interval_join(execution).unwrap())
      assert_eq(execution.state.workspace.live, 0)
      assert_true(execution.state.comparison is None)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "bounded interval checks metadata and output workspace limits" {
  // Two rows on each side, one key, and two selected columns retain 14
  // structural entries; one output row and its checked copy add four.
  match bounded_interval_fixture_result(0, max_entries=13) {
    Err(Rows(RowLimit)) => ()
    _ => fail("expected early workspace rejection")
  }
  let (_, execution, _) = bounded_interval_fixture(max_entries=18)
  let mut complete = false
  for _ in 0..<500 {
    if !complete {
      match advance_bounded_interval_join(execution, 1).unwrap() {
        BoundedIntervalJoinContinue(..) => ()
        BoundedIntervalJoinComplete(output, ..) => {
          assert_eq(completed_row_count(output), 3)
          complete = true
        }
        _ => fail("unexpected terminal result")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_interval_join(execution).unwrap())
  let (_, short, inputs) = bounded_interval_fixture(max_entries=17)
  let mut failed = false
  for _ in 0..<500 {
    if !failed {
      match advance_bounded_interval_join(short, 1).unwrap() {
        BoundedIntervalJoinContinue(..) => ()
        BoundedIntervalJoinFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short workspace did not fail before completion")
      }
    }
  }
  assert_true(failed)
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_interval_join_cleanup_pending(short))
  assert_true(cleanup_bounded_interval_join(short).unwrap())
  assert_false(bounded_interval_join_cleanup_pending(short))
}

///|
test "bounded interval charges every explored pair" {
  // This fixed two-by-two fixture includes four clock-loading steps and four
  // pair visits, three output rows, and finalization in the 132-unit work
  // envelope. The literal is independent of the execution's work counter.
  let (_, exact, _) = bounded_interval_fixture(max_work=132)
  let mut exact_terminal = false
  while !exact_terminal {
    match advance_bounded_interval_join(exact, 1).unwrap() {
      BoundedIntervalJoinContinue(..) => ()
      BoundedIntervalJoinComplete(output, ..) => {
        assert_eq(completed_row_count(output), 3)
        exact_terminal = true
      }
      BoundedIntervalJoinFailed(_, ..) => fail("unexpected exact failure")
      BoundedIntervalJoinStopped(_, ..) => fail("unexpected exact stop")
    }
  }
  assert_true(cleanup_bounded_interval_join(exact).unwrap())
  let (_, short, inputs) = bounded_interval_fixture(max_work=131)
  let mut short_terminal = false
  while !short_terminal {
    match advance_bounded_interval_join(short, 1).unwrap() {
      BoundedIntervalJoinContinue(..) => ()
      BoundedIntervalJoinComplete(_, ..) => fail("one-short work completed")
      BoundedIntervalJoinFailed(Rows(RowLimit), ..) => short_terminal = true
      BoundedIntervalJoinFailed(_, ..) => fail("unexpected one-short issue")
      BoundedIntervalJoinStopped(_, ..) => fail("unexpected one-short stop")
    }
  }
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_interval_join_cleanup_pending(short))
  assert_true(cleanup_bounded_interval_join(short).unwrap())
  assert_false(bounded_interval_join_cleanup_pending(short))
}

///|
test "bounded interval join resumes exact pair search and completes" {
  let (_, execution, inputs) = bounded_interval_fixture()
  let mut advances = 0
  let mut complete : CompletedOutput? = None
  while complete is None {
    advances += 1
    match advance_bounded_interval_join(execution, 1).unwrap() {
      BoundedIntervalJoinContinue(..) => ()
      BoundedIntervalJoinComplete(output, ..) => complete = Some(output)
      BoundedIntervalJoinFailed(_, ..) => fail("unexpected failure")
      BoundedIntervalJoinStopped(_, ..) => fail("unexpected stop")
    }
  }
  assert_true(advances > 10)
  let output = complete.unwrap()
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(10.0)))
  assert_true(completed_cell(output, 0, 1) is Some(Number(20.0)))
  assert_true(completed_cell(output, 1, 1) is Some(Number(21.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(11.0)))
  assert_true(completed_cell(output, 2, 1) is Some(Null))
  assert_true(completed_output_matches_inputs(output, inputs))
  assert_true(cleanup_bounded_interval_join(execution).unwrap())
  assert_false(bounded_interval_join_cleanup_pending(execution))
}

///|
test "bounded interval join cancels before publishing partial output" {
  let (control, execution, inputs) = bounded_interval_fixture()
  match advance_bounded_interval_join(execution, 3).unwrap() {
    BoundedIntervalJoinContinue(..) => ()
    _ => fail("expected partial progress")
  }
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_interval_join(execution, 1).unwrap() {
    BoundedIntervalJoinStopped(@bounded.Cancelled, ..) => ()
    _ => fail("expected cancellation")
  }
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_interval_join_cleanup_pending(execution))
  assert_true(cleanup_bounded_interval_join(execution).unwrap())
  assert_false(bounded_interval_join_cleanup_pending(execution))
}
