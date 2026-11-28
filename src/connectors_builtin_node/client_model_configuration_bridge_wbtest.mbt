///|
test "installed Chat checks the selected transport on the exact current original binding" {
  let provider = "models/direct"
  let install = "{\"provider_id\":\"models/direct\"}"
  let contract = "{\"required\":[\"model_defaults\"]}"
  let make = (adapter, mode, endpoint) => {
    let config = "{\"provider_id\":\"models/direct\",\"selector\":\"risk\",\"model_id\":\"fixture\",\"adapter_kind\":\"" +
      adapter +
      "\",\"api_mode\":\"" +
      mode +
      "\",\"endpoint\":\"" +
      endpoint +
      "\"}"
    let originals = client_program_prepare_model_provider_originals(
      install, contract, config, 4096, 256, 16, 100000,
    ).unwrap()
    let binding = @publication_host.issue_client_model_provider_binding(
      provider,
      originals.0,
      originals.2,
      originals.4,
    ).unwrap()
    (binding, originals.4)
  }
  let https = "https://fixture.invalid/v1/chat/completions"
  let http = "http://fixture.invalid/v1/chat/completions"
  let portable = make("portable-http", "chat-completions", https)
  let insecure = make("portable-http", "chat-completions", http)
  let sdk = make("ai-sdk", "chat_completions", https)
  let verifies = (
    original : (@publication.RunEvidenceValue, String),
    model,
    endpoint,
    transport,
  ) => {
    client_program_installed_chat_configuration_matches(
      original.0,
      original.1,
      provider,
      "risk",
      model,
      endpoint,
      transport,
    )
  }
  assert_true(verifies(portable, "fixture", https, "portable-http"))
  assert_false(verifies(sdk, "fixture", https, "ai-sdk"))
  assert_true(
    @publication_host.client_model_registered_sdk_structured_support(
      sdk.0,
      sdk.1,
      provider,
      "risk",
      "fixture",
      "chat_completions",
      https,
    )
    is None,
  )
  assert_false(verifies(portable, "fixture", https, "ai-sdk"))
  assert_false(verifies(sdk, "fixture", https, "portable-http"))
  assert_false(verifies(portable, "fixture", https, ""))
  assert_false(verifies(portable, "foreign", https, "portable-http"))
  assert_false(verifies(insecure, "fixture", http, "portable-http"))
  assert_false(verifies((portable.0, sdk.1), "fixture", https, "portable-http"))
}
