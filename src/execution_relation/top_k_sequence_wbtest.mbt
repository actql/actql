///|
fn execute_top_k(
  owner : @lower.BoundPrepared,
  rows : Array[@decode.Cursor],
) -> CompletedSequence raise {
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    rows,
    max_rows=rows.length(),
    run_limits().input_values,
  ).unwrap()
  execute_generated_sequence(generated, [input], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
}

///|
fn nullable_partition_top_k_owner() -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("group"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("score"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=3,
    max_name_bytes=12,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  sort_input_owner(
    @pipeline.KeyedInput(key),
    "[{\"top_k_by\":{\"partition_by\":[\"group\"],\"k\":1,\"by\":[{\"score\":\"desc\"}]}}]",
  )
}

///|
test "global top-k executes its completed total order as one owned operation" {
  let owner = take_key_owner("[{\"top_k\":{\"k\":2,\"by\":[{\"s\":\"asc\"}]}}]")
  let result = execute_top_k(owner, [
    input_cursor("{\"n\":3,\"s\":\"b\"}"),
    input_cursor("{\"n\":2,\"s\":\"a\"}"),
    input_cursor("{\"n\":1,\"s\":\"a\"}"),
    input_cursor("{\"n\":4,\"s\":\"b\"}"),
  ])
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[1][0] is Number(2))
  assert_true(table.rows[0][1] is Text("a"))
  assert_true(table.rows[1][1] is Text("a"))
}

///|
test "partitioned top-k retains repeated and empty partition occurrences" {
  let rows = [
    input_cursor("{\"n\":3,\"s\":\"b\"}"),
    input_cursor("{\"n\":2,\"s\":\"a\"}"),
    input_cursor("{\"n\":1,\"s\":\"a\"}"),
    input_cursor("{\"n\":4,\"s\":\"b\"}"),
  ]
  let partitioned = take_key_owner(
    "[{\"top_k_by\":{\"partition_by\":[\"s\",\"s\"],\"k\":1,\"by\":[{\"n\":\"desc\"}]}}]",
  )
  let selected = test_row_output(
    completed_output(execute_top_k(partitioned, rows), Step(0)).unwrap(),
  )
  assert_eq(selected.rows.length(), 2)
  assert_true(selected.rows[0][0] is Number(2))
  assert_true(selected.rows[0][1] is Text("a"))
  assert_true(selected.rows[1][0] is Number(4))
  assert_true(selected.rows[1][1] is Text("b"))

  let global_partition = take_key_owner(
    "[{\"top_k_by\":{\"partition_by\":[],\"k\":2,\"by\":[{\"n\":\"desc\"}]}}]",
  )
  let global = test_row_output(
    completed_output(execute_top_k(global_partition, rows), Step(0)).unwrap(),
  )
  assert_eq(global.rows.length(), 2)
  assert_true(global.rows[0][0] is Number(4))
  assert_true(global.rows[1][0] is Number(3))
}

///|
test "partitioned top-k orders nullable partitions canonically before ranking" {
  let owner = nullable_partition_top_k_owner()
  let selected = test_row_output(
    completed_output(
      execute_top_k(owner, [
        input_cursor("{\"group\":\"b\",\"id\":1,\"score\":2}"),
        input_cursor("{\"group\":null,\"id\":2,\"score\":3}"),
        input_cursor("{\"group\":\"a\",\"id\":3,\"score\":1}"),
        input_cursor("{\"group\":null,\"id\":4,\"score\":4}"),
        input_cursor("{\"group\":\"a\",\"id\":5,\"score\":5}"),
      ]),
      Step(0),
    ).unwrap(),
  )
  assert_eq(selected.names, ["group", "id", "score"])
  assert_eq(selected.rows.length(), 3)
  assert_true(selected.rows[0][0] is Null)
  assert_true(selected.rows[0][1] is Number(4))
  assert_true(selected.rows[1][0] is Text("a"))
  assert_true(selected.rows[1][1] is Number(5))
  assert_true(selected.rows[2][0] is Text("b"))
  assert_true(selected.rows[2][1] is Number(1))
}

///|
test "top-k validates the complete supplied key before prefix selection" {
  let owner = take_key_owner("[{\"top_k\":{\"k\":1,\"by\":[{\"s\":\"asc\"}]}}]")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["top_k_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"first\"}"),
      input_cursor("{\"n\":9,\"s\":\"last\"}"),
      input_cursor("{\"n\":9,\"s\":\"duplicate outside top-k\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    execute_generated_sequence(generated, [input], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(InputKey(0, _)),
  )
}

///|
test "top-k shares one execution budget and accepts the exact boundary" {
  let owner = take_key_owner("[{\"top_k\":{\"k\":1,\"by\":[{\"s\":\"asc\"}]}}]")
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["top_k_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":2,\"s\":\"b\"}"),
      input_cursor("{\"n\":1,\"s\":\"a\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["top_k_0"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: used,
    max_frames: 100,
  }
  assert_true(execute_generated_sequence(generated, [input], limits) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..limits,
      max_work: used - 1,
    })
    is Err(_),
  )
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..limits,
      rows: { ..limits.rows, operation_entries: 0, },
    })
    is Err(_),
  )
  assert_true(execute_generated_sequence(generated, [input], limits) is Ok(_))
}
