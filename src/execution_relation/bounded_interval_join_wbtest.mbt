///|
fn bounded_interval_source(
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let schema = "{\"key\":{\"type\":\"number\",\"nullable\":true}," +
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
fn bounded_interval_fixture() -> (
  @bounded.Control,
  BoundedIntervalJoinExecution,
  Array[ProducerRead],
) raise {
  let (left_owner, left_output) = bounded_interval_source(
    "[{\"key\":1,\"start\":0,\"end\":5,\"time\":2,\"value\":10}," +
    "{\"key\":2,\"start\":5,\"end\":8,\"time\":7,\"value\":11}]",
  )
  let (right_owner, right_output) = bounded_interval_source(
    "[{\"key\":1,\"start\":0,\"end\":3,\"time\":1,\"value\":20}," +
    "{\"key\":1,\"start\":2,\"end\":4,\"time\":2,\"value\":21}]",
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
  let execution = start_bounded_interval_join(
    control,
    generated,
    left,
    right,
    10,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution, [left, right])
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
