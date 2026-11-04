///|
fn managed_quote_original(nested : Bool) -> RecordDeclaration {
  let body = if nested {
    b"{\"revision\":\"7\",\"properties\":{\"Items\":{\"code\":\"Items\",\"type\":\"SUBTABLE\",\"fields\":{\"Label\":{\"code\":\"Label\",\"type\":\"SINGLE_LINE_TEXT\"}}}}}"
  } else {
    b"{\"revision\":\"7\",\"properties\":{\"Items\":{\"code\":\"Items\",\"type\":\"SINGLE_LINE_TEXT\"}}}"
  }
  declare_records(
    @catalog.project_form_fields(body, "12", read_quote_form_limits()).unwrap(),
    None,
    ["Items"],
    "kintone",
    "kintone/0.1",
    "rows",
    read_quote_value_limits(),
    read_quote_declaration_limits(),
  ).unwrap()
}

///|
fn managed_quote_pages() -> @catalog.RecordPageLimits {
  {
    max_bytes: 64,
    max_nodes: 1000,
    max_depth: 24,
    max_rows: 2,
    max_columns: 16,
    max_cells: 64,
    max_table_rows: 16,
  }
}

///|
test "managed Kintone base derives original selection and bounds request copies" {
  let original = managed_quote_original(true)
  let quote = fn(maximum) {
    managed_record_construction_capacity(
      original,
      managed_quote_pages(),
      read_quote_value_limits(),
      100,
      2,
      maximum,
    ).unwrap()
  }
  let small = @execution.execution_capacity_execution_bytes(quote(64))
  let enough = @execution.execution_capacity_execution_bytes(quote(8192))
  assert_true(small > 0L)
  assert_true(enough > small)
  assert_eq(
    enough,
    @execution.execution_capacity_execution_bytes(quote(2147483647)),
  )
  assert_true(
    managed_record_construction_capacity(
      original,
      managed_quote_pages(),
      read_quote_value_limits(),
      100,
      3,
      8192,
    )
    is None,
  )
  assert_true(
    managed_record_construction_capacity(
      original,
      managed_quote_pages(),
      read_quote_value_limits(),
      0,
      2,
      8192,
    )
    is None,
  )
}

///|
test "managed Kintone Form inventory keeps original copied paths independent of new body" {
  let flat = managed_quote_original(false)
  let nested = managed_quote_original(true)
  let geometry = @catalog.form_construction_geometry(nested.catalog).unwrap()
  assert_eq(geometry.fields, 2)
  assert_eq(geometry.path_slots, 3L)
  assert_eq(geometry.max_path_depth, 2)
  let form = read_quote_form_limits()
  let flat_units = managed_record_form_inventory(flat, 32, form).unwrap()
  let nested_units = managed_record_form_inventory(nested, 32, form).unwrap()
  assert_true(nested_units.record_headers > flat_units.record_headers)
  assert_true(nested_units.reference_slots > flat_units.reference_slots)
  let larger = managed_record_form_inventory(nested, 64, form).unwrap()
  assert_true(larger.record_headers > nested_units.record_headers)
  let unused = managed_record_form_inventory(nested, 32, {
    ..form,
    max_bytes: 2147483647,
    max_nodes: 2147483647,
    max_depth: 2147483647,
  }).unwrap()
  // The effective depth differs (24 versus 32), but a still larger unused
  // ceiling cannot grow the same 32-byte construction again.
  let bounded = managed_record_form_inventory(nested, 32, {
    ..form,
    max_nodes: 32,
    max_depth: 32,
  }).unwrap()
  assert_eq(unused.record_headers, bounded.record_headers)
  assert_eq(unused.reference_slots, bounded.reference_slots)
  assert_eq(unused.owned_utf16_units, bounded.owned_utf16_units)
  assert_true(managed_record_form_inventory(nested, -1, form) is None)
  assert_true(
    managed_record_form_inventory(nested, form.max_bytes + 1, form) is None,
  )
  assert_true(
    managed_record_form_inventory(nested, 32, { ..form, max_fields: 0, })
    is None,
  )
}

///|
test "managed Kintone page quote follows actual bytes and original empty table geometry" {
  let original = managed_quote_original(true)
  let body = b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"1\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"1\"},\"Items\":{\"type\":\"SUBTABLE\",\"value\":[]}}],\"totalCount\":null}"
  let pages = { ..managed_quote_pages(), max_bytes: 8192, }
  let values = read_quote_value_limits()
  let page = @catalog.project_record_page(
    body,
    original.catalog,
    original.names,
    pages,
  ).unwrap()
  @catalog.project_checked_record_page(page, None, values).unwrap() |> ignore
  let geometry = @catalog.selected_form_construction_geometry(
    original.catalog,
    original.names,
  ).unwrap()
  assert_eq(geometry.fields, 2)
  assert_eq(geometry.tables, 1)
  assert_eq(geometry.max_children, 1)
  assert_eq(geometry.code_units, 10L)
  let quote = fn(bytes, selected_pages) {
    managed_record_page_inventory(
      original,
      original.names,
      2,
      bytes,
      selected_pages,
      values,
      100,
    ).unwrap()
  }
  let units = quote(body.length(), pages)
  let capacity = managed_record_capacity(units).unwrap()
  println(
    "Kintone managed page body_bytes=\{body.length()} native_bytes=\{@execution.execution_capacity_execution_bytes(capacity)}",
  )
  assert_true(units.record_headers > 0L)
  let large_ceiling = quote(body.length(), {
    ..pages,
    max_bytes: 2147483647,
    max_nodes: 2147483647,
    max_depth: 2147483647,
  })
  let actual_bound = quote(body.length(), {
    ..pages,
    max_nodes: body.length(),
    max_depth: body.length(),
  })
  assert_eq(large_ceiling.record_headers, actual_bound.record_headers)
  assert_eq(large_ceiling.reference_slots, actual_bound.reference_slots)
  assert_eq(large_ceiling.owned_utf16_units, actual_bound.owned_utf16_units)
  let smaller = quote(32, pages)
  assert_true(units.record_headers > smaller.record_headers)
  assert_true(
    managed_record_page_inventory(
      original,
      original.names,
      2,
      -1,
      pages,
      values,
      100,
    )
    is None,
  )
  assert_true(
    managed_record_page_inventory(
      original,
      original.names,
      2,
      8193,
      pages,
      values,
      100,
    )
    is None,
  )
}

///|
test "managed Kintone page inventory accompanies synthetic table id and timestamp normalization" {
  let form = b"{\"revision\":\"7\",\"properties\":{\"Items\":{\"code\":\"Items\",\"type\":\"SUBTABLE\",\"fields\":{\"When\":{\"code\":\"When\",\"type\":\"DATETIME\"}}}}}"
  let values = read_quote_value_limits()
  let original = declare_records(
    @catalog.project_form_fields(form, "12", read_quote_form_limits()).unwrap(),
    None,
    ["Items"],
    "kintone",
    "kintone/0.1",
    "rows",
    values,
    read_quote_declaration_limits(),
  ).unwrap()
  let body = b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"1\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"1\"},\"Items\":{\"type\":\"SUBTABLE\",\"value\":[{\"id\":\"9007199254740993\",\"value\":{\"When\":{\"type\":\"DATETIME\",\"value\":\"2026-11-03T01:02:03Z\"}}}]}}],\"totalCount\":null}"
  let pages = { ..managed_quote_pages(), max_bytes: 8192, }
  let units = managed_record_page_inventory(
    original,
    original.names,
    2,
    body.length(),
    pages,
    values,
    100,
  ).unwrap()
  assert_true(units.owned_utf16_units >= 43L)
  let page = @catalog.project_record_page(
    body,
    original.catalog,
    original.names,
    pages,
  ).unwrap()
  let checked = @catalog.project_checked_record_page(page, None, values).unwrap()
  let row = @catalog.checked_record_rows(checked)[0]
  let writer = @encode.writer(8192, 1000, 24)
  @admitted.emit_checked_wire_value(row[1], writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("9007199254740993"))
  assert_true(wire.contains("2026-11-03T01:02:03.000Z"))
  println(
    "Kintone managed normalized body_bytes=\{body.length()} native_bytes=\{@execution.execution_capacity_execution_bytes(managed_record_capacity(units).unwrap())}",
  )
}

///|
test "managed Kintone identity extent derives original fields without target serialization" {
  let body = b"{\"revision\":\"7\",\"properties\":{\"Items\":{\"code\":\"Items\",\"type\":\"SINGLE_LINE_TEXT\"},\"Extra\":{\"code\":\"Extra\",\"type\":\"SINGLE_LINE_TEXT\"}}}"
  let catalog = @catalog.project_form_fields(
    body,
    "12",
    read_quote_form_limits(),
  ).unwrap()
  let make = fn(names) {
    declare_records(
      catalog,
      None,
      names,
      "kintone",
      "kintone/0.1",
      "rows",
      read_quote_value_limits(),
      read_quote_declaration_limits(),
    ).unwrap()
  }
  let one = make(["Items"])
  let two = make(["Items", "Extra"])
  assert_eq(managed_record_column_count(one), 2)
  assert_eq(managed_record_column_count(two), 3)
  let quote = fn(original, guest) {
    managed_record_identity_units(
      original, "https://example.invalid", "rows", guest,
    ).unwrap()
  }
  assert_eq(quote(two, "") - quote(one, ""), 3L + 6L * 5L)
  assert_eq(quote(one, "123") - quote(one, ""), 18L)
  assert_eq(
    quote(one, ""),
    256L + 3L * 2L + 71L + 6L * (3L + 2L + 23L + 4L + 5L),
  )
}
