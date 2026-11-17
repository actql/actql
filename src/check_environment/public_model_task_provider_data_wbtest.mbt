///|
fn provider_data_original() -> NormalizedPublicModelTask {
  let task = read_public_model_task_document(
    declaration_base(""),
    "json",
    declaration_limits(),
  ).unwrap()
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(defaults, None, None, 1000).unwrap()
  normalize_public_model_task(
    task,
    defaults,
    resolved,
    "operator",
    declaration_limits(),
  ).unwrap()
}

///|
test "normalized Provider DATA preserves original schema selector and canonical prompt payload" {
  let original = provider_data_original()
  let before = normalized_public_model_task_materials(original)
  let (schema, selector, payload) = normalized_public_model_task_provider_data(
    original, 10000, 1000, 32, 11000,
  ).unwrap()
  assert_eq(schema, original.declaration.output.cid)
  assert_eq(selector, original.resolved.model)
  assert_eq(
    payload,
    (
      #|{"format":"actql.openai_chat_prompt/0.1","instructions":"Original é\r\n"}
    ),
  )
  // The independently expected payload above and the existing full prompt
  // retain the exact instruction text, including decomposition and CRLF.
  let (_, _, prompt, _) = before
  let object = @decode.open_object(declaration_cursor(prompt)).unwrap()
  let retained = @decode.lookup(object, "payload").unwrap()
  assert_eq(
    @decode.text(
      @decode.lookup(@decode.open_object(retained).unwrap(), "instructions").unwrap(),
    ),
    Ok("Original e\u{0301}\r\n"),
  )
  assert_eq(normalized_public_model_task_materials(original), before)
}

///|
test "normalized Provider DATA refuses insufficient output and work without mutating originals" {
  let original = provider_data_original()
  let before = normalized_public_model_task_materials(original)
  for (bytes, nodes, depth) in [(1, 1000, 32), (10000, 1, 32), (10000, 1000, 0)] {
    assert_true(
      normalized_public_model_task_provider_data(
        original, bytes, nodes, depth, 11000,
      )
      is Err({ kind: BodyLimit, .. }),
    )
  }
  assert_true(
    normalized_public_model_task_provider_data(original, 10000, 1000, 32, 10999)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    normalized_public_model_task_provider_data(original, -1, 1000, 32, 11000)
    is Err({ kind: InvalidLimits, .. }),
  )
  assert_eq(normalized_public_model_task_materials(original), before)
  assert_true(
    normalized_public_model_task_provider_data(original, 10000, 1000, 32, 11000)
    is Ok(_),
  )
}
