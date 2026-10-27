///|
fn clear_columns_wire() -> String {
  "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]"
}

///|
fn clear_range_wire() -> String {
  "{\"sheetId\":7,\"startRow\":2,\"endRow\":4,\"startColumn\":1,\"endColumn\":3}"
}

///|
test "clear Command keeps the complete closed role bodies and independent identities" {
  let wire = clear_command_json(
    "sheets-book",
    clear_columns_wire(),
    clear_range_wire(),
    owned_limits(),
  ).unwrap()
  let parsed = @json.parse(wire) catch { _ => abort("clear declaration") }
  guard parsed is Object(root) &&
    root.get("command") is Some(Object(command)) &&
    root.get("contracts") is Some(Array(contracts)) else {
    abort("clear declaration")
  }
  let expected = "sha256:54f3da4509fc84f409ea96b9bcb93d10cde9c71190c01d3b90ff2745774f0c1a"
  assert_eq(command.get("contract_cid"), Some(expected.to_json()))
  command.remove("contract_cid") |> ignore
  assert_eq(
    range_content_cid(Json::object(command), owned_limits()),
    Ok(expected),
  )
  assert_eq(
    command.get("command_id"),
    Some("command:sheets-book.sheets.clear_range.v1".to_json()),
  )
  assert_eq(command.get("permissions"), Some(["sheets:cells:clear"].to_json()))
  assert_eq(
    command.get("input_contract"),
    Some(({ "additional_properties": false, "fields": {} } : Json)),
  )
  assert_eq(contracts.length(), 2)
  assert_eq(
    range_contract_cid(contracts[0]),
    "sha256:99915de3605da823974eb6955042ad0dc027197bfdbba15b1ba4fe151c7c20c5",
  )
  assert_eq(
    range_contract_cid(contracts[1]),
    "sha256:6cb65e3a8f8e63fe9d44b570fe3165791157d6598d4b76c1ffc224dbab2e4536",
  )
}

///|
test "clear declaration refuses invalid or oversized original grid configuration" {
  for
    range in [
      "null", "{}", "{\"sheetId\":7,\"startRow\":4,\"endRow\":2,\"startColumn\":1,\"endColumn\":3}",
    ] {
    assert_true(
      clear_command_json(
        "sheets-book",
        clear_columns_wire(),
        range,
        owned_limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    clear_command_json("sheets-book", "[]", clear_range_wire(), owned_limits())
    is Err(_),
  )
  assert_true(
    clear_command_json(
      "sheets-book",
      clear_columns_wire(),
      clear_range_wire(),
      { ..owned_limits(), max_cells: 3, },
    )
    is Err(_),
  )
  assert_true(
    clear_command_json(
      "sheets-book",
      clear_columns_wire(),
      clear_range_wire(),
      { ..owned_limits(), max_bytes: 1, },
    )
    is Err(_),
  )
}
