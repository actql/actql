///|
fn model_execution_test_tasks() -> @environment.ModelTasks {
  let body =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" + body + "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
  ).unwrap()
  @environment.check_model_tasks(environment, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
}

///|
fn model_execution_test_output(
  task : @environment.ModelTaskContract,
) -> @admitted.CheckedValue {
  let reason = @admitted.null_value()
  let risk = @admitted.text_value("high", 100).unwrap()
  let value = @admitted.object_value([("reason", reason), ("risk", risk)]).unwrap()
  @admitted.recheck_runtime_value(
    value,
    @environment.model_task_output(task),
    { max_nodes: 20, max_depth: 8, max_text_bytes: 100, },
  ).unwrap()
}

///|
test "model capture replay validates task and fixed request without provider calls" {
  let tasks = model_execution_test_tasks()
  let task = @environment.resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  let fixed = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  let slot = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
  let capture : ModelSlotCapture = {
    slot: 0,
    slot_cid: slot,
    fixed_request_cid: fixed,
    provider_id: "models/fixture",
    provider_request_id: "request-1",
    value: model_execution_test_output(task),
    input_tokens: 1L,
    output_tokens: 2L,
    observed_at: "2026-10-01T00:00:00.000Z",
  }
  let bundle : ModelCaptureBundle = {
    task_cid: @environment.model_task_identity(task).2,
    fixed_request_cid: fixed,
    captures: [capture],
  }
  let replayed = replay_model_capture(task, fixed, bundle).unwrap()
  assert_eq(replayed.length(), 1)
  assert_true(
    replay_model_capture(task, "sha256:3333333333333333333333333333333333333333333333333333333333333333", bundle)
    is Err(OutputIdentity),
  )
}

///|
test "model provider registration rejects an empty physical identity" {
  assert_true(
    install_model_provider("", _ => Err(RateLimit)) is Err(InvalidProvider),
  )
  let provider = install_model_provider("models/fixture", _ => {
    Err(Cancelled)
  }).unwrap()
  assert_eq(provider.provider_id, "models/fixture")
}
