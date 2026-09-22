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
  max_output_rows? : Int? = None,
  max_work? : Int = 100000,
) -> (@bounded.Control, BoundedSequenceMatchExecution, ProducerRead) raise {
  let (source_owner, source_output) = bounded_sequence_source(empty~)
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let output_guard = match max_output_rows {
    Some(limit) => ",\"max_output_rows\":" + limit.to_string()
    None => ""
  }
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
      "\"" +
      output_guard +
      "}}]",
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
    max_work,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
fn assert_bounded_sequence_scratch_reclaimed(
  execution : BoundedSequenceMatchExecution,
) -> Unit raise {
  let state = bounded_sequence_match_state(execution)
  assert_true(state.sort is None)
  assert_true(state.predicate_execution is None)
  assert_true(state.output is None)
  assert_eq(state.identity_order.length(), 0)
  assert_eq(state.ordered.length(), 0)
  assert_eq(state.clocks.length(), 0)
  assert_eq(state.predicates.length(), 0)
  assert_eq(state.selected.length(), 0)
  assert_eq(state.partials.length(), 0)
  assert_eq(state.row_matches.length(), 0)
  assert_eq(state.matches.length(), 0)
  assert_eq(state.predicate_input.length(), 0)
  assert_true(state.output_scope is None)
  assert_eq(state.output_row.length(), 0)
  assert_eq(state.checked_row.length(), 0)
  assert_eq(state.workspace.live, 0)
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
  assert_bounded_sequence_scratch_reclaimed(execution)
}

///|
test "bounded sequence match cancels without publishing partial rows" {
  let (control, execution, input) = bounded_sequence_fixture()
  assert_eq(bounded_sequence_match_state(execution).predicate_entries.val, 0)
  match advance_bounded_sequence_match(execution, 8).unwrap() {
    BoundedSequenceMatchContinue(..) => ()
    _ => fail("expected partial sequence progress")
  }
  assert_true(bounded_sequence_match_state(execution).predicate_entries.val > 0)
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_sequence_match(execution, 1).unwrap() {
    BoundedSequenceMatchStopped(@bounded.Cancelled, ..) => ()
    _ => fail("expected bounded sequence cancellation")
  }
  assert_true(producer_read_available(input))
  assert_true(bounded_sequence_match_cleanup_pending(execution))
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_false(bounded_sequence_match_cleanup_pending(execution))
  assert_eq(bounded_sequence_match_state(execution).predicate_entries.val, 0)
  assert_bounded_sequence_scratch_reclaimed(execution)
}

///|
test "bounded sequence output-limit failure reclaims all scratch" {
  let (_, execution, _) = bounded_sequence_fixture(max_output_rows=Some(2))
  let mut failed = false
  while !failed {
    match advance_bounded_sequence_match(execution, 2).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      BoundedSequenceMatchFailed(Rows(RowLimit), ..) => failed = true
      _ => fail("expected atomic sequence output-limit failure")
    }
  }
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_bounded_sequence_scratch_reclaimed(execution)
}

///|
fn finish_bounded_sequence(
  execution : BoundedSequenceMatchExecution,
) -> BoundedSequenceMatchPoll {
  while true {
    match advance_bounded_sequence_match(execution, 1000).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      terminal => return terminal
    }
  }
  abort("unreachable")
}

///|
test "bounded sequence work boundary charges output before row allocation" {
  let maximum = 100000
  let (_, measured, _) = bounded_sequence_fixture(max_work=maximum)
  assert_true(
    finish_bounded_sequence(measured) is BoundedSequenceMatchComplete(_, ..),
  )
  let required = maximum -
    bounded_sequence_match_state(measured).control.remaining
  assert_true(required > 0)
  cleanup_bounded_sequence_match(measured).unwrap() |> ignore

  let (_, exact, _) = bounded_sequence_fixture(max_work=required)
  assert_true(
    finish_bounded_sequence(exact) is BoundedSequenceMatchComplete(_, ..),
  )
  cleanup_bounded_sequence_match(exact).unwrap() |> ignore

  let (_, short, _) = bounded_sequence_fixture(max_work=required - 1)
  match finish_bounded_sequence(short) {
    BoundedSequenceMatchFailed(Rows(RowLimit), ..) => ()
    BoundedSequenceMatchFailed(InvalidExecution, ..) =>
      fail("work exhaustion was misclassified as invalid execution")
    BoundedSequenceMatchFailed(_, ..) => fail("unexpected sequence failure")
    BoundedSequenceMatchComplete(_, ..) => fail("short work budget completed")
    BoundedSequenceMatchStopped(_, ..) => fail("short work budget stopped")
    BoundedSequenceMatchContinue(..) => fail("terminal helper continued")
  }
  cleanup_bounded_sequence_match(short).unwrap() |> ignore
  assert_bounded_sequence_scratch_reclaimed(short)
}

///|
test "bounded sequence cancellation precedes predicate initialization" {
  let (control, execution, _) = bounded_sequence_fixture()
  assert_eq(bounded_sequence_match_state(execution).predicate_entries.val, 0)
  assert_true(@bounded.request_cancel(control))
  match advance_bounded_sequence_match(execution, 1).unwrap() {
    BoundedSequenceMatchStopped(@bounded.Cancelled, progress=0L, work=0L) => ()
    _ => fail("expected cancellation before predicate initialization")
  }
  assert_eq(bounded_sequence_match_state(execution).predicate_entries.val, 0)
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_eq(bounded_sequence_match_state(execution).predicate_entries.val, 0)
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
