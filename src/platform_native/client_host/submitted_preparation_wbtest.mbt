///|
fn submitted_prepare(
  intent : @host.ClientSubmittedIntent,
) -> Result[
  NativeClientSubmittedPreparation,
  NativeClientSubmittedPreparationIssue,
] {
  let environment = preparation_environment()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  prepare_native_client_submitted_program(
    intent,
    environment,
    Some(context),
    [],
    @host.client_standard_effect_computation_limits(),
  )
}

///|
test "Native original-intent preparation reports its finite envelope budget separately" {
  // A valid original unchecked envelope may exceed this physical profile.
  // No frontend rejection or replacement Program is used to hide that limit.
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"" +
    " ".repeat(65536) +
    "SELECT 1 AS id\"},\"parameters\":null}",
    131072,
    8192,
    64,
  ).unwrap()
  assert_true(submitted_prepare(intent) is Err(SubmittedInputLimit))
}

///|
test "Native original intent prepares its own structured Program without replacement" {
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let connected = submitted_prepare(intent).unwrap()
  assert_eq(
    native_client_submitted_preparation_intent_cid(connected),
    @host.client_submitted_intent_cid(intent),
  )
  guard native_client_submitted_preparation(connected) is Computation(prepared) else {
    fail("original Program was not prepared")
  }
  assert_eq(@host.prepared_client_result_count(prepared), 1)
  assert_eq(@host.prepared_client_result_name(prepared, 0), Some("answer"))
  let changed = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}") +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let other = submitted_prepare(changed).unwrap()
  assert_true(
    native_client_submitted_preparation_intent_cid(other) !=
    native_client_submitted_preparation_intent_cid(connected),
  )
  guard native_client_submitted_preparation(other)
    is Computation(other_prepared) else {
    fail("changed Program was not prepared")
  }
  assert_true(
    @host.prepared_client_identity(prepared).program_definition_cid !=
    @host.prepared_client_identity(other_prepared).program_definition_cid,
  )
}

///|
test "Native original query retains declarations and five distinct supplied strings" {
  let identities : Array[String] = []
  for encoded in ["e\\u0301", "é", "\\r", "\\n", "\\r\\n"] {
    let intent = @host.prepare_client_submitted_intent(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT @message AS message\",\"parameterDeclarations\":{\"message\":{\"type\":\"string\"}}},\"parameters\":{\"message\":\"" +
      encoded +
      "\"}}",
      65536,
      8192,
      64,
    ).unwrap()
    let connected = submitted_prepare(intent).unwrap()
    assert_eq(
      native_client_submitted_preparation_intent_cid(connected),
      @host.client_submitted_intent_cid(intent),
    )
    guard native_client_submitted_preparation(connected)
      is Computation(prepared) else {
      fail("original query was not prepared")
    }
    let cid = @host.prepared_client_identity(prepared).parameter_values_cid
    assert_false(identities.contains(cid))
    identities.push(cid)
  }
  assert_eq(identities.length(), 5)
  let wrong = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT @message AS message\",\"parameterDeclarations\":{\"message\":{\"type\":\"string\"}}},\"parameters\":{\"message\":null}}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(submitted_prepare(wrong) is Err(Preparation(_)))
}

///|
test "Native original query rejects wrong form extra fields and unsupported declaration placement" {
  // AQL text intentionally accepts the existing SELECT query form. This
  // expectation follows source_frontend's query-script grammar, not fallback.
  let text_query = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"aql-text\",\"text\":\"SELECT 1 AS id\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(submitted_prepare(text_query) is Ok(_))
  let wrong_form = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"aql-text\",\"text\":\"{}\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(
    submitted_prepare(wrong_form)
    is Err(Preparation(Frontend(@frontend.WrongQueryForm))),
  )
  for
    input in [
      "{\"format\":\"sql\",\"text\":\"SELECT 1 AS id\",\"replacementProgram\":{}}",
      "{\"format\":\"json\",\"text\":\"{}\",\"parameterDeclarations\":{}}",
    ] {
    let intent = @host.prepare_client_submitted_intent(
      "{\"kind\":\"aql\",\"input\":" + input + ",\"parameters\":null}",
      65536,
      8192,
      64,
    ).unwrap()
    assert_true(submitted_prepare(intent) is Err(InvalidSubmittedInput))
  }
}
