// Generated from independently authored Interactive Control vectors.

///|
test "interactive identity 0: control_profile" {
  let value = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50",
  )
  let restored = admit_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"version\":\"actql-control-profile/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 1: control_command" {
  let value = seal_run_evidence_value(
    "control_command", "{\"expected_control_revision\":18,\"interval\":{\"guards\":null,\"until\":\"terminal\"},\"operation\":\"resume\",\"operation_id\":\"original-command\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-command/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:7f7e365b0dad169d951aa7fa88311bc12f8fb0caa13551dea104c4bf18084cce",
  )
  let restored = admit_run_evidence_value(
    "control_command", "{\"expected_control_revision\":18,\"interval\":{\"guards\":null,\"until\":\"terminal\"},\"operation\":\"resume\",\"operation_id\":\"original-command\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:7f7e365b0dad169d951aa7fa88311bc12f8fb0caa13551dea104c4bf18084cce\",\"version\":\"actql-control-command/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:7f7e365b0dad169d951aa7fa88311bc12f8fb0caa13551dea104c4bf18084cce",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "control_command", "{\"expected_control_revision\":18,\"interval\":{\"guards\":null,\"until\":\"terminal\"},\"operation\":\"resume\",\"operation_id\":\"original-command\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:7f7e365b0dad169d951aa7fa88311bc12f8fb0caa13551dea104c4bf18084cce\",\"version\":\"actql-control-command/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 2: logical_step_key" {
  let value = seal_run_evidence_value(
    "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9",
  )
  let restored = admit_run_evidence_value(
    "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 3: logical_step_key" {
  let value = seal_run_evidence_value(
    "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd",
  )
  let restored = admit_run_evidence_value(
    "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 4: explanation_facts" {
  let value = seal_run_evidence_value(
    "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682",
  )
  let restored = admit_run_evidence_value(
    "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 5: control_request_intent" {
  let value = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631",
  )
  let restored = admit_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"self_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"self_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 6: resolved_control_profile" {
  let value = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78",
  )
  let restored = admit_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"self_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"self_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"version\":\"actql-resolved-control-profile/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 7: logical_map" {
  let value = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14",
  )
  let restored = admit_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"self_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"self_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 8: control_admission" {
  let value = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:68a293066e01d364566e7330d782ede2ccda77c253b469356c946e27c8b6d967",
  )
  let restored = admit_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:68a293066e01d364566e7330d782ede2ccda77c253b469356c946e27c8b6d967\",\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:68a293066e01d364566e7330d782ede2ccda77c253b469356c946e27c8b6d967",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:68a293066e01d364566e7330d782ede2ccda77c253b469356c946e27c8b6d967\",\"version\":\"actql-control-admission/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 9: sample_source_generation" {
  let value = seal_run_evidence_value(
    "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f",
  )
  let restored = admit_run_evidence_value(
    "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 10: sample_original_capture" {
  let value = seal_run_evidence_value(
    "sample_original_capture", "{\"control_admission_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"max_artifacts\":20,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":false,\"resolved_profile_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"strategy\":\"execution_prefix\",\"ttl_seconds\":300,\"version\":\"actql-sample-original-capture/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217",
  )
  let restored = admit_run_evidence_value(
    "sample_original_capture", "{\"control_admission_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"max_artifacts\":20,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":false,\"resolved_profile_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"self_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"strategy\":\"execution_prefix\",\"ttl_seconds\":300,\"version\":\"actql-sample-original-capture/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "sample_original_capture", "{\"control_admission_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"max_artifacts\":20,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":false,\"resolved_profile_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"self_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"strategy\":\"execution_prefix\",\"ttl_seconds\":300,\"version\":\"actql-sample-original-capture/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 11: sample_emission_provenance" {
  let value = seal_run_evidence_value(
    "sample_emission_provenance", "{\"completeness\":\"unknown\",\"ordering_evidence_cid\":null,\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"relation_prefix_cid\":\"sha256:d99a3579f96c2e4e42e9893971082746920e75437a2cd69e978dffe7677d2508\",\"sampled_items\":\"1\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"total\":{\"kind\":\"unknown\",\"reason\":\"count_not_observed\",\"unit\":\"rows\"},\"truncation\":\"unknown\",\"version\":\"actql-sample-emission-provenance/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6",
  )
  let restored = admit_run_evidence_value(
    "sample_emission_provenance", "{\"completeness\":\"unknown\",\"ordering_evidence_cid\":null,\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"relation_prefix_cid\":\"sha256:d99a3579f96c2e4e42e9893971082746920e75437a2cd69e978dffe7677d2508\",\"sampled_items\":\"1\",\"self_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"total\":{\"kind\":\"unknown\",\"reason\":\"count_not_observed\",\"unit\":\"rows\"},\"truncation\":\"unknown\",\"version\":\"actql-sample-emission-provenance/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "sample_emission_provenance", "{\"completeness\":\"unknown\",\"ordering_evidence_cid\":null,\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"relation_prefix_cid\":\"sha256:d99a3579f96c2e4e42e9893971082746920e75437a2cd69e978dffe7677d2508\",\"sampled_items\":\"1\",\"self_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"total\":{\"kind\":\"unknown\",\"reason\":\"count_not_observed\",\"unit\":\"rows\"},\"truncation\":\"unknown\",\"version\":\"actql-sample-emission-provenance/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 12: sample_reference" {
  let value = seal_run_evidence_value(
    "sample_reference", "{\"emission_provenance_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-sample-reference/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561",
  )
  let restored = admit_run_evidence_value(
    "sample_reference", "{\"emission_provenance_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"version\":\"actql-sample-reference/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "sample_reference", "{\"emission_provenance_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"version\":\"actql-sample-reference/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive identity 13: sample_adoption_receipt" {
  let value = seal_run_evidence_value(
    "sample_adoption_receipt", "{\"adoption\":\"retained_relation_prefix\",\"expires_at_epoch_ms\":\"1795389900000\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"sample_ref_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"version\":\"actql-sample-adoption-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856",
  )
  let restored = admit_run_evidence_value(
    "sample_adoption_receipt", "{\"adoption\":\"retained_relation_prefix\",\"expires_at_epoch_ms\":\"1795389900000\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"sample_ref_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"self_cid\":\"sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856\",\"version\":\"actql-sample-adoption-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856",
  )
  assert_true(
    parse_interactive_run_control_shape(
      "sample_adoption_receipt", "{\"adoption\":\"retained_relation_prefix\",\"expires_at_epoch_ms\":\"1795389900000\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"sample_ref_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"self_cid\":\"sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856\",\"version\":\"actql-sample-adoption-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 0: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 1: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"control_revision\":17,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 2: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"control_revision\":17,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":true,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 3: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"control_revision\":17,\"expiry_pending\":true,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 4: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"control_revision\":17,\"expiry_pending\":true,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":true,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 5: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":true,\"control_revision\":17,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 6: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":true,\"control_revision\":17,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":true,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 7: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":true,\"control_revision\":17,\"expiry_pending\":true,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 8: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":true,\"control_revision\":17,\"expiry_pending\":true,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":true,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 9: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"boundary\":{\"consumed_boundary_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"logical_step\",\"position\":\"after\",\"step_id\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"cleanup_pending\":false,\"control_revision\":18,\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"expiry_pending\":false,\"matched_breakpoints\":[],\"pause_pending\":false,\"paused_at\":\"2026-10-11T00:00:00.000Z\",\"run_id\":\"original\",\"status\":\"paused\",\"stop_reason\":\"pause\",\"ttl_policy_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 10: controlled_run_state" {
  assert_true(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":19,\"expiry_pending\":false,\"pause_pending\":false,\"resume_origin\":{\"command_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"continuation_generation_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"fence_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"kind\":\"manual\"},\"run_id\":\"original\",\"status\":\"resuming\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 11: sample_relation" {
  assert_true(
    parse_interactive_run_control_shape(
      "sample_relation", "{\"columns\":[{\"name\":\"p\",\"position\":0,\"required\":false,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"kind\":\"relation\",\"ordering_evidence_cid\":null,\"rows\":[[{\"presence\":\"present\",\"value\":null,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],[{\"presence\":\"absent\"}],[{\"presence\":\"present\",\"value\":\"é\\r\\né\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}]],\"schema_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"version\":\"actql-sample-relation/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 12: sample_graph" {
  assert_true(
    parse_interactive_run_control_shape(
      "sample_graph", "{\"edges\":[{\"definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"domain_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"dst_identity_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"identity_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"key\":[{\"value\":1,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"label\":{\"presence\":\"absent\"},\"properties\":[],\"src_identity_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\"},{\"definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"domain_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"dst_identity_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"identity_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"key\":[{\"value\":2,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"label\":{\"presence\":\"present\",\"value\":null,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"},\"properties\":[],\"src_identity_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\"}],\"graph_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"kind\":\"graph\",\"nodes\":[],\"topology_complete\":false,\"version\":\"actql-sample-graph/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 13: sample_vectors" {
  assert_true(
    parse_interactive_run_control_shape(
      "sample_vectors", "{\"items\":[{\"components\":[{\"index\":0,\"value\":0.5},{\"index\":1,\"value\":0}],\"components_complete\":false,\"dimension\":1536,\"key\":[{\"value\":\"q\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"},{\"value\":1,\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"}],\"precision\":\"float64\"}],\"kind\":\"vectors\",\"vectors_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"version\":\"actql-sample-vectors/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 14: sample_events" {
  assert_true(
    parse_interactive_run_control_shape(
      "sample_events", "{\"clock_evidence_cid\":null,\"events_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"identity_role\":\"event_id\",\"kind\":\"events\",\"late_evidence_cid\":null,\"occurrences\":[{\"key\":[{\"value\":\"same-id\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"occurrence_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"payload\":{\"presence\":\"present\",\"value\":{\"v\":1},\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"},\"timestamp\":{\"presence\":\"present\",\"value\":\"2026-10-11T00:00:00.000Z\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}},{\"key\":[{\"value\":\"same-id\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"occurrence_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"payload\":{\"presence\":\"present\",\"value\":{\"v\":1},\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"},\"timestamp\":{\"presence\":\"present\",\"value\":\"2026-10-11T00:00:00.000Z\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}}],\"order_proven\":false,\"ordering_evidence_cid\":null,\"time_role\":\"event_time\",\"version\":\"actql-sample-events/0.1\",\"watermark_evidence_cid\":null,\"window_evidence_cid\":null}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 15: run_sample" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_sample", "{\"state\":\"forbidden\"}", 20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 16: run_sample" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_sample", "{\"state\":\"expired\"}", 20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 17: run_sample" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_sample", "{\"reason\":\"selection_required\",\"state\":\"unavailable\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 18: run_sample" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_sample", "{\"reason\":\"evicted\",\"state\":\"unavailable\"}", 20000,
      2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 19: control_operation_lookup" {
  assert_true(
    parse_interactive_run_control_shape(
      "control_operation_lookup", "{\"reason\":\"bounded_history_expired\",\"state\":\"history_unavailable\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 20: control_money" {
  assert_true(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"0\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 21: control_money" {
  assert_true(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"9007199254740993\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 22: control_money" {
  assert_true(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"9223372036854775806\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 23: control_money" {
  assert_true(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"9223372036854775807\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 24: explanation_facts" {
  assert_true(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 25: run_explanation_view" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_explanation_view", "{\"explanation\":{\"facts\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"},\"state\":\"projected\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"namespaceId\":\"original-namespace\",\"runDefinitionCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"version\":\"actql-run-explanation-view/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive positive 26: run_explanation_view" {
  assert_true(
    parse_interactive_run_control_shape(
      "run_explanation_view", "{\"explanation\":{\"reason\":\"not_retained\",\"state\":\"not_projected\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"namespaceId\":\"original-namespace\",\"runDefinitionCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"version\":\"actql-run-explanation-view/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 0: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":null,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 1: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 2: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":\"unknown\",\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 3: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":null,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 4: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":0,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 5: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":\"unknown\",\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 6: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":null,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 7: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":0,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 8: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":\"unknown\",\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 9: control_profile" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_profile", "{\"execution\":{\"breakpoints\":[{\"kind\":\"logical_step\",\"position\":\"after\",\"select\":{\"by\":\"operator\",\"operator\":\"effect\"}}],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:871edfaeaa6ed37ff3ddbb314c064a9664ef96c1079db0dc3311519afe311295\",\"version\":\"actql-control-profile/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 10: control_profile" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_profile", "{\"execution\":{\"breakpoints\":[{\"kind\":\"logical_step\",\"position\":\"after\",\"select\":{\"by\":\"operator\",\"operator\":\"unregistered_operator\"}}],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"self_cid\":\"sha256:83cddf804d91061411f6758268edf59fb9e43ffd05e876e49df7c97bad219954\",\"version\":\"actql-control-profile/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 11: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":\"17\",\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 12: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":2147483648,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 13: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"boundary\":{\"consumed_boundary_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"logical_step\",\"position\":\"after\",\"step_id\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"cleanup_pending\":false,\"control_revision\":18,\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"matched_breakpoints\":[],\"pause_pending\":false,\"paused_at\":\"2026-10-11T00:00:00.000Z\",\"run_id\":\"original\",\"status\":\"paused\",\"stop_reason\":\"pause\",\"ttl_policy_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 14: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":19,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"resuming\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"resume_origin\":{\"command_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"continuation_generation_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"fence_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"kind\":\"manual\"},\"run_id\":\"original\",\"status\":\"resuming\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 15: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"stop_reason\":\"pause\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 16: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"boundary\":{\"consumed_boundary_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"logical_step\",\"position\":\"after\",\"step_id\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"cleanup_pending\":false,\"control_revision\":18,\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"expiry_pending\":false,\"matched_breakpoints\":[],\"pause_pending\":false,\"paused_at\":\"2026-10-11T00:00:00.000Z\",\"previous_stop_reason\":\"entry\",\"run_id\":\"original\",\"status\":\"paused\",\"stop_reason\":\"pause\",\"ttl_policy_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 17: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"boundary\":{\"consumed_boundary_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"logical_step\",\"position\":\"after\",\"step_id\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"cleanup_pending\":false,\"control_revision\":18,\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"expiry_pending\":false,\"matched_breakpoints\":[],\"pause_pending\":false,\"paused_at\":\"2026-10-11T00:00:00.000Z\",\"run_id\":\"original\",\"status\":\"paused\",\"stop_reason\":\"breakpoint\",\"ttl_policy_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 18: run_sample" {
  assert_false(
    parse_interactive_run_control_shape(
      "run_sample", "{\"count\":1,\"kind\":\"graph\",\"state\":\"forbidden\"}", 20000,
      2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 19: run_sample" {
  assert_false(
    parse_interactive_run_control_shape(
      "run_sample", "{\"source\":{},\"state\":\"expired\"}", 20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 20: control_quantity" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_quantity", "{\"kind\":\"unknown\",\"reason\":\"unobserved\",\"unit\":\"rows\",\"value\":\"0\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 21: control_quantity" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_quantity", "{\"basis_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"bound\",\"scope_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"unit\":\"bytes\",\"value\":\"01\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 22: control_quantity" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_quantity", "{\"basis_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"bound\",\"scope_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"unit\":\"bytes\",\"value\":\"1\\n\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 23: sample_relation" {
  assert_false(
    parse_interactive_run_control_shape(
      "sample_relation", "{\"columns\":[{\"name\":\"p\",\"position\":0,\"required\":false,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"kind\":\"graph\",\"ordering_evidence_cid\":null,\"rows\":[[{\"presence\":\"present\",\"value\":null,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],[{\"presence\":\"absent\"}],[{\"presence\":\"present\",\"value\":\"é\\r\\né\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}]],\"schema_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"version\":\"actql-sample-relation/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 24: sample_relation" {
  assert_false(
    parse_interactive_run_control_shape(
      "sample_relation", "{\"columns\":[{\"name\":\"p\",\"position\":0,\"required\":false,\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"kind\":\"relation\",\"ordering_evidence_cid\":null,\"rows\":[[{\"presence\":\"absent\",\"value\":null}]],\"schema_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"version\":\"actql-sample-relation/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 25: sample_events" {
  assert_false(
    parse_interactive_run_control_shape(
      "sample_events", "{\"clock_evidence_cid\":null,\"events_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"identity_role\":\"event_id\",\"kind\":\"events\",\"late_evidence_cid\":null,\"occurrences\":[{\"key\":[{\"value\":\"same-id\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"occurrence_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"payload\":{\"presence\":\"present\",\"value\":{\"v\":1},\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"},\"timestamp\":{\"presence\":\"present\",\"value\":\"2026-10-11T00:00:00.000Z\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}},{\"key\":[{\"value\":\"same-id\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}],\"occurrence_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"payload\":{\"presence\":\"present\",\"value\":{\"v\":1},\"value_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"},\"timestamp\":{\"presence\":\"present\",\"value\":\"2026-10-11T00:00:00.000Z\",\"value_contract_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\"}}],\"order_proven\":true,\"ordering_evidence_cid\":null,\"time_role\":\"event_time\",\"version\":\"actql-sample-events/0.1\",\"watermark_evidence_cid\":null,\"window_evidence_cid\":null}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 26: control_interval" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_interval", "{\"guards\":null,\"until\":\"automatically_retry\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 27: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"9223372036854775808\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 28: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"00\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 29: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"+1\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 30: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"-1\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 31: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1e3\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 32: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\" 1\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 33: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1.0\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 34: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1\\n\",\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 35: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":1,\"currency\":\"USD\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 36: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1\",\"currency\":\"usd\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 37: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1\",\"currency\":\"US\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 38: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1\",\"currency\":\"USDA\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 39: control_money" {
  assert_false(
    parse_interactive_run_control_shape(
      "control_money", "{\"amount_micro\":\"1\",\"currency\":\"USD\\n\",\"scope_cids\":[\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"],\"tariff_revision_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"valid_until\":\"2026-10-11T00:00:00.000Z\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 40: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 41: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":null,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 42: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":-1,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 43: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0.5,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 44: controlled_run_state" {
  assert_false(
    parse_interactive_run_control_shape(
      "controlled_run_state", "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":9007199254740992,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 45: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"},\"value\":\"private\"}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 46: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"},\"value_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 47: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"length\":\"private\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 48: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"byte_length\":\"private\",\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 49: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"text\":\"private\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 50: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"source\":\"private\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 51: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"prompt\":\"private\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 52: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"max_utf8_bytes\":17,\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 53: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"max_codepoints\":17,\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 54: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"enumeration\":17,\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 55: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"contract_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 56: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"prompt\":\"private\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 57: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"source_body\":\"private\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 58: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"can_execute\":\"private\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 59: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"sample\":\"private\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 60: explanation_facts" {
  assert_false(
    parse_interactive_run_control_shape(
      "explanation_facts", "{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"values\",\"row_count\":9,\"schema\":{\"fields\":[]}},\"operator\":\"values\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive negative 61: run_explanation_view" {
  assert_false(
    parse_interactive_run_control_shape(
      "run_explanation_view", "{\"explanation\":{\"facts\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"disclosure\":\"structural\",\"logical_map_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"parameter_values_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"program_definition_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"self_cid\":\"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682\",\"steps\":[{\"input_ports\":[\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"],\"key\":{\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\",\"stage_ordinal\":0,\"version\":\"actql-logical-step-key/0.1\"},\"meaning\":{\"kind\":\"filter\",\"predicate\":{\"nodes\":[{\"children\":[1,2],\"form\":\"operation\",\"operator\":\"gt\",\"type\":{\"kind\":\"boolean\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"field\",\"name\":\"id\",\"scope\":\"fields\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}},{\"form\":\"literal_redacted\",\"type\":{\"kind\":\"number\",\"nullable\":false,\"projection\":\"shape_and_nullability\"}}],\"root\":0,\"state\":\"projected\"}},\"operator\":\"filter\",\"output_ports\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"step_id\":\"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8\"}],\"version\":\"actql-explanation-facts/0.1\"},\"reason\":\"not_retained\",\"state\":\"not_projected\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"namespaceId\":\"original-namespace\",\"runDefinitionCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"version\":\"actql-run-explanation-view/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive legacy projection stays exact and rejects manual origins" {
  assert_eq(
    project_interactive_legacy_state(
      "{\"cleanup_pending\":false,\"control_revision\":17,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    ).unwrap(),
    "{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
  )
  assert_eq(
    project_interactive_legacy_state(
      "{\"boundary\":{\"consumed_boundary_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"logical_step\",\"position\":\"after\",\"step_id\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},\"cleanup_pending\":false,\"control_revision\":18,\"expires_at\":\"2026-10-11T00:10:00.000Z\",\"expiry_pending\":false,\"matched_breakpoints\":[],\"pause_pending\":false,\"paused_at\":\"2026-10-11T00:00:00.000Z\",\"run_id\":\"original\",\"status\":\"paused\",\"stop_reason\":\"pause\",\"ttl_policy_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    ),
    Err(RunStateVersionUnsupported),
  )
  assert_eq(
    project_interactive_legacy_state(
      "{\"cleanup_pending\":false,\"control_revision\":19,\"expiry_pending\":false,\"pause_pending\":false,\"resume_origin\":{\"command_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"continuation_generation_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"fence_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"kind\":\"manual\"},\"run_id\":\"original\",\"status\":\"resuming\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    ),
    Err(RunStateVersionUnsupported),
  )
  assert_eq(
    project_interactive_legacy_state(
      "{\"cleanup_pending\":false,\"control_revision\":18,\"expiry_pending\":false,\"legacy_state\":{\"control\":{\"cancellation_requested\":false,\"physical_stop\":\"unknown\",\"revision\":17},\"next_action\":{\"kind\":\"none\"},\"result_availability\":{},\"result_available\":false,\"revision\":0,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-run-state/0.1\"},\"pause_pending\":false,\"run_id\":\"original\",\"status\":\"running\",\"updated_at\":\"2026-10-11T00:00:00.000Z\",\"version\":\"actql-controlled-run-state/0.1\"}",
      20000, 2000, 32,
    ),
    Err(LegacyProjectionMismatch("control_revision")),
  )
}

///|
test "interactive binding original intent and input-only Plan map" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 0" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 1" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 2" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 3" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 4" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 5" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 6" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 7" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 8" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 9" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[{\"kind\":\"logical_step\",\"position\":\"before\",\"step_id\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"}],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 10" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 11" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 12" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive binding rehashed substitution 13" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let profile = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"requested_profile_cid\":\"sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50\",\"sample_output_port_ids\":[],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:b8ae769f4a12476cb618e0c5fe8944330fe634fdb04ad59156905252e6959631\",\"resolved_profile_cid\":\"sha256:ca3bd661efba7c8d414a565bf10164ba85edc2b70704af1375d537c4eef74e78\",\"run_ref\":{\"authorityScopeCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value0, profile, profile, value1, value2, value3, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding all original outputs" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"all_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"sample_output_port_ids\":[\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:c59aa3244adccb4a6b262a2ebee1a88e96548adbd650ff83aa6cc711979ff35e\",\"resolved_profile_cid\":\"sha256:ac9da49c917424d887f2effc53b28440e25b22cbc0c319916e54be7b3bcd3439\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding all outputs cannot omit a projected target" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"all_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:6ccb1d7af9804ebe6f94a71329a9979dc3d39de86c3166a7bad045138ad4f5ee\",\"sample_output_port_ids\":[\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:c59aa3244adccb4a6b262a2ebee1a88e96548adbd650ff83aa6cc711979ff35e\",\"resolved_profile_cid\":\"sha256:9e8022d1b72a638413d366252511ddcb3f61dc82a132fef4a3f894a1856dd81a\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding operator selects the original operation" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"selected_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[{\"by\":\"operator\",\"operator\":\"select\"}],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"sample_output_port_ids\":[\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:967ac94e5e797f039627bab163ef4193c520591db5e50e5d7e666d582a65b91b\",\"resolved_profile_cid\":\"sha256:2b932a4779e2535ccf08c52d4fe197fea893ab9875509ca92e903bff4cbcf070\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding operator cannot add an unrelated output" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"selected_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[{\"by\":\"operator\",\"operator\":\"select\"}],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:7940966fcbbf408bb59487ba9a4158c78612a3b7dd2ec85f973f21025eab9802\",\"sample_output_port_ids\":[\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:967ac94e5e797f039627bab163ef4193c520591db5e50e5d7e666d582a65b91b\",\"resolved_profile_cid\":\"sha256:08a3269202071a6bd8e4f8e91b6ca5e6712dcc3c5be0870b3cd3cf90ea756777\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding name selects an input-only output" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"selected_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[{\"by\":\"name\",\"name\":\"answer\"}],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"sample_output_port_ids\":[\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:7a9c4eeb1729df6c09acedd9c7fadfb73c26d5eea9dcaaac7630dd3e85b062cf\",\"resolved_profile_cid\":\"sha256:3384fda9ca45a8d9675dd3ee5022f8e015b3729db829116d021f02955918f837\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding name cannot substitute a different valid output" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"selected_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[{\"by\":\"name\",\"name\":\"answer\"}],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:22b2dbb137f0d4cd67f9b8f973a28e925f156f4be8515604aca472705acb64c7\",\"sample_output_port_ids\":[\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:7a9c4eeb1729df6c09acedd9c7fadfb73c26d5eea9dcaaac7630dd3e85b062cf\",\"resolved_profile_cid\":\"sha256:7f253076c1d6ec416e4396a0e34cc7ed207163de796a72d8da6f2f749cc9bc62\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_false(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive Sample target binding overlapping selectors retain one original port" {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value0 = seal_run_evidence_value(
    "control_profile", "{\"execution\":{\"breakpoints\":[],\"default_until\":\"terminal\",\"guards\":null,\"stop_on_entry\":false},\"retain\":{\"samples\":{\"capture_scope\":\"selected_outputs\",\"graph\":{\"max_edges\":0,\"max_nodes\":0},\"max_artifacts\":2,\"max_bytes\":\"65536\",\"max_items\":50,\"required\":true,\"strategy\":\"execution_prefix\",\"targets\":[{\"by\":\"id\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"},{\"by\":\"name\",\"name\":\"computed\"}],\"ttl_seconds\":30,\"vectors\":{\"max_components_per_item\":1}}},\"version\":\"actql-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value1 = seal_run_evidence_value(
    "control_request_intent", "{\"expected_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"legacy_request_fingerprint_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"requested_profile_cid\":\"sha256:89fbf0fa52006bbca5b4754a88da0fc23c52e8e2c5ee4171abe368c01dac279a\",\"submission_ref\":{\"epoch\":{\"authenticator\":\"2222222222222222222222222222222222222222222222222222222222222222\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"expiresAt\":2,\"notBefore\":1,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-request\"},\"version\":\"actql-control-request-intent/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value2 = seal_run_evidence_value(
    "resolved_control_profile", "{\"breakpoints\":[],\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"effective_profile_cid\":\"sha256:89fbf0fa52006bbca5b4754a88da0fc23c52e8e2c5ee4171abe368c01dac279a\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"requested_profile_cid\":\"sha256:89fbf0fa52006bbca5b4754a88da0fc23c52e8e2c5ee4171abe368c01dac279a\",\"sample_output_port_ids\":[\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\"],\"version\":\"actql-resolved-control-profile/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value3 = seal_run_evidence_value(
    "logical_map", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"steps\":[{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"answer\"],\"operator\":null,\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2\",\"port_ordinal\":0,\"role\":\"input\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}},{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"input_port_ordinal\":0,\"kind\":\"stage_input\",\"stage_ordinal\":1}}],\"step_id\":\"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b\",\"stop_reason\":\"not_installed\"},{\"can_stop_after\":false,\"can_stop_before\":false,\"key\":{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"},\"names\":[\"computed\"],\"operator\":\"select\",\"ports\":[{\"can_sample\":false,\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"port_ordinal\":0,\"role\":\"output\",\"sample_reason\":\"not_installed\",\"source\":{\"kind\":\"logical_output\",\"output_port_id\":\"sha256:84c92423fcff8339ca72446d0221e408e438c25096c4d6bef14783b8ea02fece\",\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\"}}],\"step_id\":\"sha256:c061d0b34a4d3f85959270c7a70e4863cf4ade33f65e48b09f45c740b403404c\",\"stop_reason\":\"not_installed\"}],\"version\":\"actql-logical-map/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let value4 = seal_run_evidence_value(
    "control_admission", "{\"compiled_plan_cid\":\"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22\",\"logical_map_cid\":\"sha256:4e0ea61c05fa4269b0f806dc4d3eb66a4e11ea3a56f545a6bd66168023594191\",\"policy_revision_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"request_intent_cid\":\"sha256:0bc0fa032a7a634d3421114759a8420fc770f8714adba1de3b31b9cb10a74d4d\",\"resolved_profile_cid\":\"sha256:861d9a30ae525183453692736d0c61958844d74346233345924b2b19eee8240c\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"version\":\"actql-control-admission/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    check_interactive_admission_binding(
      value1, value0, value0, value2, value3, value4, plan, "workspace:test", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "interactive sample invalid body 0" {
  assert_true(
    seal_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"graph\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample invalid body 1" {
  assert_true(
    seal_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"0\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample invalid body 2" {
  assert_true(
    seal_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\",\"task_ordinal\":7},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample invalid body 3" {
  assert_true(
    seal_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"9223372036854775808\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample invalid body 4" {
  assert_true(
    seal_run_evidence_value(
      "sample_original_capture", "{\"control_admission_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"max_artifacts\":20,\"max_bytes\":\"01\",\"max_items\":50,\"required\":false,\"resolved_profile_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"source_generation_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"strategy\":\"execution_prefix\",\"ttl_seconds\":300,\"version\":\"actql-sample-original-capture/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample invalid body 5" {
  assert_true(
    seal_run_evidence_value(
      "sample_adoption_receipt", "{\"adoption\":\"retained_relation_prefix\",\"expires_at_epoch_ms\":\"0\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"sample_ref_cid\":\"sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561\",\"version\":\"actql-sample-adoption-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "interactive sample substituted identity 0" {
  assert_true(
    admit_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"6\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "interactive sample substituted identity 1" {
  assert_true(
    admit_run_evidence_value(
      "sample_source_generation", "{\"carrier\":\"relation\",\"carrier_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"committed_generation\":\"13\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"logical_map_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"output_port_id\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_occurrence\":{\"attempt_sequence\":\"7\",\"kind\":\"first_physical_start\",\"start_revision\":\"2\"},\"run_ref\":{\"authorityScopeCid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"self_cid\":\"sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f\",\"step_id\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-sample-source-generation/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "interactive sample substituted identity 2" {
  assert_true(
    admit_run_evidence_value(
      "sample_emission_provenance", "{\"completeness\":\"unknown\",\"ordering_evidence_cid\":null,\"original_capture_cid\":\"sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217\",\"relation_prefix_cid\":\"sha256:d99a3579f96c2e4e42e9893971082746920e75437a2cd69e978dffe7677d2508\",\"sampled_items\":\"1\",\"self_cid\":\"sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6\",\"source_generation_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"total\":{\"kind\":\"unknown\",\"reason\":\"count_not_observed\",\"unit\":\"rows\"},\"truncation\":\"unknown\",\"version\":\"actql-sample-emission-provenance/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "interactive sample substituted identity 3" {
  assert_true(
    admit_run_evidence_value(
      "sample_adoption_receipt", "{\"adoption\":\"retained_relation_prefix\",\"expires_at_epoch_ms\":\"1795389900000\",\"run_ref\":{\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"namespaceId\":\"workspace:test\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"sample_ref_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"self_cid\":\"sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856\",\"version\":\"actql-sample-adoption-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}
