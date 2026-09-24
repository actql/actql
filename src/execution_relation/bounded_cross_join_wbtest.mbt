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
  input_nodes? : Int = 1000,
  input_text? : Int = 10000,
  left_rows? : String = "[{\"id\":1},{\"id\":2}]",
  right_rows? : String = "[{\"tag\":\"a\"},{\"tag\":\"b\"}]",
  self_source? : Bool = false,
) -> (
  @bounded.Control,
  Result[BoundedCrossJoinExecution, BoundedCrossJoinIssue],
  Array[ProducerRead],
) raise {
  let (left_owner, left_output) = if self_source {
    bounded_cross_source(
      "{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}}",
      "[{\"id\":1,\"tag\":\"a\"},{\"id\":2,\"tag\":\"b\"}]",
    )
  } else {
    bounded_cross_source(
      "{\"id\":{\"type\":\"number\",\"nullable\":false}}", left_rows,
    )
  }
  let (right_owner, right_output) = if self_source {
    (left_owner, left_output)
  } else {
    bounded_cross_source(
      "{\"tag\":{\"type\":\"string\",\"nullable\":false}}", right_rows,
    )
  }
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
    {
      max_nodes: input_nodes,
      max_text_bytes: input_text,
      max_depth: 100,
      max_work: 10000,
    },
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  )
  (control, execution, [left, right])
}

///|
test "bounded cross join admits both inputs before producing pairs" {
  let (_, zero, _) = bounded_cross_fixture(input_nodes=0)
  let rejected = zero.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_cross_join(rejected, 1).unwrap() {
        BoundedCrossJoinFailed(InputLimit, ..) => failed = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("zero input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
  let (_, exact, _) = bounded_cross_fixture(input_nodes=8)
  let admitted = exact.unwrap()
  let mut complete = false
  for _ in 0..<100 {
    if !complete {
      match advance_bounded_cross_join(admitted, 1).unwrap() {
        BoundedCrossJoinComplete(_, ..) => complete = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("exact input budget rejected")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_cross_join(admitted).unwrap())
  let (_, short, _) = bounded_cross_fixture(input_nodes=7)
  let rejected = short.unwrap()
  failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_cross_join(rejected, 1).unwrap() {
        BoundedCrossJoinFailed(InputLimit, ..) => failed = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("one-short input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
}

///|
test "bounded cross join validates a nonempty input with empty output" {
  let (_, started, _) = bounded_cross_fixture(right_rows="[]", input_nodes=3)
  let execution = started.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_cross_join(execution, 1).unwrap() {
        BoundedCrossJoinFailed(InputLimit, ..) => failed = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("empty output bypassed input admission")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  let (_, started, _) = bounded_cross_fixture(right_rows="[]", input_nodes=4)
  let execution = started.unwrap()
  let mut complete = false
  let mut polls = 0
  while !complete && polls < 100 {
    polls += 1
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinComplete(output, ..) => {
        assert_eq(completed_row_count(output), 0)
        complete = true
      }
      BoundedCrossJoinContinue(..) => ()
      _ => fail("valid empty output rejected")
    }
  }
  assert_true(complete)
  assert_true(polls < 30)
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
}

///|
test "bounded cross join charges input field and text bytes" {
  let (_, short, _) = bounded_cross_fixture(
    right_rows="[{\"tag\":\"abcdefgh\"},{\"tag\":\"b\"}]",
    input_text=18,
  )
  let rejected = short.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_cross_join(rejected, 1).unwrap() {
        BoundedCrossJoinFailed(InputLimit, ..) => failed = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("one-short text budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
  let (_, exact, _) = bounded_cross_fixture(
    right_rows="[{\"tag\":\"abcdefgh\"},{\"tag\":\"b\"}]",
    input_text=19,
  )
  let execution = exact.unwrap()
  let mut complete = false
  for _ in 0..<100 {
    if !complete {
      match advance_bounded_cross_join(execution, 1).unwrap() {
        BoundedCrossJoinComplete(_, ..) => complete = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("exact text budget rejected")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
}

///|
test "bounded cross join scans long text across resumptions" {
  let mut tag = ""
  for _ in 0..<256 {
    tag += "x"
  }
  let (_, started, _) = bounded_cross_fixture(
    left_rows="[{\"id\":1}]",
    right_rows="[{\"tag\":\"" + tag + "\"}]",
    input_text=261,
  )
  let execution = started.unwrap()
  let mut polls = 0
  let mut complete = false
  let mut prior_work = 0L
  while !complete && polls < 400 {
    polls += 1
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinContinue(work~, ..) => {
        assert_true(work - prior_work <= 1L)
        prior_work = work
      }
      BoundedCrossJoinComplete(output, work~, ..) => {
        assert_true(work - prior_work <= 1L)
        assert_eq(completed_row_count(output), 1)
        complete = true
      }
      _ => fail("long input text did not complete")
    }
  }
  assert_true(complete)
  assert_true(polls > 256)
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
}

///|
test "bounded self cross charges each input position" {
  let (_, exact, inputs) = bounded_cross_fixture(
    self_source=true,
    input_nodes=12,
  )
  let execution = exact.unwrap()
  let mut complete = false
  for _ in 0..<150 {
    if !complete {
      match advance_bounded_cross_join(execution, 1).unwrap() {
        BoundedCrossJoinComplete(output, ..) => {
          assert_eq(completed_row_count(output), 4)
          complete = true
        }
        BoundedCrossJoinContinue(..) => ()
        _ => fail("exact self-cross input budget rejected")
      }
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
  let (_, short, _) = bounded_cross_fixture(self_source=true, input_nodes=11)
  let rejected = short.unwrap()
  let mut failed = false
  for _ in 0..<150 {
    if !failed {
      match advance_bounded_cross_join(rejected, 1).unwrap() {
        BoundedCrossJoinFailed(InputLimit, ..) => failed = true
        BoundedCrossJoinContinue(..) => ()
        _ => fail("one-short self-cross input budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_cross_join(rejected).unwrap())
}

///|
test "bounded cross join advances empty and singleton sides at quantum one" {
  for variant in 0..<3 {
    let left_rows = if variant < 2 { "[]" } else { "[{\"id\":1},{\"id\":2}]" }
    let right_rows = if variant == 1 {
      "[]"
    } else if variant == 2 {
      "[{\"tag\":\"a\"}]"
    } else {
      "[{\"tag\":\"a\"},{\"tag\":\"b\"}]"
    }
    let nodes = if variant == 1 { 0 } else if variant == 2 { 6 } else { 4 }
    let expected = if variant == 2 { 2 } else { 0 }
    let (_, started, _) = bounded_cross_fixture(
      left_rows~,
      right_rows~,
      input_nodes=nodes,
    )
    let execution = started.unwrap()
    let mut complete = false
    let mut polls = 0
    let mut prior_work = 0L
    while !complete && polls < 100 {
      polls += 1
      match advance_bounded_cross_join(execution, 1).unwrap() {
        BoundedCrossJoinContinue(work~, ..) => {
          assert_true(work - prior_work <= 1L)
          prior_work = work
        }
        BoundedCrossJoinComplete(output, work~, ..) => {
          assert_true(work - prior_work <= 1L)
          assert_eq(completed_row_count(output), expected)
          complete = true
        }
        _ => fail("empty or singleton cross join did not progress")
      }
    }
    assert_true(complete)
    assert_true(cleanup_bounded_cross_join(execution).unwrap())
  }
}

///|
test "bounded cross join stops and reclaims during input admission" {
  let (control, started, inputs) = bounded_cross_fixture()
  let execution = started.unwrap()
  match advance_bounded_cross_join(execution, 1).unwrap() {
    BoundedCrossJoinContinue(progress~, work~) => {
      assert_eq(progress, 0L)
      assert_eq(work, 1L)
    }
    _ => fail("input admission did not yield")
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_cross_join(execution, 1).unwrap()
    is BoundedCrossJoinStopped(_),
  )
  assert_true(cleanup_bounded_cross_join(execution).unwrap())
  assert_true(producer_read_available(inputs[0]))
  assert_true(producer_read_available(inputs[1]))
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
  // each charge one begin step and two checked cells: 14 + 12.
  // Input admission adds 26 row, field and text transitions: 52 total.
  let (_, exact, _) = bounded_cross_fixture(max_work=52)
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
  let (_, short, _) = bounded_cross_fixture(max_work=51)
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
