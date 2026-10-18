///|
fn signed64_row_read(
  foreign_schema? : Bool = false,
) -> (@lower.BoundPrepared, RowSourceRead) {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.Signed64Type, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let checked = @pipeline.check(
    row_presence_cursor("[{\"select\":[\"id\"]}]"),
    [("rows", schema)],
    None,
    Some(row_presence_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 4096,
      max_nodes: 256,
      max_tokens: 256,
      max_depth: 16,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 4096,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let original = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    0,
  ).unwrap()
  let used = if foreign_schema {
    @schema.from_fields(
      [
        (
          @schema.Unqualified("id"),
          @contract.primitive(@contract.Signed64Type, nullable=false),
        ),
      ],
      max_fields=1,
      max_name_bytes=2,
    ).unwrap()
  } else {
    original
  }
  (
    owner,
    new_row_source_read(
      owner,
      0,
      used,
      ["id"],
      ["id"],
      { max_bytes: 4096, max_nodes: 256, max_depth: 8, max_rows: 4, },
      4,
      row_presence_retention(),
      None,
      None,
      None,
    ).unwrap(),
  )
}

///|
test "signed64 original row input captures and serializes all exact boundary values" {
  let (owner, read) = signed64_row_read()
  let texts = [
    "-9223372036854775808", "9007199254740992", "9007199254740993", "9223372036854775807",
  ]
  let exact = [
    -9223372036854775808L, 9007199254740992L, 9007199254740993L, 9223372036854775807L,
  ]
  let wire = "[" +
    texts.map(text => "{\"id\":\"" + text + "\"}").join(",") +
    "]"
  assert_eq(accept_row_source_page(read, @utf8.encode(wire)).unwrap(), 4)
  let captured = @execution.finish_admitted_input(read.input).unwrap()
  assert_true(physical_equal(@execution.captured_owner(captured), owner))
  assert_true(physical_equal(@execution.captured_schema(captured), read.schema))
  let current = Ref(true)
  let supplied = @execution.prepare_supplied_relation_read(owner, 0, captured, () => {
    current.val
  }).unwrap()
  for row in 0..<4 {
    guard! @execution.captured_cell(captured, row, 0)
      is Some(@admitted.Signed64(value))
    assert_eq(value, exact[row])
    assert_eq(
      @execution.supplied_relation_read_row_wire(supplied, row, {
        max_columns: 1,
        max_order_work: 64,
        max_bytes: 128,
        max_nodes: 32,
        max_depth: 8,
      }).unwrap(),
      "{\"id\":\"" + texts[row] + "\"}",
    )
  }
  let (foreign, _) = signed64_row_read()
  assert_true(
    @execution.prepare_supplied_relation_read(foreign, 0, captured, () => true)
    is Err(_),
  )
  current.val = false
  assert_true(
    @execution.supplied_relation_read_row_wire(supplied, 0, {
      max_columns: 1,
      max_order_work: 64,
      max_bytes: 128,
      max_nodes: 32,
      max_depth: 8,
    })
    is Err(_),
  )
}

///|
test "signed64 row source refuses overflow Number and equal foreign schema before capture" {
  for
    body in [
      "[{\"id\":\"9223372036854775808\"}]", "[{\"id\":\"-9223372036854775809\"}]",
      "[{\"id\":9007199254740993}]", "[{\"id\":\"01\"}]",
    ] {
    let (_, read) = signed64_row_read()
    assert_true(accept_row_source_page(read, @utf8.encode(body)) is Err(_))
    assert_false(read.open)
    assert_true(@execution.finish_admitted_input(read.input) is Err(_))
  }
  let (_, foreign) = signed64_row_read(foreign_schema=true)
  assert_true(
    accept_row_source_page(foreign, @utf8.encode("[{\"id\":\"1\"}]")) is Err(_),
  )
  assert_false(foreign.open)
  assert_true(@execution.finish_admitted_input(foreign.input) is Err(_))
}
