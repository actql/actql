///|
fn bounded_asof_source(
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"key\":{\"type\":\"number\",\"nullable\":false}," +
    "\"clock\":{\"type\":\"number\",\"nullable\":false}," +
    "\"priority\":{\"type\":\"number\",\"nullable\":true}," +
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
fn bounded_asof_fixture_result(
  max_entries : Int,
  max_work : Int,
) -> Result[
  (@bounded.Control, BoundedAsOfJoinExecution, Array[ProducerRead]),
  BoundedAsOfJoinIssue,
] raise {
  let (left_owner, left_output) = bounded_asof_source(
    "[{\"id\":2,\"key\":1,\"clock\":105,\"priority\":null,\"value\":20}," +
    "{\"id\":1,\"key\":1,\"clock\":100,\"priority\":null,\"value\":10}," +
    "{\"id\":3,\"key\":2,\"clock\":110,\"priority\":null,\"value\":30}]",
  )
  let (right_owner, right_output) = bounded_asof_source(
    "[{\"id\":11,\"key\":1,\"clock\":90,\"priority\":5,\"value\":100}," +
    "{\"id\":12,\"key\":1,\"clock\":100,\"priority\":2,\"value\":200}," +
    "{\"id\":13,\"key\":1,\"clock\":100,\"priority\":1,\"value\":300}]",
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
      "[{\"from\":\"l\",\"asof_join\":{\"with\":\"r\"," +
      "\"kind\":\"left\",\"by\":[{\"left\":\"key\",\"right\":\"key\"}]," +
      "\"left_id\":\"id\",\"left_time\":\"clock\"," +
      "\"right_time\":\"clock\",\"direction\":\"backward\"," +
      "\"tolerance\":20,\"right_tie_break\":[\"priority\"]," +
      "\"select\":{\"id\":\"left.id\",\"matched\":\"right.value\"}}}]",
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
    ["asof_join_0"],
    100000,
    10000,
  ).unwrap()
  let generated = constrain_generated_asof_search(generated, 0, 9L).unwrap()
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
    start_bounded_asof_join(
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
fn bounded_asof_fixture(
  max_entries? : Int = 10000,
) -> (@bounded.Control, BoundedAsOfJoinExecution, Array[ProducerRead]) raise {
  bounded_asof_fixture_result(max_entries, 100000).unwrap()
}

///|
test "bounded as-of join checks metadata and output workspace limits" {
  // Three rows per side, one key, two fields, identity, and tie retain 14
  // entries. Sort peaks at 20; ordered indices, the output row, and its
  // checked copy peak at 21 entries.
  match bounded_asof_fixture_result(13, 0) {
    Err(Rows(RowLimit)) => ()
    _ => fail("expected early workspace rejection")
  }
  let (_, execution, _) = bounded_asof_fixture(max_entries=21)
  let mut complete = false
  for _ in 0..<500 {
    if !complete {
      match advance_bounded_asof_join(execution, 1).unwrap() {
        BoundedAsOfJoinContinue(..) => ()
        BoundedAsOfJoinComplete(output, ..) => {
          assert_eq(completed_row_count(output), 3)
          complete = true
        }
        _ => fail("unexpected terminal result")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_asof_join(execution).unwrap())
  let (_, short, inputs) = bounded_asof_fixture(max_entries=20)
  let mut failed = false
  for _ in 0..<500 {
    if !failed {
      match advance_bounded_asof_join(short, 1).unwrap() {
        BoundedAsOfJoinContinue(..) => ()
        BoundedAsOfJoinFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short workspace did not fail before completion")
      }
    }
  }
  assert_true(failed)
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_asof_join_cleanup_pending(short))
  assert_true(cleanup_bounded_asof_join(short).unwrap())
  assert_false(bounded_asof_join_cleanup_pending(short))
}

///|
test "bounded as-of join resumes search and preserves output order" {
  let (_, execution, inputs) = bounded_asof_fixture()
  let mut advances = 0
  let mut complete : CompletedOutput? = None
  while complete is None {
    advances += 1
    match advance_bounded_asof_join(execution, 1).unwrap() {
      BoundedAsOfJoinContinue(..) => ()
      BoundedAsOfJoinComplete(output, ..) => complete = Some(output)
      BoundedAsOfJoinFailed(_, ..) => fail("unexpected failure")
      BoundedAsOfJoinStopped(_, ..) => fail("unexpected stop")
    }
  }
  assert_true(advances > 20)
  let output = complete.unwrap()
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
  assert_true(completed_cell(output, 0, 1) is Some(Number(300.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 1, 1) is Some(Number(300.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(3.0)))
  assert_true(completed_cell(output, 2, 1) is Some(Null))
  assert_true(completed_output_matches_inputs(output, inputs))
  assert_true(cleanup_bounded_asof_join(execution).unwrap())
  assert_false(bounded_asof_join_cleanup_pending(execution))
}

///|
test "bounded as-of join cancels before publishing partial output" {
  let (control, execution, inputs) = bounded_asof_fixture()
  match advance_bounded_asof_join(execution, 5).unwrap() {
    BoundedAsOfJoinContinue(..) => ()
    _ => fail("expected partial progress")
  }
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_asof_join(execution, 1).unwrap() {
    BoundedAsOfJoinStopped(@bounded.Cancelled, ..) => ()
    _ => fail("expected cancellation")
  }
  assert_true(inputs.all(producer_read_available))
  assert_true(bounded_asof_join_cleanup_pending(execution))
  assert_true(cleanup_bounded_asof_join(execution).unwrap())
  assert_false(bounded_asof_join_cleanup_pending(execution))
}

///|
test "bounded as-of join admits exact and one-short control work" {
  // The fixed three-by-three fixture includes checked field resolution,
  // identity validation and sort, clock reads, nine candidate visits,
  // tie handling, three output rows, and finalization. Its fixed work
  // boundary is 136 units, not a value read from the execution counter.
  for (budget, accepted) in [(136, true), (135, false)] {
    let (_, execution, inputs) = bounded_asof_fixture_result(10000, budget).unwrap()
    let mut terminal = false
    for _ in 0..<600 {
      if terminal {
        break
      }
      match advance_bounded_asof_join(execution, 1).unwrap() {
        BoundedAsOfJoinContinue(..) => ()
        BoundedAsOfJoinComplete(output, ..) => {
          assert_true(accepted)
          assert_eq(completed_row_count(output), 3)
          terminal = true
        }
        BoundedAsOfJoinFailed(Rows(RowLimit), ..) => {
          assert_false(accepted)
          assert_true(bounded_asof_join_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected as-of work boundary result")
      }
    }
    assert_true(terminal)
    assert_true(inputs.all(producer_read_available))
    assert_true(cleanup_bounded_asof_join(execution).unwrap())
    assert_false(bounded_asof_join_cleanup_pending(execution))
  }
}
