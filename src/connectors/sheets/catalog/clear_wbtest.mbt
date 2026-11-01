// Fixed Google wire and framed identity independently authored by Python.

///|
fn clear_fixed_marker() -> String {
  "12345678-1234-4234-8234-123456789abc"
}

///|
fn clear_fixed_body() -> String {
  "{\"requests\":[{\"updateCells\":{\"range\":{\"sheetId\":7,\"startRowIndex\":2,\"endRowIndex\":4,\"startColumnIndex\":1,\"endColumnIndex\":3},\"rows\":[],\"fields\":\"userEnteredValue\"}},{\"createDeveloperMetadata\":{\"developerMetadata\":{\"metadataKey\":\"actql_request\",\"metadataValue\":\"{\\\"marker\\\":\\\"12345678-1234-4234-8234-123456789abc\\\",\\\"range\\\":{\\\"endColumn\\\":3,\\\"endRow\\\":4,\\\"sheetId\\\":7,\\\"startColumn\\\":1,\\\"startRow\\\":2}}\",\"location\":{\"sheetId\":7},\"visibility\":\"DOCUMENT\"}}}]}"
}

///|
fn clear_fixed_reply() -> String {
  "{\"spreadsheetId\":\"book\",\"replies\":[{},{\"createDeveloperMetadata\":{\"developerMetadata\":{\"metadataId\":17,\"metadataKey\":\"actql_request\",\"metadataValue\":\"{\\\"marker\\\":\\\"12345678-1234-4234-8234-123456789abc\\\",\\\"range\\\":{\\\"endColumn\\\":3,\\\"endRow\\\":4,\\\"sheetId\\\":7,\\\"startColumn\\\":1,\\\"startRow\\\":2}}\",\"location\":{\"sheetId\":7},\"visibility\":\"DOCUMENT\"}}}]}"
}

///|
fn clear_fixed_target() -> String {
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"identity_cid\":\"sha256:3df522c65a0e49bd6aa3b16c946d9b5f587b824800bbdc6e021654f4a524042d\",\"provider_identity_cid\":\"sha256:d7482f414734110c3d1775460ab9c00fd769271779374b48ceef7bf4ecc73845\",\"provider_namespace\":\"sheets\",\"resource_kind\":\"sheet_range\",\"version\":\"actql-resource-ref/0.1\"}"
}

///|
fn clear_grid() -> GridRange {
  { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 3, }
}

///|
fn clear_columns() -> Array[Column] {
  [
    { name: "text", cell_type: Text, nullable: false, },
    { name: "flag", cell_type: Boolean, nullable: true, },
  ]
}

///|
fn clear_limits() -> Limits {
  { max_bytes: 300000, max_nodes: 200000, max_depth: 32, max_cells: 6400, }
}

///|
test "explicit clear masks only values and atomically retains its original marker" {
  let body = clear_request(
    clear_grid(),
    clear_columns(),
    clear_fixed_marker(),
    clear_limits(),
  ).unwrap()
  assert_eq(body, clear_fixed_body())
  assert_false(body.contains("formulaValue"))
  assert_false(body.contains("userEnteredFormat"))
  assert_false(body.contains("deleteDimension"))
  assert_true(
    update_request(clear_grid(), clear_columns(), [], clear_limits())
    is Err(InvalidRange),
  )
}

///|
test "clear has an independent framed domain and exact immutable body target identity" {
  let body = clear_request(
    clear_grid(),
    clear_columns(),
    clear_fixed_marker(),
    clear_limits(),
  ).unwrap()
  let origin = "https://sheets.example.test"
  let path = "/v4/spreadsheets/book:batchUpdate"
  let expected = "sha256:81315af16226c59724b599898ad401dae6b8e15410312e4d2de4fc23a3d42fd3"
  assert_eq(
    clear_request_identity(origin, path, body, clear_fixed_target()),
    Ok(expected),
  )
  assert_not_eq(
    range_request_cid(origin, path, body, clear_fixed_target()),
    Ok(expected),
  )
  assert_not_eq(
    clear_request_identity(
      origin + "/foreign",
      path,
      body,
      clear_fixed_target(),
    ),
    Ok(expected),
  )
  assert_not_eq(
    clear_request_identity(
      origin,
      path + "?foreign=1",
      body,
      clear_fixed_target(),
    ),
    Ok(expected),
  )
  assert_not_eq(
    clear_request_identity(origin, path, body + "\n", clear_fixed_target()),
    Ok(expected),
  )
  assert_not_eq(clear_request_identity(origin, path, body, "{}"), Ok(expected))
}

///|
test "clear requires bounded exact geometry and one original canonical marker" {
  for
    marker in [
      "",
      "12345678-1234-1234-8234-123456789abc",
      "12345678-1234-4234-0234-123456789abc",
      "12345678-1234-4234-8234-123456789ABC",
      clear_fixed_marker() + "extra",
    ] {
    assert_true(
      clear_request(clear_grid(), clear_columns(), marker, clear_limits())
      is Err(InvalidSchema),
    )
  }
  let grid = clear_grid()
  assert_true(
    clear_request(
      { ..grid, end_row: grid.start_row, },
      clear_columns(),
      clear_fixed_marker(),
      clear_limits(),
    )
    is Err(InvalidRange),
  )
  assert_true(
    clear_request(grid, [], clear_fixed_marker(), clear_limits())
    is Err(InvalidSchema),
  )
  let bytes = @utf8.encode(clear_fixed_body()).length()
  assert_true(
    clear_request(grid, clear_columns(), clear_fixed_marker(), {
      ..clear_limits(),
      max_bytes: bytes,
    })
    is Ok(_),
  )
  assert_true(
    clear_request(grid, clear_columns(), clear_fixed_marker(), {
      ..clear_limits(),
      max_bytes: bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    clear_request(grid, clear_columns(), clear_fixed_marker(), {
      ..clear_limits(),
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    clear_request(grid, clear_columns(), clear_fixed_marker(), {
      ..clear_limits(),
      max_cells: 3,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "clear acknowledgement requires the same marker geometry and complete atomic reply" {
  let body = @utf8.encode(clear_fixed_reply())
  assert_eq(
    classify_clear(
      200,
      body,
      "book",
      clear_grid(),
      clear_fixed_marker(),
      clear_limits(),
    ),
    Applied,
  )
  assert_eq(
    classify_clear(
      200,
      body,
      "other",
      clear_grid(),
      clear_fixed_marker(),
      clear_limits(),
    ),
    Unknown,
  )
  assert_eq(
    classify_clear(
      429,
      body,
      "book",
      clear_grid(),
      clear_fixed_marker(),
      clear_limits(),
    ),
    Unknown,
  )
  assert_eq(
    classify_clear(
      200,
      body,
      "book",
      clear_grid(),
      "12345678-1234-4234-8234-123456789abd",
      clear_limits(),
    ),
    Unknown,
  )
  assert_eq(
    classify_clear(
      200,
      body,
      "book",
      { ..clear_grid(), end_row: 5, },
      clear_fixed_marker(),
      clear_limits(),
    ),
    Unknown,
  )
  assert_eq(
    classify_clear(
      200,
      @utf8.encode("{\"spreadsheetId\":\"book\",\"replies\":[{}]}"),
      "book",
      clear_grid(),
      clear_fixed_marker(),
      clear_limits(),
    ),
    Unknown,
  )
  assert_eq(
    classify_clear(200, body, "book", clear_grid(), clear_fixed_marker(), {
      ..clear_limits(),
      max_bytes: body.length() - 1,
    }),
    Unknown,
  )
}

///|
test "clear acknowledgement marker canonical projection has its original fixed geometry" {
  let marker = clear_fixed_marker()
  let value = clear_marker_value(
    {
      sheet_id: 2147483647,
      start_row: 2147483646,
      end_row: 2147483647,
      start_column: 2147483646,
      end_column: 2147483647,
    },
    marker,
  )
  assert_eq(range_template_nodes(value), 8)
  assert_eq(range_template_depth(value), 2)
  let wire = range_canonical(value, clear_limits()).unwrap()
  assert_true(@utf8.encode(wire).length() <= 256)
  let canonical = @canonical.from_json(value, 8, 2, 256, data_keys=true) catch {
    _ => fail("same closed value")
  }
  let extent = @canonical.representation_extent(canonical, 8, 2, 256).unwrap()
  assert_eq(extent.nodes, 8L)
  assert_eq(extent.objects, 2L)
  assert_eq(extent.arrays, 0L)
}
