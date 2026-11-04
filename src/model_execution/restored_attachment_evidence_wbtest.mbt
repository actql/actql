///|
fn restored_attachment_test_pin(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn restored_attachment_test_seal(
  name : String,
  value : Json,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, value.stringify(), 16384, 1024, 8).unwrap()
}

///|
fn restored_attachment_test_record(
  authority : @publication.RunEvidenceValue,
  slot : String,
) -> @publication.RunEvidenceValue {
  let pin = restored_attachment_test_pin
  let body : Json = {
    "version": "actql-model-attachment-admission/0.1",
    "slot_cid": slot,
    "model_task_cid": pin("5"),
    "fixed_request_cid": pin("6"),
    "authority_evidence_cid": @publication.run_evidence_value_identity(
      authority,
    ),
    "attachments": [
      {
        "role": "document",
        "item": -1,
        "content_ref_cid": pin("a"),
        "content_cid": pin("b"),
        "media_input_cid": pin("c"),
        "policy_cid": pin("d"),
        "media_type": "application/pdf",
        "size_bytes": 3,
        "classification": "internal",
        "region": "fixture-region",
        "egress_scope_cid": pin("e"),
        "pages": 1,
        "frames": null,
        "complete": true,
        "transfer_method": "inline_bytes",
      },
    ],
  }
  restored_attachment_test_seal("model_attachment_admission", body)
}

///|
fn restored_attachment_test_originals(
  principal? : String = "fixture-principal",
) -> (
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) {
  let pin = restored_attachment_test_pin
  let authority = restored_attachment_test_seal("model_dispatch_authority", {
    "version": "actql-model-dispatch-authority/0.1",
    "program_definition_cid": pin("1"),
    "run_definition_cid": pin("2"),
    "run_authorization_cid": pin("3"),
    "account_configuration_cid": pin("4"),
    "model_task_cid": pin("5"),
    "fixed_request_cid": pin("6"),
    "execution_context_cid": pin("7"),
    "host_policy_cid": pin("8"),
    "principal": principal,
    "connection": "models/fixture",
    "resource": pin("5"),
    "operation": "infer",
    "entry_id": "model-policy",
    "basis": "account_allow",
    "answering_authority": null,
    "satisfied_claims": [],
  })
  let make_capture = (references : Array[String]) => {
    restored_attachment_test_seal("model_slot_capture", {
      "version": "actql-model-slot-capture/0.1",
      "slot_cid": pin("9"),
      "model_task_cid": pin("5"),
      "fixed_request_cid": pin("6"),
      "input_artifact_cid": pin("4"),
      "input_key_cid": pin("7"),
      "outcome": "ok",
      "accounting_evidence_cid": pin("b"),
      "authority_evidence_cid": @publication.run_evidence_value_identity(
        authority,
      ),
      "policy_cid": pin("d"),
      "outcome_evidence_cid": pin("e"),
      "adopted_attempt_cid": pin("a"),
      "ordered_attempt_cids": [pin("a")],
      "typed_value_artifact_cid": pin("b"),
      "response_artifact_cid": pin("f"),
      "response_issuer_evidence_cid": pin("e"),
      "attachment_admission_cids": references,
    })
  }
  let record = restored_attachment_test_record(authority, pin("9"))
  let capture = make_capture([@publication.run_evidence_value_identity(record)])
  (authority, record, capture, make_capture([]))
}

///|
test "restored Model attachment inventory preserves empty and original nonempty evidence" {
  let (authority, record, capture, empty) = restored_attachment_test_originals()
  assert_true(
    restore_model_attachment_admission(empty, authority, None) is Ok(None),
  )
  let restored = restore_model_attachment_admission(
      capture,
      authority,
      Some(record),
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(restored, record))
  assert_true(
    restore_model_attachment_admission(capture, authority, None)
    is Err(InvocationEvidence(_)),
  )
  assert_true(
    restore_model_attachment_admission(empty, authority, Some(record))
    is Err(InvocationEvidence(_)),
  )
  // Schema-valid evidence for another call or authority cannot replace the
  // immutable inventory whose exact references the saved capture names.
  let (foreign_authority, _, _, _) = restored_attachment_test_originals(
    principal="another-principal",
  )
  let foreign_record = restored_attachment_test_record(
    authority,
    restored_attachment_test_pin("0"),
  )
  assert_true(
    restore_model_attachment_admission(capture, foreign_authority, Some(record))
    is Err(InvocationEvidence(_)),
  )
  assert_true(
    restore_model_attachment_admission(capture, authority, Some(foreign_record))
    is Err(InvocationEvidence(_)),
  )
  assert_true(
    restore_model_attachment_admission(capture, record, Some(record))
    is Err(InvocationEvidence(_)),
  )
  assert_true(
    restore_model_attachment_admission(capture, authority, Some(authority))
    is Err(InvocationEvidence(_)),
  )
}

///|
test "restored Model attachment aliases survive stop and pending cleanup then retire with their same owner" {
  // Synthetic startup/trace construction isolates existing same-owner lifetime;
  // the public replay separately exercises Store, attempt and scope admission.
  let (authority, _record, _capture, _empty) = restored_attachment_test_originals()
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  let pin = restored_attachment_test_pin
  let call = restored_attachment_test_seal("model_call_slot", {
    "version": "actql-model-call-slot/0.1",
    "program_definition_cid": pin("1"),
    "unit_definition_cid": pin("2"),
    "source_ordinal": 0,
    "effective_inputs_cid": pin("3"),
    "input_artifact_cid": pin("4"),
    "input_key_cid": pin("7"),
    "model_task_cid": pin("5"),
    "fixed_request_cid": pin("6"),
  })
  let admission = restored_attachment_test_record(
    authority,
    @publication.run_evidence_value_identity(call),
  )
  let capture = restored_attachment_test_seal("model_slot_capture", {
    "version": "actql-model-slot-capture/0.1",
    "slot_cid": @publication.run_evidence_value_identity(call),
    "model_task_cid": pin("5"),
    "fixed_request_cid": pin("6"),
    "input_artifact_cid": pin("4"),
    "input_key_cid": pin("7"),
    "outcome": "failed:timeout",
    "accounting_evidence_cid": pin("b"),
    "authority_evidence_cid": @publication.run_evidence_value_identity(
      authority,
    ),
    "policy_cid": pin("d"),
    "outcome_evidence_cid": pin("e"),
    "adopted_attempt_cid": pin("a"),
    "ordered_attempt_cids": [pin("a")],
    "typed_value_artifact_cid": null,
    "response_artifact_cid": null,
    "response_issuer_evidence_cid": null,
    "attachment_admission_cids": [
      @publication.run_evidence_value_identity(admission),
    ],
  })
  let binding = @publication.bind_model_slot_capture(call, capture).unwrap()
  let proof : ModelAttemptEvidence = {
    attempt: authority,
    accounting: authority,
    outcome: authority,
    authority,
  }
  active.state.restored_calls[0] = {
    record: capture,
    binding,
    proof,
    bundle: None,
    attachment_admission: Some(admission),
    outcome: "failed:timeout",
  }
  assert_true(
    model_execution_issued_attachment_admission(active, 0)
    is Err(OutputIdentity),
  )
  active.state.attempts[0] = {
    attempt: proof.attempt,
    call,
    authority,
    reservation: None,
    input_tokens: None,
    output_tokens: None,
    category: "provider_failure",
    failure: None,
    work: 0,
    response_cid: None,
    output_cid: None,
    response_issuer: None,
    evidence: Some(proof),
  }
  let observed = model_execution_issued_attachment_admission(active, 0)
    .unwrap()
    .unwrap()
  assert_true(physical_equal(observed, admission))
  let trace = active.state.attempts[0]
  trace.evidence = Some({ ..proof, })
  assert_true(
    model_execution_issued_attachment_admission(active, 0)
    is Err(OutputIdentity),
  )
  trace.evidence = Some(proof)
  let stopped = Ref(false)
  active.state.physical_cursors.push({
    advance: () => Err(InvalidProvider),
    cleanup: () => stopped.val,
  })
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(
    physical_equal(
      model_execution_issued_attachment_admission(active, 0).unwrap().unwrap(),
      admission,
    ),
  )
  assert_eq(active.state.restored_calls.length(), 1)
  stopped.val = true
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(active.state.restored_calls.length(), 0)
  assert_true(
    model_execution_issued_attachment_admission(active, 0)
    is Err(OutputIdentity),
  )
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  // The actual immutable original remains readable after this owner's aliases end.
  assert_eq(
    @publication.run_evidence_value_name(observed),
    "model_attachment_admission",
  )
}
