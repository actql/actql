///|
test "project connections retain exact selected value spans and original order" {
  let first = "{ \"connector\" : \"notion\", \"databases\":{}, \"credentials\":{\"integration_token\":{\"env\":\"N\\u004fTION\"}} }"
  let second = "{\"connector\":\"future-connector\",\"original\":\"é😀\"}"
  let wire = " \n{\"version\":\"actql-connectors/0.1\",\"connections\":{\"café😀\":" +
    first +
    ",\"second\":" +
    second +
    "}}\n"
  let original = admit_client_project_connections(wire).unwrap()
  assert_eq(original.original_wire(), wire)
  assert_eq(original.count(), 2)
  assert_eq(original.at(0), Some(("café😀", "notion", first)))
  assert_eq(original.at(1), Some(("second", "future-connector", second)))
  assert_eq(original.at(-1), None)
  assert_eq(original.at(2), None)
}

///|
test "project connections reject invalid unused members and duplicate originals" {
  let valid = "\"valid\":{\"connector\":\"notion\"}"
  for
    entry in [
      "null", "[]", "false", "{}", "{\"connector\":null}", "{\"connector\":false}",
      "{\"connector\":\"\"}", "{\"connector\":\"a\\u0000b\"}", "{\"connector\":\"notion\",\"connector\":\"notion\"}",
      "{\"connector\":\"notion\",\"credentials\":{\"x\":1,\"x\":2}}",
    ] {
    assert_true(
      admit_client_project_connections(
        "{\"version\":\"actql-connectors/0.1\",\"connections\":{" +
        valid +
        ",\"unused\":" +
        entry +
        "}}",
      )
      is Err(InvalidBindings),
    )
  }
  for
    wire in [
      "null", "[]", "{}", "{\"version\":\"unsupported\",\"connections\":{}}", "{\"version\":\"actql-connectors/0.1\",\"connections\":null}",
      "{\"version\":\"actql-connectors/0.1\",\"connections\":[]}", "{\"version\":\"actql-connectors/0.1\",\"connections\":{},\"allow\":true}",
      "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"x\":{\"connector\":\"a\"},\"x\":{\"connector\":\"b\"}}}",
      "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"\":{\"connector\":\"a\"}}}",
    ] {
    assert_true(admit_client_project_connections(wire) is Err(InvalidBindings))
  }
}

///|
test "project connections preserve original wire geometry without a source-free fallback" {
  let wire = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"n\":{\"connector\":\"notion\"}}}"
  let exact = wire + String::make(65536 - wire.length(), ' ')
  assert_eq(
    admit_client_project_connections(exact).unwrap().original_wire(),
    exact,
  )
  assert_eq(
    admit_client_project_connections(exact + " ").unwrap().original_wire(),
    exact + " ",
  )
  assert_true(
    admit_client_source_free_project_bindings(Some(wire), None)
    is Err(BindingsUnavailable),
  )
  let empty = "{\"version\":\"actql-connectors/0.1\",\"connections\":{}}"
  assert_eq(admit_client_project_connections(empty).unwrap().count(), 0)
  assert_true(
    admit_client_source_free_project_bindings(Some(empty), None) is Ok(_),
  )
}
