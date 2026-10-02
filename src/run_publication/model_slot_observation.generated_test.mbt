// Generated independent slot/ObservationSet vectors.

///|
test "model slot observation: success adopted slot" {
  let value = seal_run_evidence_value(
    "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2",
  )
  let restored = admit_run_evidence_value(
    "model_slot_capture",
    run_evidence_value_json(value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    run_evidence_value_identity(value),
  )
}

///|
test "model slot observation: response-less failed slot" {
  let value = seal_run_evidence_value(
    "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"failed:timeout\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":null,\"slot_cid\":\"sha256:30e1c1ebcfd762836736b8f60f217868f54ec471b45c44744d088d711707be07\",\"typed_value_artifact_cid\":null,\"version\":\"actql-model-slot-capture/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99",
  )
  let restored = admit_run_evidence_value(
    "model_slot_capture",
    run_evidence_value_json(value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    run_evidence_value_identity(value),
  )
}

///|
test "model slot observation: non-INFER observation unchanged" {
  let value = seal_run_evidence_value(
    "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:d291b34b750d1b704c61fce28fb09b520843bfad4493d1659b7b3b937d0caa6c",
  )
  let restored = admit_run_evidence_value(
    "observation_set",
    run_evidence_value_json(value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    run_evidence_value_identity(value),
  )
}

///|
test "model slot observation: zero-key INFER observation" {
  let value = seal_run_evidence_value(
    "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:e92dbffc213b5dcb7c444659a6738395378e6d074130c8b4613a2e04b37f8137",
  )
  let restored = admit_run_evidence_value(
    "observation_set",
    run_evidence_value_json(value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    run_evidence_value_identity(value),
  )
}

///|
test "model slot observation: success and failure observation" {
  let value = seal_run_evidence_value(
    "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:9d195a7cabd6a8a4cc15d6aa702d6058d8180e2b37a564247e47b2eb1e1756e2",
  )
  let restored = admit_run_evidence_value(
    "observation_set",
    run_evidence_value_json(value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    run_evidence_value_identity(value),
  )
}

///|
test "slot observation exact ordered success and failure bindings" {
  let first = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-model-call-slot/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let second = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-model-call-slot/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let success = seal_run_evidence_value(
    "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let timeout = seal_run_evidence_value(
    "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"failed:timeout\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":null,\"slot_cid\":\"sha256:30e1c1ebcfd762836736b8f60f217868f54ec471b45c44744d088d711707be07\",\"typed_value_artifact_cid\":null,\"version\":\"actql-model-slot-capture/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let a = bind_model_slot_capture(first, success).unwrap()
  let b = bind_model_slot_capture(second, timeout).unwrap()
  assert_true(bind_model_slot_capture(first, timeout) is Err(_))
  assert_true(bind_model_slot_capture(second, success) is Err(_))
  assert_true(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [a, b],
    )
    is Ok(_),
  )
  assert_false(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [a, b],
    )
    is Ok(_),
  )
  assert_false(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [a, b],
    )
    is Ok(_),
  )
  assert_false(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\",\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [a, b],
    )
    is Ok(_),
  )
  assert_false(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\",\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [a, b],
    )
    is Ok(_),
  )
  let observation = seal_run_evidence_value(
    "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_true(verify_model_observation_slots(observation, [b, a]) is Err(_))
  assert_true(verify_model_observation_slots(observation, [a, a]) is Err(_))
  assert_true(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [],
    )
    is Err(_),
  )
  assert_true(
    verify_model_observation_slots(
      seal_run_evidence_value(
        "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
      [],
    )
    is Ok(_),
  )
  let template = seal_run_evidence_value(
    "bound_invocation_template", "{\"barrier_contract_manifest_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"check_environment_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"grammar_manifest_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"invocation_bindings_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"parameter_values_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"required_profile_contracts\":[{\"contract_cid\":\"sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd\",\"profile_id\":\"actql-infer/0.1\"}],\"source_evidence\":\"unbound\",\"version\":\"actql-bound-invocation-template/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_true(
    issue_run_invocation(template, observation, 16384, 1024, 20) is Err(_),
  )
  let wire = "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:55bd7323d1ba930c06059904b2d4fbbb556affdce3f26fff4830a4ba1dc98a99\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}".replace(
    old="sha256:1111111111111111111111111111111111111111111111111111111111111111",
    new=run_evidence_value_identity(template),
  )
  let matched = seal_run_evidence_value(
    "observation_set", wire, 16384, 1024, 20,
  ).unwrap()
  assert_true(
    issue_model_run_invocation(template, matched, [a, b], 16384, 1024, 20)
    is Ok(_),
  )
  assert_true(
    issue_model_run_invocation(template, matched, [b, a], 16384, 1024, 20)
    is Err(_),
  )
  assert_true(
    issue_model_run_invocation(template, matched, [a], 16384, 1024, 20)
    is Err(_),
  )
  let foreign = seal_run_evidence_value(
    "bound_invocation_template", "{\"barrier_contract_manifest_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"check_environment_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"grammar_manifest_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"invocation_bindings_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"parameter_values_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"required_profile_contracts\":[{\"contract_cid\":\"sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd\",\"profile_id\":\"actql-infer/0.1\"}],\"source_evidence\":\"unbound\",\"version\":\"actql-bound-invocation-template/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_true(
    issue_model_run_invocation(foreign, matched, [a, b], 16384, 1024, 20)
    is Err(RunEvidenceReferenceMismatch("observation.invocation_template_cid")),
  )
  let wire = wire.replace(
    old=run_evidence_value_identity(template),
    new=run_evidence_value_identity(foreign),
  )
  let other_program = seal_run_evidence_value(
    "observation_set", wire, 16384, 1024, 20,
  ).unwrap()
  assert_true(
    issue_model_run_invocation(foreign, other_program, [a, b], 16384, 1024, 20)
    is Err(
      RunEvidenceReferenceMismatch("model_slot_capture.program_definition_cid")
    ),
  )
  let wire = "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}".replace(
    old="sha256:1111111111111111111111111111111111111111111111111111111111111111",
    new=run_evidence_value_identity(template),
  )
  let zero = seal_run_evidence_value("observation_set", wire, 16384, 1024, 20).unwrap()
  assert_true(
    issue_model_run_invocation(template, zero, [], 16384, 1024, 20) is Ok(_),
  )
  assert_true(
    issue_run_invocation(
      template,
      evidence_test_observation(template),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceReferenceMismatch("model_slot_capture_cids")),
  )
  let source_only = evidence_test_template(
    "sha256:1111111111111111111111111111111111111111111111111111111111111111",
  )
  assert_true(
    issue_model_run_invocation(
      source_only,
      evidence_test_observation(source_only),
      [],
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceReferenceMismatch("model_slot_capture_cids")),
  )
}

///|
test "slot capture cannot repair foreign inputs or fabricated outcomes" {
  let call = seal_run_evidence_value(
    "model_call_slot", "{\"effective_inputs_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-model-call-slot/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":null,\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":null,\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"failed:timeout\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":null,\"slot_cid\":\"sha256:30e1c1ebcfd762836736b8f60f217868f54ec471b45c44744d088d711707be07\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    bind_model_slot_capture(
      call,
      seal_run_evidence_value(
        "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"failed:timeout\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"response_issuer_evidence_cid\":null,\"slot_cid\":\"sha256:30e1c1ebcfd762836736b8f60f217868f54ec471b45c44744d088d711707be07\",\"typed_value_artifact_cid\":null,\"version\":\"actql-model-slot-capture/0.1\"}",
        16384, 1024, 20,
      ).unwrap(),
    )
    is Err(_),
  )
}

///|
test "observation slot references reject duplicate identities before binding" {
  assert_true(
    seal_run_evidence_value(
      "observation_set", "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"invocation_template_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"model_slot_capture_cids\":[\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\",\"sha256:8ba35fae69d9c4cd3991cf9ee662ce1f3f028534ab19b90aa90f04963be7bad2\"],\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}",
      16384, 1024, 20,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "adopted slots match only exact successful saved bundle records" {
  let a = bind_model_slot_capture(
    seal_run_evidence_value(
      "model_call_slot", "{\"effective_inputs_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-model-call-slot/0.1\"}",
      16384, 1024, 20,
    ).unwrap(),
    seal_run_evidence_value(
      "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"ok\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"response_issuer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"typed_value_artifact_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-slot-capture/0.1\"}",
      16384, 1024, 20,
    ).unwrap(),
  ).unwrap()
  let b = bind_model_slot_capture(
    seal_run_evidence_value(
      "model_call_slot", "{\"effective_inputs_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_ordinal\":2,\"unit_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"version\":\"actql-model-call-slot/0.1\"}",
      16384, 1024, 20,
    ).unwrap(),
    seal_run_evidence_value(
      "model_slot_capture", "{\"accounting_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"adopted_attempt_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"attachment_admission_cids\":[],\"authority_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"input_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_key_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"ordered_attempt_cids\":[\"sha256:9999999999999999999999999999999999999999999999999999999999999999\"],\"outcome\":\"failed:timeout\",\"outcome_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":null,\"slot_cid\":\"sha256:30e1c1ebcfd762836736b8f60f217868f54ec471b45c44744d088d711707be07\",\"typed_value_artifact_cid\":null,\"version\":\"actql-model-slot-capture/0.1\"}",
      16384, 1024, 20,
    ).unwrap(),
  ).unwrap()
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:508b0ba46dd8050091264f721a001ad6f641ab6c69a69fbd892997c8c6ec2891\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:508b0ba46dd8050091264f721a001ad6f641ab6c69a69fbd892997c8c6ec2891\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}},{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:508b0ba46dd8050091264f721a001ad6f641ab6c69a69fbd892997c8c6ec2891\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:508b0ba46dd8050091264f721a001ad6f641ab6c69a69fbd892997c8c6ec2891\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, a], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, a], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_true(verify_model_slot_capture_bundle([b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:508b0ba46dd8050091264f721a001ad6f641ab6c69a69fbd892997c8c6ec2891\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"model_invocation_evidence_cid\":\"sha256:3feb58a0b0c18aba9874ddd8d7e87d1e1ceebf5077475f68590571fc8d49e983\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:f6c1ec92e63b10aff2e54741d4c452748084cc87c428cdebc917ac2fb15fec58\",\"model_task_contract_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:6f0cd151eb9758a0d10f979a8cd03aa14b9c82f1b6ad67a6ffea6585af4356d1\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:92bf928b84fa719292541efc59d71204ccb3e2719fda7da1f05d908e6fbfef57\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:c4b1f7089883736180200b6f77e7d78546beb105253b037a57e123f89f734ae6\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:7d3c1040298019481cc179d68de08c6dcde0804a63ca2b50d64172c5dcfc69d4\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"validated_structured_output_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
  let saved = seal_run_evidence_value(
    "model_capture_bundle", "{\"barrier_receipts\":[],\"captures\":[{\"evidence\":{\"attempt\":1,\"authored_model_selector\":\"fixture-model\",\"finish_reason\":\"stop\",\"input_result_artifact_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_row_identity\":\"fixture-key\",\"input_row_identity_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"input_tokens\":1,\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"model_invocation_evidence_cid\":\"sha256:50daa7b354c04250b60d5ad5094bc6766037d97adb43667176892e7c957e01f4\",\"model_task_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"observed_at\":\"2026-10-02T00:00:00.000Z\",\"output_tokens\":2,\"provider_reported_model_id\":\"fixture-model\",\"provider_request_id\":\"fixture-1\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response_artifact_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"validated_structured_output_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-model-invocation-evidence/0.1\"},\"model_call_slot_cid\":\"sha256:4a9210998cf1d4e699936ee121d6c9f969d1855db86b0d81d345906cbd70b4e2\",\"semantic_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"structured_response\":{}}],\"version\":\"actql-model-capture-bundle/0.1\"}",
    16384, 1024, 20,
  ).unwrap()
  let read = read_model_capture_bundle(
    run_evidence_value_json(saved),
    run_evidence_value_identity(saved),
    16384,
    1024,
    20,
  ).unwrap()
  assert_false(verify_model_slot_capture_bundle([a, b], read) is Ok(_))
  assert_true(release_model_capture_bundle_read(read))
  assert_true(verify_model_slot_capture_bundle([a, b], read) is Err(_))
}
