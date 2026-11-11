///|
test "project catalog preserves exact nested declaration spans and connection order" {
  let first = "{ \"views\" : [{\"schema\":{\"label\":{\"type\":\"string\",\"nullable\":false}},\"raw\":9007199254740993}], \"label\":\"e\\u0301😀\" }"
  let second = "{\"views\":[],\"query_aliases\":[]}"
  let wire = " \n{\"connections\":{\"café😀\":" +
    first +
    ",\"second\":" +
    second +
    "}}\n"
  let original = admit_client_project_catalog(wire).unwrap()
  assert_eq(original.original_wire(), wire)
  assert_eq(original.count(), 2)
  assert_eq(original.at(0), Some(("café😀", first)))
  assert_eq(original.at(1), Some(("second", second)))
  assert_eq(original.at(-1), None)
  assert_eq(original.at(2), None)
}

///|
test "project catalog rejects malformed unused entries and duplicates at every depth" {
  for
    entry in [
      "null", "[]", "false", "42", "\"text\"", "{\"views\":[],\"views\":[]}", "{\"views\":[],\"v\\u0069ews\":[]}",
      "{\"views\":[{\"schema\":{\"id\":{\"type\":\"string\",\"type\":\"string\"}}}]}",
      "{\"value\":\"\\ud800\"}",
    ] {
    assert_true(
      admit_client_project_catalog(
        "{\"connections\":{\"valid\":{},\"unused\":" + entry + "}}",
      )
      is Err(InvalidCatalog),
    )
  }
  for
    wire in [
      "null", "[]", "{}", "{\"connections\":null}", "{\"connections\":[]}", "{\"connections\":{},\"version\":\"unknown\"}",
      "{\"connections\":{},\"allow\":true}", "{\"connections\":{},\"connections\":{}}",
      "{\"connections\":{\"x\":{},\"x\":{}}}", "{\"connections\":{\"x\":{},\"\\u0078\":{}}}",
      "{\"connections\":{\"\":{}}}", "{\"connections\":{\"a\\u0000b\":{}}}", "{\"connections\":{}}{}",
    ] {
    assert_true(admit_client_project_catalog(wire) is Err(InvalidCatalog))
  }
}

///|
test "project catalog retains empty declared range and exact bounded intake" {
  let wire = "{\"connections\":{}}"
  let empty = admit_client_project_catalog(wire).unwrap()
  assert_eq(empty.count(), 0)
  assert_eq(empty.at(0), None)
  let exact = wire + String::make(65536 - wire.length(), ' ')
  assert_eq(admit_client_project_catalog(exact).unwrap().original_wire(), exact)
  assert_true(admit_client_project_catalog(exact + " ") is Err(InvalidCatalog))
  let deep = "{\"connections\":{\"x\":{\"value\":" +
    "[".repeat(17) +
    "0" +
    "]".repeat(17) +
    "}}}"
  assert_true(admit_client_project_catalog(deep) is Err(InvalidCatalog))
}
