///|
fn bounded_sequence_source(
  empty? : Bool = false,
  unicode? : Bool = false,
  extra_columns? : Int = 0,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  if extra_columns < 0 || (extra_columns > 0 && !empty) {
    fail("wide sequence source requires empty rows")
  }
  let key = if unicode { "clé" } else { "key" }
  let mut extra_schema = ""
  for index in 0..<extra_columns {
    extra_schema += ",\"z" +
      index.to_string() +
      "\":{\"type\":\"number\",\"nullable\":false}"
  }
  let rows = if empty {
    "[]"
  } else {
    "[{\"id\":3,\"" +
    key +
    "\":1,\"clock\":3,\"value\":2}," +
    "{\"id\":1,\"" +
    key +
    "\":1,\"clock\":1,\"value\":1}," +
    "{\"id\":4,\"" +
    key +
    "\":2,\"clock\":4,\"value\":2}," +
    "{\"id\":2,\"" +
    key +
    "\":1,\"clock\":2,\"value\":2}," +
    "{\"id\":5,\"" +
    key +
    "\":2,\"clock\":3,\"value\":1}]"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"" +
    key +
    "\":{\"type\":\"number\",\"nullable\":false}," +
    "\"clock\":{\"type\":\"number\",\"nullable\":false}," +
    "\"value\":{\"type\":\"number\",\"nullable\":false}" +
    extra_schema +
    "}," +
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
fn bounded_sequence_try_fixture(
  overlap? : String = "allow",
  contiguity? : String = "subsequence",
  empty? : Bool = false,
  grouped? : Bool = true,
  max_output_rows? : Int? = None,
  max_work? : Int = 100000,
  max_rows? : Int = 100,
  max_entries? : Int = 10000,
  unicode? : Bool = false,
  extra_columns? : Int = 0,
) -> (
  @bounded.Control,
  Result[BoundedSequenceMatchExecution, BoundedSequenceMatchIssue],
  ProducerRead,
) raise {
  let (source_owner, source_output) = bounded_sequence_source(
    empty~,
    unicode~,
    extra_columns~,
  )
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let output_guard = match max_output_rows {
    Some(limit) => ",\"max_output_rows\":" + limit.to_string()
    None => ""
  }
  let key = if unicode { "clé" } else { "key" }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"events\",\"sequence\":{\"by\":" +
      (if grouped { "[\"" + key + "\"]" } else { "[]" }) +
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
    10000,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_sequence_match(
    control,
    generated,
    input,
    max_rows,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  )
  (control, execution, input)
}

///|
fn bounded_sequence_fixture(
  overlap? : String = "allow",
  contiguity? : String = "subsequence",
  empty? : Bool = false,
  grouped? : Bool = true,
  max_output_rows? : Int? = None,
  max_work? : Int = 100000,
  max_rows? : Int = 100,
  max_entries? : Int = 10000,
  unicode? : Bool = false,
) -> (@bounded.Control, BoundedSequenceMatchExecution, ProducerRead) raise {
  let (control, execution, input) = bounded_sequence_try_fixture(
    overlap~,
    contiguity~,
    empty~,
    grouped~,
    max_output_rows~,
    max_work~,
    max_rows~,
    max_entries~,
    unicode~,
  )
  (control, execution.unwrap(), input)
}

///|
fn assert_bounded_sequence_scratch_reclaimed(
  execution : BoundedSequenceMatchExecution,
) -> Unit raise {
  let state = bounded_sequence_match_state(execution)
  assert_eq(state.input_names.length(), 0)
  assert_eq(state.key_columns.length(), 0)
  assert_eq(state.output_names.length(), 0)
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
  let mut reached_predicates = false
  for _ in 0..<64 {
    if bounded_sequence_match_state(execution).predicate_entries.val > 0 {
      reached_predicates = true
      break
    }
    match advance_bounded_sequence_match(execution, 1).unwrap() {
      BoundedSequenceMatchContinue(..) => ()
      _ => fail("expected partial sequence progress")
    }
  }
  assert_true(reached_predicates)
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
test "bounded sequence admits exact and one-short workspace" {
  // The five-row, two-pattern fixture starts with 29 metadata slots:
  // four input names, one group key, five clocks, two pattern containers,
  // ten predicate cells, and seven output names. During output, five
  // ordered indices and three two-position matches add 14 more slots.
  // The charged output row and checked copy add eight and seven slots,
  // respectively, for a 58-slot peak.
  let (_, early, _) = bounded_sequence_try_fixture(max_entries=28)
  assert_true(early is Err(Rows(RowLimit)))
  let (control, admitted, input) = bounded_sequence_try_fixture(max_entries=29)
  let admitted = admitted.unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_sequence_match(admitted, 1).unwrap()
    is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
  )
  assert_true(cleanup_bounded_sequence_match(admitted).unwrap())
  assert_true(producer_read_available(input))

  let (_, exact, _) = bounded_sequence_fixture(max_entries=58)
  assert_true(
    finish_bounded_sequence(exact) is BoundedSequenceMatchComplete(_, ..),
  )
  assert_eq(bounded_sequence_match_state(exact).workspace.peak, 58)
  assert_true(cleanup_bounded_sequence_match(exact).unwrap())
  assert_bounded_sequence_scratch_reclaimed(exact)

  let (_, short, input) = bounded_sequence_fixture(max_entries=57)
  assert_true(
    finish_bounded_sequence(short)
    is BoundedSequenceMatchFailed(Rows(RowLimit), ..),
  )
  assert_true(producer_read_available(input))
  assert_true(bounded_sequence_match_cleanup_pending(short))
  assert_true(cleanup_bounded_sequence_match(short).unwrap())
  assert_bounded_sequence_scratch_reclaimed(short)
}

///|
test "bounded sequence resolves columns in charged resumable steps" {
  // The four-column schema probes key=22, id=13, and clock=11 units.
  // Without a key, only id and clock are demanded. The UTF-8 key adds
  // four units across its three comparisons.
  for
    (grouped, unicode, required) in [
      (true, false, 46),
      (false, false, 24),
      (true, true, 50),
    ] {
    for (budget, admitted) in [(required - 1, false), (required, true)] {
      let (control, result, input) = bounded_sequence_try_fixture(
        empty=true,
        grouped~,
        unicode~,
        max_work=budget,
      )
      let execution = result.unwrap()
      let state = bounded_sequence_match_state(execution)
      assert_eq(state.input_names.length(), 0)
      assert_eq(state.resolve_field, 0)
      assert_eq(state.control.remaining, budget)
      let mut resolved = false
      let mut failed = false
      for _ in 0..<64 {
        if state.resolve_field ==
          @lower.sequence_match_key_count(state.kernel) + 2 {
          resolved = true
          break
        }
        match advance_bounded_sequence_match(execution, 1).unwrap() {
          BoundedSequenceMatchContinue(..) => ()
          BoundedSequenceMatchFailed(Rows(RowLimit), ..) => {
            failed = true
            break
          }
          _ => fail("unexpected sequence column resolution result")
        }
      }
      assert_eq(resolved, admitted)
      assert_eq(failed, !admitted)
      if admitted {
        assert_eq(state.control.remaining, 0)
        assert_true(@bounded.request_cancel(control))
        assert_true(
          advance_bounded_sequence_match(execution, 1).unwrap()
          is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
        )
      }
      assert_true(cleanup_bounded_sequence_match(execution).unwrap())
      assert_true(producer_read_available(input))
      assert_bounded_sequence_scratch_reclaimed(execution)
    }
  }
}

///|
test "bounded sequence stops during wide input-name initialization" {
  let (control, result, input) = bounded_sequence_try_fixture(
    empty=true,
    extra_columns=32,
  )
  let execution = result.unwrap()
  let state = bounded_sequence_match_state(execution)
  assert_eq(state.input_names.length(), 0)
  assert_eq(state.control.remaining, 100000)
  for loaded in 1..<=20 {
    match advance_bounded_sequence_match(execution, 1).unwrap() {
      BoundedSequenceMatchContinue(progress~, work~) => {
        assert_eq(progress, loaded.to_int64())
        assert_eq(work, loaded.to_int64())
      }
      _ => fail("wide sequence initialization did not yield")
    }
    assert_eq(state.input_names.length(), loaded)
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_sequence_match(execution, 1).unwrap()
    is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
  )
  assert_true(cleanup_bounded_sequence_match(execution).unwrap())
  assert_true(producer_read_available(input))
  assert_bounded_sequence_scratch_reclaimed(execution)
}

///|
test "bounded sequence input row limit is a resource error" {
  let (_, result, _) = bounded_sequence_try_fixture(max_rows=4)
  assert_true(result is Err(Rows(RowLimit)))
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
