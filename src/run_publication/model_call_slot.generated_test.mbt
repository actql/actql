// Generated independent model identity admission vectors.

///|
test "model identity: empty effective inputs" {
  let issued = seal_run_evidence_value(
    "model_effective_inputs", "{\"input_artifacts\":{},\"invocation_bindings_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"parameter_values_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"actql-model-effective-inputs/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647",
  )
  let reconstructed = admit_run_evidence_value(
    "model_effective_inputs",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: named upstream inputs" {
  let issued = seal_run_evidence_value(
    "model_effective_inputs", "{\"input_artifacts\":{\"left\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"right\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"},\"invocation_bindings_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"parameter_values_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"actql-model-effective-inputs/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:dc262f1ef51914676db3090bbdcfafb57cdea129639fadce5d2127f77d85572a",
  )
  let reconstructed = admit_run_evidence_value(
    "model_effective_inputs",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: completed prefix artifact" {
  let issued = seal_run_evidence_value(
    "model_input_artifact", "{\"completeness\":\"complete\",\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"input_fragment_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"logical_relation_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"ordered_rows_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"relation_schema_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-input-artifact/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96",
  )
  let reconstructed = admit_run_evidence_value(
    "model_input_artifact",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: typed string key" {
  let issued = seal_run_evidence_value(
    "model_input_key", "{\"components\":[{\"field\":\"id\",\"value_cid\":\"sha256:ac8d8342bbb2362d13f0a559a3621bb407011368895164b628a54f7fc33fc43c\",\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"}],\"version\":\"actql-model-input-key/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991",
  )
  let reconstructed = admit_run_evidence_value(
    "model_input_key",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: ordered compound key" {
  let issued = seal_run_evidence_value(
    "model_input_key", "{\"components\":[{\"field\":\"id\",\"value_cid\":\"sha256:ac8d8342bbb2362d13f0a559a3621bb407011368895164b628a54f7fc33fc43c\",\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"},{\"field\":\"partition\",\"value_cid\":\"sha256:6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b\",\"value_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}],\"version\":\"actql-model-input-key/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:6f64dac8543e79ca525c931b5a47ebe5046f03649c290f3e93d68ae0ba91d8a9",
  )
  let reconstructed = admit_run_evidence_value(
    "model_input_key",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: call slot" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:4bdd5a64f99fb1708bdbe098c241597b720a6c59de913d93fbbe44c297ed45b9",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed program_definition_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:b043cb169a543c9a4996fec2d72563f9becb4c71a59ed9040a66c1032a682785",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed unit_definition_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:9e29d23ecac273379384904558ecd304895d4b4ae450e1b9b6d3937849b1fc7f",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed source_ordinal" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":3,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:38524e75ffabef328a26fda92ba6af57bce7c8a0fbf7bcd072d8eaee7e5808c3",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed effective_inputs_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:935e936ddd561fde4e1c901b13c518919f98a313108385b23f8f3a7cfedd0b75",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed input_artifact_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:f02fbd6fb96b83160634e5af6bb3c19598a21f2ce935b5a0f631a1d786af3d5d",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed input_key_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:396a2e0627ecb16af562cbced58f2c168721cc2115a70b0ea647445cbc6f6d60",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed model_task_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:c01f76fa05a59539e19ea93f07a1b7f11ceeb73c219b45d06d055123d7346b05",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}

///|
test "model identity: changed fixed_request_cid" {
  let issued = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:529456bd584b31b0ad2c1799bc9272022c4d91660207be7fbc30feef60786647\",\"fixed_request_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"input_artifact_cid\":\"sha256:c18c8f3618bb0fa17a0c42563c1f631a37fabd28330b8393e69799f3838f2f96\",\"input_key_cid\":\"sha256:a6a85fa5b6807bfa83164539574450577216c354ac54c9821da93a93c4d3c991\",\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-model-call-slot/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:148ae20da27aedb32a60d3d5b77b82d0ffa3793e0cbb7a7029959f7e3357c0fb",
  )
  let reconstructed = admit_run_evidence_value(
    "model_call_slot",
    run_evidence_value_json(issued),
    10000,
    1000,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(reconstructed),
    run_evidence_value_identity(issued),
  )
}
