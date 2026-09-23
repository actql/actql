///|
fn bounded_cross_source(
  schema : String,
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
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
fn bounded_cross_fixture(
  max_rows? : Int = 4,
  max_work? : Int = 1000,
  max_entries? : Int = 100,
) -> (
  @bounded.Control,
  Result[BoundedCrossJoinExecution, BoundedCrossJoinIssue],
  Array[ProducerRead],
) raise {
  let (left_owner, left_output) = bounded_cross_source(
    "{\"id\":{\"type\":\"number\",\"nullable\":false}}", "[{\"id\":1},{\"id\":2}]",
  )
  let (right_owner, right_output) = bounded_cross_source(
    "{\"tag\":{\"type\":\"string\",\"nullable\":false}}", "[{\"tag\":\"a\"},{\"tag\":\"b\"}]",
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
      "[{\"from\":\"l\",\"cross_join\":{\"with\":\"r\"," +
      "\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}}}]",
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
    ["cross_join_0"],
    100000,
    10000,
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
  let execution = start_bounded_cross_join(
    control,
    generated,
    left,
    right,
    max_rows,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  )
  (control, execution, [left, right])
}

///|
test "bounded cross join emits left-major pairs within quantum" {
  let (_, started, inputs) = bounded_cross_fixture()
  let execution = started.unwrap()
  let mut advances = 0
  let mut last_work = 0L
  let mut completed = false
  while !completed && advances < 1000 {
    advances += 1
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinContinue(work~, ..) => {
        assert_true(work - last_work <= 1L)
        last_work = work
      }
      BoundedCrossJoinComplete(output, work~, ..) => {
        assert_true(work - last_work <= 1L)
        assert_eq(completed_row_count(output), 4)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
        assert_true(completed_cell(output, 1, 0) is Some(Number(1.0)))
        assert_true(completed_cell(output, 2, 0) is Some(Number(2.0)))
        assert_true(completed_cell(output, 3, 0) is Some(Number(2.0)))
        completed = true
      }
      BoundedCrossJoinFailed(_, ..) => fail("cross join failed")
      BoundedCrossJoinStopped(_, ..) => fail("cross join stopped")
    }
  }
  assert_true(completed)
  assert_true(advances > 10)
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
}

///|
test "bounded cross join stops after pair work without publishing" {
  let (control, started, inputs) = bounded_cross_fixture()
  let execution = started.unwrap()
  for _ in 0..<12 {
    assert_true(
      advance_bounded_cross_join(execution, 1)
      is Ok(BoundedCrossJoinContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_cross_join(execution, 1)
    is Ok(BoundedCrossJoinStopped(@bounded.Cancelled, ..)),
  )
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
}

///|
test "bounded cross join rejects an excessive product before allocation" {
  let (_, started, _) = bounded_cross_fixture(max_rows=3)
  assert_true(started is Err(Rows(RowLimit)))
}

///|
test "bounded cross join admits its exact structural workspace" {
  let (_, exact, _) = bounded_cross_fixture(max_entries=12)
  let execution = exact.unwrap()
  let mut completed = false
  while !completed {
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinComplete(output, ..) => {
        assert_eq(completed_row_count(output), 4)
        completed = true
      }
      _ => fail("exact cross join workspace failed")
    }
  }
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  let (_, short, _) = bounded_cross_fixture(max_entries=11)
  let rejected = short.unwrap()
  let mut failed = false
  while !failed {
    match advance_bounded_cross_join(rejected, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("one-short cross join workspace had another result")
    }
  }
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
}

///|
test "bounded cross join charges exact metadata and pair work" {
  // id and tag each charge their output and source name once. Four pairs
  // each charge one begin step and two checked cells: 14 + 12 = 26.
  let (_, exact, _) = bounded_cross_fixture(max_work=26)
  let execution = exact.unwrap()
  let mut completed = false
  while !completed {
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinComplete(output, ..) => {
        assert_eq(completed_row_count(output), 4)
        completed = true
      }
      _ => fail("exact cross join control work failed")
    }
  }
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  let (_, short, _) = bounded_cross_fixture(max_work=25)
  let rejected = short.unwrap()
  let mut failed = false
  while !failed {
    match advance_bounded_cross_join(rejected, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("one-short cross join work had another result")
    }
  }
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
}
