// Generated original fixture; existing independent Decision bytes/CIDs unchanged.

///|
fn native_decision_projection_fixture(
  state_wire : String,
) -> (AdmittedModelProvider, ModelRequest, () -> Int) {
  let limits : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 10,
  }
  let env = @environment.read(
    @utf8.encode(
      "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:62cd998ce7e29bae3ab085d81383449e2777e1bd86192ac45a8fefd237a807fd\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[{\"authored_model_selector\":\"fixture-native\",\"connector_id\":\"models/fixture\",\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"data_handling\":{\"accepted_classifications\":[\"public\"],\"allowed_regions\":[\"fixture\"],\"contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention\":\"none\",\"training_use\":\"forbidden\"},\"decision_config\":{\"answer_profile\":\"actql.decision_answers/0.1\",\"distribution_policy\":\"required_for_choice_and_score\",\"probability_source\":\"native\"},\"input_contract\":{\"additional_properties\":false,\"fields\":{\"state\":{\"nullable\":true,\"type\":\"json\"}},\"nullable\":false,\"type\":\"object\"},\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"max_items\":4,\"output_contract\":{\"additional_properties\":false,\"fields\":{\"__proto__\":{\"additional_properties\":false,\"fields\":{\"choice\":{\"nullable\":false,\"type\":\"string\"},\"probabilities\":{\"items\":{\"additional_properties\":false,\"fields\":{\"option\":{\"nullable\":false,\"type\":\"string\"},\"probability\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"nullable\":true,\"type\":\"array\"}},\"nullable\":false,\"type\":\"object\"},\"constructor\":{\"additional_properties\":false,\"fields\":{\"probabilities\":{\"items\":{\"additional_properties\":false,\"fields\":{\"level\":{\"nullable\":false,\"type\":\"number\"},\"probability\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"nullable\":true,\"type\":\"array\"},\"score\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"enabled\":{\"additional_properties\":false,\"fields\":{\"probability\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}},\"nullable\":false,\"type\":\"object\"},\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\",\"prompt_template_cid\":\"sha256:3cb49cca43b2ada3360038ff65eb699c5c79e93c2630bd3e3e4ed2fdd980db80\",\"retrieval_policy\":\"none\",\"schema\":\"actql.model_task/0.2\",\"streaming\":false,\"task_id\":\"model-task:decision-fixture\",\"task_kind\":\"decision\",\"tool_policy\":\"none\",\"version\":\"1\"}],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    ),
    "sha256:62cd998ce7e29bae3ab085d81383449e2777e1bd86192ac45a8fefd237a807fd",
    limits,
  ).unwrap()
  let tasks = @environment.check_model_tasks(env, {
    bodies: limits,
    contracts: { max_nodes: 1000, max_depth: 50, max_text_bytes: 10000, },
    max_work: 1000000,
  }).unwrap()
  let task = @environment.resolve_model_task(
    tasks, "model-task:decision-fixture",
  ).unwrap()
  let execution = @environment.read_model_execution_contract(
    task,
    @utf8.encode(
      "{\"backoff_contract_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"default_publication\":\"outcomes\",\"max_attempts_per_slot\":1,\"max_total_attempts\":1,\"max_total_cost_units\":0,\"max_total_duration_ms\":1000,\"max_total_token_reservation\":128,\"max_total_wire_bytes\":2048,\"media_input_contracts\":{},\"model_task_contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"retry_classification_contract_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"self_cid\":\"sha256:de6383143d932950e1472a28c5dc61a44fa473df3c0848e82f5310a3bbaea334\",\"version\":\"actql-model-execution-contract/0.1\"}",
    ),
    "sha256:de6383143d932950e1472a28c5dc61a44fa473df3c0848e82f5310a3bbaea334",
    limits,
    1000000,
  ).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(
      @utf8.encode(
        "{\"payload\":{\"format\":\"actql.decision_prompt/0.1\",\"questions\":[{\"id\":\"__proto__\",\"instructions\":\"Choose a routing label.\\r\\né\",\"options\":[{\"description\":\"toString\",\"id\":\"toString\"},{\"description\":\"__proto__\",\"id\":\"__proto__\"},{\"description\":\"constructor\",\"id\":\"constructor\"}],\"type\":\"choice\"},{\"id\":\"constructor\",\"instructions\":\"Score the state.\",\"levels\":[\"low\",\"medium\",\"high\"],\"type\":\"score\"},{\"id\":\"enabled\",\"instructions\":\"P(true) for eligibility.\",\"type\":\"boolean\"}],\"state_input\":\"state\"},\"self_cid\":\"sha256:3cb49cca43b2ada3360038ff65eb699c5c79e93c2630bd3e3e4ed2fdd980db80\",\"version\":\"actql-model-prompt/0.1\"}",
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
  let admitted = admit_model_provider(provider, execution, dependencies, (_, _) => {
    true
  }).unwrap()
  let value_limits : @admitted.Limits = {
    max_nodes: 1000,
    max_depth: 50,
    max_text_bytes: 10000,
  }
  let (literal, _, _) = @admitted.admit_json_literal(state_wire, value_limits).unwrap()
  let state = @admitted.recheck_runtime_value(
    literal.value,
    @contract.primitive(JsonType, nullable=true),
    value_limits,
  ).unwrap()
  let request : ModelRequest = {
    task,
    slot: 0,
    slot_cid: "sha256:" + "1".repeat(64),
    fixed_request_cid: "sha256:" + "2".repeat(64),
    key: [],
    inputs: [("state", state)],
  }
  (admitted, request, () => calls)
}
