// Generated independent provider capability binding fixture.

///|
fn provider_admission_fixture() -> (
  @environment.ModelExecutionContract,
  @environment.SingleAttemptModelDependencies,
) {
  let limits : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 10,
  }
  let environment = @environment.read(
    @utf8.encode(
      "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:9467d5ab9a9dc179c8f6d76d9953519da330847134ecc843c52f351df6d20057\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[{\"authored_model_selector\":\"fixture-risk-model\",\"connector_id\":\"models/fixture\",\"contract_cid\":\"sha256:1338eb4818d71fb229fa020a1c98f518a51a8d9c1c204356ac9108855a60d524\",\"data_handling\":{\"accepted_classifications\":[\"public\",\"internal\"],\"allowed_regions\":[\"fixture-region\"],\"contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention\":\"none\",\"training_use\":\"forbidden\"},\"generation_config\":{\"max_output_tokens\":32,\"seed_requested\":-7,\"temperature\":0,\"top_p\":1},\"input_contract\":{\"additional_properties\":false,\"fields\":{\"text\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"max_items\":2,\"output_contract\":{\"additional_properties\":false,\"fields\":{\"reason\":{\"nullable\":true,\"type\":\"string\"},\"risk\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\",\"prompt_template_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"retrieval_policy\":\"none\",\"schema\":\"actql.model_task/0.1\",\"streaming\":false,\"task_id\":\"model-task:risk-score.v1\",\"task_kind\":\"structured_generate\",\"tool_policy\":\"none\",\"version\":\"1\"}],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    ),
    "sha256:9467d5ab9a9dc179c8f6d76d9953519da330847134ecc843c52f351df6d20057",
    limits,
  ).unwrap()
  let tasks = @environment.check_model_tasks(environment, {
    bodies: limits,
    contracts: { max_nodes: 1000, max_depth: 50, max_text_bytes: 10000, },
    max_work: 1000000,
  }).unwrap()
  let task = @environment.resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  let execution = @environment.read_model_execution_contract(
    task,
    @utf8.encode(
      "{\"backoff_contract_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"default_publication\":\"outcomes\",\"max_attempts_per_slot\":1,\"max_total_attempts\":1,\"max_total_cost_units\":0,\"max_total_duration_ms\":500,\"max_total_token_reservation\":33,\"max_total_wire_bytes\":66536,\"media_input_contracts\":{},\"model_task_contract_cid\":\"sha256:1338eb4818d71fb229fa020a1c98f518a51a8d9c1c204356ac9108855a60d524\",\"retry_classification_contract_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"self_cid\":\"sha256:0c747b9b485cfda32ea153f4e9535b7da1e367afc90819da09076365d8e9fe36\",\"version\":\"actql-model-execution-contract/0.1\"}",
    ),
    "sha256:0c747b9b485cfda32ea153f4e9535b7da1e367afc90819da09076365d8e9fe36",
    limits,
    1000000,
  ).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(
      @utf8.encode(
        "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
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
  (execution, dependencies)
}

///|
test "Provider payload admission retains the exact execution without dispatch" {
  let (execution, dependencies) = provider_admission_fixture()
  let (foreign, foreign_dependencies) = provider_admission_fixture()
  let mut calls = 0
  let mut validations = 0
  let provider = install_model_provider("models/fixture", _ => {
    calls += 1
    Err(Cancelled)
  }).unwrap()
  let validate = (task, prompt) => {
    validations += 1
    @environment.model_task_identity(task).2 ==
    "sha256:1338eb4818d71fb229fa020a1c98f518a51a8d9c1c204356ac9108855a60d524" &&
    @environment.model_task_model_selector(task) == "fixture-risk-model" &&
    @environment.model_dependency_identity(prompt) ==
    "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268"
  }
  assert_true(
    admit_model_provider(provider, execution, foreign_dependencies, validate)
    is Err(ForeignDependencies),
  )
  let wrong = install_model_provider("models/foreign", _ => Err(Cancelled)).unwrap()
  assert_true(
    admit_model_provider(wrong, execution, dependencies, validate)
    is Err(ForeignProvider),
  )
  assert_eq(validations, 0)
  assert_true(
    admit_model_provider(provider, execution, dependencies, (_, _) => false)
    is Err(UnsupportedPrompt),
  )
  let admitted = admit_model_provider(
    provider, execution, dependencies, validate,
  ).unwrap()
  assert_eq(validations, 1)
  assert_true(
    admitted_model_provider_for(admitted, execution) is Some(actual) &&
    physical_equal(actual, provider),
  )
  assert_true(admitted_model_provider_for(admitted, foreign) is None)
  assert_eq(calls, 0)
}
