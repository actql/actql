///|
fn collection_group_sequence(
  rows : String,
  string_limit? : Int = 20,
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"k":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}},"rows":
    ) +
    rows +
    (
      #|},"as":"seed"},{"group":{"by":["k"],"aggregates":{"items":{"fn":"array_agg","field":"label","distinct":true,"order_by":[{"id":"asc"}],"max_items":5},"text":{"fn":"string_agg","field":"label","distinct":true,"order_by":[{"id":"desc"}],"delimiter":"|","max_bytes":
    ) +
    string_limit.to_string() +
    "}}}}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
}

///|
fn collection_limits(
  generated : GeneratedSequence,
  items : Int64,
  bytes : Int64,
) -> GeneratedSequence {
  let with_items = constrain_generated_aggregate_output(
    generated,
    1,
    "items",
    ArrayItems,
    items,
  ).unwrap()
  constrain_generated_aggregate_output(
    with_items,
    1,
    "text",
    StringBytes,
    bytes,
  ).unwrap()
}

///|
fn string_group_sequence(
  rows : String,
  delimiter : String,
  distinct : Bool,
) -> GeneratedSequence raise {
  let distinct_option = if distinct { ",\"distinct\":true" } else { "" }
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}},"rows":
    ) +
    rows +
    (
      #|},"as":"seed"},{"group":{"by":[],"aggregates":{"text":{"fn":"string_agg","field":"label","order_by":[{"id":"asc"}],"delimiter":"
    ) +
    delimiter +
    "\"" +
    distinct_option +
    ",\"max_bytes\":20}}}}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
}

///|
fn run_string_group(
  generated : GeneratedSequence,
  maximum : Int64,
) -> Result[CompletedSequence, SequenceRunIssue] {
  execute_generated_sequence(
    constrain_generated_aggregate_output(
      generated,
      1,
      "text",
      StringBytes,
      maximum,
    ).unwrap(),
    [],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
  )
}

///|
test "collection aggregates preserve independent order and first distinct occurrence" {
  let rows =
    #|[{"id":1,"k":1,"label":{"literal":"b"}},{"id":2,"k":1,"label":null},{"id":3,"k":1,"label":{"literal":"a"}},{"id":4,"k":1,"label":{"literal":"b"}}]
  let generated = collection_limits(collection_group_sequence(rows), 2L, 3L)
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(1)).unwrap())
  assert_eq(table.names, ["items", "k", "text"])
  assert_eq(table.rows.length(), 1)
  guard table.rows[0][0] is Captured(@admitted.Array(items)) else {
    fail("array aggregate expected")
  }
  assert_eq(@admitted.element_count(items), 2)
  assert_true(@admitted.element_at(items, 0) is Some(@admitted.Text("b")))
  assert_true(@admitted.element_at(items, 1) is Some(@admitted.Text("a")))
  assert_true(table.rows[0][2] is Text("b|a"))
}

///|
test "empty collection aggregates retain array and string empty laws" {
  let program =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}},"rows":[]},"as":"seed"},{"group":{"by":[],"aggregates":{"items":{"fn":"array_agg","field":"label","order_by":[{"id":"asc"}],"max_items":5},"text":{"fn":"string_agg","field":"label","order_by":[{"id":"asc"}],"delimiter":"|","max_bytes":20}}}}]
  let owner = bound_pipeline(program)
  let generated = collection_limits(
    prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["group_1"],
      100000,
      10000,
    ).unwrap(),
    0L,
    0L,
  )
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(1)).unwrap())
  assert_eq(table.rows.length(), 1)
  guard table.rows[0][0] is Captured(@admitted.Array(items)) else {
    fail("empty array aggregate expected")
  }
  assert_eq(@admitted.element_count(items), 0)
  assert_true(table.rows[0][1] is Null)
}

///|
test "selected collection limits fail atomically at one short" {
  let rows =
    #|[{"id":1,"k":1,"label":{"literal":"a"}},{"id":2,"k":1,"label":{"literal":"b"}}]
  let source = collection_group_sequence(rows)
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  assert_true(
    execute_generated_sequence(collection_limits(source, 1L, 3L), [], limits)
    is Err(Rows(1, RowLimit)),
  )
  assert_true(
    execute_generated_sequence(collection_limits(source, 2L, 2L), [], limits)
    is Err(Rows(1, RowLimit)),
  )
  assert_true(
    execute_generated_sequence(collection_limits(source, 2L, 3L), [], limits)
    is Ok(_),
  )
}

///|
test "string aggregate measures raw UTF-8 output including delimiters" {
  let program =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"k":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}},"rows":[{"id":1,"k":1,"label":{"literal":"é"}},{"id":2,"k":1,"label":{"literal":"€"}}]},"as":"seed"},{"group":{"by":["k"],"aggregates":{"items":{"fn":"array_agg","field":"label","order_by":[{"id":"asc"}],"max_items":5},"text":{"fn":"string_agg","field":"label","order_by":[{"id":"asc"}],"delimiter":"😀","max_bytes":20}}}}]
  let owner = bound_pipeline(program)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  assert_true(
    execute_generated_sequence(collection_limits(generated, 2L, 8L), [], limits)
    is Err(Rows(1, RowLimit)),
  )
  let result = execute_generated_sequence(
    collection_limits(generated, 2L, 9L),
    [],
    limits,
  ).unwrap()
  assert_true(
    completed_cell(completed_output(result, Step(1)).unwrap(), 0, 2)
    is Some(Text("é😀€")),
  )
}

///|
test "string aggregate charges only delimiters present in the output" {
  let singleton = string_group_sequence(
    (
      #|[{"id":1,"label":{"literal":"x"}}]
    ),
    "😀",
    false,
  )
  let singleton_result = run_string_group(singleton, 1L).unwrap()
  assert_true(
    completed_cell(completed_output(singleton_result, Step(1)).unwrap(), 0, 0)
    is Some(Text("x")),
  )

  let after_null = string_group_sequence(
    (
      #|[{"id":1,"label":null},{"id":2,"label":{"literal":"x"}}]
    ),
    "😀",
    false,
  )
  assert_true(run_string_group(after_null, 1L) is Ok(_))

  let after_distinct = string_group_sequence(
    (
      #|[{"id":1,"label":{"literal":"x"}},{"id":2,"label":{"literal":"x"}}]
    ),
    "😀",
    true,
  )
  assert_true(run_string_group(after_distinct, 1L) is Ok(_))

  let pair = string_group_sequence(
    (
      #|[{"id":1,"label":{"literal":"x"}},{"id":2,"label":{"literal":"x"}}]
    ),
    "😀",
    false,
  )
  assert_true(run_string_group(pair, 5L) is Err(Rows(1, RowLimit)))
  let pair_result = run_string_group(pair, 6L).unwrap()
  assert_true(
    completed_cell(completed_output(pair_result, Step(1)).unwrap(), 0, 0)
    is Some(Text("x😀x")),
  )
}

///|
test "string aggregate retains empty and all-null laws at zero bytes" {
  let empty_rows = "[]"
  let null_rows = "[{\"id\":1,\"label\":null}]"
  for rows in [empty_rows, null_rows] {
    let result = run_string_group(
      string_group_sequence(rows, "😀", false),
      0L,
    ).unwrap()
    assert_true(
      completed_cell(completed_output(result, Step(1)).unwrap(), 0, 0)
      is Some(Null),
    )
  }
  let empty_delimiter = string_group_sequence(
    (
      #|[{"id":1,"label":{"literal":"日"}},{"id":2,"label":{"literal":"本"}}]
    ),
    "",
    false,
  )
  assert_true(run_string_group(empty_delimiter, 5L) is Err(Rows(1, RowLimit)))
  let result = run_string_group(empty_delimiter, 6L).unwrap()
  assert_true(
    completed_cell(completed_output(result, Step(1)).unwrap(), 0, 0)
    is Some(Text("日本")),
  )
}

///|
test "array aggregate retains admitted structured items and nested nullability" {
  let program =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"tag":{"type":"string","nullable":false},"note":{"type":"string","nullable":true}}}},"rows":[{"id":1,"payload":{"tag":"a","note":null}},{"id":2,"payload":null},{"id":3,"payload":{"tag":"b","note":"kept"}}]},"as":"seed"},{"group":{"by":[],"aggregates":{"items":{"fn":"array_agg","field":"payload","order_by":[{"id":"asc"}],"max_items":3}}}}]
  let owner = bound_pipeline(program)
  let generated = constrain_generated_aggregate_output(
    prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["group_1"],
      100000,
      10000,
    ).unwrap(),
    1,
    "items",
    ArrayItems,
    2L,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  guard completed_cell(completed_output(result, Step(1)).unwrap(), 0, 0)
    is Some(Captured(@admitted.Array(items))) else {
    fail("structured array aggregate expected")
  }
  assert_eq(@admitted.element_count(items), 2)
  guard @admitted.element_at(items, 0) is Some(@admitted.Object(first)) &&
    @admitted.element_at(first, 0) is Some(("note", @admitted.Null)) &&
    @admitted.element_at(first, 1) is Some(("tag", @admitted.Text("a"))) else {
    fail("first structured item expected")
  }
  guard @admitted.element_at(items, 1) is Some(@admitted.Object(second)) &&
    @admitted.element_at(second, 0) is Some(("note", @admitted.Text("kept"))) &&
    @admitted.element_at(second, 1) is Some(("tag", @admitted.Text("b"))) else {
    fail("second structured item expected")
  }
}

///|
test "aggregate output constraints reject foreign or ambiguous occurrences" {
  let generated = collection_group_sequence("[]")
  assert_true(
    constrain_generated_aggregate_output(generated, 0, "items", ArrayItems, 1L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(
      generated,
      1,
      "missing",
      ArrayItems,
      1L,
    )
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(generated, 1, "items", StringBytes, 1L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(generated, 1, "items", ArrayItems, 6L)
    is Err(InputSet),
  )
  let once = constrain_generated_aggregate_output(
    generated,
    1,
    "items",
    ArrayItems,
    5L,
  ).unwrap()
  assert_true(
    constrain_generated_aggregate_output(once, 1, "items", ArrayItems, 4L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(generated, 1, "items", ArrayItems, -1L)
    is Err(InvalidLimits),
  )
}
