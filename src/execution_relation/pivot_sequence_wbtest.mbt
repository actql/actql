///|
fn pivot_sequence_owner(body : String) -> @lower.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=true),
      ),
      (
        @schema.Unqualified("status"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=14,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  sort_input_owner(
    @pipeline.CarrierInput(carrier),
    "[{\"pivot\":" + body + "}]",
  )
}

///|
fn pivot_generated(owner : @lower.BoundPrepared) -> GeneratedSequence raise {
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["pivot_0"],
    100000,
    10000,
  ).unwrap()
}

///|
test "pivot count uses canonical groups and generated-column order" {
  let owner = pivot_sequence_owner(
    "{\"index\":[\"id\",\"id\"],\"column\":\"status\",\"values\":[\"won\",\"open\"],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"id\":2,\"status\":\"open\",\"amount\":20}"),
      input_cursor("{\"id\":1,\"status\":\"won\",\"amount\":10}"),
      input_cursor("{\"id\":2,\"status\":\"open\",\"amount\":30}"),
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":null}"),
      input_cursor("{\"id\":1,\"status\":\"other\",\"amount\":99}"),
      input_cursor("{\"id\":1,\"status\":null,\"amount\":5}"),
    ],
    max_rows=6,
    run_limits().input_values,
  ).unwrap()
  let completed = execute_generated_sequence(pivot_generated(owner), [input], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(0)).unwrap())
  assert_eq(table.names, ["id", "open", "won"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Number(0))
  assert_true(table.rows[0][2] is Number(1))
  assert_true(table.rows[1][0] is Number(2))
  assert_true(table.rows[1][1] is Number(2))
  assert_true(table.rows[1][2] is Number(0))
}

///|
test "pivot min fills empty buckets and ignores undeclared axes" {
  let owner = pivot_sequence_owner(
    "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"won\",\"open\"],\"value\":\"amount\",\"aggregate\":\"min\",\"fill\":0}",
  )
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":30}"),
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":20}"),
      input_cursor("{\"id\":2,\"status\":\"other\",\"amount\":10}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let completed = execute_generated_sequence(pivot_generated(owner), [input], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(0)).unwrap())
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][1] is Number(20))
  assert_true(table.rows[0][2] is Number(0))
  assert_true(table.rows[1][1] is Number(0))
  assert_true(table.rows[1][2] is Number(0))
}

///|
test "pivot max and first preserve their distinct aggregate laws" {
  let maximum = pivot_sequence_owner(
    "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"max\"}",
  )
  let input = capture_input(
    maximum,
    0,
    [
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":10}"),
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":30}"),
      input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":20}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let max_result = execute_generated_sequence(
    pivot_generated(maximum),
    [input],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
  ).unwrap()
  let max_table = test_row_output(
    completed_output(max_result, Step(0)).unwrap(),
  )
  assert_true(max_table.rows[0][1] is Number(30))

  let first = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"status\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"status\":\"open\",\"amount\":20},{\"id\":1,\"status\":\"open\",\"amount\":30},{\"id\":1,\"status\":\"open\",\"amount\":10}]},\"as\":\"seed\"},{\"from\":\"seed\",\"pivot\":{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"first\"}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(first),
    [],
    ["pivot_1"],
    100000,
    10000,
  ).unwrap()
  let first_result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let first_table = test_row_output(
    completed_output(first_result, Step(1)).unwrap(),
  )
  assert_eq(first_table.rows.length(), 2)
  assert_true(first_table.rows[0][0] is Number(1))
  assert_true(first_table.rows[0][1] is Number(30))
  assert_true(first_table.rows[1][0] is Number(2))
  assert_true(first_table.rows[1][1] is Number(20))
}

///|
test "empty pivot axes retain first index occurrence and global empty output" {
  let indexed = pivot_sequence_owner(
    "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let input = capture_input(
    indexed,
    0,
    [
      input_cursor("{\"id\":2,\"status\":\"open\",\"amount\":1}"),
      input_cursor("{\"id\":1,\"status\":\"won\",\"amount\":2}"),
      input_cursor("{\"id\":2,\"status\":null,\"amount\":3}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let first = execute_generated_sequence(pivot_generated(indexed), [input], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(first, Step(0)).unwrap())
  assert_eq(table.names, ["id"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(2))
  assert_true(table.rows[1][0] is Number(1))

  let global = pivot_sequence_owner(
    "{\"index\":[],\"column\":\"status\",\"values\":[],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let empty = capture_input(
    global,
    0,
    [],
    max_rows=0,
    run_limits().input_values,
  ).unwrap()
  let second = execute_generated_sequence(pivot_generated(global), [empty], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let empty_table = test_row_output(completed_output(second, Step(0)).unwrap())
  assert_eq(empty_table.names, [])
  assert_eq(empty_table.rows.length(), 1)
  assert_eq(empty_table.rows[0].length(), 0)
}

///|
test "pivot accepts exact shared work and rejects one-short execution" {
  let owner = pivot_sequence_owner(
    "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = pivot_generated(owner)
  let input = capture_input(
    owner,
    0,
    [input_cursor("{\"id\":1,\"status\":\"open\",\"amount\":10}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["pivot_0"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
  let exact : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: used,
    max_frames: 100,
  }
  assert_true(execute_generated_sequence(generated, [input], exact) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..exact,
      max_work: used - 1,
    })
    is Err(_),
  )
}
