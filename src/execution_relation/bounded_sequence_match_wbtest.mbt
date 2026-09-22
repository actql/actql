///|
fn bounded_sequence_source(
  empty? : Bool = false,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let rows = if empty {
    "[]"
  } else {
    "[{\"id\":3,\"key\":1,\"clock\":3,\"value\":2}," +
    "{\"id\":1,\"key\":1,\"clock\":1,\"value\":1}," +
    "{\"id\":4,\"key\":2,\"clock\":4,\"value\":2}," +
    "{\"id\":2,\"key\":1,\"clock\":2,\"value\":2}," +
    "{\"id\":5,\"key\":2,\"clock\":3,\"value\":1}]"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"key\":{\"type\":\"number\",\"nullable\":false}," +
    "\"clock\":{\"type\":\"number\",\"nullable\":false}," +
    "\"value\":{\"type\":\"number\",\"nullable\":false}}," +
    "\"rows\":" +
    rows +
    "}," +
    "\"as\":\"source\"}]",
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
fn bounded_sequence_fixture(
  overlap? : String = "allow",
  contiguity? : String = "subsequence",
  empty? : Bool = false,
  grouped? : Bool = true,
) -> (@bounded.Control, BoundedSequenceMatchExecution, ProducerRead) raise {
  let (source_owner, source_output) = bounded_sequence_source(empty~)
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"events\",\"sequence\":{\"by\":" +
      (if grouped { "[\"key\"]" } else { "[]" }) +
      "," +
      "\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{" +
      "\"as\":\"start\",\"where\":\"value = 1\"},{" +
      "\"as\":\"end\",\"where\":\"value = 2\"}]," +
      "\"within\":10,\"overlap\":\"" +
      overlap +
      "\",\"contiguity\":\"" +
      contiguity +
      "\"}}]",
    ),
    [("events", @pipeline.ProducedInput(producer))],
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
    ["sequence_0"],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_sequence_match(
    control,
    generated,
    input,
    100,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
test "bounded sequence match resumes and preserves canonical match order" {
  let (_, execution, input) = bounded_sequence_fixture()
  let mut advances = 0
  let mut complete : CompletedOutput? = None
  while complete is None {
    advances += 1
    match advance_bounded_sequence_match(execution, 1).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      BoundedSequenceMatchComplete(output, ..) => complete = Some(output)
      BoundedSequenceMatchFailed(_, ..) =>
        fail("unexpected bounded sequence failure")
      BoundedSequenceMatchStopped(_, ..) => fail("unexpected sequence stop")
    }
  }
  assert_true(advances > 20)
  let output = complete.unwrap()
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2.0)))
  assert_true(completed_cell(output, 0, 2) is Some(Number(1.0)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(3.0)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(4.0)))
  assert_true(completed_cell(output, 2, 2) is Some(Number(2.0)))
  assert_true(completed_output_matches_inputs(output, [input]))
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_false(bounded_sequence_match_cleanup_pending(execution))
}

///|
test "bounded sequence match cancels without publishing partial rows" {
  let (control, execution, input) = bounded_sequence_fixture()
  assert_eq(execution.predicate_entries.val, 0)
  match advance_bounded_sequence_match(execution, 8).unwrap() {
    BoundedSequenceMatchContinue(..) => ()
    _ => fail("expected partial sequence progress")
  }
  assert_true(execution.predicate_entries.val > 0)
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_sequence_match(execution, 1).unwrap() {
    BoundedSequenceMatchStopped(@bounded.Cancelled, ..) => ()
    _ => fail("expected bounded sequence cancellation")
  }
  assert_true(producer_read_available(input))
  assert_true(bounded_sequence_match_cleanup_pending(execution))
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_false(bounded_sequence_match_cleanup_pending(execution))
  assert_eq(execution.predicate_entries.val, 0)
}

///|
test "bounded sequence cancellation precedes predicate initialization" {
  let (control, execution, _) = bounded_sequence_fixture()
  assert_eq(execution.predicate_entries.val, 0)
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_sequence_match(execution, 1).unwrap() {
    BoundedSequenceMatchStopped(@bounded.Cancelled, progress=0L, work=0L) => ()
    _ => fail("expected cancellation before predicate initialization")
  }
  assert_eq(execution.predicate_entries.val, 0)
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_eq(execution.predicate_entries.val, 0)
}

///|
test "bounded sequence match preserves adjacent disallow semantics" {
  let (_, execution, _) = bounded_sequence_fixture(
    overlap="disallow",
    contiguity="adjacent",
  )
  let mut complete : CompletedOutput? = None
  while complete is None {
    match advance_bounded_sequence_match(execution, 2).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      BoundedSequenceMatchComplete(output, ..) => complete = Some(output)
      BoundedSequenceMatchFailed(_, ..) => fail("unexpected sequence failure")
      BoundedSequenceMatchStopped(_, ..) => fail("unexpected sequence stop")
    }
  }
  assert_eq(completed_row_count(complete.unwrap()), 2)
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
}

///|
test "bounded sequence match covers the remaining policy combinations" {
  for
    (overlap, contiguity) in [
      ("allow", "adjacent"),
      ("disallow", "subsequence"),
    ] {
    let (_, execution, _) = bounded_sequence_fixture(overlap~, contiguity~)
    let mut complete : CompletedOutput? = None
    while complete is None {
      match advance_bounded_sequence_match(execution, 2).unwrap() {
        BoundedSequenceMatchContinue(..) => ()
        BoundedSequenceMatchComplete(output, ..) => complete = Some(output)
        BoundedSequenceMatchFailed(_, ..) => fail("unexpected sequence failure")
        BoundedSequenceMatchStopped(_, ..) => fail("unexpected sequence stop")
      }
    }
    assert_eq(completed_row_count(complete.unwrap()), 2)
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  }
}

///|
test "bounded sequence match accepts an empty input" {
  let (_, execution, _) = bounded_sequence_fixture(empty=true)
  let mut complete : CompletedOutput? = None
  while complete is None {
    match advance_bounded_sequence_match(execution, 1).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      BoundedSequenceMatchComplete(output, ..) => complete = Some(output)
      BoundedSequenceMatchFailed(_, ..) => fail("unexpected sequence failure")
      BoundedSequenceMatchStopped(_, ..) => fail("unexpected sequence stop")
    }
  }
  assert_eq(completed_row_count(complete.unwrap()), 0)
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
}

///|
test "bounded sequence match supports the global partition" {
  let (_, execution, _) = bounded_sequence_fixture(grouped=false)
  let mut complete : CompletedOutput? = None
  while complete is None {
    match advance_bounded_sequence_match(execution, 2).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      BoundedSequenceMatchComplete(output, ..) => complete = Some(output)
      BoundedSequenceMatchFailed(_, ..) => fail("unexpected sequence failure")
      BoundedSequenceMatchStopped(_, ..) => fail("unexpected sequence stop")
    }
  }
  assert_eq(completed_row_count(complete.unwrap()), 4)
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
}
