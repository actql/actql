///|
// External roots below exercise exact all-slot matching only. They are not
// authority, accounting, adopted-attempt or durable Store evidence.
fn observation_failure_record(
  saved : @model.VerifiedModelCapture,
  index : Int,
) -> @publication.RunEvidenceValue raise {
  let call = @model.verified_model_capture_call_at(saved, index).unwrap()
  guard @json.parse(@publication.run_evidence_value_json(call))
    is Object(fields) else {
    abort("invalid checked call")
  }
  let root : Json = Json::string("sha256:" + "a".repeat(64))
  slot_binding_seal(
    Json::object({
      "version": Json::string("actql-model-slot-capture/0.1"),
      "slot_cid": fields["model_call_slot_cid"],
      "model_task_cid": fields["model_task_cid"],
      "fixed_request_cid": fields["fixed_request_cid"],
      "input_artifact_cid": fields["input_artifact_cid"],
      "input_key_cid": fields["input_key_cid"],
      "ordered_attempt_cids": Json::array([root]),
      "adopted_attempt_cid": root,
      "outcome": Json::string(
        @model.verified_model_capture_outcome(saved, index).unwrap(),
      ),
      "typed_value_artifact_cid": Json::null(),
      "accounting_evidence_cid": root,
      "authority_evidence_cid": root,
      "policy_cid": root,
      "outcome_evidence_cid": root,
      "response_artifact_cid": Json::null(),
      "response_issuer_evidence_cid": Json::null(),
      "attachment_admission_cids": Json::array([]),
    }),
  )
}

///|
fn slot_observation(
  identities : Array[String]?,
) -> @publication.RunEvidenceValue raise {
  slot_observation_admit(identities).unwrap()
}

///|
fn slot_observation_admit(
  identities : Array[String]?,
) -> Result[@publication.RunEvidenceValue, @publication.RunEvidenceValueIssue] raise {
  let root : Json = Json::string("sha256:" + "a".repeat(64))
  let fields : Map[String, Json] = {
    "version": Json::string("actql-observation-set/0.1"),
    "invocation_template_cid": root,
    "captured_input_artifact_cids": Json::array([]),
    "source_evidence_cids": Json::array([]),
    "data_policy_cid": root,
    "consistency": Json::string("no_external_sources"),
    "capture_started_at": Json::null(),
    "capture_completed_at": Json::null(),
    "replayability": Json::object({
      "materialized": Json::boolean(false),
      "availability_evidence_cids": Json::array([]),
    }),
  }
  if identities is Some(values) {
    fields["model_slot_capture_cids"] = Json::array(values.map(Json::string))
  }
  @publication.seal_run_evidence_value(
    "observation_set",
    fixture_canonical(Json::object(fields)),
    16384,
    1024,
    20,
  )
}

///|
fn observation_verification_limits() -> @model.ModelObservationVerificationLimits {
  { max_slots: 2, max_slot_wire_units: 16384, max_work: 3, }
}

///|
test "bounded observation matching derives all slots from the actual execution" {
  let calls = Ref(0)
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  let original = failed_outcome_start(@model.Timeout, calls, rows~, mixed=true)
  assert_true(fixture_finish(original) is Complete(_, ..))
  let saved = acquire_capture(original).unwrap()
  let failure = observation_failure_record(saved, 0)
  let success = slot_binding_seal(
    slot_binding_record(invocation_evidence(original, 1).unwrap()),
  )
  let records = [failure, success]
  let identities = records.map(@publication.run_evidence_value_identity)
  let observation = slot_observation(Some(identities))
  assert_true(
    @model.start_model_observation_verification(saved, observation, records, {
      ..observation_verification_limits(),
      max_slots: 1,
    })
    is Err(@model.ItemLimit),
  )
  // The successful-response subset has one record; the checked execution has
  // two calls. Neither a matching subset nor its count can erase the failure.
  assert_eq(capture(original).unwrap().captures.length(), 1)
  assert_true(
    @model.start_model_observation_verification(
      saved,
      slot_observation(Some([identities[1]])),
      [success],
      observation_verification_limits(),
    )
    is Err(
      @model.InvocationEvidence(
        @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids")
      )
    ),
  )
  for work in [3, 2] {
    let active = @model.start_model_observation_verification(
      saved,
      observation,
      records,
      { ..observation_verification_limits(), max_work: work, },
    ).unwrap()
    assert_true(@model.model_observation_verification_value(active) is None)
    // Exactly one transition per slot, plus terminal acceptance. This bound
    // is independent of successful execution's observed work counter.
    for expected in 1..<3 {
      let (done, spent) = @model.advance_model_observation_verification(
        active, 1,
      ).unwrap()
      assert_true(!done)
      assert_eq(spent, expected.to_int64())
      assert_true(@model.model_observation_verification_value(active) is None)
    }
    if work == 3 {
      assert_eq(
        @model.advance_model_observation_verification(active, 1).unwrap(),
        (true, 3L),
      )
      assert_eq(
        @publication.run_evidence_value_identity(
          @model.model_observation_verification_value(active).unwrap(),
        ),
        @publication.run_evidence_value_identity(observation),
      )
    } else {
      assert_true(
        @model.advance_model_observation_verification(active, 1)
        is Err(@model.WorkLimit),
      )
      assert_true(@model.model_observation_verification_value(active) is None)
    }
    assert_true(!cleanup(original).unwrap())
    assert_true(@model.cleanup_model_observation_verification(active).unwrap())
    assert_eq(records.length(), 2)
  }
  for changed in [[identities[1], identities[0]]] {
    let active = @model.start_model_observation_verification(
      saved,
      slot_observation(Some(changed)),
      records,
      observation_verification_limits(),
    ).unwrap()
    let first = @model.advance_model_observation_verification(active, 1)
    let failure = if first is Err(_) {
      first
    } else {
      @model.advance_model_observation_verification(active, 1)
    }
    assert_true(
      failure
      is Err(
        @model.InvocationEvidence(
          @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids")
        )
      ),
    )
    assert_true(@model.model_observation_verification_value(active) is None)
    assert_true(@model.cleanup_model_observation_verification(active).unwrap())
  }
  let reversed = @model.start_model_observation_verification(
    saved,
    observation,
    [success, failure],
    observation_verification_limits(),
  ).unwrap()
  assert_true(
    @model.advance_model_observation_verification(reversed, 1)
    is Err(
      @model.InvocationEvidence(
        @publication.RunEvidenceReferenceMismatch("model_slot_capture.slot_cid")
      )
    ),
  )
  assert_true(@model.cleanup_model_observation_verification(reversed).unwrap())
  let oversized = @model.start_model_observation_verification(
    saved,
    observation,
    records,
    { ..observation_verification_limits(), max_slot_wire_units: 1, },
  ).unwrap()
  assert_true(
    @model.advance_model_observation_verification(oversized, 1)
    is Err(@model.RequestLimit),
  )
  assert_true(@model.cleanup_model_observation_verification(oversized).unwrap())
  // The closed schema rejects duplicate CIDs before owner verification.
  assert_true(
    slot_observation_admit(Some([identities[0], identities[0]]))
    is Err(@publication.RunEvidenceInvalidShape),
  )
  for
    changed in [
      None,
      Some([]),
      Some([identities[0]]),
      Some([..identities, "sha256:" + "0".repeat(64)]),
    ] {
    assert_true(
      @model.start_model_observation_verification(
        saved,
        slot_observation(changed),
        records,
        observation_verification_limits(),
      )
      is Err(_),
    )
  }
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "changing a pending record source cannot certify an incomplete inventory" {
  let calls = Ref(0)
  let rows = "[{\"id\":\"a\",\"text\":\"first\"},{\"id\":\"b\",\"text\":\"second\"}]"
  let original = failed_outcome_start(@model.Timeout, calls, rows~)
  assert_true(fixture_finish(original) is Complete(_, ..))
  let saved = acquire_capture(original).unwrap()
  let records = [
    observation_failure_record(saved, 0),
    observation_failure_record(saved, 1),
  ]
  let observation = slot_observation(
    Some(records.map(@publication.run_evidence_value_identity)),
  )
  let active = @model.start_model_observation_verification(
    saved,
    observation,
    records,
    observation_verification_limits(),
  ).unwrap()
  assert_eq(
    @model.advance_model_observation_verification(active, 1).unwrap(),
    (false, 1L),
  )
  records.clear()
  assert_true(
    @model.advance_model_observation_verification(active, 1)
    is Err(@model.OutputIdentity),
  )
  assert_true(@model.model_observation_verification_value(active) is None)
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(!cleanup(original).unwrap())
  assert_true(@model.cleanup_model_observation_verification(active).unwrap())
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "observation verification cancellation retains custody until cleanup" {
  let calls = Ref(0)
  let rows = "[{\"id\":\"a\",\"text\":\"first\"},{\"id\":\"b\",\"text\":\"second\"}]"
  let original = failed_outcome_start(@model.Timeout, calls, rows~)
  assert_true(fixture_finish(original) is Complete(_, ..))
  let saved = acquire_capture(original).unwrap()
  let records = [
    observation_failure_record(saved, 0),
    observation_failure_record(saved, 1),
  ]
  let observation = slot_observation(
    Some(records.map(@publication.run_evidence_value_identity)),
  )
  let active = @model.start_model_observation_verification(
    saved,
    observation,
    records,
    observation_verification_limits(),
  ).unwrap()
  assert_true(@model.release_verified_model_capture(saved))
  assert_eq(
    @model.advance_model_observation_verification(active, 1).unwrap(),
    (false, 1L),
  )
  assert_true(@model.cancel_model_observation_verification(active))
  assert_true(!@model.cleanup_model_observation_verification(active).unwrap())
  assert_true(!cleanup(original).unwrap())
  assert_true(
    @model.advance_model_observation_verification(active, 1)
    is Err(@model.Cancelled),
  )
  assert_true(@model.model_observation_verification_value(active) is None)
  assert_true(!cleanup(original).unwrap())
  assert_true(@model.cleanup_model_observation_verification(active).unwrap())
  assert_true(@model.cleanup_model_observation_verification(active).unwrap())
  assert_eq(records.length(), 2)
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "zero-key observation requires an explicit empty slot array" {
  let calls = Ref(0)
  let original = failed_outcome_start(@model.Timeout, calls, rows="[]")
  assert_true(fixture_finish(original) is Complete(_, ..))
  let saved = acquire_capture(original).unwrap()
  assert_eq(@model.verified_model_capture_call_count(saved), Some(0))
  assert_true(
    @model.start_model_observation_verification(
      saved,
      slot_observation(None),
      [],
      observation_verification_limits(),
    )
    is Err(_),
  )
  let observation = slot_observation(Some([]))
  let active = @model.start_model_observation_verification(
    saved,
    observation,
    [],
    observation_verification_limits(),
  ).unwrap()
  assert_eq(
    @model.advance_model_observation_verification(active, 1).unwrap(),
    (true, 1L),
  )
  assert_true(@model.model_observation_verification_value(active) is Some(_))
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(!cleanup(original).unwrap())
  assert_true(@model.cleanup_model_observation_verification(active).unwrap())
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 0)
}
