///|
fn submitted_options_intent(
  document : String,
  options : String,
) -> @host.ClientSubmittedIntent {
  @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    document +
    ",\"parameters\":null" +
    options +
    "}",
    65536,
    8192,
    64,
  ).unwrap()
}

///|
fn submitted_options_effect(
  intent : @host.ClientSubmittedIntent,
) -> Result[
  NativeClientSubmittedPreparation,
  NativeClientSubmittedPreparationIssue,
] {
  prepare_native_client_submitted_program(
    intent,
    native_client_effect_fixture_environment(),
    None,
    [],
    @host.client_standard_effect_computation_limits(),
  )
}

///|
test "Native preparation retains the four original option identities without changing the Program" {
  let options = [
    "", ",\"stopBefore\":\"commit\"", ",\"readOnly\":true", ",\"stopBefore\":\"commit\",\"readOnly\":true",
  ]
  // Independent Python hashlib over the declared canonical intent preimage.
  // These expectations are not derived from the preparation or codec output.
  let expected = [
    "sha256:7c257776d10e9de69e4f8c448787a196a48c79e280931dbf95fb19cce371ea17", "sha256:28c315a2ea7c235f0cad86ac2e1de7726e6b62e18cf9ab20796aafda4a0c854d",
    "sha256:570cac2994d3146a8d2789655f45f5e1d769eac3cd833d60a16399390d6aac98", "sha256:bf132d4d6da3c04042aa30f7ec8ae87f7fe209698b2aa2e1760bff23865c2427",
  ]
  let program_ids : Array[String] = []
  let parameter_ids : Array[String] = []
  for index = 0; index < options.length(); index = index + 1 {
    let intent = submitted_options_intent(
      preparation_values_document(),
      options[index],
    )
    let connected = submitted_prepare(intent).unwrap()
    assert_eq(
      native_client_submitted_preparation_intent_cid(connected),
      expected[index],
    )
    assert_eq(@host.client_submitted_intent_cid(intent), expected[index])
    guard native_client_submitted_preparation(connected)
      is Computation(prepared) else {
      fail("original Values Program was not prepared")
    }
    let identity = @host.prepared_client_identity(prepared)
    program_ids.push(identity.program_definition_cid)
    parameter_ids.push(identity.parameter_values_cid)
  }
  assert_true(program_ids.all(value => value == program_ids[0]))
  assert_true(parameter_ids.all(value => value == parameter_ids[0]))
}

///|
test "Native option adoption preserves original SQL declarations and supplied string bytes" {
  let identities : Array[String] = []
  for encoded in ["e\\u0301", "é", "\\r", "\\n", "\\r\\n"] {
    let intent = @host.prepare_client_submitted_intent(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT @message AS message\",\"parameterDeclarations\":{\"message\":{\"type\":\"string\"}}},\"parameters\":{\"message\":\"" +
      encoded +
      "\"},\"stopBefore\":\"commit\",\"readOnly\":true}",
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
      fail("original SQL query was not prepared")
    }
    let cid = @host.prepared_client_identity(prepared).parameter_values_cid
    assert_false(identities.contains(cid))
    identities.push(cid)
  }
  assert_eq(identities.length(), 5)
}

///|
test "Native readOnly rejects the complete prepared Effect inventory including empty input" {
  for
    document in [
      native_client_effect_fixture_document,
      native_client_effect_fixture_document.replace(
        old="\"rows\":[{\"value\":\"e\\u0301\\r\\n\"}]",
        new="\"rows\":[]",
      ),
    ] {
    for options in ["", ",\"stopBefore\":\"commit\""] {
      let intent = submitted_options_intent(document, options)
      let connected = submitted_options_effect(intent).unwrap()
      assert_true(
        native_client_submitted_preparation(connected) is EffectComputation(_),
      )
      assert_eq(
        native_client_submitted_preparation_intent_cid(connected),
        @host.client_submitted_intent_cid(intent),
      )
    }
    for
      options in [
        ",\"readOnly\":true", ",\"stopBefore\":\"commit\",\"readOnly\":true",
      ] {
      assert_true(
        submitted_options_effect(submitted_options_intent(document, options))
        is Err(ReadOnlyEffect),
      )
    }
  }
}

///|
test "Native original preparation refusal precedes readOnly compatibility" {
  let intent = submitted_options_intent(
    native_client_effect_fixture_document, ",\"readOnly\":true",
  )
  // The source-free environment has no Mapping for this original Effect.
  assert_true(
    submitted_prepare(intent) is Err(Preparation(EffectComputation(_))),
  )
  let wrong_parameters = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT @message AS message\",\"parameterDeclarations\":{\"message\":{\"type\":\"string\"}}},\"parameters\":{\"message\":null},\"readOnly\":true,\"stopBefore\":\"commit\"}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(submitted_prepare(wrong_parameters) is Err(Preparation(_)))
}

///|
test "Native option adoption keeps malformed option rejection at the original opaque admission" {
  for
    options in [
      ",\"readOnly\":false", ",\"readOnly\":null", ",\"stopBefore\":\"effect\"",
      ",\"stopBefore\":null", ",\"replacementPreparation\":{}",
    ] {
    assert_true(
      @host.prepare_client_submitted_intent(
        "{\"kind\":\"program\",\"input\":" +
        preparation_values_document() +
        ",\"parameters\":null" +
        options +
        "}",
        65536,
        8192,
        64,
      )
      is Err(_),
    )
  }
}
