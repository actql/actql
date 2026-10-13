// Generated independent original Provider projection fixture.

///|
fn openai_projection_fixture() -> (
  AdmittedModelProvider,
  ModelRequest,
  () -> Int,
) {
  let limits : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 10,
  }
  let env = @environment.read(
    @utf8.encode(
      "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:e3312d25f97217872acca89d19526263eb28af666318c01f090f07b3134dd0e7\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[{\"authored_model_selector\":\"fixture-chat\",\"connector_id\":\"models/fixture\",\"contract_cid\":\"sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f\",\"data_handling\":{\"accepted_classifications\":[\"public\"],\"allowed_regions\":[\"fixture\"],\"contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention\":\"none\",\"training_use\":\"forbidden\"},\"generation_config\":{\"max_output_tokens\":16,\"seed_requested\":-7,\"temperature\":0.25,\"top_p\":0.875},\"input_contract\":{\"additional_properties\":false,\"fields\":{\"absent\":{\"nullable\":true,\"type\":\"boolean\"},\"amount\":{\"nullable\":false,\"precision\":20,\"scale\":2,\"type\":\"decimal\"},\"text\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"input_schema_cid\":\"sha256:72b560b69347d1b6e7b74fa3ebca73f808d0be12a7cd6b53b3a53da4a3954b2a\",\"max_items\":1,\"output_contract\":{\"additional_properties\":false,\"fields\":{\"answer\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"output_schema_cid\":\"sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317\",\"prompt_template_cid\":\"sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba\",\"retrieval_policy\":\"none\",\"schema\":\"actql.model_task/0.1\",\"streaming\":false,\"task_id\":\"model-task:chat-fixture\",\"task_kind\":\"structured_generate\",\"tool_policy\":\"none\",\"version\":\"1\"}],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    ),
    "sha256:e3312d25f97217872acca89d19526263eb28af666318c01f090f07b3134dd0e7",
    limits,
  ).unwrap()
  let tasks = @environment.check_model_tasks(env, {
    bodies: limits,
    contracts: { max_nodes: 1000, max_depth: 50, max_text_bytes: 10000, },
    max_work: 1000000,
  }).unwrap()
  let task = @environment.resolve_model_task(tasks, "model-task:chat-fixture").unwrap()
  let execution = @environment.read_model_execution_contract(
    task,
    @utf8.encode(
      "{\"backoff_contract_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"default_publication\":\"outcomes\",\"max_attempts_per_slot\":1,\"max_total_attempts\":1,\"max_total_cost_units\":0,\"max_total_duration_ms\":1000,\"max_total_token_reservation\":17,\"max_total_wire_bytes\":65536,\"media_input_contracts\":{},\"model_task_contract_cid\":\"sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f\",\"retry_classification_contract_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"self_cid\":\"sha256:635bfcc9ae49f51b2393ac731e51cc92c7b56047d4c21bff71b6cb8240eed8a8\",\"version\":\"actql-model-execution-contract/0.1\"}",
    ),
    "sha256:635bfcc9ae49f51b2393ac731e51cc92c7b56047d4c21bff71b6cb8240eed8a8",
    limits,
    1000000,
  ).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(
      @utf8.encode(
        "{\"payload\":{\"format\":\"actql.openai_chat_prompt/0.1\",\"instructions\":\"é\\r\\né\\n😀\"},\"self_cid\":\"sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
    ),
    Some(
      @utf8.encode(
        "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
    ),
    Some(
      @utf8.encode(
        "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
    ),
    limits,
    1000000,
  ).unwrap()
  let mut calls = 0
  let provider = install_model_provider("models/fixture", _ => {
    calls += 1
    Err(Cancelled)
  }).unwrap()
  let admitted = admit_model_provider(provider, execution, dependencies, (_, p) => {
    @environment.model_openai_chat_instructions(p) is Some(_)
  }).unwrap()
  let text = @admitted.text_value("é\r\n😀", 100).unwrap()
  let input = @admitted.recheck_runtime_value(
    text,
    @contract.primitive(@contract.StringType, nullable=true),
    { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
  ).unwrap()
  let amount = @admitted.recheck_runtime_value(
    @admitted.decimal_from_coefficient("900719925474099300", 20, 2).unwrap(),
    @contract.decimal_contract(20, 2, nullable=false).unwrap(),
    { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
  ).unwrap()
  let absent = @admitted.recheck_runtime_value(
    @admitted.null_value(),
    @contract.primitive(@contract.BooleanType, nullable=true),
    { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
  ).unwrap()
  let request : ModelRequest = {
    task,
    slot: 0,
    slot_cid: "sha256:" + "1".repeat(64),
    fixed_request_cid: "sha256:" + "2".repeat(64),
    key: [],
    inputs: [("absent", absent), ("amount", amount), ("text", input)],
  }
  (admitted, request, () => calls)
}

///|
test "original OpenAI projection binds actual Task prompt schema and preserves input" {
  let (provider, request, calls) = openai_projection_fixture()
  let value = project_openai_chat_request(
    provider, request, 10000, 1000, 40, 100, 10000,
  ).unwrap()
  assert_eq(
    value,
    (
      "é\r\né\n😀", "{\"absent\":null,\"amount\":\"9007199254740993.00\",\"text\":\"é\\r\\n😀\"}",
      "{\"additionalProperties\":false,\"properties\":{\"answer\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"answer\"],\"type\":\"object\"}",
      "sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f",
      "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
      "sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317",
      "fixture-chat",
    ),
  )
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(value.2)),
    "sha256:62f7715bfc032ac33d95a93b2d80aae42c76d6c83f5ba1986d51cfbe4725888d",
  )
  let (foreign, _, foreign_calls) = openai_projection_fixture()
  assert_true(
    project_openai_chat_request(foreign, request, 10000, 1000, 40, 100, 10000)
    is Err(ForeignRequest),
  )
  assert_true(
    project_openai_chat_request(provider, request, 10000, 1000, 40, 100, 0)
    is Err(Limit),
  )
  assert_true(
    project_openai_chat_request(provider, request, 10, 1000, 40, 100, 10000)
    is Err(Limit),
  )
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}
