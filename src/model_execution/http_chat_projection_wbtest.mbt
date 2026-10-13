///|
test "HTTP Chat original request preserves typed input and explicit one-choice profile" {
  let (provider, request, calls) = openai_projection_fixture()
  let projected = project_http_chat_request(
    provider, request, "fixture-http", 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_eq(
    projected.0,
    "{\"max_tokens\":16,\"messages\":[{\"content\":\"é\\r\\né\\n😀\",\"role\":\"system\"},{\"content\":\"{\\\"absent\\\":null,\\\"amount\\\":\\\"9007199254740993.00\\\",\\\"text\\\":\\\"é\\\\r\\\\n😀\\\"}\",\"role\":\"user\"}],\"model\":\"fixture-http\",\"n\":1,\"response_format\":{\"json_schema\":{\"name\":\"actql_output\",\"schema\":{\"additionalProperties\":false,\"properties\":{\"answer\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"answer\"],\"type\":\"object\"},\"strict\":true},\"type\":\"json_schema\"},\"seed\":-7,\"stream\":false,\"temperature\":0.25,\"top_p\":0.875}",
  )
  assert_eq(
    (projected.1, projected.2, projected.3, projected.4),
    (
      "sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f",
      "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
      "sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317",
      "fixture-chat",
    ),
  )
  assert_eq(calls(), 0)
}

///|
test "HTTP Chat projection refuses foreign provider and missing physical model" {
  let (provider, request, calls) = openai_projection_fixture()
  let (foreign, _, foreign_calls) = openai_projection_fixture()
  assert_true(
    project_http_chat_request(
      foreign, request, "fixture-http", 10000, 1000, 40, 100, 20000,
    )
    is Err(ForeignRequest),
  )
  assert_true(
    project_http_chat_request(
      provider, request, "", 10000, 1000, 40, 100, 20000,
    )
    is Err(Unsupported),
  )
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}

///|
test "HTTP Chat projection enforces cumulative preparation and outbound ceilings" {
  let (provider, request, calls) = openai_projection_fixture()
  assert_true(
    project_http_chat_request(
      provider, request, "fixture-http", 10, 1000, 40, 100, 20000,
    )
    is Err(Limit),
  )
  assert_true(
    project_http_chat_request(
      provider, request, "fixture-http", 10000, 1000, 40, 100, 0,
    )
    is Err(Limit),
  )
  assert_eq(calls(), 0)
}
