///|
fn physical_row_json_read(max_bytes? : Int = 4096) -> RowSourceRead {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("payload"),
        @contract.primitive(@contract.JsonType, nullable=false),
      ),
      (
        @schema.Unqualified("é"),
        @contract.primitive(@contract.StringType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=32,
  ).unwrap()
  let pipeline = @pipeline.check(
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
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 4096,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let original_schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    0,
  ).unwrap()
  new_row_source_read(
    owner,
    0,
    original_schema,
    ["id", "payload", "é"],
    ["id", "payload", "é"],
    { max_bytes, max_nodes: 256, max_depth: 16, max_rows: 3, },
    3,
    row_presence_retention(),
    None,
    None,
    None,
  ).unwrap()
}

///|
test "physical row JSON keeps distinct Unicode data keys and literal marker through the real input owner" {
  let read = physical_row_json_read()
  let bytes = @utf8.encode(
    (
      #|[{"id":1,"payload":{"$json":"literal","é":"é\r\n","é":"é"},"é":null}]
    ),
  )
  assert_eq(accept_row_source_page(read, bytes).unwrap(), 1)
  let captured = @execution.finish_admitted_input(read.input).unwrap()
  guard @execution.captured_presence_cell(captured, 0, 1)
    is Ok(@execution.Present(value)) &&
    value is @admitted.JsonData(_) else {
    abort("original JSON cell")
  }
  let writer = @encode.writer(4096, 256, 16)
  @admitted.emit_wire_value(value, writer)
  assert_eq(
    @encode.finish(writer),
    (
      #|{"$json":{"$json":"literal","é":"é\r\n","é":"é"}}
    ),
  )
}

///|
test "physical row JSON retains duplicate bounds schema identity and full attempt refusal" {
  for
    invalid in [
      (
        #|[{"id":1,"payload":{"é":1,"é":2},"é":null}]
      ),
      (
        #|[{"id":1,"payload":{},"é":null}]
      ),
      (
        #|[{"id":1,"payload":{},"é":null,"extra":1}]
      ),
      (
        #|[{"id":1,"payload":{},"é":null},{"id":2,"payload":null,"é":null}]
      ),
    ] {
    let read = physical_row_json_read()
    assert_true(accept_row_source_page(read, @utf8.encode(invalid)) is Err(_))
    assert_false(read.open)
    assert_true(@execution.finish_admitted_input(read.input) is Err(_))
  }
  let wire = @utf8.encode("[{\"id\":1,\"payload\":{},\"é\":null}]")
  let short = physical_row_json_read(max_bytes=wire.length() - 1)
  assert_true(accept_row_source_page(short, wire) is Err(InvalidPage))
  assert_false(short.open)
  let malformed = physical_row_json_read()
  assert_true(accept_row_source_page(malformed, b"\xff") is Err(InvalidPage))
  assert_false(malformed.open)
}
