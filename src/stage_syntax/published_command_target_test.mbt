///|
fn published_command_header(selector : String) -> Program raise {
  effect_program(
    "    invoke: {command: {from: {result: rows}, target: " +
    selector +
    ", contract: command:mailbox.send.v1, input: {}}}",
  )
}

///|
test "published Command header retains fixed target original separately from STORE" {
  let program = published_command_header(
    "{published_command: {target_ref: 'connector://mailbox/current'}}",
  )
  let headers = collect_effect_headers(program, 1, 1).unwrap()
  let header = effect_header_at(headers, 0).unwrap()
  assert_eq(
    effect_header_published_command_target(header),
    Some(("connector://mailbox/current", None)),
  )
  assert_true(effect_header_published_store_target(header) is None)
  assert_eq(effect_header_contract_ref(header), "command:mailbox.send.v1")
  assert_true(collect_effect_headers(program, 1, 0) is Err(_))
}

///|
test "published Command identifier is a retained field selector not a ResourceRef" {
  let headers = collect_effect_headers(
    published_command_header(
      "{published_command: {target_ref: 'connector://mailbox/current', identifier_field: address}}",
    ),
    1,
    1,
  ).unwrap()
  assert_eq(
    effect_header_published_command_target(
      effect_header_at(headers, 0).unwrap(),
    ),
    Some(("connector://mailbox/current", Some("address"))),
  )
}

///|
test "published Command target rejects mixed modes missing empty and extra selector data" {
  for
    selector in [
      "{published_command:null}", "{published_command:{}}", "{published_command:{target_ref:''}}",
      "{published_command:{target_ref:other}}", "{published_command:{target_ref:'connector://mailbox/current',identifier_field:null}}",
      "{published_command:{target_ref:'connector://mailbox/current',identifier_field:''}}",
      "{published_command:{target_ref:'connector://mailbox/current',extra:true}}",
      "{published_command:{target_ref:'connector://mailbox/current'},field:destination}",
      "{published_command:{target_ref:'connector://mailbox/current'},published_store:{target_ref:'connector://mailbox/current',mapping_ref:mapping:mailbox.write.v1}}",
      "{field:destination,published_command:null}",
    ] {
    assert_eq(
      effect_header_error(published_command_header(selector)),
      InvalidBody,
    )
  }
}
