///|
fn typed_json_page(wire : String) -> RowSourceProjectedJsonPage {
  project_row_source_typed_json_page(
    @utf8.encode(wire), ["items"], true, ["next"], 4096, 256, 16, 4, 64,
  ).unwrap()
}

///|
test "typed JSON page keeps whole schema NULL Unicode and original cursor without wire replay" {
  let page = typed_json_page(
    (
      #|{"items":[{"id":1,"payload":{"$json":"literal","é":1,"é":2},"é":null},{"id":2,"payload":{},"é":"é\r\n"}],"next":""}
    ),
  )
  assert_eq(row_source_typed_json_page_row_count(page), 2)
  assert_true(row_source_typed_json_page_has_next_cursor(page))
  assert_eq(row_source_typed_json_page_next_cursor(page).unwrap(), "")
  let read = physical_row_json_read()
  assert_eq(accept_row_source_projected_page(read, page).unwrap(), 2)
  assert_eq(read.rows, 2L)
  assert_eq(read.pages, 1L)
  let captured = @execution.finish_admitted_input(read.input).unwrap()
  guard @execution.captured_presence_cell(captured, 0, 1)
    is Ok(@execution.Present(value)) else {
    abort("original JSON cell")
  }
  let writer = @encode.writer(4096, 256, 16)
  @admitted.emit_wire_value(value, writer)
  assert_eq(
    @encode.finish(writer),
    (
      #|{"$json":{"$json":"literal","é":1,"é":2}}
    ),
  )
}

///|
test "typed JSON page retains signed64 strings and rejects numeric substitution under the same schema" {
  let page = typed_json_page(
    "{\"items\":[{\"id\":\"-9223372036854775808\"},{\"id\":\"9007199254740993\"},{\"id\":\"9223372036854775807\"}]}",
  )
  let (_, read) = signed64_row_read()
  assert_eq(accept_row_source_projected_page(read, page).unwrap(), 3)
  let captured = @execution.finish_admitted_input(read.input).unwrap()
  let expected = [
    -9223372036854775808L, 9007199254740993L, 9223372036854775807L,
  ]
  for index in 0..<expected.length() {
    guard @execution.captured_presence_cell(captured, index, 0)
      is Ok(@execution.Present(value)) && value is @admitted.Signed64(actual) else {
      abort("original signed64 cell")
    }
    assert_eq(actual, expected[index])
  }
  let (_, refused) = signed64_row_read()
  assert_true(
    accept_row_source_projected_page(
      refused, typed_json_page("{\"items\":[{\"id\":9223372036854775807}]}"),
    ) is Err(_),
  )
  assert_false(refused.open)
}

///|
test "typed JSON page admission preserves schema byte row and cancelled-read refusals" {
  for
    rows in [
      "[{\"id\":1,\"payload\":{},\"é\":null}]",
      "[{\"id\":1,\"payload\":{},\"é\":null,\"extra\":1}]",
      "[{\"id\":1,\"payload\":null,\"é\":null}]",
      "[{\"id\":1,\"payload\":{},\"é\":null},{\"id\":2,\"payload\":{},\"é\":null},{\"id\":3,\"payload\":{},\"é\":null},{\"id\":4,\"payload\":{},\"é\":null}]",
    ] {
    let read = physical_row_json_read()
    let page = typed_json_page("{\"items\":" + rows + "}")
    assert_true(accept_row_source_projected_page(read, page) is Err(_))
    assert_false(read.open)
    assert_true(@execution.finish_admitted_input(read.input) is Err(_))
  }
  let rows = "[{\"id\":1,\"payload\":{},\"é\":null}]"
  let page = typed_json_page("{\"items\":" + rows + "}")
  let read = physical_row_json_read(max_bytes=@utf8.encode(rows).length() - 1)
  assert_true(accept_row_source_projected_page(read, page) is Err(InvalidPage))
  assert_false(read.open)
  let stopped = physical_row_json_read()
  assert_true(cancel_row_source_read(stopped))
  assert_true(accept_row_source_projected_page(stopped, page) is Err(Closed))
}

///|
test "typed JSON page and legacy transform projection share the exact parsed original" {
  let rows = "[ {\"id\":1,\"payload\":{},\"é\":null} ]"
  let projected = json_page_test("{\"items\":" + rows + ",\"next\":\"later\"}").unwrap()
  let original = row_source_json_page_original(projected)
  assert_true(physical_equal(original, row_source_json_page_original(projected)))
  assert_eq(row_source_json_page_rows_wire(projected), rows)
  assert_eq(row_source_typed_json_page_row_count(original), 1)
  assert_eq(row_source_typed_json_page_next_cursor(original).unwrap(), "later")
  let read = physical_row_json_read()
  assert_eq(accept_row_source_projected_page(read, original).unwrap(), 1)
}

///|
test "typed JSON page namespace provenance refuses a foreign original without wire fallback" {
  let page = typed_json_page("{\"items\":[]}")
  let foreign = { ..page, origin: Ref(()) }
  let read = physical_row_json_read()
  assert_true(accept_row_source_projected_page(read, foreign) is Err(InvalidPage))
  assert_false(read.open)
  let original = physical_row_json_read()
  assert_eq(accept_row_source_projected_page(original, page).unwrap(), 0)
  assert_eq(original.pages, 1L)
  assert_eq(original.rows, 0L)
  cancel_row_source_read(original) |> ignore
}
