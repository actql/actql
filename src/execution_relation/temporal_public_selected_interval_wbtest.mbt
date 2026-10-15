// Isolate the original typed 3+2 inputs and a selected occurrence after a
// pure projection. The original full-prefix experiment remains in preimages.

///|
fn temporal_public_completed_source(
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
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(0)).unwrap())
}

///|
test "original temporal operands complete through selected interval with exact six-pair budget" {
  let (left_owner, left_output) = temporal_public_completed_source(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"id\":1,\"at\":10},{\"id\":2,\"at\":30},{\"id\":3,\"at\":50}]",
  )
  let (right_owner, right_output) = temporal_public_completed_source(
    "{\"id\":{\"type\":\"number\",\"nullable\":false},\"begin\":{\"type\":\"number\",\"nullable\":false},\"finish\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"id\":7,\"begin\":5,\"finish\":15},{\"id\":8,\"begin\":20,\"finish\":25}]",
  )
  let left_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(left_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let right_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(right_owner)),
    @pipeline.Step(0),
  ).unwrap()
  for projected in [false, true] {
    let prefix = if projected {
      "{\"from\":\"l\",\"select\":[\"id\",\"at\"],\"as\":\"current\"},"
    } else {
      ""
    }
    let from = if projected { "current" } else { "l" }
    let steps = "[" +
      prefix +
      "{\"from\":\"" +
      from +
      "\",\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":3}}]"
    let checked = @pipeline.check_with_evidence(
      input_cursor(steps),
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
    let step = if projected { 1 } else { 0 }
    let retained = if projected {
      ["select_0", "interval_join_1"]
    } else {
      ["interval_join_0"]
    }
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      retained,
      100000,
      10000,
    ).unwrap()
    let generated = constrain_generated_interval_search(generated, step, 6L).unwrap()
    let generated = constrain_generated_join_output(generated, step, 3L).unwrap()
    let completed = execute_generated_sequence(
      generated,
      [],
      compute_test_limits(),
      produced=[
        bind_completed_input(owner, 0, left_owner, left_output).unwrap(),
        bind_completed_input(owner, 1, right_owner, right_output).unwrap(),
      ],
    ).unwrap()
    let left = if projected {
      prepare_producer_read(
        owner,
        bind_completed_operation_input(
          owner,
          step,
          0,
          owner,
          completed_output(completed, @pipeline.Step(0)).unwrap(),
        ).unwrap(),
        100,
        10000,
      ).unwrap()
    } else {
      prepare_producer_read(
        owner,
        bind_completed_operation_input(owner, step, 0, left_owner, left_output).unwrap(),
        100,
        10000,
      ).unwrap()
    }
    let right = prepare_producer_read(
      owner,
      bind_completed_operation_input(owner, step, 1, right_owner, right_output).unwrap(),
      100,
      10000,
    ).unwrap()
    let selected = select_generated_sequence_step(generated, step).unwrap()
    let limits = compute_test_limits()
    let active = start_bounded_interval_join(
      @bounded.control(),
      selected,
      left,
      right,
      3,
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      10000,
    ).unwrap()
    let mut output = None
    for _ in 0..<100000 {
      if output is None {
        match advance_bounded_interval_join(active, 1).unwrap() {
          BoundedIntervalJoinContinue(..) => ()
          BoundedIntervalJoinComplete(value, ..) => output = Some(value)
          BoundedIntervalJoinFailed(InvalidExecution, ..) =>
            fail("selected invalid_execution")
          BoundedIntervalJoinFailed(Rows(RowLimit), ..) =>
            fail("selected rows.row_limit")
          BoundedIntervalJoinFailed(_, ..) =>
            fail("selected other_typed_failure")
          BoundedIntervalJoinStopped(_, ..) => fail("unexpected interval stop")
        }
      }
    }
    let rows = output.unwrap()
    assert_eq(completed_row_count(rows), 3)
    assert_true(completed_cell(rows, 0, 0) is Some(Number(1.0)))
    assert_true(completed_cell(rows, 1, 0) is Some(Number(2.0)))
    assert_true(completed_cell(rows, 2, 0) is Some(Number(3.0)))
    assert_true(completed_cell(rows, 0, 1) is Some(Number(7.0)))
    assert_true(completed_cell(rows, 1, 1) is Some(Null))
    assert_true(completed_cell(rows, 2, 1) is Some(Null))
    assert_true(cleanup_bounded_interval_join(active).unwrap())
    assert_false(bounded_interval_join_cleanup_pending(active))
  }
}
