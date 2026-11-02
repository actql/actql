///|
fn read_quote_form_limits() -> @catalog.FormFieldLimits {
  {
    max_bytes: 8192,
    max_nodes: 2000,
    max_depth: 24,
    max_fields: 16,
    max_name_units: 512,
  }
}

///|
fn read_quote_value_limits() -> @catalog.RecordValueLimits {
  {
    max_columns: 16,
    max_name_bytes: 512,
    max_nodes: 2000,
    max_depth: 24,
    max_text_bytes: 8192,
  }
}

///|
fn read_quote_declaration_limits() -> @rows.RowDeclarationLimits {
  {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 24,
    max_views: 1,
    max_fields: 16,
  }
}

///|
test "Kintone quote backs original nested SUBTABLE schema and fixed id facts" {
  let body = b"{\"revision\":\"7\",\"properties\":{\"Items\":{\"code\":\"Items\",\"type\":\"SUBTABLE\",\"fields\":{\"Label\":{\"code\":\"Label\",\"type\":\"SINGLE_LINE_TEXT\"}}}}}"
  let form = read_quote_form_limits()
  let values = read_quote_value_limits()
  let declaration = read_quote_declaration_limits()
  let capacity = record_read_declaration_construction_capacity(
    body.length(),
    4 * ((body.length() + 2) / 3),
    1,
    5,
    2,
    4,
    7,
    11,
    form,
    values,
    declaration,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(capacity)
  println("Kintone constructor body_bytes=\{body.length()} peak_bytes=\{peak}")
  assert_true(peak < 536870912L)
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), peak)
  let catalog = @catalog.project_form_fields(body, "12", form).unwrap()
  let original = declare_records(
    catalog,
    None,
    ["Items"],
    "kintone",
    "kintone/0.1",
    "rows",
    values,
    declaration,
  ).unwrap()
  let declared = record_declaration(original)
  assert_eq(declared.views[0].fields, ["$id", "Items"])
  assert_true(declared.catalog.contains("candidate_keys"))
}

///|
test "Kintone quote refuses invalid geometry and keeps unused output ceiling neutral" {
  let quote = fn(bytes, maximum) {
    record_read_declaration_construction_capacity(
      bytes,
      268,
      1,
      5,
      2,
      4,
      7,
      11,
      read_quote_form_limits(),
      read_quote_value_limits(),
      { ..read_quote_declaration_limits(), max_bytes: maximum, },
    )
  }
  assert_true(quote(-1, 200000) is None)
  assert_true(quote(8193, 200000) is None)
  assert_eq(
    @execution.execution_capacity_execution_bytes(quote(200, 200000).unwrap()),
    @execution.execution_capacity_execution_bytes(quote(200, 200001).unwrap()),
  )
}
