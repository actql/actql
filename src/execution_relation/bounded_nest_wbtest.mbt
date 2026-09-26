///|
fn bounded_nest_fixture(
  nest? : String = "\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":3",
  grouped_bytes? : Int64 = 10000L,
  attached_bytes? : Int64 = 10000L,
  max_work? : Int = 1000,
  max_entries? : Int = 100,
  left_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true}}",
  right_schema? : String = "{\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"number\",\"nullable\":true}}",
  left_rows? : String = "[{\"id\":1,\"key\":1},{\"id\":2,\"key\":1},{\"id\":3,\"key\":null},{\"id\":4,\"key\":2}]",
  right_rows? : String = "[{\"key\":1,\"value\":null},{\"key\":1,\"value\":10},{\"key\":null,\"value\":30}]",
  input_nodes? : Int = 1000,
  max_rows? : Int = 10,
) -> (
  @bounded.Control,
  Result[BoundedNestExecution, BoundedNestIssue],
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
    input_cursor("[{\"from\":\"l\",\"nest\":{\"with\":\"r\"," + nest + "}}]"),
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
    ["nest_0"],
    10000,
    1000,
  ).unwrap()
  let generated = constrain_generated_aggregate_output(
    generated,
    0,
    "items",
    NestGroupedBytes,
    grouped_bytes,
  ).unwrap()
  let generated = constrain_generated_aggregate_output(
    generated,
    0,
    "items",
    NestAttachedBytes,
    attached_bytes,
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
  let execution = start_bounded_nest(
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
fn drive_bounded_nest(execution : BoundedNestExecution) -> BoundedNestPoll {
  for _ in 0..<100000 {
    match advance_bounded_nest(execution, 1) {
      Ok(BoundedNestContinue(..)) => ()
      Ok(poll) => return poll
      Err(_) => return BoundedNestFailed(InvalidExecution, progress=0L, work=0L)
    }
  }
  BoundedNestFailed(InvalidExecution, progress=0L, work=0L)
}

///|
fn bounded_nest_item_counts(output : CompletedOutput) -> Array[Int] {
  let column = Array::makei(completed_column_count(output), index => {
      completed_column_name(output, index).unwrap()
    })
    .search("items")
    .unwrap()
  Array::makei(completed_row_count(output), row => {
    match completed_cell(output, row, column) {
      Some(Captured(@admitted.Array(items))) => @admitted.element_count(items)
      _ => -1
    }
  })
}

///|
test "bounded nest groups parents in order and never matches NULL keys" {
  let (_, started, reads) = bounded_nest_fixture(
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  match drive_bounded_nest(execution) {
    BoundedNestComplete(output, ..) =>
      assert_eq(bounded_nest_item_counts(output), [2, 2, 0, 0])
    _ => fail("bounded nest did not complete")
  }
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded nest enforces the per-parent item limit" {
  let (_, started, _) = bounded_nest_fixture(
    nest="\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":1",
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  assert_true(
    drive_bounded_nest(execution)
    is BoundedNestFailed(Rows(NestItemLimit(0)), ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
}

///|
test "bounded nest enforces the grouped byte envelope" {
  let (_, started, _) = bounded_nest_fixture(
    grouped_bytes=1L,
    max_work=100000,
    max_entries=1000,
  )
  let execution = started.unwrap()
  assert_true(
    drive_bounded_nest(execution)
    is BoundedNestFailed(Rows(NestEnvelope(GroupedBytes)), ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
}

///|
test "bounded nest stops after positive work without publishing" {
  let (control, started, reads) = bounded_nest_fixture()
  let execution = started.unwrap()
  for _ in 0..<40 {
    assert_true(
      advance_bounded_nest(execution, 1).unwrap() is BoundedNestContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_nest(execution, 1).unwrap() is BoundedNestStopped(_, ..),
  )
  assert_true(cleanup_bounded_nest(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded nest admits exact work and rejects one unit short" {
  // Input admission, per row 1 and per field 1 + name bytes + 1 value
  // (10 parent, 13 child); key `key`: entry 1 and name scans over parent
  // `id` (6) and `key` (7) and child `key` (7): 21; field `value`: entry 1
  // and scans over `key` (9) and `value` (11): 21; output names and parent
  // resolution: `id` 2 + 5, `key` 3 + 13, `items` 5: 28; child seed 1 and
  // sort 3; parent entry 1; one search and one match comparison 2; row
  // charge for one item, three names and the row 5; item entry 1; nested
  // measurement: array 1, object 1, key `amount` 6, number 1: 9. Total 115.
  let exact_work = 115
  let left = "[{\"id\":1,\"key\":1}]"
  let right = "[{\"key\":1,\"value\":5}]"
  let (_, exact, _) = bounded_nest_fixture(
    left_rows=left,
    right_rows=right,
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_nest(exact) {
    BoundedNestComplete(output, ..) =>
      assert_eq(bounded_nest_item_counts(output), [1])
    _ => fail("exact nest work rejected")
  }
  assert_true(cleanup_bounded_nest(exact).unwrap())
  let (_, short, _) = bounded_nest_fixture(
    left_rows=left,
    right_rows=right,
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_nest(short) {
    BoundedNestFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short nest work accepted")
  }
  assert_true(cleanup_bounded_nest(short).unwrap())
}
