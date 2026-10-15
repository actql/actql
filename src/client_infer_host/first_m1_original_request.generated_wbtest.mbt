// Generated independent first-M1 application originals; static DATA only.

///|
let first_m1_current_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:dfb5302d0d8d4df85de7a271f56e6f9003eaa92c5b6188074c75d4dcb950714a","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:96ac9b2a06dae7a547aba6db6011d92bf6649a8832f65b1b986068b9561c8b31","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:6510cda280e9beee95537f359641df15e566d5abf101c85bf3e6a77eba7b3240","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let first_m1_current_environment_cid : String =
  #|sha256:dfb5302d0d8d4df85de7a271f56e6f9003eaa92c5b6188074c75d4dcb950714a

///|
let first_m1_current_program : String =
  #|{"version":"actql/0.1","id":"infer-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"captured":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"captured"}}}}

///|
let first_m1_current_execution : String =
  #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":66536,"media_input_contracts":{},"model_task_contract_cid":"sha256:96ac9b2a06dae7a547aba6db6011d92bf6649a8832f65b1b986068b9561c8b31","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:b7feb240420f15786b76167ee8bba0b0ba699e3c1fdab575071d74433c4d1698","version":"actql-model-execution-contract/0.1"}

///|
let first_m1_current_execution_cid : String =
  #|sha256:b7feb240420f15786b76167ee8bba0b0ba699e3c1fdab575071d74433c4d1698

///|
let first_m1_current_prompt : String =
  #|{"payload":{"format":"actql.openai_chat_prompt/0.1","instructions":"Original é\r\n"},"self_cid":"sha256:6510cda280e9beee95537f359641df15e566d5abf101c85bf3e6a77eba7b3240","version":"actql-model-prompt/0.1"}

///|
let first_m1_current_retry : String =
  #|{"retryable_failures":[],"self_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","version":"actql-model-retry-policy/0.1"}

///|
let first_m1_current_backoff : String =
  #|{"delays_ms":[],"self_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","version":"actql-model-backoff/0.1"}
