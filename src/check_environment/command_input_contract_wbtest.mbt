///|
fn command_presence_cursor(wire : String) -> @decode.Cursor {
  let source = @source.parse_json(wire, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 32,
  }).unwrap()
  @decode.admit(source, {
    max_nodes: 1000,
    max_depth: 32,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
}

///|
fn command_presence_body(required : String) -> String {
  "{\"additional_properties\":false,\"fields\":{\"name\":{\"nullable\":false,\"type\":\"string\"},\"overwrite\":{\"nullable\":false,\"type\":\"boolean\"}},\"required_fields\":" +
  required +
  "}"
}

///|
fn command_presence_limits() -> @value_contract.Limits {
  { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, }
}

///|
test "Command presence retains required subset without optional values or a general Object type" {
  let body = command_presence_body("[\"name\"]")
  let original = read_command_input_contract(
    command_presence_cursor(body),
    command_presence_limits(),
  ).unwrap()
  assert_eq(command_input_contract_field_count(original), 2)
  assert_eq(command_input_contract_field_at(original, 0).unwrap().name, "name")
  assert_true(command_input_contract_field_required(original, "name"))
  assert_false(command_input_contract_field_required(original, "overwrite"))
  assert_true(command_input_contract_field_at(original, 2) is None)
  let (nodes, text) = command_input_contract_usage(original)
  assert_true(nodes > 0 && text > 0)
  assert_true(
    read_command_input_contract(command_presence_cursor(body), {
      ..command_presence_limits(),
      max_nodes: nodes,
      max_text_bytes: text,
    })
    is Ok(_),
  )
  for
    limits in [
      { ..command_presence_limits(), max_nodes: nodes - 1, },
      { ..command_presence_limits(), max_text_bytes: text - 1, },
    ] {
    assert_true(
      read_command_input_contract(command_presence_cursor(body), limits)
      is Err(CommandInputBudget),
    )
  }
  assert_true(
    command_input_contract_matches(original, command_presence_cursor(body), 100).unwrap().0,
  )
  assert_false(
    command_input_contract_matches(
      original,
      command_presence_cursor(command_presence_body("[]")),
      100,
    ).unwrap().0,
  )
}

///|
test "Command presence refuses invalid subsets and invalid omitted child contracts" {
  for required in ["null", "{}", "[1]", "[\"name\",\"name\"]", "[\"unknown\"]"] {
    assert_true(
      read_command_input_contract(
        command_presence_cursor(command_presence_body(required)),
        command_presence_limits(),
      )
      is Err(_),
    )
  }
  let optional = command_presence_body("[]")
  assert_true(
    read_command_input_contract(
      command_presence_cursor(optional),
      command_presence_limits(),
    )
    is Ok(_),
  )
  let invalid = optional.replace(
    old="\"type\":\"boolean\"",
    new="\"type\":\"unknown\"",
  )
  assert_true(
    read_command_input_contract(
      command_presence_cursor(invalid),
      command_presence_limits(),
    )
    is Err(InvalidCommandInputType("overwrite", _)),
  )
  let first = read_command_input_contract(
    command_presence_cursor(command_presence_body("[\"name\",\"overwrite\"]")),
    command_presence_limits(),
  ).unwrap()
  assert_false(
    command_input_contract_matches(
      first,
      command_presence_cursor(command_presence_body("[\"overwrite\",\"name\"]")),
      100,
    ).unwrap().0,
  )
  assert_true(
    command_input_contract_matches(
      first,
      command_presence_cursor(command_presence_body("[\"name\",\"overwrite\"]")),
      0,
    )
    is Err(CommandInputBudget),
  )
}
