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
  let original = match
    bind_model_slot_attempt_originals(
      slot, attempt, accounting, outcome, authority, definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let program = contract_string_from_value(
    slot.call.value,
    "program_definition_cid",
  ).unwrap()
  guard contract_string_from_value(authority.value, "run_authorization_cid") ==
    Some(admission.authorization.identity) &&
    contract_string_from_value(authority.value, "execution_context_cid") ==
    Some(admission.authorization_context_cid) &&
    contract_string_from_value(authority.value, "host_policy_cid") ==
    contract_string_from_value(admission.prepared.value, "host_policy_cid") &&
    check_run_publication_program_binding(
      admission,
      definition,
      program,
      contract_string(admission.compiled_plan, "program_semantics_cid").unwrap(),
      contract_string_from_value(
        admission.template.value,
        "check_environment_cid",
      ).unwrap(),
    )
    is Ok(_) else {
    return Err(RunEvidenceReferenceMismatch("model_attempt_evidence"))
  }
  Ok(original)
}

///|
fn bind_model_slot_attempt_originals(
  slot : BoundModelSlotCapture,
  attempt : RunEvidenceValue,
  accounting : RunEvidenceValue,
  outcome : RunEvidenceValue,
  authority : RunEvidenceValue,
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
  guard contract_string_from_value(authority.value, "execution_context_cid") ==
    contract_string(definition, "authorization_context_cid") else {
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
      (attempt, "provider_id", authority, "connection"),
    ] {
    if contract_string_from_value(body.value, field) !=
      contract_string_from_value(source.value, source_field) {
      return Err(mismatch)
    }
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
  verify_model_attempt_reported_raw_original(
    evidence,
    scope.definition,
    scope.scope.identity,
    raw,
  )
}

///|
fn verify_model_attempt_reported_raw_original(
  evidence : BoundModelAttemptEvidence,
  definition : PublicationContract,
  scope_cid : String,
  raw : RunEvidenceValue?,
) -> Result[Unit, RunEvidenceValueIssue] {
  guard @json.object_field(evidence.outcome.value, "reported_response")
    is Some(report) else {
    return Ok(())
  }
  let mismatch = RunEvidenceReferenceMismatch("model_attempt_reported_raw")
  guard raw is Some(raw) &&
    model_attempt_raw_matches_scope(evidence, definition, scope_cid, raw) &&
    @json.object_field(raw.value, "transport_eof") is Some(@json.Bool(true)) &&
    @json.object_field(raw.value, "http_status") is Some(@json.Number(status)) &&
    status >= 200 &&
    status < 300 else {
    return Err(mismatch)
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

///|
/// Match the same successful adopted observation to its exact complete Raw
/// descriptor. The scoped Store still owns the original response bytes.
pub fn verify_model_attempt_success_raw(
  evidence : BoundModelAttemptEvidence,
  scope : BoundModelInvocationScope,
  observation : RunEvidenceValue,
  raw : BoundModelRawResponse,
) -> Result[Unit, RunEvidenceValueIssue] {
  verify_model_attempt_success_raw_original(
    evidence,
    scope.definition,
    scope.scope.identity,
    observation,
    model_raw_response_value(raw),
  )
}

///|
/// Verify the retained metadata of an original successful producer under
/// the caller's authenticated same-Store read. No invocation or policy is
/// recreated from the retained reference.
pub fn verify_retained_model_http_success(
  definition : PublicationContract,
  scope_cid : String,
  store_authority_cid : String,
  slot : BoundModelSlotCapture,
  attempt : RunEvidenceValue,
  accounting : RunEvidenceValue,
  outcome : RunEvidenceValue,
  authority : RunEvidenceValue,
  observation : RunEvidenceValue,
  raw : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  guard valid_contract_cid(store_authority_cid) &&
    contract_string_from_value(raw.value, "store_authority_cid") ==
    Some(store_authority_cid) else {
    return Err(RunEvidenceReferenceMismatch("model_success_raw"))
  }
  check_retained_model_call_entry_scope(
    definition,
    scope_cid,
    slot.call,
    attempt,
    authority,
  )
  .bind(_ => {
    bind_model_slot_attempt_originals(
      slot, attempt, accounting, outcome, authority, definition,
    )
  })
  .bind(evidence => {
    verify_model_attempt_success_raw_original(
      evidence, definition, scope_cid, observation, raw,
    )
  })
}

///|
fn verify_model_attempt_success_raw_original(
  evidence : BoundModelAttemptEvidence,
  definition : PublicationContract,
  scope_cid : String,
  observation : RunEvidenceValue,
  raw : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  verify_model_slot_success_observation(evidence.slot, observation).bind(_ => {
    guard model_attempt_raw_matches_scope(evidence, definition, scope_cid, raw) &&
      @json.object_field(raw.value, "transport_eof") is Some(@json.Bool(true)) &&
      @json.object_field(raw.value, "http_status") is Some(@json.Number(status)) &&
      status >= 200 &&
      status < 300 &&
      @json.object_field(observation.value, "response_complete")
      is Some(@json.Bool(true)) &&
      contract_string_from_value(observation.value, "raw_response_artifact_cid") ==
      Some(raw.identity) &&
      contract_string_from_value(observation.value, "response_profile_cid") ==
      contract_string_from_value(raw.value, "response_profile_cid") &&
      contract_string_from_value(observation.value, "observed_at") ==
      contract_string_from_value(raw.value, "observed_at") else {
      return Err(RunEvidenceReferenceMismatch("model_success_raw"))
    }
    Ok(())
  })
}

///|
fn model_attempt_raw_matches_scope(
  evidence : BoundModelAttemptEvidence,
  definition : PublicationContract,
  scope_cid : String,
  raw : RunEvidenceValue,
) -> Bool {
  if raw.name != "model_raw_response" {
    return false
  }
  for
    (field, expected) in [
      ("run_definition_cid", definition.identity),
      ("scope_cid", scope_cid),
      ("slot_cid", evidence.slot.call.identity),
      ("attempt_cid", evidence.attempt.identity),
    ] {
    if contract_string_from_value(raw.value, field) != Some(expected) {
      return false
    }
  }
  true
}

///|
/// Bound DATA for an unpublished HTTP Model failure. The original Host must
/// supply its authenticated Store originals and exact Attempt locator. This
/// evidence cannot establish physical stop, current permission, or settlement.
pub struct BoundModelHttpFailure {
  run_definition_cid : String
  attempt_cid : String
  raw_cid : String
  diagnostic : (String, String)
}

///|
/// Exact attempt and Raw identities selected by the original binding.
pub fn model_http_failure_evidence_identity(
  value : BoundModelHttpFailure,
) -> (String, String) {
  (value.attempt_cid, value.raw_cid)
}

///|
/// The same typed diagnostic emitted into this original RunState.
pub fn model_http_failure_diagnostic(
  value : BoundModelHttpFailure,
) -> (String, String) {
  value.diagnostic
}

///|
/// Bind the original live, policy-selected Slot, Attempt and complete Raw.
pub fn bind_model_http_failure(
  evidence : BoundModelAttemptEvidence,
  scope : BoundModelInvocationScope,
  slot : Int,
  expected_attempt_cid : String,
  expected_raw_cid : String,
  bound_raw : BoundModelRawResponse,
) -> Result[BoundModelHttpFailure, RunEvidenceValueIssue] {
  match
    check_model_invocation_attempt(
      scope,
      slot,
      evidence.attempt,
      evidence.authority,
      1L,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  bind_model_http_failure_original(
    evidence,
    scope.definition,
    scope.scope.identity,
    (expected_attempt_cid, expected_raw_cid),
    model_raw_response_value(bound_raw),
  )
}

///|
/// Link the original saved Entry to the selected durable Model scope before
/// opening any settlement cell. This verifies metadata only.
pub fn check_retained_model_call_entry_scope(
  definition : PublicationContract,
  scope_cid : String,
  call : RunEvidenceValue,
  attempt : RunEvidenceValue,
  authority : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  let mismatch = RunEvidenceReferenceMismatch("model_retained_entry")
  guard definition.name == "run_definition" &&
    valid_contract_cid(scope_cid) &&
    call.name == "model_call_slot" &&
    attempt.name == "model_call_attempt" &&
    authority.name == "model_dispatch_authority" &&
    contract_string_from_value(authority.value, "operation") == Some("infer") &&
    contract_string_from_value(authority.value, "execution_context_cid") ==
    contract_string(definition, "authorization_context_cid") &&
    model_scope_count(attempt.value, "attempt") == Some(1L) else {
    return Err(mismatch)
  }
  for
    (body, field, expected) in [
      (attempt, "run_definition_cid", definition.identity),
      (attempt, "slot_cid", call.identity),
      (attempt, "authority_evidence_cid", authority.identity),
      (authority, "run_definition_cid", definition.identity),
      (authority, "model_invocation_scope_cid", scope_cid),
    ] {
    if contract_string_from_value(body.value, field) != Some(expected) {
      return Err(mismatch)
    }
  }
  check_model_attempt_authority_basis(authority)
}

///|
/// Restore DATA from the Store-authenticated original Entry and settlement.
/// The caller selects the exact authorized Run, scoped Slot and immutable
/// cells before supplying these leaves. Restoration grants no dispatch right.
pub fn bind_retained_model_http_failure(
  definition : PublicationContract,
  scope_cid : String,
  store_authority_cid : String,
  locator : (String, String),
  slot : BoundModelSlotCapture,
  attempt : RunEvidenceValue,
  accounting : RunEvidenceValue,
  outcome : RunEvidenceValue,
  authority : RunEvidenceValue,
  raw : RunEvidenceValue,
) -> Result[BoundModelHttpFailure, RunEvidenceValueIssue] {
  let mismatch = RunEvidenceReferenceMismatch("model_http_failure")
  guard valid_contract_cid(store_authority_cid) &&
    contract_string_from_value(raw.value, "store_authority_cid") ==
    Some(store_authority_cid) else {
    return Err(mismatch)
  }
  match
    check_retained_model_call_entry_scope(
      definition,
      scope_cid,
      slot.call,
      attempt,
      authority,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let evidence = match
    bind_model_slot_attempt_originals(
      slot, attempt, accounting, outcome, authority, definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_model_http_failure_original(
    evidence, definition, scope_cid, locator, raw,
  )
}

///|
fn bind_model_http_failure_original(
  evidence : BoundModelAttemptEvidence,
  definition : PublicationContract,
  scope_cid : String,
  locator : (String, String),
  raw : RunEvidenceValue,
) -> Result[BoundModelHttpFailure, RunEvidenceValueIssue] {
  let mismatch = RunEvidenceReferenceMismatch("model_http_failure")
  let (expected_attempt_cid, expected_raw_cid) = locator
  guard evidence.attempt.identity == expected_attempt_cid &&
    raw.identity == expected_raw_cid &&
    model_attempt_raw_matches_scope(evidence, definition, scope_cid, raw) &&
    @json.object_field(raw.value, "transport_eof") is Some(@json.Bool(true)) &&
    @json.object_field(raw.value, "http_status") is Some(@json.Number(status)) &&
    contract_string_from_value(evidence.outcome.value, "failure")
    is Some(failure) else {
    return Err(mismatch)
  }
  match
    verify_model_slot_no_response_failure(evidence.slot, "failed:" + failure) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    verify_model_attempt_reported_raw_original(
      evidence,
      definition,
      scope_cid,
      Some(raw),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let success_status = status >= 200 && status < 300
  let diagnostic = match failure {
    "rate_limit" if status == 429 =>
      (
        "ACTQL_E_MODEL_RATE_LIMIT", "The Model provider rate-limited the request",
      )
    "provider_error" if status >= 300 && status <= 599 && status != 429 =>
      (
        "ACTQL_E_MODEL_PROVIDER_ERROR", "The Model provider returned an HTTP error",
      )
    "schema_invalid" if success_status =>
      (
        "ACTQL_E_MODEL_SCHEMA_INVALID", "The Model response did not match the output contract",
      )
    "refusal" if success_status =>
      ("ACTQL_E_MODEL_REFUSAL", "The Model provider refused the request")
    "truncated" if success_status =>
      ("ACTQL_E_MODEL_TRUNCATED", "The Model response was truncated")
    "safety_rejected" if success_status =>
      (
        "ACTQL_E_MODEL_SAFETY_REJECTED", "The Model provider rejected the request for safety",
      )
    _ => return Err(mismatch)
  }
  Ok({
    run_definition_cid: definition.identity,
    attempt_cid: expected_attempt_cid,
    raw_cid: expected_raw_cid,
    diagnostic,
  })
}
