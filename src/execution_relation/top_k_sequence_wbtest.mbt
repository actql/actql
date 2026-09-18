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
fn top_k_contract_owner(
  partition : @contract.Contract,
  rank : @contract.Contract,
  payload : @contract.Contract,
  partitioned : Bool,
) -> @lower.BoundPrepared {
  let id = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), id),
      (@schema.Unqualified("partition"), partition),
      (@schema.Unqualified("rank"), rank),
      (@schema.Unqualified("payload"), payload),
    ],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 100,
  }).unwrap()
  sort_input_owner(
    @pipeline.KeyedInput(key),
    if partitioned {
      "[{\"top_k_by\":{\"partition_by\":[\"partition\"],\"k\":1," +
      "\"by\":[{\"rank\":\"desc\"}]}}]"
    } else {
      "[{\"top_k\":{\"k\":1,\"by\":[{\"rank\":\"desc\"}]}}]"
    },
  )
}

///|
fn run_top_k_contract_rows(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Result[Table, RowIssue] {
  let kernel = row_kernel(owner, 0)
  evaluate_rows(
    kernel,
    {
      owner,
      id: @lower.kernel_input(kernel),
      names: ["id", "partition", "rank", "payload"],
      rows,
    },
    rows.length(),
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
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

///|
test "top-k variants preserve every relation value payload domain" {
  let scalar = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
    ),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}", "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]", "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]", "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for partitioned in [false, true] {
    for (body, wire, kind) in cases {
      let payload = select_checked_contract(body)
      let live = Ref(true)
      let value = assertion_admitted_value(payload, wire, kind, live)
      let result = run_top_k_contract_rows(
        top_k_contract_owner(scalar, scalar, payload, partitioned),
        [[Number(1), Number(1), Number(1), value]],
      ).unwrap()
      assert_eq(result.rows.length(), 1)
      assert_true(append_value_equal(result.rows[0][3], value))
      live.val = false
    }
  }
}

///|
test "top-k variants order every author orderable domain" {
  let scalar = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"a\"", "\"é\""),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "2"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "\"2.30\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "false", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "\"2000-03-01T12:30:00.000Z\"",
    ),
    (
      "{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "\"2000-02-29\"",
    ),
  ]
  for partitioned in [false, true] {
    for (body, low_wire, high_wire) in cases {
      let rank = select_checked_contract(body)
      let live = Ref(true)
      let low = assertion_admitted_value(rank, low_wire, "ordinary", live)
      let high = assertion_admitted_value(rank, high_wire, "ordinary", live)
      let result = run_top_k_contract_rows(
        top_k_contract_owner(scalar, rank, scalar, partitioned),
        [
          [Number(1), Number(1), low, Number(10)],
          [Number(2), Number(1), high, Number(20)],
        ],
      ).unwrap()
      assert_eq(result.rows.length(), 1)
      assert_true(result.rows[0][3] is Number(20))
    }
  }
}

///|
test "partitioned top-k compares every key domain including owned references" {
  let scalar = select_checked_contract(
    "{\"type\":\"number\",\"nullable\":false}",
  )
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for (body, wire, kind) in cases {
    let partition = select_checked_contract(body)
    let live = Ref(true)
    let value = assertion_admitted_value(partition, wire, kind, live)
    let owner = top_k_contract_owner(partition, scalar, scalar, true)
    let rows = [
      [Number(1), value, Number(1), Number(10)],
      [Number(2), value, Number(2), Number(20)],
    ]
    let result = run_top_k_contract_rows(owner, rows).unwrap()
    assert_eq(result.rows.length(), 1)
    assert_true(result.rows[0][3] is Number(20))
    live.val = false
    if kind != "ordinary" {
      assert_true(
        run_top_k_contract_rows(owner, rows) is Err(Comparison(InvalidOperand)),
      )
    }
  }
}
