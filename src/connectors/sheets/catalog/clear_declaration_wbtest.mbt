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
  let expected = "sha256:a62ffa81aaa9baea1bc589e0cf117c8665e78f09b890161c3b56d392e5df859a"
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
    "sha256:6089e4d88766135685e548243a3e4a294d8e37a27a12d72516a005f2a5b4bcc5",
  )
  assert_eq(
    range_contract_cid(contracts[1]),
    "sha256:fc9fa0579508e4c3633701b21108710759ea4c8cc34f0d48a34a9df472272de2",
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
