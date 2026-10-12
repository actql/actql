///|
fn content_model_test_slot(key : String) -> BoundModelSlotCapture raise {
  let call = seal_run_evidence_value(
    "model_call_slot",
    "{\"version\":\"actql-model-call-slot/0.1\",\"program_definition_cid\":\"" +
    ordering_test_cid("8") +
    "\",\"unit_definition_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"effective_inputs_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"input_artifact_cid\":\"" +
    ordering_test_cid("4") +
    "\",\"model_task_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"fixed_request_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"input_key_cid\":\"" +
    ordering_test_cid(key) +
    "\",\"source_ordinal\":2}",
    16384,
    1024,
    20,
  ).unwrap()
  // Independent Node crypto vectors for the two complete call bodies.
  let slot = if key == "7" {
    "sha256:d162c149f17a0c0482bc3f410d7469c030ff83327efa71c3e6a66e78e5e5246b"
  } else {
    "sha256:be7ff7e78c8f07c7b443644ef1993d33d617dbc3658711e9a09b3af3ad107c32"
  }
  assert_eq(run_evidence_value_identity(call), slot)
  let capture = seal_run_evidence_value(
    "model_slot_capture",
    "{\"version\":\"actql-model-slot-capture/0.1\",\"slot_cid\":\"" +
    slot +
    "\",\"model_task_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"fixed_request_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"input_artifact_cid\":\"" +
    ordering_test_cid("4") +
    "\",\"input_key_cid\":\"" +
    ordering_test_cid(key) +
    "\",\"ordered_attempt_cids\":[\"" +
    ordering_test_cid("9") +
    "\"],\"adopted_attempt_cid\":\"" +
    ordering_test_cid("9") +
    "\",\"outcome\":\"failed:timeout\",\"typed_value_artifact_cid\":null," +
    "\"response_artifact_cid\":null,\"response_issuer_evidence_cid\":null," +
    "\"attachment_admission_cids\":[],\"accounting_evidence_cid\":\"" +
    ordering_test_cid("b") +
    "\",\"authority_evidence_cid\":\"" +
    ordering_test_cid("c") +
    "\",\"policy_cid\":\"" +
    ordering_test_cid("d") +
    "\",\"outcome_evidence_cid\":\"" +
    ordering_test_cid("e") +
    "\"}",
    16384,
    1024,
    20,
  ).unwrap()
  bind_model_slot_capture(call, capture).unwrap()
}

///|
fn content_model_test_inventory(
  live : Ref[Bool],
) -> (
  RunEvidenceValue,
  RunEvidenceValue,
  BoundContentGeneration,
  Array[BoundModelSlotCapture],
) raise {
  let original = receipt_test_template(ordering_test_cid("8"))
  let body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(original)),
    "bound_invocation_template_cid",
  ).unwrap()
  let template = seal_run_evidence_value(
    "bound_invocation_template",
    captured_test_wire(body).replace(
      old="\"required_profile_contracts\":[]",
      new="\"required_profile_contracts\":[{\"profile_id\":\"actql-content/0.1\",\"contract_cid\":\"" +
        ordering_test_cid("c") +
        "\"},{\"profile_id\":\"actql-infer/0.1\",\"contract_cid\":\"" +
        ordering_test_cid("d") +
        "\"}]",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let run = issue_run_definition(
    receipt_test_admission(template, ordering_test_cid("8")),
    "scope",
    "run",
    ordering_test_cid("0"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let generation = content_capture_test_generation(template, run, live)
  let models = [content_model_test_slot("7"), content_model_test_slot("8")]
  let observation_body = @json.object_without_field(
    captured_test_value(
      run_evidence_value_json(receipt_test_observation(template)),
    ),
    "observation_set_cid",
  ).unwrap()
  let observation_wire = captured_test_wire(observation_body)
    .replace(old="\"materialized\":false", new="\"materialized\":true")
    .replace(
      old="\"availability_evidence_cids\":[]",
      new="\"availability_evidence_cids\":[\"" + ordering_test_cid("3") + "\"]",
    )
  let observation = seal_run_evidence_value(
    "observation_set",
    "{\"content_generation_cids\":[\"" +
    run_evidence_value_identity(
      bound_content_generation_value(generation).unwrap(),
    ) +
    "\"],\"model_slot_capture_cids\":[\"" +
    run_evidence_value_identity(bound_model_slot_capture_value(models[0])) +
    "\",\"" +
    run_evidence_value_identity(bound_model_slot_capture_value(models[1])) +
    "\"]," +
    observation_wire[1:].to_owned(),
    65536,
    4096,
    32,
  ).unwrap()
  (template, observation, generation, models)
}

///|
test "joint Content Model invocation requires both exact ordered inventories" {
  let live = Ref(true)
  let (template, observation, generation, models) = content_model_test_inventory(
    live,
  )
  let invocation = issue_content_model_run_invocation(
    template,
    observation,
    models,
    [generation],
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    publication_contract_json(invocation).contains(
      run_evidence_value_identity(observation),
    ),
  )
  for slots in [[], [models[0]], [models[1], models[0]], [models[0], models[0]]] {
    assert_true(
      issue_content_model_run_invocation(
        template,
        observation,
        slots,
        [generation],
        65536,
        4096,
        32,
      )
      is Err(_),
    )
  }
  for generations in [[], [generation, generation]] {
    assert_true(
      issue_content_model_run_invocation(
        template, observation, models, generations, 65536, 4096, 32,
      )
      is Err(_),
    )
  }
  // Neither dedicated path, nor the generic issuer, may ignore the other
  // component just because all supplied evidence was individually admitted.
  assert_true(
    issue_model_run_invocation(template, observation, models, 65536, 4096, 32)
    is Err(_),
  )
  assert_true(
    issue_content_run_invocation(
      template,
      observation,
      [generation],
      65536,
      4096,
      32,
    )
    is Err(_),
  )
  assert_true(
    issue_run_invocation(template, observation, 65536, 4096, 32) is Err(_),
  )
  live.val = false
  assert_true(
    issue_content_model_run_invocation(
      template,
      observation,
      models,
      [generation],
      65536,
      4096,
      32,
    )
    is Err(_),
  )
}

///|
test "joint Content Model invocation refuses substituted availability" {
  let (template, observation, generation, models) = content_model_test_inventory(
    Ref(true),
  )
  let body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(observation)),
    "observation_set_cid",
  ).unwrap()
  for
    (field, before, after) in [
      (
        "availability_evidence_cids",
        ordering_test_cid("3"),
        ordering_test_cid("4"),
      ),
    ] {
    let old = if field == "availability_evidence_cids" {
      "\"" + field + "\":[\"" + before + "\"]"
    } else {
      "\"" + field + "\":\"" + before + "\""
    }
    let changed = captured_test_wire(body).replace(
      old~,
      new=old.replace(old=before, new=after),
    )
    let substituted = seal_run_evidence_value(
      "observation_set", changed, 65536, 4096, 32,
    ).unwrap()
    assert_true(
      issue_content_model_run_invocation(
        template,
        substituted,
        models,
        [generation],
        65536,
        4096,
        32,
      )
      is Err(_),
    )
  }
}

///|
test "joint Content Model preserves intermediate policy independently of final Model policy" {
  let (template, observation, generation, models) = content_model_test_inventory(
    Ref(true),
  )
  let body = @json.object_without_field(
    captured_test_value(run_evidence_value_json(observation)),
    "observation_set_cid",
  ).unwrap()
  let model_observation = seal_run_evidence_value(
    "observation_set",
    captured_test_wire(body).replace(
      old="\"data_policy_cid\":\"" + ordering_test_cid("e") + "\"",
      new="\"data_policy_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let _ = issue_content_model_run_invocation(
    template,
    model_observation,
    models,
    [generation],
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    content_capture_test_string(
      captured_test_value(
        run_evidence_value_json(
          bound_content_generation_derivation(generation).unwrap(),
        ),
      ),
      "effective_data_policy_cid",
    ),
    ordering_test_cid("e"),
  )
}
