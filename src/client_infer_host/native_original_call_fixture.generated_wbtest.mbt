// Generated from independent Decision/profile admission inputs.

///|
let native_call_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:a3579e07d83bc48a4ced859410984ebc2d3024500af3183fe0782134550ba2e0","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"fixture-native","connector_id":"models/fixture","contract_cid":"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e","data_handling":{"accepted_classifications":["public"],"allowed_regions":["fixture"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"decision_config":{"answer_profile":"actql.decision_answers/0.1","distribution_policy":"required_for_choice_and_score","probability_source":"native"},"input_contract":{"additional_properties":false,"fields":{"state":{"nullable":true,"type":"json"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466","max_items":4,"output_contract":{"additional_properties":false,"fields":{"__proto__":{"additional_properties":false,"fields":{"choice":{"nullable":false,"type":"string"},"probabilities":{"items":{"additional_properties":false,"fields":{"option":{"nullable":false,"type":"string"},"probability":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"nullable":true,"type":"array"}},"nullable":false,"type":"object"},"constructor":{"additional_properties":false,"fields":{"probabilities":{"items":{"additional_properties":false,"fields":{"level":{"nullable":false,"type":"number"},"probability":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"nullable":true,"type":"array"},"score":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"enabled":{"additional_properties":false,"fields":{"probability":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9","prompt_template_cid":"sha256:3cb49cca43b2ada3360038ff65eb699c5c79e93c2630bd3e3e4ed2fdd980db80","retrieval_policy":"none","schema":"actql.model_task/0.2","streaming":false,"task_id":"model-task:decision-fixture","task_kind":"decision","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let native_call_environment_cid : String =
  #|sha256:a3579e07d83bc48a4ced859410984ebc2d3024500af3183fe0782134550ba2e0

///|
let native_call_program : String =
  #|{"id":"native-original-call","results":{"answer":{"from":{"result":"answer","stage":"main"}}},"stages":[{"id":"main","inputs":{},"results":{"answer":{"fields":["id","outcome","value"],"from":"answer"}},"steps":[{"as":"input","values":{"rows":[{"id":"b"},{"id":"a"}],"schema":{"id":{"nullable":false,"type":"string"}}}},{"as":"unique","assert_rows":{"unique_by":["id"]}},{"as":"answer","infer":{"contract":"model-task:decision-fixture","input":{"state":{"if":[{"eq":[{"field":"id"},{"literal":"b"}]},{"typed_literal":{"type":"json","value":"null"}},{"typed_literal":{"type":"json","value":"[\"é\\r\\n\",false,0]"}}]}},"key":"id"}}]}],"version":"actql/0.1"}

///|
let native_call_execution : String =
  #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":2,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":256,"max_total_wire_bytes":133072,"media_input_contracts":{},"model_task_contract_cid":"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:868fd5dd5254c18783844e3964b114585438f6a067495cae75d5865eabdfe7ab","version":"actql-model-execution-contract/0.1"}

///|
let native_call_execution_cid : String =
  #|sha256:868fd5dd5254c18783844e3964b114585438f6a067495cae75d5865eabdfe7ab

///|
let native_call_prompt : String =
  #|{"payload":{"format":"actql.decision_prompt/0.1","questions":[{"id":"__proto__","instructions":"Choose a routing label.\r\né","options":[{"description":"toString","id":"toString"},{"description":"__proto__","id":"__proto__"},{"description":"constructor","id":"constructor"}],"type":"choice"},{"id":"constructor","instructions":"Score the state.","levels":["low","medium","high"],"type":"score"},{"id":"enabled","instructions":"P(true) for eligibility.","type":"boolean"}],"state_input":"state"},"self_cid":"sha256:3cb49cca43b2ada3360038ff65eb699c5c79e93c2630bd3e3e4ed2fdd980db80","version":"actql-model-prompt/0.1"}

///|
let native_call_retry : String =
  #|{"retryable_failures":[],"self_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","version":"actql-model-retry-policy/0.1"}

///|
let native_call_backoff : String =
  #|{"delays_ms":[],"self_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","version":"actql-model-backoff/0.1"}

///|
let native_call_profile_wire : String =
  #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/sdk-builder","builder_revision":"1","codec_id":"fixture/native-decision","codec_revision":"1","port_abi":"model-physical-port/1","sdk":{"interface":"v4","lock_artifact_cid":"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367","package":"@ai-sdk/typesafe-ai","version":"3.0.13"}},"completion":{"basis":"native_decision","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1000,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/systemone","method":"POST","streaming":false},"probability":{"source":"native","validation_profile_cid":"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f"},"self_cid":"sha256:6d772ee910ac6e58eed6e1e591de6c6acb3171eca276084d7cc27d532e1830d3","task":{"contract_cid":"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e","input_schema_cid":"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466","kind":"decision","output_schema_cid":"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9"},"version":"actql-model-response-profile/0.1"}

///|
let native_call_profile_cid : String =
  #|sha256:6d772ee910ac6e58eed6e1e591de6c6acb3171eca276084d7cc27d532e1830d3

///|
fn native_call_installation() -> @environment.ModelResponseProfileInstallation {
  {
    builder_id: "fixture/sdk-builder",
    builder_revision: "1",
    codec_id: "fixture/native-decision",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    endpoint: "https://fixture.invalid/systemone",
    http_method: "POST",
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "native_decision",
    streaming: false,
    sdk: Some({
      package_name: "@ai-sdk/typesafe-ai",
      version: "3.0.13",
      interface: "v4",
      lock_artifact_cid: "sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367",
    }),
  }
}
