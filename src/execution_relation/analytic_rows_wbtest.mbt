///|
fn analytic_execution_owner(body : String) -> @lower.BoundPrepared {
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
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=13,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{" + body + "}]"),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=64,
  ).unwrap()
}

///|
fn analytic_execution_rows() -> Array[@decode.Cursor] {
  [
    input_cursor("{\"group\":\"a\",\"id\":3,\"amount\":30}"),
    input_cursor("{\"group\":null,\"id\":2,\"amount\":20}"),
    input_cursor("{\"group\":\"a\",\"id\":1,\"amount\":10}"),
    input_cursor("{\"group\":null,\"id\":4,\"amount\":null}"),
    input_cursor("{\"group\":\"a\",\"id\":5,\"amount\":30}"),
  ]
}

///|
fn analytic_execution_input(owner : @lower.BoundPrepared) -> Table {
  let rows = analytic_execution_rows()
  table_from_capture(
    capture_input(
      owner,
      0,
      rows,
      max_rows=rows.length(),
      run_limits().input_values,
    ).unwrap(),
  )
}

///|
test "analytic ranking navigation and frame values retain source order" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[\"group\",\"group\"]," +
    "\"order_by\":[{\"field\":\"amount\",\"dir\":\"desc\"," +
    "\"nulls\":\"first\"}],\"frame\":{\"start\":{" +
    "\"preceding\":1},\"end\":{\"following\":1}},\"functions\":{" +
    "\"dense\":{\"fn\":\"dense_rank\"}," +
    "\"first\":{\"fn\":\"first_value\",\"expr\":\"amount\"}," +
    "\"last\":{\"fn\":\"last_value\",\"expr\":\"amount\"}," +
    "\"next\":{\"fn\":\"lead\",\"expr\":\"amount\"}," +
    "\"peer\":{\"fn\":\"rank\"}," +
    "\"position\":{\"fn\":\"row_number\"}," +
    "\"previous\":{\"fn\":\"lag\",\"expr\":\"amount\"}}}",
  )
  let analytic = @lower.kernel_analytic(row_kernel(owner, 0)).unwrap()
  assert_true(analytic_execution_supported(analytic))
  let table = evaluate_rows(
    row_kernel(owner, 0),
    analytic_execution_input(owner),
    5,
    { remaining: 100000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(table.names, [
    "amount", "dense", "first", "group", "id", "last", "next", "peer", "position",
    "previous",
  ])
  assert_eq(table.rows.length(), 5)
  // The first source occurrence is first in its partition and peers with id 5.
  assert_true(table.rows[0][4] is Number(3))
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][7] is Number(1))
  assert_true(table.rows[0][8] is Number(1))
  assert_true(table.rows[0][9] is Null)
  assert_true(table.rows[0][6] is Number(30))
  assert_true(table.rows[0][2] is Number(30))
  assert_true(table.rows[0][5] is Number(30))
  // NULL is a peer value and first_value preserves it.
  assert_true(table.rows[3][4] is Number(4))
  assert_true(table.rows[3][8] is Number(1))
  assert_true(table.rows[3][2] is Null)
  assert_true(table.rows[3][5] is Number(20))
  // Output occurrences remain in their original source order.
  assert_true(table.rows[1][4] is Number(2))
  assert_true(table.rows[2][4] is Number(1))
  assert_true(table.rows[4][4] is Number(5))
  assert_true(table.rows[4][8] is Number(2))
  assert_true(table.rows[2][8] is Number(3))
}

///|
test "analytic does not clamp an out of partition frame start" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[\"group\"]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":{" +
    "\"following\":2},\"end\":{\"following\":3}},\"functions\":{" +
    "\"first\":{\"fn\":\"first_value\",\"expr\":\"amount\"}," +
    "\"last\":{\"fn\":\"last_value\",\"expr\":\"amount\"}}}",
  )
  let table = evaluate_rows(
    row_kernel(owner, 0),
    analytic_execution_input(owner),
    5,
    { remaining: 100000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(table.names, ["amount", "first", "group", "id", "last"])
  // id 5 is last in group a; following frames are empty, not id 5 again.
  assert_true(table.rows[4][3] is Number(5))
  assert_true(table.rows[4][1] is Null)
  assert_true(table.rows[4][4] is Null)
}

///|
test "analytic navigation evaluates only referenced source rows" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"functions\":{" +
    "\"previous\":{\"fn\":\"lag\",\"expr\":\"1 / (5 - id)\"}}}",
  )
  // id 5 is never referenced by lag, so its failing argument is not demanded.
  let table = evaluate_rows(
    row_kernel(owner, 0),
    analytic_execution_input(owner),
    5,
    { remaining: 100000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(table.rows.length(), 5)
  assert_true(table.rows[4][3] is Number(1))
}

///|
test "analytic expression failure follows partition source and call order" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[\"group\"]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"functions\":{" +
    "\"z\":{\"fn\":\"lag\",\"expr\":\"1 / 0\",\"offset\":0}," +
    "\"a\":{\"fn\":\"lag\",\"expr\":\"1 / 0\",\"offset\":0}}}",
  )
  guard evaluate_rows(
      row_kernel(owner, 0),
      analytic_execution_input(owner),
      5,
      { remaining: 100000, max_frames: 100, },
      row_output(),
    )
    is Err(Evaluation(row, call, _)) else {
    fail("analytic expression failure expected")
  }
  // NULL is the first canonical partition. Source occurrence 1 is its first
  // row, and output name "a" is the first canonical call.
  assert_eq((row, call), (1, 0))
}

///|
test "analytic execution has an exact control work boundary" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[\"group\"]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"functions\":{" +
    "\"position\":{\"fn\":\"row_number\"}}}",
  )
  let control = { remaining: 100000, max_frames: 100, }
  ignore(
    evaluate_rows(
      row_kernel(owner, 0),
      analytic_execution_input(owner),
      5,
      control,
      row_output(),
    ).unwrap(),
  )
  let used = 100000 - control.remaining
  assert_true(
    evaluate_rows(
      row_kernel(owner, 0),
      analytic_execution_input(owner),
      5,
      { remaining: used, max_frames: 100, },
      row_output(),
    )
    is Ok(_),
  )
  assert_true(
    evaluate_rows(
      row_kernel(owner, 0),
      analytic_execution_input(owner),
      5,
      { remaining: used - 1, max_frames: 100, },
      row_output(),
    )
    is Err(RowLimit),
  )
}

///|
test "analytic aggregates stay outside the partial execution capability" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":" +
    "\"unbounded_preceding\",\"end\":\"current_row\"}," +
    "\"functions\":{\"total\":{\"fn\":\"sum\"," +
    "\"field\":\"amount\"}}}",
  )
  let analytic = @lower.kernel_analytic(row_kernel(owner, 0)).unwrap()
  assert_false(analytic_execution_supported(analytic))
}

///|
test "analytic collection limits bind exact prepared calls" {
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[]," +
    "\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":" +
    "\"unbounded_preceding\",\"end\":\"current_row\"}," +
    "\"functions\":{\"items\":{\"fn\":\"array_agg\"," +
    "\"field\":\"amount\",\"max_items\":3},\"text\":{" +
    "\"fn\":\"string_agg\",\"field\":\"group\"," +
    "\"delimiter\":\",\",\"max_bytes\":5}}}",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["analytic_0"],
    100000,
    10000,
  ).unwrap()
  let items = constrain_generated_aggregate_output(
    generated,
    0,
    "items",
    ArrayItems,
    2L,
  ).unwrap()
  let complete = constrain_generated_aggregate_output(
    items,
    0,
    "text",
    StringBytes,
    4L,
  )
  assert_true(complete is Ok(_))
  assert_true(
    constrain_generated_aggregate_output(generated, 0, "items", ArrayItems, 4L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(generated, 0, "items", StringBytes, 2L)
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(
      generated,
      0,
      "missing",
      ArrayItems,
      1L,
    )
    is Err(InputSet),
  )
  assert_true(
    constrain_generated_aggregate_output(items, 0, "items", ArrayItems, 1L)
    is Err(InputSet),
  )
}
