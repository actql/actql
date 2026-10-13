// Generated independent OpenAI prompt payload vectors.

///|
test "OpenAI payload: empty" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":\"\"},\"self_cid\":\"sha256:569a0ace73cebaae33dc947794fdb88961739bf54f4b61257af9a07305e3c976\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:569a0ace73cebaae33dc947794fdb88961739bf54f4b61257af9a07305e3c976",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), Some(""))
}

///|
test "OpenAI payload: raw Unicode and line endings" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":\"é\\r\\né\\n😀\"},\"self_cid\":\"sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), Some("é\r\né\n😀"))
}

///|
test "OpenAI payload: missing instructions" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\"},\"self_cid\":\"sha256:1e0e02a1c1fdbdf0f7338967280c8eab6d376b3c51d90fe7bee47a8e5274b5cc\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:1e0e02a1c1fdbdf0f7338967280c8eab6d376b3c51d90fe7bee47a8e5274b5cc",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}

///|
test "OpenAI payload: NULL instructions" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":null},\"self_cid\":\"sha256:7066b9e83570e3858efdccac6e3daa820f1db8080c9406d0d205f94285eaa6ce\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:7066b9e83570e3858efdccac6e3daa820f1db8080c9406d0d205f94285eaa6ce",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}

///|
test "OpenAI payload: wrong type" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":false},\"self_cid\":\"sha256:96624984d2435d881ce3cad8a70b3c8b298b43c1ed75b45dffe8b95fcbf7e925\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:96624984d2435d881ce3cad8a70b3c8b298b43c1ed75b45dffe8b95fcbf7e925",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}

///|
test "OpenAI payload: extra key" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":\"\",\"tool\":null},\"self_cid\":\"sha256:9257a89611616aa871319a82fafb888f0d3722865946fefb0fd663f2487706ed\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:9257a89611616aa871319a82fafb888f0d3722865946fefb0fd663f2487706ed",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}

///|
test "OpenAI payload: wrong format" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"fixture-other/0.1\",\"instructions\":\"\"},\"self_cid\":\"sha256:9cde7433fbb09dce0b82330a1b9729b425219635f52747cb95c702a9f6011ef7\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:9cde7433fbb09dce0b82330a1b9729b425219635f52747cb95c702a9f6011ef7",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}

///|
test "OpenAI payload: NULL payload" {
  let prompt = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
    model_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(model_openai_chat_instructions(prompt), None)
}
