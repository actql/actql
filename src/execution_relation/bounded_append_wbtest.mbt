///|
fn bounded_append_source(
  rows : String,
  schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
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
    10000,
    1000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(0)).unwrap())
}

///|
fn bounded_append_fixture(
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  right_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  left_rows? : String = "[{\"id\":1},{\"id\":2}]",
  right_rows? : String = "[{\"id\":3}]",
) -> (
  @bounded.Control,
  Result[BoundedAppendExecution, BoundedAppendIssue],
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
    input_cursor("[{\"from\":\"l\",\"append\":{\"with\":\"r\"}}]"),
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
    ["append_0"],
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
  let execution = start_bounded_append(
    control,
    generated,
    left,
    right,
    3,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    1000,
  )
  (control, execution, [left, right])
}

///|
test "bounded append preserves order across quantum-one resumes" {
  let (_, started, _) = bounded_append_fixture()
  let execution = started.unwrap()
  let mut done = false
  let mut polls = 0
  let mut progress = 0L
  let mut work = 0L
  while !done && polls < 100 {
    polls += 1
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(progress=next_progress, work=next_work) => {
        assert_true(next_work - work <= 1L)
        progress = next_progress
        work = next_work
      }
      BoundedAppendComplete(output, progress=next_progress, work=next_work) => {
        assert_true(next_work - work <= 1L)
        progress = next_progress
        work = next_work
        assert_eq(completed_row_count(output), 3)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
        assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
        assert_true(completed_cell(output, 2, 0) is Some(Number(3)))
        done = true
      }
      _ => fail("bounded append did not complete")
    }
  }
  assert_true(done)
  assert_eq(progress, 3L)
  assert_true(work > 3L)
  assert_true(cleanup_bounded_append(execution).unwrap())
}

///|
test "bounded append admits independently calculated work and workspace" {
  // One name costs 1 + 2 control units. Three rows cost two units each.
  let (_, exact, _) = bounded_append_fixture(max_work=9, max_entries=10)
  let execution = exact.unwrap()
  let mut done = false
  while !done {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendComplete(_, ..) => done = true
      _ => fail("exact append resource boundary failed")
    }
  }
  assert_true(cleanup_bounded_append(execution).unwrap())
  let (_, short_work, _) = bounded_append_fixture(max_work=8, max_entries=10)
  let rejected_work = short_work.unwrap()
  let mut failed_work = false
  while !failed_work {
    match advance_bounded_append(rejected_work, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendFailed(Rows(RowLimit), ..) => failed_work = true
      _ => fail("one-short append work had another outcome")
    }
  }
  assert_true(cleanup_bounded_append(rejected_work).unwrap())
  let (_, short_space, _) = bounded_append_fixture(max_work=9, max_entries=9)
  let rejected_space = short_space.unwrap()
  let mut failed_space = false
  while !failed_space {
    match advance_bounded_append(rejected_space, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendFailed(Rows(RowLimit), ..) => failed_space = true
      _ => fail("one-short append workspace had another outcome")
    }
  }
  assert_true(cleanup_bounded_append(rejected_space).unwrap())
}

///|
test "bounded append stops after row progress and discards partial output" {
  let (control, started, _) = bounded_append_fixture()
  let execution = started.unwrap()
  let mut progressed = false
  while !progressed {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(progress~, ..) => progressed = progress > 0L
      _ => fail("append completed before cancellation")
    }
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_append(execution, 1).unwrap() is BoundedAppendStopped(_),
  )
  assert_true(cleanup_bounded_append(execution).unwrap())
}

///|
test "bounded append aligns nullable fields in authored left order" {
  let (_, started, _) = bounded_append_fixture(
    left_schema="{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":true}}",
    right_schema="{\"tag\":{\"type\":\"string\",\"nullable\":true},\"id\":{\"type\":\"number\",\"nullable\":false}}",
    left_rows="[{\"id\":1,\"tag\":null}]",
    right_rows="[{\"tag\":{\"literal\":\"right\"},\"id\":2}]",
  )
  let execution = started.unwrap()
  let mut done = false
  while !done {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendComplete(output, ..) => {
        assert_eq(completed_column_name(output, 0), Some("id"))
        assert_eq(completed_column_name(output, 1), Some("tag"))
        assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
        assert_true(completed_cell(output, 0, 1) is Some(Null))
        assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
        assert_true(completed_cell(output, 1, 1) is Some(Text("right")))
        done = true
      }
      _ => fail("aligned append did not complete")
    }
  }
  assert_true(cleanup_bounded_append(execution).unwrap())
}
