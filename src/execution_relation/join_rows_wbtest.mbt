///|
fn join_test_sequence(
  left : String,
  right : String,
  options? : String = "",
  tail? : String = "",
) -> GeneratedSequence raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":true},\"v\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    left +
    "},\"as\":\"l\"}," +
    "{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    right +
    "},\"as\":\"r\"}," +
    "{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"k\":\"left.id\",\"l\":\"left.v\",\"r\":\"right.v\"}" +
    options +
    "},\"from\":\"l\"}" +
    tail +
    "]",
  )
  let sequence = prepared_sequence(owner)
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [if tail == "" { "join_2" } else { "group_3" }],
    100000,
    10000,
  ).unwrap()
}

///|
test "owned generated inner join executes both inputs and keeps duplicate pair order" {
  let generated = join_test_sequence(
    "[{\"id\":1,\"v\":10},{\"id\":1,\"v\":11},{\"id\":null,\"v\":12}]", "[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21},{\"id\":null,\"v\":22}]",
  )
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(2)).unwrap())
  assert_eq(table.names, ["k", "l", "r"])
  assert_eq(table.rows.length(), 4)
  for
    (index, l, r) in [
      (0, 10.0, 20.0),
      (1, 10.0, 21.0),
      (2, 11.0, 20.0),
      (3, 11.0, 21.0),
    ] {
    assert_true(table.rows[index][0] is Number(1))
    assert_true(table.rows[index][1] is Number(v) && v == l)
    assert_true(table.rows[index][2] is Number(v) && v == r)
  }
  assert_true(completed_output(result, Step(0)) is None)
  assert_true(completed_output(result, Step(1)) is None)
}

///|
test "join cardinality and null obligations run even when no pair can be emitted" {
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let duplicate = join_test_sequence(
    "[]",
    "[{\"id\":1,\"v\":1},{\"id\":1,\"v\":2}]",
    options=",\"cardinality\":\"many_to_one\"",
  )
  assert_true(
    execute_generated_sequence(duplicate, [], limits)
    is Err(Rows(2, JoinDuplicateKey(false, 1, 0))),
  )
  let nulls = "[{\"id\":null,\"v\":1},{\"id\":null,\"v\":2}]"
  let allowed = join_test_sequence(
    "[]",
    nulls,
    options=",\"cardinality\":\"many_to_one\"",
  )
  let result = execute_generated_sequence(allowed, [], limits).unwrap()
  assert_eq(completed_row_count(completed_output(result, Step(2)).unwrap()), 0)
  let rejected = join_test_sequence(
    "[]",
    nulls,
    options=",\"null_key\":\"fail\"",
  )
  assert_true(
    execute_generated_sequence(rejected, [], limits)
    is Err(Rows(2, JoinNullKey(false, 0, 0))),
  )
}

///|
test "join intermediate output guard cannot be hidden by a one row count result" {
  let rows = "[{\"id\":1,\"v\":1},{\"id\":1,\"v\":2}]"
  let tail = ",{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}"
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let rejected = join_test_sequence(
    rows,
    rows,
    options=",\"max_output_rows\":3",
    tail~,
  )
  assert_true(
    execute_generated_sequence(rejected, [], limits) is Err(Rows(2, RowLimit)),
  )
  let accepted = join_test_sequence(
    rows,
    rows,
    options=",\"max_output_rows\":4",
    tail~,
  )
  let output = completed_output(
    execute_generated_sequence(accepted, [], limits).unwrap(),
    Step(3),
  ).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(4)))
}
