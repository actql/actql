///|
fn json_page_test(
  wire : String,
  cursor? : Bool = true,
  rows? : Int = 4,
) -> Result[RowSourceJsonPage, RowSourceJsonPageIssue] {
  project_row_source_json_page(
    @utf8.encode(wire),
    ["items"],
    cursor,
    if cursor {
      ["next"]
    } else {
      []
    },
    4096,
    256,
    16,
    rows,
    64,
  )
}

///|
test "original JSON page keeps exact array tokens keys strings and explicit cursor state" {
  let rows = "[ {\"id\":9007199254740993,\"s\":\"é\\r\\n\",\"é\":1,\"é\":2,\"n\":1.50e0} ]"
  let page = json_page_test("{\"items\":" + rows + ",\"next\":\"\"}").unwrap()
  assert_eq(row_source_json_page_rows_wire(page), rows)
  assert_eq(row_source_json_page_row_count(page), 1)
  assert_true(row_source_json_page_has_next_cursor(page))
  assert_eq(row_source_json_page_next_cursor(page).unwrap(), "")
  for suffix in ["", ",\"next\":null"] {
    let page = json_page_test("{\"items\":[]" + suffix + "}", rows=0).unwrap()
    assert_eq(row_source_json_page_rows_wire(page), "[]")
    assert_eq(row_source_json_page_row_count(page), 0)
    assert_false(row_source_json_page_has_next_cursor(page))
    assert_true(row_source_json_page_next_cursor(page) is Err(NoNextCursor))
  }
  let page = project_row_source_json_page(
    @utf8.encode("{\"é\":{\"rows\":[]},\"é\":1,\"cursor\":\"é\\r\\n\"}"),
    ["é", "rows"],
    true,
    ["cursor"],
    4096,
    256,
    16,
    0,
    64,
  ).unwrap()
  assert_eq(row_source_json_page_next_cursor(page).unwrap(), "é\r\n")
}

///|
test "original JSON page validates whole body rows paths cursor and every bound before output" {
  for
    body in [
      "{\"items\":[{},1]}", "{\"items\":{}}", "{\"items\":null}", "{}", "{\"items\":[{\"a\":1,\"a\":2}]}",
      "{\"items\":[],\"ignored\":{\"a\":1,\"a\":2}}", "{\"items\":[],\"next\":false}",
      "{\"items\":[],\"next\":1}", "{\"items\":[],\"next\":{}}", "{\"items\":[],\"next\":[]}",
      "{\"items\":[]} trailing",
    ] {
    assert_true(json_page_test(body) is Err(_))
  }
  let bytes = @utf8.encode("{\"items\":[{}],\"next\":\"é\"}")
  for
    (bound, nodes, depth, rows, cursor) in [
      (bytes.length() - 1, 256, 16, 1, 64),
      (4096, 1, 16, 1, 64),
      (4096, 256, 1, 1, 64),
      (4096, 256, 16, 0, 64),
      (4096, 256, 16, 1, 1),
    ] {
    assert_true(
      project_row_source_json_page(
        bytes,
        ["items"],
        true,
        ["next"],
        bound,
        nodes,
        depth,
        rows,
        cursor,
      )
      is Err(_),
    )
  }
  assert_true(
    project_row_source_json_page(b"\xff", [], false, [], 4096, 256, 16, 1, 64)
    is Err(InvalidPage),
  )
  assert_true(
    project_row_source_json_page(
      b"[]",
      [],
      false,
      ["unexpected"],
      4096,
      256,
      16,
      1,
      64,
    )
    is Err(InvalidLimits),
  )
}

///|
test "original JSON page array enters existing full row admission without dropping fields or rounding" {
  let rows = "[{\"id\":1,\"payload\":{\"$json\":\"literal\",\"é\":1,\"é\":2},\"é\":null}]"
  let page = json_page_test("{\"items\":" + rows + "}").unwrap()
  let read = physical_row_json_read()
  assert_eq(
    accept_row_source_page(
      read,
      @utf8.encode(row_source_json_page_rows_wire(page)),
    ).unwrap(),
    1,
  )
  let exact = json_page_test("{\"items\":[{\"id\":\"9223372036854775807\"}]}").unwrap()
  let (_, signed) = signed64_row_read()
  assert_eq(
    accept_row_source_page(
      signed,
      @utf8.encode(row_source_json_page_rows_wire(exact)),
    ).unwrap(),
    1,
  )
  let numeric = json_page_test("{\"items\":[{\"id\":9223372036854775807}]}").unwrap()
  assert_eq(
    row_source_json_page_rows_wire(numeric),
    "[{\"id\":9223372036854775807}]",
  )
  let (_, rejected) = signed64_row_read()
  assert_true(
    accept_row_source_page(
      rejected,
      @utf8.encode(row_source_json_page_rows_wire(numeric)),
    )
    is Err(_),
  )
}

///|
test "original JSON page supports root arrays and bounded nullable nested cursor paths" {
  let rows = "[ {\"id\":\"1\"} ]"
  let root = project_row_source_json_page(
    @utf8.encode(" \r\n" + rows + "\t"),
    [],
    false,
    [],
    4096,
    256,
    16,
    1,
    0,
  ).unwrap()
  assert_eq(row_source_json_page_rows_wire(root), rows)
  assert_false(row_source_json_page_has_next_cursor(root))
  let nested = project_row_source_json_page(
    @utf8.encode(
      "{\"ignored\":\"🚀\",\"data\":{\"rows\":" +
      rows +
      "},\"paging\":{\"cursor\":\"\"}}",
    ),
    ["data", "rows"],
    true,
    ["paging", "cursor"],
    4096,
    256,
    16,
    1,
    0,
  ).unwrap()
  assert_eq(row_source_json_page_rows_wire(nested), rows)
  assert_true(row_source_json_page_has_next_cursor(nested))
  assert_eq(row_source_json_page_next_cursor(nested).unwrap(), "")
  for cursor in ["null", "{}"] {
    let page = project_row_source_json_page(
      @utf8.encode("{\"items\":[],\"paging\":" + cursor + "}"),
      ["items"],
      true,
      ["paging", "cursor"],
      4096,
      256,
      16,
      0,
      64,
    ).unwrap()
    assert_false(row_source_json_page_has_next_cursor(page))
  }
  for cursor in ["false", "[]", "{\"cursor\":false}"] {
    assert_true(
      project_row_source_json_page(
        @utf8.encode("{\"items\":[],\"paging\":" + cursor + "}"),
        ["items"],
        true,
        ["paging", "cursor"],
        4096,
        256,
        16,
        0,
        64,
      )
      is Err(InvalidCursor),
    )
  }
}
