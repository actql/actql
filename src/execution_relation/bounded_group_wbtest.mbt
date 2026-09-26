///|
fn bounded_group_fixture(
  rows : String,
  max_work? : Int = 1000,
  max_entries? : Int = 1000,
) -> (@bounded.Control, BoundedGroupExecution, CompletedOutput) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
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
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"seed\",\"group\":{\"by\":[\"k\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"field\":\"k\"}}}}]",
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
    ["group_0"],
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
  let execution = start_bounded_group_execution(
    control,
    generated,
    read,
    10,
    run_limits().input_values,
    run_limits().output_values,
    run_limits().input_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, source)
}

///|
fn drive_bounded_group(execution : BoundedGroupExecution) -> BoundedGroupPoll {
  for _ in 0..<10000 {
    match advance_bounded_group_execution(execution, 1) {
      Ok(BoundedGroupContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) =>
        return BoundedGroupFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedGroupFailed(InvalidExecution, progress=0L, work=0L)
}

///|
test "bounded group admits exact work and rejects one unit short" {
  // One input row charge (1); names: input k (2), key k (2), aggregate m
  // (2) and its field k (2), output k and m (4); stable order: one term,
  // one row check and one index (3); one group boundary (1); one group (1);
  // one max contributor (1); no comparison; two output cells (2).
  let exact_work = 21
  let (_, exact, source) = bounded_group_fixture(
    "[{\"k\":1}]",
    max_work=exact_work,
  )
  match drive_bounded_group(exact) {
    BoundedGroupComplete(output, ..) =>
      assert_eq(completed_row_count(output), 1)
    _ => fail("exact group work rejected")
  }
  assert_true(cleanup_bounded_group_execution(exact).unwrap())
  let (_, short, _) = bounded_group_fixture(
    "[{\"k\":1}]",
    max_work=exact_work - 1,
  )
  match drive_bounded_group(short) {
    BoundedGroupFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short group work accepted")
  }
  assert_true(cleanup_bounded_group_execution(short).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded group stops after positive work without publishing" {
  let (control, execution, source) = bounded_group_fixture(
    "[{\"k\":3},{\"k\":1},{\"k\":3},{\"k\":2}]",
  )
  for _ in 0..<5 {
    assert_true(
      advance_bounded_group_execution(execution, 1)
      is Ok(BoundedGroupContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_group_execution(execution, 1) is Ok(BoundedGroupStopped(_, ..)),
  )
  assert_true(cleanup_bounded_group_execution(execution).unwrap())
  assert_true(completed_output_available(source))
}
