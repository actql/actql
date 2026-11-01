///|
fn source_command_projection(command : String) -> Unit raise {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  // Explicit declaration DATA exercises this original projection only, not
  // Common Catalog admission, Resource backing or installed execution.
  let original : Json = {
    "catalog": "{\"commands\":[],\"contracts\":[]}",
    "contracts": [],
    "view_bodies": ["original-view"],
  }
  let combined = range_catalog_json(original.stringify(), command, limits).unwrap()
  guard @json.parse(combined) is Object(projected) else {
    fail("Expected declaration projection")
  }
  guard @json.parse(command) is Object(command) else {
    fail("Expected original command")
  }
  guard command["installed"] is Object(installed) else {
    fail("Expected original installed command")
  }
  assert_eq(projected["command_bodies"], Json::array([installed["body"]]))
  assert_eq(projected["view_bodies"], Json::array(["original-view".to_json()]))
  // Adding the retained body does not change the original Catalog's command
  // or its contracts. Environment construction can consume that SAME body.
  guard projected["catalog"] is String(catalog_wire) else {
    fail("Expected catalog wire")
  }
  guard @json.parse(catalog_wire) is Object(catalog) else {
    fail("Expected catalog")
  }
  assert_eq(catalog["commands"], Json::array([command["command"]]))
}

///|
test "Sheets range Source projection retains the original installed Command body for common Environment construction" {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  source_command_projection(
    range_command_json(
      "sheets-book", "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]",
      "{\"sheetId\":7,\"startRow\":0,\"endRow\":1,\"startColumn\":0,\"endColumn\":1}",
      limits,
    ).unwrap(),
  )
}

///|
test "Sheets clear Source projection retains its distinct original Command body without a second Environment recipe" {
  let limits : Limits = {
    max_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  source_command_projection(
    clear_command_json(
      "sheets-book", "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]",
      "{\"sheetId\":7,\"startRow\":0,\"endRow\":1,\"startColumn\":0,\"endColumn\":1}",
      limits,
    ).unwrap(),
  )
}
