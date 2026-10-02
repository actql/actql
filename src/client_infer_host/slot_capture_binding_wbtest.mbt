///|
// Symbolic external roots exercise exact owner binding only. They are not
// issued accounting, policy, authority or durable adopted-attempt evidence.
fn slot_binding_record(evidence : @publication.RunEvidenceValue) -> Json raise {
  guard @json.parse(@publication.run_evidence_value_json(evidence))
    is Object(observation) else {
    abort("invalid observation fixture")
  }
  let root : Json = Json::string("sha256:" + "a".repeat(64))
  Json::object({
    "version": Json::string("actql-model-slot-capture/0.1"),
    "slot_cid": observation["model_call_slot_cid"],
    "model_task_cid": observation["model_task_contract_cid"],
    "fixed_request_cid": observation["semantic_request_cid"],
    "input_artifact_cid": observation["input_result_artifact_cid"],
    "input_key_cid": observation["input_row_identity_cid"],
    "ordered_attempt_cids": Json::array([root]),
    "adopted_attempt_cid": root,
    "outcome": Json::string("ok"),
    "typed_value_artifact_cid": observation["validated_structured_output_cid"],
    "accounting_evidence_cid": root,
    "authority_evidence_cid": root,
    "policy_cid": root,
    "outcome_evidence_cid": root,
    "response_artifact_cid": observation["structured_response_artifact_cid"],
    "response_issuer_evidence_cid": root,
    "attachment_admission_cids": Json::array([]),
  })
}

///|
fn slot_binding_seal(body : Json) -> @publication.RunEvidenceValue raise {
  @publication.seal_run_evidence_value(
    "model_slot_capture",
    fixture_canonical(body),
    16384,
    1024,
    20,
  ).unwrap()
}

///|
test "slot binding uses the accepted normal Program call and checked response" {
  let (original, saved, calls) = replay_fixture_original()
  assert_eq(@model.verified_model_capture_call_count(saved), Some(1))
  let call = @model.verified_model_capture_call_at(saved, 0).unwrap()
  assert_eq(@publication.run_evidence_value_name(call), "model_call_slot")
  assert_eq(
    @publication.run_evidence_value_identity(call),
    capture(original).unwrap().captures[0].slot_cid,
  )
  assert_true(@model.verified_model_capture_call_at(saved, -1) is None)
  assert_true(@model.verified_model_capture_call_at(saved, 1) is None)
  let body = slot_binding_record(invocation_evidence(original, 0).unwrap())
  let record = slot_binding_seal(body)
  let binding = @model.bind_verified_model_slot_capture(saved, 0, record).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(
      @publication.bound_model_slot_capture_value(binding),
    ),
    @publication.run_evidence_value_identity(record),
  )
  assert_true(
    @model.bind_verified_model_slot_capture(saved, 1, record)
    is Err(@model.OutputIdentity),
  )
  for
    (field, expected) in [
      ("fixed_request_cid", "model_slot_capture.fixed_request_cid"),
      ("response_artifact_cid", "model_slot_capture.response_artifact_cid"),
      (
        "typed_value_artifact_cid", "model_slot_capture.typed_value_artifact_cid",
      ),
    ] {
    // A fresh, structurally valid identity cannot replace the owner's input
    // or response. Reject the exact field, not an unrelated parse failure.
    let changed = slot_binding_record(invocation_evidence(original, 0).unwrap())
    guard changed is Object(fields) else { abort("invalid fixture") }
    fields[field] = Json::string("sha256:" + "0".repeat(64))
    guard @model.bind_verified_model_slot_capture(
        saved,
        0,
        slot_binding_seal(changed),
      )
      is Err(
        @model.InvocationEvidence(
          @publication.RunEvidenceReferenceMismatch(actual)
        )
      ) else {
      abort("wrong typed binding failure")
    }
    assert_eq(actual, expected)
  }
  let other = @model.retain_verified_model_capture(saved).unwrap()
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(@model.verified_model_capture_call_count(saved) is None)
  assert_true(@model.verified_model_capture_call_at(saved, 0) is None)
  assert_true(
    @model.bind_verified_model_slot_capture(saved, 0, record)
    is Err(@model.OutputIdentity),
  )
  assert_true(!cleanup(original).unwrap())
  assert_eq(@model.verified_model_capture_call_count(other), Some(1))
  assert_eq(
    @publication.run_evidence_value_json(
      @model.verified_model_capture_call_at(other, 0).unwrap(),
    ),
    @publication.run_evidence_value_json(call),
  )
  assert_true(@model.release_verified_model_capture(other))
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "accepted call inventory preserves typed key order and explicit zero keys" {
  for empty in [false, true] {
    let rows = if empty {
      "[]"
    } else {
      "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
    }
    let prepared = fixture_prepared(
      source=infer_fixture_program.replace(
        old="[{\"id\":\"a\",\"text\":\"hello\"}]",
        new=rows,
      ),
    )
    let plan = call_identity_plan(prepared)
    let keys : Array[String] = []
    let provider = @model.install_model_provider("models/fixture", request => {
      keys.push(@admitted.canonical_scalar_text(request.key[0], 100).unwrap())
      Ok({
        value: @admitted.object_value([
          ("reason", @admitted.null_value()),
          ("risk", @admitted.text_value("high", 100).unwrap()),
        ]).unwrap(),
        provider_model: "fixture-risk-model",
        provider_request_id: "fixture-response",
        input_tokens: 1L,
        output_tokens: 2L,
        observed_at: "2026-10-01T00:00:00.000Z",
      })
    }).unwrap()
    let active = start(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      provider,
      @publication_host.client_infer_plan_graph_request_cid(plan),
      standard_limits(),
      plan=Some(plan),
    ).unwrap()
    assert_true(fixture_finish(active) is Complete(_, ..))
    let saved = acquire_capture(active).unwrap()
    let count = if empty { 0 } else { 2 }
    assert_eq(@model.verified_model_capture_call_count(saved), Some(count))
    assert_eq(keys, if empty { [] } else { ["a", "b"] })
    for index in 0..<count {
      let call = @model.verified_model_capture_call_at(saved, index).unwrap()
      assert_eq(
        @publication.run_evidence_value_identity(call),
        capture(active).unwrap().captures[index].slot_cid,
      )
      let record = slot_binding_seal(
        slot_binding_record(invocation_evidence(active, index).unwrap()),
      )
      assert_true(
        @model.bind_verified_model_slot_capture(saved, index, record) is Ok(_),
      )
    }
    assert_true(@model.verified_model_capture_call_at(saved, count) is None)
    assert_true(@model.release_verified_model_capture(saved))
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "restored execution retains the same formal call without another dispatch" {
  let (saved, _, calls) = restored_replay_fixture()
  let prior = @publication.model_capture_record_text(
    @publication.model_capture_bundle_record(saved, 0).unwrap(),
    "model_call_slot_cid",
  ).unwrap()
  let prepared = fixture_prepared()
  let replay = start_restored_replay(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared),
  ).unwrap()
  assert_true(fixture_finish(replay) is Complete(_, ..))
  let capture = acquire_capture(replay).unwrap()
  assert_eq(@model.verified_model_capture_call_count(capture), Some(1))
  assert_eq(
    @publication.run_evidence_value_identity(
      @model.verified_model_capture_call_at(capture, 0).unwrap(),
    ),
    prior,
  )
  let record = slot_binding_seal(
    slot_binding_record(invocation_evidence(replay, 0).unwrap()),
  )
  assert_true(
    @model.bind_verified_model_slot_capture(capture, 0, record) is Ok(_),
  )
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(cleanup(replay).unwrap())
  assert_true(@publication.release_model_capture_bundle_read(saved))
  assert_eq(calls.val, 1)
}
