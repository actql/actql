///|
fn bounded_set_fixture(
  operation? : String = "except",
  duplicates? : String = "all",
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  right_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  left_rows? : String = "[{\"id\":1},{\"id\":2}]",
  right_rows? : String = "[{\"id\":3}]",
  input_nodes? : Int = 1000,
  max_rows? : Int = 3,
) -> (
  @bounded.Control,
  Result[BoundedSetExecution, BoundedSetIssue],
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
    input_cursor(
      "[{\"from\":\"l\",\"" +
      operation +
      "\":{\"with\":\"r\",\"duplicates\":\"" +
      duplicates +
      "\"}}]",
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
    [operation + "_0"],
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
  let execution = start_bounded_set(
    control,
    generated,
    left,
    right,
    max_rows,
    {
      max_nodes: input_nodes,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    },
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    1000,
  )
  (control, execution, [left, right])
}

///|
fn drive_bounded_set(execution : BoundedSetExecution) -> BoundedSetPoll {
  for _ in 0..<100000 {
    match advance_bounded_set(execution, 1) {
      Ok(BoundedSetContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) => return BoundedSetFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedSetFailed(InvalidExecution, progress=0L, work=0L)
}

///|
fn bounded_set_ids(output : CompletedOutput) -> Array[String] {
  Array::makei(completed_row_count(output), row => {
    match completed_cell(output, row, 0) {
      Some(Number(value)) => value.to_string()
      Some(Text(value)) => value
      Some(Null) => "null"
      _ => "?"
    }
  })
}

///|
test "bounded set matches the synchronous survivors for every variant" {
  let left = "[{\"id\":1},{\"id\":1},{\"id\":2},{\"id\":3},{\"id\":1}]"
  let right = "[{\"id\":1},{\"id\":3},{\"id\":4}]"
  for
    case in [
      ("except", "all", ["1", "1", "2"]),
      ("intersect", "all", ["1", "3"]),
      ("except", "distinct", ["2"]),
      ("intersect", "distinct", ["1", "3"]),
    ] {
    let (operation, duplicates, expected) = case
    let (_, started, _) = bounded_set_fixture(
      operation~,
      duplicates~,
      left_rows=left,
      right_rows=right,
      max_rows=10,
      max_work=100000,
      max_entries=1000,
    )
    let execution = started.unwrap()
    match drive_bounded_set(execution) {
      BoundedSetComplete(output, ..) =>
        assert_eq(bounded_set_ids(output), expected)
      _ => fail("bounded set did not complete")
    }
    assert_true(cleanup_bounded_set(execution).unwrap())
  }
}

///|
test "bounded set compares long text one byte per advance" {
  let schema = "{\"id\":{\"type\":\"string\",\"nullable\":false}}"
  let long = "x".repeat(200)
  let (_, started, _) = bounded_set_fixture(
    left_schema=schema,
    right_schema=schema,
    left_rows="[{\"id\":\"" + long + "a\"},{\"id\":\"" + long + "b\"}]",
    right_rows="[{\"id\":\"" + long + "b\"}]",
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  let mut previous = 0L
  let mut advances = 0
  let result = while true {
    advances += 1
    match advance_bounded_set(execution, 1).unwrap() {
      BoundedSetContinue(work~, ..) => {
        assert_true(work - previous <= 1L)
        previous = work
      }
      BoundedSetComplete(output, ..) => break bounded_set_ids(output)
      _ => fail("bounded text set did not complete")
    }
  } nobreak {
    []
  }
  assert_eq(result, [long + "a"])
  assert_true(advances > 400)
  assert_true(cleanup_bounded_set(execution).unwrap())
}

///|
test "bounded set admits exact work and rejects one unit short" {
  // Input admission for one left row with one number field (7); field id
  // entry and name bytes (3); one left seed coordinate (1); left merge sort
  // copy, end of copy and result (3); empty right sort (2); one keep flag
  // (1); one output row entry and cell (2).
  let exact_work = 19
  let (_, exact, _) = bounded_set_fixture(
    left_rows="[{\"id\":1}]",
    right_rows="[]",
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_set(exact) {
    BoundedSetComplete(output, ..) =>
      assert_eq(bounded_set_ids(output), ["1"])
    _ => fail("exact set work rejected")
  }
  assert_true(cleanup_bounded_set(exact).unwrap())
  let (_, short, _) = bounded_set_fixture(
    left_rows="[{\"id\":1}]",
    right_rows="[]",
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_set(short) {
    BoundedSetFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short set work accepted")
  }
  assert_true(cleanup_bounded_set(short).unwrap())
}

///|
test "bounded set stops after positive work without publishing" {
  let (control, started, reads) = bounded_set_fixture(
    left_rows="[{\"id\":3},{\"id\":1},{\"id\":2}]",
    right_rows="[{\"id\":2}]",
  )
  let execution = started.unwrap()
  for _ in 0..<15 {
    assert_true(
      advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_set(execution, 1).unwrap() is BoundedSetStopped(_, ..),
  )
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}
