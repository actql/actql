///|
test "original Command presence meter retains completed and partial child charges" {
  let source = command_presence_cursor(command_presence_body("[\"name\"]"))
  let (result, nodes, text) = observe_command_input_contract(
    source,
    command_presence_limits(),
  )
  let original = result.unwrap()
  assert_eq(command_input_contract_usage(original), (nodes, text))
  assert_eq(command_input_contract_field_count(original), 2)
  let facts = observe_command_input_construction(source)
  assert_true(facts.presence_form)
  assert_eq((facts.fields, facts.required), (2, 1))
  let bad = command_presence_cursor(
    command_presence_body("[]").replace(
      old="\"type\":\"boolean\"",
      new="\"type\":\"unknown\"",
    ),
  )
  let (result, used_nodes, used_text) = observe_command_input_contract(
    bad,
    command_presence_limits(),
  )
  assert_true(result is Err(InvalidCommandInputType("overwrite", _)))
  assert_true(used_nodes > 2 && used_text > 0)
  assert_true(
    read_command_input_contract(bad, command_presence_limits())
    is Err(InvalidCommandInputType("overwrite", _)),
  )
}
