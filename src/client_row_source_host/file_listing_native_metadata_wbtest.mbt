///|
// Actual Row admission/capture with explicit reference fixtures. This supplies
// no physical Root, permission, report issuer or funded Source admission.
fn native_listing_read_fixture() -> RowSourceRead {
  let base = selection_read_fixture(AllFiles)
  let fields = []
  for i in 0..<@schema.field_count(base.schema) {
    let field = @schema.field_at(base.schema, i).unwrap()
    let name = @schema.field_reference_name(field)
    fields.push(
      (
        @schema.Unqualified(name),
        if name == "path" {
          @contract.primitive(@contract.StringType, nullable=false)
        } else {
          @schema.field_contract(field)
        },
        @schema.Required,
      ),
    )
  }
  fields.push(
    (
      @schema.Unqualified("size"),
      @contract.primitive(@contract.Signed64Type, nullable=false),
      @schema.Required,
    ),
  )
  fields.push(
    (
      @schema.Unqualified("modified_time"),
      @contract.primitive(@contract.TimestampType, nullable=false),
      @schema.Required,
    ),
  )
  let schema = @schema.from_presence_fields(
    fields,
    max_fields=9,
    max_name_bytes=128,
  ).unwrap()
  let checked = @pipeline.check(
    row_presence_cursor("[{\"select\":[\"size\",\"modified_time\"]}]"),
    [("files", schema)],
    None,
    Some(row_presence_cursor("\"files\"")),
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
  let schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    0,
  ).unwrap()
  let columns = []
  for i in 0..<@schema.field_count(schema) {
    columns.push(
      @schema.field_reference_name(@schema.field_at(schema, i).unwrap()),
    )
  }
  let limits = base.listing.unwrap().limits.copy()
  let resolved = base.listing.unwrap().resolved_rows
  let issuer = base.reference_issuer
  cancel_row_source_read(base) |> ignore
  {
    ..base,
    schema,
    columns,
    declared_fields: columns.copy(),
    input: @execution.prepare_admitted_input(
      owner,
      0,
      3,
      row_presence_retention(),
    ).unwrap(),
    reference_issuer: issuer,
    listing: Some(
      new_row_listing_progress(
        limits,
        resolved_rows=resolved,
        selection=Some(AllFiles),
      ),
    ),
    open: true,
  }
}

///|
fn native_listing_row() -> String {
  let row = selection_row("d", "a.csv")
  row[0:row.length() - 1].to_owned() +
  ",\"size\":\"9007199254740993\",\"modified_time\":\"2026-10-20T00:00:00.000000001Z\"}"
}

///|
test "listing capture preserves the full native Int64 Timestamp schema including empty input" {
  let read = native_listing_read_fixture()
  assert_eq(@schema.field_count(read.schema), 9)
  assert_eq(
    selection_accept(read, "[" + native_listing_row() + "]", None, None, 1).unwrap(),
    1,
  )
  let captured = finish_row_source_read(read).unwrap()
  assert_true(physical_equal(@execution.captured_schema(captured), read.schema))
  assert_true(
    @execution.captured_presence_cell(
      captured,
      0,
      read.columns.search("size").unwrap(),
    )
    is Ok(@execution.Present(@admitted.Signed64(9007199254740993L))),
  )
  assert_true(
    @execution.captured_presence_cell(
      captured,
      0,
      read.columns.search("modified_time").unwrap(),
    )
    is Ok(
      @execution.Present(@admitted.Timestamp("2026-10-20T00:00:00.000000001Z"))
    ),
  )
  assert_false(cancel_row_source_read(read))
  let empty = native_listing_read_fixture()
  assert_eq(selection_accept(empty, "[]", None, None, 1).unwrap(), 0)
  let captured = finish_row_source_read(empty).unwrap()
  assert_eq(@execution.captured_row_count(captured), 0)
  assert_true(
    physical_equal(@execution.captured_schema(captured), empty.schema),
  )
  assert_eq(@schema.field_count(@execution.captured_schema(captured)), 9)
}

///|
test "listing native metadata obeys full declared type presence and byte admission" {
  let row = native_listing_row()
  for
    broken in [
      row.replace(
        old="\"size\":\"9007199254740993\"",
        new="\"size\":9007199254740992",
      ),
      row.replace(old="\"size\":\"9007199254740993\"", new="\"size\":null"),
      row.replace(old=",\"size\":\"9007199254740993\"", new=""),
      row.replace(old="\"path\":\"a.csv\"", new="\"path\":null"),
      row.replace(old="2026-10-20T00:00:00.000000001Z", new="invalid"),
      row.replace(old="\"size\":", new="\"undeclared_size\":"),
    ] {
    let read = native_listing_read_fixture()
    assert_true(
      selection_accept(read, "[" + broken + "]", None, None, 1) is Err(_),
    )
    assert_true(finish_row_source_read(read) is Err(_))
  }
  let read = native_listing_read_fixture()
  let limited = {
    ..read,
    page_limits: { ..read.page_limits, max_bytes: row.length() - 1, },
  }
  assert_true(
    selection_accept(limited, "[" + row + "]", None, None, 1) is Err(_),
  )
  assert_true(finish_row_source_read(limited) is Err(_))
}
