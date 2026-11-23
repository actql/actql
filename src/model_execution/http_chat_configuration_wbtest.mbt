///|
test "portable Model HTTP route requires the same adopted file identities" {
  let revision = "sha256:" + "1".repeat(64)
  let contract = "sha256:" + "2".repeat(64)
  let profile = "sha256:" + "3".repeat(64)
  let foreign = "sha256:" + "4".repeat(64)
  let wire = "{\"adapter_kind\":\"portable-http\",\"api_mode\":\"chat-completions\",\"configuration_contract_cid\":\"" +
    contract +
    "\",\"credential_ref\":\"file:provider.key\",\"endpoint\":\"https://models.example/v1/chat/completions\",\"installation_revision_cid\":\"" +
    revision +
    "\",\"model_id\":\"deployed-model\",\"provider_id\":\"models/http\",\"response_profile_cid\":\"" +
    profile +
    "\",\"selector\":\"authored-alias\"}"
  let body = @utf8.encode(wire)
  let limits : @environment.Limits = {
    max_bytes: 1024,
    max_nodes: 16,
    max_depth: 4,
    max_members: 8,
  }
  let route = read_portable_model_http_chat_file_route(
    body, "models/http", revision, contract, profile, "provider.key", limits,
  ).unwrap()
  assert_eq(route.selector, "authored-alias")
  assert_eq(route.model_id, "deployed-model")
  assert_eq(route.endpoint, "https://models.example/v1/chat/completions")
  let next = read_portable_model_http_chat_file_route(
    @utf8.encode(wire.replace(old="deployed-model", new="another-model!")),
    "models/http",
    revision,
    contract,
    profile,
    "provider.key",
    limits,
  )
  assert_eq(next, Some({ ..route, model_id: "another-model!", }))
  assert_true(
    read_portable_model_http_chat_file_route(
      body, "models/http", revision, contract, profile, "foreign.key", limits,
    )
    is None,
  )
  assert_true(
    read_portable_model_http_chat_file_route(
      body, "models/other", revision, contract, profile, "provider.key", limits,
    )
    is None,
  )
  for
    (revision, contract, profile) in [
      (foreign, contract, profile),
      (revision, foreign, profile),
      (revision, contract, foreign),
    ] {
    assert_true(
      read_portable_model_http_chat_file_route(
        body, "models/http", revision, contract, profile, "provider.key", limits,
      )
      is None,
    )
  }
  for
    (old, new) in [
      ("portable-http", "node-ai-sdk"),
      ("chat-completions", "responses"),
      ("\"model_id\":\"deployed-model\",", ""),
      ("https://", "http://"),
    ] {
    assert_true(
      read_portable_model_http_chat_file_route(
        @utf8.encode(wire.replace(old~, new~)),
        "models/http",
        revision,
        contract,
        profile,
        "provider.key",
        limits,
      )
      is None,
    )
  }
  assert_true(
    read_portable_model_http_chat_file_route(
      body,
      "models/http",
      revision,
      contract,
      profile,
      "provider.key",
      { ..limits, max_bytes: body.length() - 1, },
    )
    is None,
  )
}

///|
test "portable Model HTTP execution bundle preserves original wires and rejects a replaced shape" {
  let wire =
    #|{"contract_cid":"original-cid","contract":"{\"c\":1}","prompt":"{\"p\":\"日本語\"}","retry_policy":"{\"r\":[]}","backoff":"{\"b\":[]}"}
  let bytes = @utf8.encode(wire)
  let limits : @environment.Limits = {
    max_bytes: bytes.length(),
    max_nodes: 32,
    max_depth: 8,
    max_members: 16,
  }
  let original = (
    "original-cid", "{\"c\":1}", "{\"p\":\"日本語\"}", "{\"r\":[]}", "{\"b\":[]}",
  )
  assert_eq(
    read_portable_model_http_execution_wires(bytes, limits),
    Some(original),
  )
  let retry_text =
    #|"retry_policy":"{\"r\":[]}"
  for
    (old, new) in [
      ("\"backoff\":", "\"other\":"),
      ("\"contract_cid\":", "\"contract_cid\":null,\"contract_cid\":"),
      (retry_text, "\"retry_policy\":{}"),
    ] {
    assert_true(
      read_portable_model_http_execution_wires(
        @utf8.encode(wire.replace(old~, new~)),
        { ..limits, max_bytes: 1024, },
      )
      is None,
    )
  }
  assert_true(
    read_portable_model_http_execution_wires(bytes, {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is None,
  )
}
