///|
fn nest_sequence_guard_with_bytes(
  max_items : String,
  grouped_bytes : Int64,
  attached_bytes : Int64,
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":1,\"key\":1},{\"id\":2,\"key\":1},{\"id\":3,\"key\":null},{\"id\":4,\"key\":2}]},\"as\":\"parents\"}," +
    "{\"values\":{\"schema\":{\"child_id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"child_id\":2,\"key\":1,\"value\":null},{\"child_id\":1,\"key\":1,\"value\":10},{\"child_id\":3,\"key\":null,\"value\":30}]},\"as\":\"children\"}," +
    "{\"from\":\"parents\",\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}]" +
    max_items +
    "},\"as\":\"nested\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["nest_2"],
    100000,
    10000,
  ).unwrap()
  let grouped = constrain_generated_aggregate_output(
    generated,
    2,
    "items",
    NestGroupedBytes,
    grouped_bytes,
  ).unwrap()
  constrain_generated_aggregate_output(
    grouped,
    2,
    "items",
    NestAttachedBytes,
    attached_bytes,
  ).unwrap()
}

///|
fn nest_sequence_guard(max_items : String) -> GeneratedSequence raise {
  nest_sequence_guard_with_bytes(max_items, 10000L, 10000L)
}

///|
fn nest_sequence(max_items : Int) -> GeneratedSequence raise {
  nest_sequence_guard(",\"max_items\":" + max_items.to_string())
}

///|
fn authored_order_nest_sequence() -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"key\":1}]},\"as\":\"parents\"}," +
    "{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false},\"position\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"key\":1,\"position\":0,\"value\":2},{\"key\":1,\"position\":1,\"value\":1},{\"key\":1,\"position\":2,\"value\":1}]},\"as\":\"children\"}," +
    "{\"from\":\"parents\",\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"},{\"position\":\"position\"}],\"order_by\":[{\"value\":\"asc\"}],\"max_items\":3},\"as\":\"nested\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["nest_2"],
    100000,
    10000,
  ).unwrap()
  let grouped = constrain_generated_aggregate_output(
    generated,
    2,
    "items",
    NestGroupedBytes,
    10000L,
  ).unwrap()
  constrain_generated_aggregate_output(
    grouped,
    2,
    "items",
    NestAttachedBytes,
    10000L,
  ).unwrap()
}

///|
fn nest_sibling_sequence(attached_bytes : Int64) -> GeneratedSequence raise {
  let source =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":false},"meta":{"type":"object","nullable":false,"fields":{"tag":{"type":"string","nullable":false}}}},"rows":[{"id":1,"key":1,"meta":{"tag":"x"}},{"id":2,"key":2,"meta":{"tag":"long"}}]},"as":"parents"},{"values":{"schema":{"key":{"type":"number","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"key":1,"value":10}]},"as":"children"},{"from":"parents","nest":{"with":"children","on":[{"left":"key","right":"key"}],"into":"items","fields":[{"amount":"value"}],"max_items":1},"as":"nested"}]
  let owner = bound_pipeline(source)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["nest_2"],
    100000,
    10000,
  ).unwrap()
  let items = constrain_generated_aggregate_output(
    generated,
    2,
    "items",
    ArrayItems,
    1L,
  ).unwrap()
  let grouped = constrain_generated_aggregate_output(
    items,
    2,
    "items",
    NestGroupedBytes,
    15L,
  ).unwrap()
  constrain_generated_aggregate_output(
    grouped,
    2,
    "items",
    NestAttachedBytes,
    attached_bytes,
  ).unwrap()
}

///|
fn nested_amounts(row : Array[Value]) -> Array[Value] raise {
  guard row[1] is Captured(@admitted.Array(items)) else { fail("nested array") }
  let output : Array[Value] = []
  for index in 0..<@admitted.element_count(items) {
    guard @admitted.element_at(items, index) is Some(@admitted.Object(fields)) &&
      @admitted.element_count(fields) == 1 &&
      @admitted.element_at(fields, 0) is Some(("amount", value)) else {
      fail("nested object")
    }
    output.push(capture(value))
  }
  output
}

///|
test "nest preserves parents child order NULL keys and empty arrays" {
  let completed = execute_generated_sequence(nest_sequence(2), [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_eq(table.names, ["id", "items", "key"])
  assert_eq(table.rows.length(), 4)
  for row in 0..<4 {
    assert_true(
      table.rows[row][0] is Number(number) && number == (row + 1).to_double(),
    )
  }
  let first = nested_amounts(table.rows[0])
  let second = nested_amounts(table.rows[1])
  assert_eq(first.length(), 2)
  assert_eq(second.length(), 2)
  assert_true(first[0] is Null)
  assert_true(first[1] is Number(10))
  assert_true(second[0] is Null)
  assert_true(second[1] is Number(10))
  assert_true(nested_amounts(table.rows[2]).is_empty())
  assert_true(nested_amounts(table.rows[3]).is_empty())
}

///|
test "nest authored order sorts values and preserves inherited ties" {
  let completed = execute_generated_sequence(
    authored_order_nest_sequence(),
    [],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
  ).unwrap()
  let table = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_eq(table.rows.length(), 1)
  guard table.rows[0][1] is Captured(@admitted.Array(items)) else {
    fail("nested array")
  }
  let expected = [(1.0, 1.0), (1.0, 2.0), (2.0, 0.0)]
  assert_eq(@admitted.element_count(items), expected.length())
  for index in 0..<expected.length() {
    guard @admitted.element_at(items, index) is Some(@admitted.Object(fields)) &&
      @admitted.element_at(fields, 0)
      is Some(("amount", @admitted.Number(amount))) &&
      @admitted.element_at(fields, 1)
      is Some(("position", @admitted.Number(position))) else {
      fail("nested ordered object")
    }
    assert_eq((amount, position), expected[index])
  }
}

///|
test "nest item guard fails atomically without truncation" {
  assert_true(
    execute_generated_sequence(nest_sequence(1), [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestItemLimit(0))),
  )
}

///|
test "selected nest item ceiling binds the exact output occurrence" {
  let generated = nest_sequence_guard("")
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestItemLimitRequired)),
  )
  let constrained = constrain_generated_aggregate_output(
    generated,
    2,
    "items",
    ArrayItems,
    1L,
  ).unwrap()
  assert_true(
    execute_generated_sequence(constrained, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestItemLimit(0))),
  )
  assert_true(
    constrain_generated_aggregate_output(
      generated,
      2,
      "missing",
      ArrayItems,
      1L,
    )
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(generated, 2, "items", StringBytes, 1L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(
      constrained,
      2,
      "items",
      ArrayItems,
      1L,
    )
    is Err(InputSet),
  )
}

///|
test "selected nest item ceiling cannot weaken an authored guard" {
  assert_true(
    constrain_generated_aggregate_output(
      nest_sequence(2),
      2,
      "items",
      ArrayItems,
      3L,
    )
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(
      nest_sequence(2),
      2,
      "items",
      ArrayItems,
      1L,
    )
    is Ok(_),
  )
}

///|
test "nest grouped and attached byte scopes count distinct and repeated arrays" {
  let exact = nest_sequence_guard_with_bytes(",\"max_items\":2", 31L, 66L)
  assert_true(
    execute_generated_sequence(exact, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Ok(_),
  )
  let grouped_short = nest_sequence_guard_with_bytes(
    ",\"max_items\":2", 30L, 66L,
  )
  assert_true(
    execute_generated_sequence(grouped_short, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestEnvelope(GroupedBytes))),
  )
  let attached_short = nest_sequence_guard_with_bytes(
    ",\"max_items\":2", 31L, 65L,
  )
  assert_true(
    execute_generated_sequence(attached_short, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestEnvelope(AttachedBytes))),
  )
}

///|
test "nest attached byte scope includes recursive parent siblings" {
  assert_true(
    execute_generated_sequence(nest_sibling_sequence(42L), [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Ok(_),
  )
  assert_true(
    execute_generated_sequence(nest_sibling_sequence(41L), [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, NestEnvelope(AttachedBytes))),
  )
}
