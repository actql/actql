///|
fn row_presence_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 256,
      max_depth: 16,
    }).unwrap(),
    {
      max_nodes: 256,
      max_depth: 16,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn row_presence_owner(
  conditional? : Bool = true,
) -> (@lower.BoundPrepared, @schema.Schema) {
  let schema = @schema.from_presence_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
        @schema.Required,
      ),
      (
        @schema.Unqualified("p"),
        @contract.primitive(@contract.NumberType, nullable=true),
        if conditional {
          @schema.Conditional
        } else {
          @schema.Required
        },
      ),
    ],
    max_fields=2,
    max_name_bytes=16,
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
  // Admission must use the preparation's exact schema, not an equal copy.
  (
    owner,
    @lower.preparation_input_schema(@lower.bound_preparation(owner), 0).unwrap(),
  )
}

///|
fn row_presence_retention() -> @execution.ValueLimits {
  { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, max_work: 4096, }
}

///|
fn row_presence_append(
  input : @execution.AdmittedInput,
  schema : @schema.Schema,
  wire : String,
) -> Result[Unit, RowSourceIssue] {
  append_row_source_object(
    input,
    schema,
    ["id", "p"],
    row_presence_cursor(wire),
    { max_nodes: 256, max_depth: 16, max_text_bytes: 4096, },
    row_presence_retention(),
  )
}

///|
test "row source admission retains omitted NULL and actual cells on its checked input" {
  let (owner, schema) = row_presence_owner()
  let input = @execution.prepare_admitted_input(
    owner,
    0,
    3,
    row_presence_retention(),
  ).unwrap()
  for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
    row_presence_append(input, schema, wire).unwrap()
  }
  let captured = @execution.finish_admitted_input(input).unwrap()
  assert_true(physical_equal(@execution.captured_owner(captured), owner))
  assert_true(physical_equal(@execution.captured_schema(captured), schema))
  assert_eq(@execution.captured_row_count(captured), 3)
  for row in 0..<3 {
    assert_true(
      @execution.captured_presence_cell(captured, row, 0)
      is Ok(@execution.Present(@admitted.Number(id))) &&
      id == (row + 1).to_double(),
    )
  }
  assert_true(
    @execution.captured_presence_cell(captured, 0, 1)
    is Ok(@execution.Present(@admitted.Number(7))),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 1, 1)
    is Ok(@execution.Present(@admitted.Null)),
  )
  assert_true(
    @execution.captured_presence_cell(captured, 2, 1) is Ok(@execution.Absent),
  )
  // Successful handoff makes cancellation unable to erase captured content.
  assert_false(@execution.cancel_admitted_input(input))
  assert_eq(@execution.captured_row_count(captured), 3)
}

///|
test "row source admission refuses missing required fields bad values and undeclared keys" {
  let (owner, schema) = row_presence_owner()
  for
    (wire, kind) in [
      ("{\"p\":7}", 0),
      ("{\"id\":null}", 1),
      ("{\"id\":1,\"p\":\"7\"}", 2),
      ("{\"id\":1,\"extra\":7}", 3),
    ] {
    let input = @execution.prepare_admitted_input(
      owner,
      0,
      2,
      row_presence_retention(),
    ).unwrap()
    row_presence_append(input, schema, "{\"id\":9}").unwrap()
    let result = row_presence_append(input, schema, wire)
    match kind {
      0 => assert_true(result is Err(MissingField("id")))
      1 => assert_true(result is Err(Value("id")))
      2 => assert_true(result is Err(Value("p")))
      _ => assert_true(result is Err(UnexpectedField("extra")))
    }
    // This is the same input cancellation performed by fail_read. Earlier
    // admitted rows cannot become a partial completed acquisition afterward.
    assert_true(@execution.cancel_admitted_input(input))
    assert_false(@execution.cancel_admitted_input(input))
    assert_true(@execution.finish_admitted_input(input) is Err(_))
  }
}

///|
test "row source conditional capture charges bounds and preserves empty schema" {
  let (owner, schema) = row_presence_owner()
  let empty = @execution.prepare_admitted_input(
    owner,
    0,
    0,
    row_presence_retention(),
  ).unwrap()
  let captured = @execution.finish_admitted_input(empty).unwrap()
  assert_eq(@execution.captured_row_count(captured), 0)
  assert_true(physical_equal(@execution.captured_schema(captured), schema))
  assert_eq(
    @schema.field_presence(@schema.field_at(schema, 1).unwrap()),
    @schema.Conditional,
  )
  let one = @execution.prepare_admitted_input(
    owner,
    0,
    1,
    row_presence_retention(),
  ).unwrap()
  row_presence_append(one, schema, "{\"id\":1}").unwrap()
  assert_true(row_presence_append(one, schema, "{\"id\":2}") is Err(Capture(_)))
  // The existing cumulative input owner closes itself on append failure.
  assert_false(@execution.cancel_admitted_input(one))
  assert_true(@execution.finish_admitted_input(one) is Err(_))
  let short = @execution.prepare_admitted_input(owner, 0, 1, {
    ..row_presence_retention(),
    max_nodes: 1,
  }).unwrap()
  // The presence container itself is charged, even with no p value.
  assert_true(
    row_presence_append(short, schema, "{\"id\":1}") is Err(Capture(_)),
  )
  assert_false(@execution.cancel_admitted_input(short))
  assert_true(@execution.finish_admitted_input(short) is Err(_))
}

///|
test "row source dense input retains required nullable semantics" {
  let (owner, schema) = row_presence_owner(conditional=false)
  let input = @execution.prepare_admitted_input(
    owner,
    0,
    1,
    row_presence_retention(),
  ).unwrap()
  assert_true(
    row_presence_append(input, schema, "{\"id\":1}") is Err(MissingField("p")),
  )
  row_presence_append(input, schema, "{\"id\":1,\"p\":null}").unwrap()
  let captured = @execution.finish_admitted_input(input).unwrap()
  assert_true(@execution.captured_cell(captured, 0, 1) is Some(@admitted.Null))
  assert_true(@schema.all_fields_required(@execution.captured_schema(captured)))
}
