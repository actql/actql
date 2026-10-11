///|
/// Integrity-bound Host selection originals. This is not a capture grant,
/// disclosure grant, Store receipt, or a permit to extend retention.
pub struct BoundModelRawCapturePolicy {
  priv policy : RunEvidenceValue
  priv retention : CapturedEffectDependencyBody
  priv metadata : CapturedEffectDependencyBody
  priv clock : CapturedEffectDependencyBody
  priv data : CapturedEffectDependencyBody
}

///|
fn model_raw_policy_error(field : String) -> RunEvidenceValueIssue {
  RunEvidenceReferenceMismatch("model_raw_capture_policy." + field)
}

///|
/// Resolve the actual selected originals, not plausible CID strings or the
/// Store's encryption key. The installed Host separately attests selection,
/// applicability, current private capture permission and trusted clock custody.
pub fn bind_model_raw_capture_policy(
  policy : RunEvidenceValue,
  retention : CapturedEffectDependencyBody,
  metadata : CapturedEffectDependencyBody,
  clock : CapturedEffectDependencyBody,
  data : CapturedEffectDependencyBody,
) -> Result[BoundModelRawCapturePolicy, RunEvidenceValueIssue] {
  if policy.name != "model_raw_capture_policy" {
    return Err(UnknownRunEvidence)
  }
  for
    (field, expected_kind, original) in [
      ("retention_contract_cid", "retention_contract", retention),
      ("metadata_retention_policy_cid", "metadata_retention_policy", metadata),
      ("clock_contract_cid", "clock_contract", clock),
      ("effective_data_policy_cid", "data_policy", data),
    ] {
    if original.node.kind != expected_kind ||
      evidence_string(policy.value, field) != Some(original.node.identity) {
      return Err(model_raw_policy_error(field))
    }
  }
  let selected = evidence_string(policy.value, "selected_at").unwrap()
  let available = evidence_string(policy.value, "available_until").unwrap()
  let deletion = evidence_string(policy.value, "delete_by").unwrap()
  let ceiling = evidence_string(policy.value, "extension_ceiling_at").unwrap()
  let metadata_deletion = evidence_string(policy.value, "metadata_delete_by").unwrap()
  if ![selected, available, deletion, ceiling, metadata_deletion].all(
      valid_timestamp,
    ) ||
    selected > available ||
    available > deletion ||
    deletion > ceiling ||
    deletion > metadata_deletion {
    return Err(model_raw_policy_error("intervals"))
  }
  Ok({ policy, retention, metadata, clock, data, })
}

///|
pub fn model_raw_capture_policy_value(
  value : BoundModelRawCapturePolicy,
) -> RunEvidenceValue {
  value.policy
}

///|
/// The installed Store port rechecks availability of these exact originals.
/// Returning their admitted bodies does not confer capture or read authority.
pub fn model_raw_capture_policy_originals(
  value : BoundModelRawCapturePolicy,
) -> Array[CapturedEffectDependencyBody] {
  [value.retention, value.metadata, value.clock, value.data]
}

///|
/// Match a raw descriptor to the original fixed policy and retained call
/// attempt. Neither this comparison nor transport EOF asserts answer success.
/// Actual original bytes and same Entry custody are verified by their owners.
pub fn check_model_raw_response_binding(
  policy : BoundModelRawCapturePolicy,
  response : RunEvidenceValue,
  scope : BoundModelInvocationScope,
  ordinal : Int,
  attempt : RunEvidenceValue,
  authority : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  if response.name != "model_raw_response" {
    return Err(UnknownRunEvidence)
  }
  guard scope.slots.get(ordinal) is Some(slot) else {
    return Err(RunEvidenceReferenceMismatch("model_raw_response.ordinal"))
  }
  match check_model_invocation_attempt(scope, ordinal, attempt, authority, 1L) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if evidence_string(policy.policy.value, "scope_cid") !=
    Some(scope.scope.identity) ||
    evidence_string(policy.policy.value, "run_definition_cid") !=
    Some(scope.definition.identity) {
    return Err(RunEvidenceReferenceMismatch("model_raw_response.scope"))
  }
  for
    field in [
      "run_definition_cid", "scope_cid", "response_profile_cid", "store_authority_cid",
      "effective_data_policy_cid",
    ] {
    if evidence_string(response.value, field) !=
      evidence_string(policy.policy.value, field) {
      return Err(RunEvidenceReferenceMismatch("model_raw_response." + field))
    }
  }
  for
    (field, expected) in [
      ("raw_capture_policy_cid", policy.policy.identity),
      ("slot_cid", slot.identity),
      ("attempt_cid", attempt.identity),
    ] {
    if evidence_string(response.value, field) != Some(expected) {
      return Err(RunEvidenceReferenceMismatch("model_raw_response." + field))
    }
  }
  if evidence_string(slot.value, "model_task_cid") !=
    evidence_string(policy.policy.value, "model_task_cid") {
    return Err(RunEvidenceReferenceMismatch("model_raw_response.attempt"))
  }
  let observed = evidence_string(response.value, "observed_at").unwrap()
  if !valid_timestamp(observed) ||
    observed < evidence_string(policy.policy.value, "selected_at").unwrap() {
    return Err(RunEvidenceReferenceMismatch("model_raw_response.observed_at"))
  }
  Ok(())
}

///|
/// Original descriptor and private cell binding, not a Store acknowledgement.
/// Retaining this typed view does not prove that its content bytes were saved.
pub struct BoundModelRawResponse {
  priv policy : BoundModelRawCapturePolicy
  priv scope : BoundModelInvocationScope
  priv response : RunEvidenceValue
  priv holding_cid : String
}

///|
pub fn bind_model_raw_response(
  policy : BoundModelRawCapturePolicy,
  response : RunEvidenceValue,
  scope : BoundModelInvocationScope,
  ordinal : Int,
  attempt : RunEvidenceValue,
  authority : RunEvidenceValue,
) -> Result[BoundModelRawResponse, RunEvidenceValueIssue] {
  match
    check_model_raw_response_binding(
      policy, response, scope, ordinal, attempt, authority,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let holding_cid = model_scoped_private_holding_cid(
    scope.definition,
    evidence_string(response.value, "store_authority_cid").unwrap(),
    scope.scope.identity,
    scope.slots[ordinal].identity,
    attempt.identity,
    1,
    "entered",
    "model_raw_response",
  ).unwrap()
  Ok({ policy, scope, response, holding_cid, })
}

///|
/// Immutable physical Store comparison inputs issued by the original owner.
/// The content CID and count are not authenticated physical bytes by themselves.
pub fn model_raw_response_store_binding(
  value : BoundModelRawResponse,
) -> (String, String, String, String, Int) {
  let count = match @json.object_field(value.response.value, "byte_count") {
    Some(@json.Number(count)) => count.to_int()
    _ => abort("admitted raw descriptor byte count")
  }
  (
    value.response.identity,
    value.holding_cid,
    value.response.wire,
    evidence_string(value.response.value, "content_cid").unwrap(),
    count,
  )
}

///|
pub fn model_raw_response_matches_selection(
  value : BoundModelRawResponse,
  policy : BoundModelRawCapturePolicy,
  scope : BoundModelInvocationScope,
) -> Bool {
  physical_equal(value.policy, policy) && physical_equal(value.scope, scope)
}

///|
pub fn model_raw_response_value(
  value : BoundModelRawResponse,
) -> RunEvidenceValue {
  value.response
}

///|
pub fn model_raw_response_profile_cid(value : BoundModelRawResponse) -> String {
  evidence_string(value.response.value, "response_profile_cid").unwrap()
}

///|
/// Actual transport observations from the original admitted raw descriptor.
/// EOF and an HTTP status are not endpoint or answer completion evidence.
pub fn model_raw_response_transport_facts(
  value : BoundModelRawResponse,
) -> (Int, Bool, String) {
  let status = match @json.object_field(value.response.value, "http_status") {
    Some(@json.Number(status)) => status.to_int()
    _ => abort("admitted raw descriptor HTTP status")
  }
  let eof = match @json.object_field(value.response.value, "transport_eof") {
    Some(@json.Bool(eof)) => eof
    _ => abort("admitted raw descriptor EOF")
  }
  (status, eof, evidence_string(value.response.value, "observed_at").unwrap())
}

///|
/// The existing Model/Store adapter supplies actual byte/transport observations.
/// This issuer binds them to original scope/attempt/policy, but is neither a
/// physical content hash verifier nor a saved receipt or completion issuer.
pub fn issue_model_raw_response(
  policy : BoundModelRawCapturePolicy,
  scope : BoundModelInvocationScope,
  ordinal : Int,
  attempt : RunEvidenceValue,
  authority : RunEvidenceValue,
  content_cid : String,
  byte_count : Int,
  http_status : Int,
  transport_eof : Bool,
  observed_at : String,
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  guard scope.slots.get(ordinal) is Some(slot) else {
    return Err(RunEvidenceReferenceMismatch("model_raw_response.ordinal"))
  }
  let body = try {
    let writer = @encode.writer(8192, 128, 8)
    @encode.begin_object(writer)
    for
      (field, text) in [
        ("version", "actql-model-raw-response/0.1"),
        ("run_definition_cid", scope.definition.identity),
        ("scope_cid", scope.scope.identity),
        ("slot_cid", slot.identity),
        ("attempt_cid", attempt.identity),
        ("phase", "entered"),
        (
          "response_profile_cid",
          evidence_string(policy.policy.value, "response_profile_cid").unwrap(),
        ),
        (
          "store_authority_cid",
          evidence_string(policy.policy.value, "store_authority_cid").unwrap(),
        ),
        (
          "effective_data_policy_cid",
          evidence_string(policy.policy.value, "effective_data_policy_cid").unwrap(),
        ),
        ("raw_capture_policy_cid", policy.policy.identity),
        ("content_cid", content_cid),
        ("observed_at", observed_at),
      ] {
      @encode.key(writer, field)
      @encode.string_value(writer, text)
    }
    for
      (field, count) in [
        ("attempt", 1),
        ("byte_count", byte_count),
        ("http_status", http_status),
      ] {
      @encode.key(writer, field)
      @encode.number_value(writer, count.to_double())
    }
    @encode.key(writer, "transport_eof")
    @encode.bool_value(writer, transport_eof)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let response = match
    seal_run_evidence_value("model_raw_response", body, 8192, 128, 8) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  check_model_raw_response_binding(
    policy, response, scope, ordinal, attempt, authority,
  ).map(_ => response)
}
