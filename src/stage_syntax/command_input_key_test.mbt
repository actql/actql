///|
fn command_key_header(key : String?) -> Program raise {
  effect_program(
    "    create: {command: {from: {result: rows}, target: {field: destination}, contract: command:mail.send.v1, input: {}" +
    (match key {
      None => ""
      Some(value) => ", input_key: " + value
    }) +
    "}}",
  )
}

///|
test "Command header retains optional original row ID separately from its target" {
  let old = effect_header_at(
    collect_effect_headers(command_key_header(None), 1, 1).unwrap(),
    0,
  ).unwrap()
  assert_true(effect_header_command_input_key(old) is None)
  let original = command_key_header(Some("row_id"))
  let header = effect_header_at(
    collect_effect_headers(original, 1, 1).unwrap(),
    0,
  ).unwrap()
  assert_eq(effect_header_command_input_key(header), Some("row_id"))
  assert_true(effect_header_published_store_target(header) is None)
  assert_true(effect_header_published_command_target(header) is None)
  assert_eq(effect_header_source_result(header), Some("rows"))
}

///|
test "Command input key is a closed nonempty field name without null literal or tuple defaults" {
  for key in ["null", "''", "false", "1", "{field: row_id}", "[row_id]"] {
    assert_eq(effect_header_error(command_key_header(Some(key))), InvalidBody)
  }
}

///|
test "Command row ID does not add an input key to another Effect kind" {
  assert_eq(
    effect_header_error(
      effect_program(
        "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, input_key: row_id}}",
      ),
    ),
    InvalidBody,
  )
}
