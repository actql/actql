///|
/// Structural and exact-call admission, not dispatch, accounting or authority
/// evidence. The capture owner must verify the referenced attempt, outcome,
/// policy and resource records before using this binding for publication.
pub struct BoundModelSlotCapture {
  call : RunEvidenceValue
  capture : RunEvidenceValue
}

///|
fn model_slot_reference_error(field : String) -> RunEvidenceValueIssue {
  RunEvidenceReferenceMismatch("model_slot_capture." + field)
}

///|
fn model_template_requires_slots(template : RunEvidenceValue) -> Bool {
  guard @json.object_field(template.value, "required_profile_contracts")
    is Some(@json.Array(profiles)) else {
    return false
  }
  for index in 0..<@json.array_count(profiles) {
    guard @json.array_at(profiles, index) is Some(profile) else { return false }
    if contract_string_from_value(profile, "profile_id") ==
      Some("actql-infer/0.1") {
      return true
    }
  }
  false
}

///|
/// Match a saved adopted outcome to its formal call identity, not merely to a
/// plausible CID or a successful-response bundle. Failed outcomes are admitted
/// here too; a response-less failure must not fabricate response artifacts.
pub fn bind_model_slot_capture(
  call : RunEvidenceValue,
  capture : RunEvidenceValue,
) -> Result[BoundModelSlotCapture, RunEvidenceValueIssue] {
  if call.name != "model_call_slot" || capture.name != "model_slot_capture" {
    return Err(UnknownRunEvidence)
  }
  for
    (capture_field, call_field) in [
      ("slot_cid", "model_call_slot_cid"),
      ("model_task_cid", "model_task_cid"),
      ("fixed_request_cid", "fixed_request_cid"),
      ("input_artifact_cid", "input_artifact_cid"),
      ("input_key_cid", "input_key_cid"),
    ] {
    if contract_string_from_value(capture.value, capture_field) !=
      contract_string_from_value(call.value, call_field) {
      return Err(model_slot_reference_error(capture_field))
    }
  }
  guard @json.object_field(capture.value, "ordered_attempt_cids")
    is Some(@json.Array(attempts)) else {
    return Err(RunEvidenceInvalidShape)
  }
  // An unattempted slot is not a fabricated provider failure.
  if @json.array_count(attempts) == 0 {
    return Err(model_slot_reference_error("ordered_attempt_cids"))
  }
  let identities : Map[String, Bool] = Map([])
  for index in 0..<@json.array_count(attempts) {
    guard @json.array_at(attempts, index) is Some(@json.String(identity)) else {
      return Err(RunEvidenceInvalidShape)
    }
    if identities.contains(identity) {
      return Err(model_slot_reference_error("ordered_attempt_cids"))
    }
    identities[identity] = true
  }
  let adopted = contract_string_from_value(capture.value, "adopted_attempt_cid")
  if adopted is Some(identity) && !identities.contains(identity) {
    return Err(model_slot_reference_error("adopted_attempt_cid"))
  }
  let typed = contract_string_from_value(
    capture.value,
    "typed_value_artifact_cid",
  )
  let response = contract_string_from_value(
    capture.value,
    "response_artifact_cid",
  )
  let issuer = contract_string_from_value(
    capture.value,
    "response_issuer_evidence_cid",
  )
  if (response is Some(_)) != (issuer is Some(_)) {
    return Err(model_slot_reference_error("response_issuer_evidence_cid"))
  }
  if contract_string_from_value(capture.value, "outcome") == Some("ok") {
    if adopted is None || typed is None || response is None || issuer is None {
      return Err(model_slot_reference_error("outcome"))
    }
  } else if typed is Some(_) {
    return Err(model_slot_reference_error("typed_value_artifact_cid"))
  }
  Ok({ call, capture, })
}

///|
pub fn bound_model_slot_capture_value(
  value : BoundModelSlotCapture,
) -> RunEvidenceValue {
  value.capture
}

///|
/// The structurally admitted classification, not evidence of execution.
pub fn bound_model_slot_capture_outcome(
  value : BoundModelSlotCapture,
) -> String? {
  contract_string_from_value(value.capture.value, "outcome")
}

///|
/// Indexed structural readers for the installing capture owner's bounded
/// verifier. An absent field is distinct from the explicit zero-key array.
pub fn model_observation_slot_count(observation : RunEvidenceValue) -> Int? {
  guard observation.name == "observation_set" &&
    @json.object_field(observation.value, "model_slot_capture_cids")
    is Some(@json.Array(captures)) else {
    return None
  }
  Some(@json.array_count(captures))
}

///|
pub fn model_observation_slot_at(
  observation : RunEvidenceValue,
  index : Int,
) -> String? {
  guard observation.name == "observation_set" &&
    @json.object_field(observation.value, "model_slot_capture_cids")
    is Some(@json.Array(captures)) else {
    return None
  }
  optional_string(@json.array_at(captures, index))
}

///|
/// Exact references to one successful observation. The executing/restoring
/// owner, not a caller-authored wire record, establishes checked response
/// content. Attempt, policy, usage and authority evidence remain separate.
pub fn verify_model_slot_success_observation(
  binding : BoundModelSlotCapture,
  observation : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  if observation.name != "model_invocation_evidence" ||
    contract_string_from_value(binding.capture.value, "outcome") != Some("ok") {
    return Err(model_slot_reference_error("outcome"))
  }
  for
    (capture_field, observation_field) in [
      ("slot_cid", "model_call_slot_cid"),
      ("model_task_cid", "model_task_contract_cid"),
      ("fixed_request_cid", "semantic_request_cid"),
      ("input_artifact_cid", "input_result_artifact_cid"),
      ("input_key_cid", "input_row_identity_cid"),
      ("typed_value_artifact_cid", "validated_structured_output_cid"),
      ("response_artifact_cid", "structured_response_artifact_cid"),
    ] {
    if contract_string_from_value(binding.capture.value, capture_field) !=
      contract_string_from_value(observation.value, observation_field) {
      return Err(model_slot_reference_error(capture_field))
    }
  }
  Ok(())
}

///|
/// Match a response-less failure to the executing owner's classification.
/// Classification/attempt/accounting authority still requires its own records;
/// this structural matcher cannot turn a caller-supplied outcome into proof.
pub fn verify_model_slot_no_response_failure(
  binding : BoundModelSlotCapture,
  outcome : String,
) -> Result[Unit, RunEvidenceValueIssue] {
  if !outcome.has_prefix("failed:") ||
    contract_string_from_value(binding.capture.value, "outcome") !=
    Some(outcome) {
    return Err(model_slot_reference_error("outcome"))
  }
  for name in ["response_artifact_cid", "response_issuer_evidence_cid"] {
    if contract_string_from_value(binding.capture.value, name) is Some(_) {
      return Err(model_slot_reference_error(name))
    }
  }
  Ok(())
}

///|
/// Match only successful saved response records to the complete adopted-slot
/// inventory. Failed slots do not acquire fabricated success bundle entries.
/// Response bytes still require the existing bounded restoring model owner;
/// this structural comparison does not prove usage, authority or custody.
pub fn verify_model_slot_capture_bundle(
  expected : Array[BoundModelSlotCapture],
  saved : ModelCaptureBundleRead,
) -> Result[Unit, RunEvidenceValueIssue] {
  let count = model_capture_bundle_count(saved)
  if count < 0 {
    return Err(model_slot_reference_error("model_capture_bundle"))
  }
  let mut index = 0
  let calls : Map[String, Bool] = Map([])
  for binding in expected {
    if calls.contains(binding.call.identity) {
      return Err(model_slot_reference_error("model_capture_bundle"))
    }
    calls[binding.call.identity] = true
    if contract_string_from_value(binding.capture.value, "outcome") !=
      Some("ok") {
      continue
    }
    let record = match model_capture_bundle_record(saved, index) {
      Ok(value) => value
      Err(_) => return Err(model_slot_reference_error("model_capture_bundle"))
    }
    match verify_model_slot_success_observation(binding, record.evidence) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    index += 1
  }
  if index != count {
    return Err(model_slot_reference_error("model_capture_bundle"))
  }
  Ok(())
}

///|
/// The checked capture owner supplies the complete expected list in saved
/// occurrence and canonical typed-key order. Do not sort either list by CID.
/// This matcher preserves exact positions and rejects missing, repeated or
/// additional calls/captures. It does not turn structural records into proof
/// that a provider executed or that private Store custody is confirmed.
pub fn verify_model_observation_slots(
  observation : RunEvidenceValue,
  expected : Array[BoundModelSlotCapture],
) -> Result[Unit, RunEvidenceValueIssue] {
  if observation.name != "observation_set" {
    return Err(UnknownRunEvidence)
  }
  guard @json.object_field(observation.value, "model_slot_capture_cids")
    is Some(@json.Array(captures)) else {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  if @json.array_count(captures) != expected.length() {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  let calls : Map[String, Bool] = Map([])
  let identities : Map[String, Bool] = Map([])
  for index, binding in expected {
    if calls.contains(binding.call.identity) ||
      identities.contains(binding.capture.identity) ||
      optional_string(@json.array_at(captures, index)) !=
      Some(binding.capture.identity) {
      return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
    }
    calls[binding.call.identity] = true
    identities[binding.capture.identity] = true
  }
  Ok(())
}

///|
/// A model-containing Invocation is issued only after the installing capture
/// owner has verified every expected record and its custody. Equal identities
/// alone are insufficient: the dedicated field must match the entire ordered
/// call list, including an explicit empty array for zero keys.
pub fn issue_model_run_invocation(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  expected : Array[BoundModelSlotCapture],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunEvidenceValueIssue] {
  if template.name != "bound_invocation_template" ||
    observation.name != "observation_set" {
    return Err(UnknownRunEvidence)
  }
  if !model_template_requires_slots(template) {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  if contract_string_from_value(observation.value, "invocation_template_cid") !=
    Some(template.identity) {
    return Err(
      RunEvidenceReferenceMismatch("observation.invocation_template_cid"),
    )
  }
  for binding in expected {
    if contract_string_from_value(binding.call.value, "program_definition_cid") !=
      contract_string_from_value(template.value, "program_definition_cid") {
      return Err(model_slot_reference_error("program_definition_cid"))
    }
  }
  match verify_model_observation_slots(observation, expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  issue_run_invocation_owned(
    template, observation, max_wire_bytes, max_nodes, max_depth,
  )
}
