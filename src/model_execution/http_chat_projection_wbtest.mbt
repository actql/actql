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

///|
fn sdk_v4_completed_fixture(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_work : Int,
) -> OpenAIChatProjection {
  let cursor = start_openai_chat_projection(
    provider, request, 10000, 1000, 40, 100, max_work,
  ).unwrap()
  while advance_openai_chat_projection(cursor).unwrap() is None {

  }
  cursor
}

///|
test "SDK v4 profile shares original materials and preserves omitted n and stream" {
  let (provider, request, calls) = openai_projection_fixture()
  let cursor = sdk_v4_completed_fixture(provider, request, 20000)
  let value = finish_openai_chat_sdk_v4_projection(
    cursor, "fixture-http", 10000,
  ).unwrap()
  assert_eq(value.7, sdk_v4_expected_wire)
  assert_eq(
    (value.3, value.4, value.5, value.6),
    (
      "sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f",
      "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
      "sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317",
      "fixture-chat",
    ),
  )
  assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  assert_true(
    finish_openai_chat_sdk_v4_projection(cursor, "fixture-http", 10000)
    is Err(ForeignRequest),
  )
  assert_eq(calls(), 0)
}

///|
test "SDK v4 finish refuses unready retired and bounded terminal children without dispatch" {
  let (provider, request, calls) = openai_projection_fixture()
  let unready = start_openai_chat_projection(
    provider, request, 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_true(
    finish_openai_chat_sdk_v4_projection(unready, "fixture-http", 10000)
    is Err(ForeignRequest),
  )
  retire_openai_chat_projection(unready)
  for
    (model, bytes) in [
      ("", 10000),
      ("fixture-http", 1),
      ("fixture-http", 357913942),
    ] {
    let cursor = sdk_v4_completed_fixture(provider, request, 20000)
    assert_true(
      finish_openai_chat_sdk_v4_projection(cursor, model, bytes) is Err(_),
    )
    assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  }
  let completed = sdk_v4_completed_fixture(provider, request, 20000)
  let used = openai_chat_projection_work(completed)
  retire_openai_chat_projection(completed)
  let cursor = sdk_v4_completed_fixture(provider, request, used)
  assert_true(
    finish_openai_chat_sdk_v4_projection(cursor, "fixture-http", 10000)
    is Err(Limit),
  )
  assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  assert_eq(calls(), 0)
}

///|
let sdk_v4_expected_wire : String = "{\"max_tokens\":16,\"messages\":[{\"content\":\"é\\r\\né\\n😀\",\"role\":\"system\"},{\"content\":\"{\\\"absent\\\":null,\\\"amount\\\":\\\"9007199254740993.00\\\",\\\"text\\\":\\\"é\\\\r\\\\n😀\\\"}\",\"role\":\"user\"}],\"model\":\"fixture-http\",\"response_format\":{\"json_schema\":{\"name\":\"actql_output\",\"schema\":{\"additionalProperties\":false,\"properties\":{\"answer\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"answer\"],\"type\":\"object\"},\"strict\":true},\"type\":\"json_schema\"},\"seed\":-7,\"temperature\":0.25,\"top_p\":0.875}"

///|
test "SDK v4 convenience preserves exact body and refuses a foreign original before SDK driving" {
  let (provider, request, calls) = openai_projection_fixture()
  let (foreign, _, foreign_calls) = openai_projection_fixture()
  let value = project_openai_chat_sdk_v4_request(
    provider, request, "fixture-http", 10000, 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_eq(value.7, sdk_v4_expected_wire)
  assert_eq(value.6, "fixture-chat")
  assert_true(
    project_openai_chat_sdk_v4_request(
      foreign, request, "fixture-http", 10000, 10000, 1000, 40, 100, 20000,
    )
    is Err(ForeignRequest),
  )
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}
