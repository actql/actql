///|
/// Integrity of original, Store-authenticated attempt leaves. This is neither
/// a new dispatch grant nor permission to retry a lost response.
pub struct BoundModelAttemptEvidence {
  slot : BoundModelSlotCapture
  attempt : RunEvidenceValue
  accounting : RunEvidenceValue
  outcome : RunEvidenceValue
  authority : RunEvidenceValue
}

///|
pub fn bind_model_slot_attempt_evidence(
  slot : BoundModelSlotCapture,
  attempt : RunEvidenceValue,
  accounting : RunEvidenceValue,
  outcome : RunEvidenceValue,
  authority : RunEvidenceValue,
  admission : RunPublicationAdmission,
  definition : PublicationContract,
) -> Result[BoundModelAttemptEvidence, RunEvidenceValueIssue] {
  if attempt.name != "model_call_attempt" ||
    accounting.name != "model_attempt_accounting" ||
    outcome.name != "model_attempt_outcome" ||
    authority.name != "model_dispatch_authority" ||
    definition.name != "run_definition" {
    return Err(UnknownRunEvidence)
  }
  let mismatch = RunEvidenceReferenceMismatch("model_attempt_evidence")
  let call = slot.call
  let capture = slot.capture
  // The current physical owner emits one attempt. A future retry owner must
  // verify its complete ordered attempt list, not silently drop old costs.
  guard @json.object_field(capture.value, "ordered_attempt_cids")
    is Some(@json.Array(attempts)) &&
    @json.array_count(attempts) == 1 &&
    @json.array_at(attempts, 0) is Some(@json.String(first_attempt)) &&
    first_attempt == attempt.identity else {
    return Err(mismatch)
  }
  for
    (body, field, expected) in [
      (capture, "adopted_attempt_cid", attempt.identity),
      (capture, "accounting_evidence_cid", accounting.identity),
      (capture, "outcome_evidence_cid", outcome.identity),
      (capture, "authority_evidence_cid", authority.identity),
      (attempt, "authority_evidence_cid", authority.identity),
      (attempt, "slot_cid", call.identity),
      (accounting, "slot_cid", call.identity),
      (outcome, "slot_cid", call.identity),
      (accounting, "attempt_cid", attempt.identity),
      (outcome, "attempt_cid", attempt.identity),
      (attempt, "run_definition_cid", definition.identity),
      (authority, "run_definition_cid", definition.identity),
      (authority, "run_authorization_cid", admission.authorization.identity),
      (authority, "execution_context_cid", admission.authorization_context_cid),
    ] {
    if contract_string_from_value(body.value, field) != Some(expected) {
      return Err(mismatch)
    }
  }
  for
    (body, field, source, source_field) in [
      (attempt, "model_task_cid", call, "model_task_cid"),
      (attempt, "fixed_request_cid", call, "fixed_request_cid"),
      (authority, "model_task_cid", call, "model_task_cid"),
      (authority, "resource", call, "model_task_cid"),
      (authority, "fixed_request_cid", call, "fixed_request_cid"),
      (authority, "program_definition_cid", call, "program_definition_cid"),
      (
        authority,
        "program_definition_cid",
        admission.template,
        "program_definition_cid",
      ),
      (authority, "host_policy_cid", admission.prepared, "host_policy_cid"),
      (attempt, "provider_id", authority, "connection"),
    ] {
    if contract_string_from_value(body.value, field) !=
      contract_string_from_value(source.value, source_field) {
      return Err(mismatch)
    }
  }
  if check_run_publication_program_binding(
      admission,
      definition,
      contract_string_from_value(call.value, "program_definition_cid").unwrap(),
      contract_string(admission.compiled_plan, "program_semantics_cid").unwrap(),
      contract_string_from_value(
        admission.template.value,
        "check_environment_cid",
      ).unwrap(),
    )
    is Err(_) {
    return Err(mismatch)
  }
  let category = contract_string_from_value(outcome.value, "category")
  let failure = contract_string_from_value(outcome.value, "failure")
  let adopted = contract_string_from_value(capture.value, "outcome").unwrap()
  if adopted == "ok" {
    if category != Some("ok") || failure is Some(_) {
      return Err(mismatch)
    }
  } else if category != Some("provider_failure") ||
    failure.map(value => "failed:" + value) != Some(adopted) {
    return Err(mismatch)
  }
  let basis = contract_string_from_value(authority.value, "basis")
  let answering = contract_string_from_value(
    authority.value,
    "answering_authority",
  )
  if (basis == Some("host_permit")) != (answering is Some(_)) {
    return Err(mismatch)
  }
  guard @json.object_field(authority.value, "satisfied_claims")
    is Some(@json.Array(claims)) else {
    return Err(mismatch)
  }
  if basis == Some("account_allow") && @json.array_count(claims) != 0 {
    return Err(mismatch)
  }
  Ok({ slot, attempt, accounting, outcome, authority, })
}

///|
/// Check the reported outcome against its original Store-authenticated Raw
/// descriptor. This verifies saved references without opening a send path.
pub fn verify_model_attempt_reported_raw(
  evidence : BoundModelAttemptEvidence,
  scope : BoundModelInvocationScope,
  raw : RunEvidenceValue?,
) -> Result[Unit, RunEvidenceValueIssue] {
  guard @json.object_field(evidence.outcome.value, "reported_response")
    is Some(report) else {
    return Ok(())
  }
  let mismatch = RunEvidenceReferenceMismatch("model_attempt_reported_raw")
  guard raw is Some(raw) &&
    raw.name == "model_raw_response" &&
    @json.object_field(raw.value, "transport_eof") is Some(@json.Bool(true)) &&
    @json.object_field(raw.value, "http_status") is Some(@json.Number(status)) &&
    status >= 200 &&
    status < 300 else {
    return Err(mismatch)
  }
  for
    (field, expected) in [
      ("run_definition_cid", scope.definition.identity),
      ("scope_cid", scope.scope.identity),
      ("slot_cid", evidence.slot.call.identity),
      ("attempt_cid", evidence.attempt.identity),
    ] {
    if contract_string_from_value(raw.value, field) != Some(expected) {
      return Err(mismatch)
    }
  }
  if contract_string_from_value(report, "raw_response_artifact_cid") !=
    Some(raw.identity) ||
    contract_string_from_value(report, "response_profile_cid") !=
    contract_string_from_value(raw.value, "response_profile_cid") ||
    contract_string_from_value(report, "observed_at") !=
    contract_string_from_value(raw.value, "observed_at") {
    return Err(mismatch)
  }
  Ok(())
}
