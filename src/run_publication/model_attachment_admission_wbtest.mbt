///|
fn attachment_test_pin(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn attachment_test_seal(name : String, value : Json) -> RunEvidenceValue {
  seal_run_evidence_value(name, value.stringify(), 16384, 1024, 8).unwrap()
}

///|
test "saved Model attachment inventory binds exact capture call and authority" {
  let pin = attachment_test_pin
  let authority = attachment_test_seal("model_dispatch_authority", {
    "version": "actql-model-dispatch-authority/0.1",
    "program_definition_cid": pin("1"),
    "run_definition_cid": pin("2"),
    "run_authorization_cid": pin("3"),
    "account_configuration_cid": pin("4"),
    "model_task_cid": pin("5"),
    "fixed_request_cid": pin("6"),
    "execution_context_cid": pin("7"),
    "host_policy_cid": pin("8"),
    "principal": "fixture-principal",
    "connection": "models/fixture",
    "resource": pin("5"),
    "operation": "infer",
    "entry_id": "model-policy",
    "basis": "account_allow",
    "answering_authority": null,
    "satisfied_claims": [],
  })
  let make_record = (field : String, value : String) => {
    let body : Json = {
      "version": "actql-model-attachment-admission/0.1",
      "slot_cid": pin("9"),
      "model_task_cid": pin("5"),
      "fixed_request_cid": pin("6"),
      "authority_evidence_cid": authority.identity,
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
    guard body is Json::Object(fields) else { abort("fixture") }
    fields[field] = value.to_json()
    attachment_test_seal("model_attachment_admission", body)
  }
  let make_capture = (references : Array[String]) => {
    attachment_test_seal("model_slot_capture", {
      "version": "actql-model-slot-capture/0.1",
      "slot_cid": pin("9"),
      "model_task_cid": pin("5"),
      "fixed_request_cid": pin("6"),
      "input_artifact_cid": pin("4"),
      "input_key_cid": pin("7"),
      "outcome": "ok",
      "accounting_evidence_cid": pin("b"),
      "authority_evidence_cid": authority.identity,
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
  let record = make_record("slot_cid", pin("9"))
  let capture = make_capture([record.identity])
  assert_true(
    verify_model_slot_attachment_admission(capture, authority, Some(record))
    is Ok(_),
  )
  assert_true(
    verify_model_slot_attachment_admission(capture, authority, None) is Err(_),
  )
  assert_true(
    verify_model_slot_attachment_admission(make_capture([]), authority, None)
    is Ok(_),
  )
  assert_true(
    verify_model_slot_attachment_admission(
      make_capture([]),
      authority,
      Some(record),
    )
    is Err(_),
  )
  // Even a valid new CID referenced by a valid capture cannot substitute a
  // different call or authority. These are not invalid-schema-only refusals.
  for
    field in [
      "slot_cid", "model_task_cid", "fixed_request_cid", "authority_evidence_cid",
    ] {
    let foreign = make_record(field, pin("0"))
    match
      verify_model_slot_attachment_admission(
        make_capture([foreign.identity]),
        authority,
        Some(foreign),
      ) {
      Err(RunEvidenceReferenceMismatch(actual)) => assert_eq(actual, field)
      _ => abort("foreign attachment binding must be rejected")
    }
  }
}
