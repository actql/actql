///|
/// Check the fixed reference boundary of the initial source-free INFER route.
/// Full slot verification, external evidence admission and durable custody
/// belong to their owners. This function grants no execution/publication right.
pub fn check_source_free_model_invocation_binding(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  invocation : PublicationContract,
  input_artifact : RunEvidenceValue,
  data_policy_cid : String,
) -> Result[Unit, RunEvidenceValueIssue] {
  if template.name != "bound_invocation_template" ||
    observation.name != "observation_set" ||
    invocation.name != "run_invocation" ||
    input_artifact.name != "model_input_artifact" {
    return Err(UnknownRunEvidence)
  }
  if !model_template_requires_slots(template) ||
    model_observation_slot_count(observation) is None {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  if contract_string_from_value(observation.value, "invocation_template_cid") !=
    Some(template.identity) ||
    contract_string_from_value(invocation.value, "invocation_template_cid") !=
    Some(template.identity) {
    return Err(
      RunEvidenceReferenceMismatch("observation.invocation_template_cid"),
    )
  }
  if contract_string_from_value(invocation.value, "observation_set_cid") !=
    Some(observation.identity) {
    return Err(RunEvidenceReferenceMismatch("invocation.observation_set_cid"))
  }
  check_source_free_model_observation_binding(
    template, observation, input_artifact, data_policy_cid,
  )
}

///|
/// Constant-size scope validation also applies when an INFER has zero keys.
/// A per-slot loop cannot establish these bindings for an empty inventory.
pub fn check_source_free_model_observation_binding(
  template : RunEvidenceValue,
  observation : RunEvidenceValue,
  input_artifact : RunEvidenceValue,
  data_policy_cid : String,
) -> Result[Unit, RunEvidenceValueIssue] {
  if template.name != "bound_invocation_template" ||
    observation.name != "observation_set" ||
    input_artifact.name != "model_input_artifact" {
    return Err(UnknownRunEvidence)
  }
  if !model_template_requires_slots(template) ||
    model_observation_slot_count(observation) is None {
    return Err(RunEvidenceReferenceMismatch("model_slot_capture_cids"))
  }
  if contract_string_from_value(observation.value, "invocation_template_cid") !=
    Some(template.identity) {
    return Err(
      RunEvidenceReferenceMismatch("observation.invocation_template_cid"),
    )
  }
  if contract_string_from_value(observation.value, "data_policy_cid") !=
    Some(data_policy_cid) {
    return Err(RunEvidenceReferenceMismatch("observation.data_policy_cid"))
  }
  if contract_string_from_value(input_artifact.value, "program_definition_cid") !=
    contract_string_from_value(template.value, "program_definition_cid") {
    return Err(
      RunEvidenceReferenceMismatch("input_artifact.program_definition_cid"),
    )
  }
  guard @json.object_field(observation.value, "captured_input_artifact_cids")
    is Some(@json.Array(inputs)) &&
    @json.array_count(inputs) == 1 &&
    optional_string(@json.array_at(inputs, 0)) == Some(input_artifact.identity) else {
    return Err(
      RunEvidenceReferenceMismatch("observation.captured_input_artifact_cids"),
    )
  }
  guard @json.object_field(observation.value, "source_evidence_cids")
    is Some(@json.Array(sources)) &&
    @json.array_count(sources) == 0 else {
    return Err(RunEvidenceReferenceMismatch("observation.source_evidence_cids"))
  }
  Ok(())
}

///|
/// Verify the original saved Run, not a fresh dispatch permit or current clock.
/// The current input owner supplies its actual checked identities and artifact.
pub fn check_saved_source_free_model_observation(
  admission : RunPublicationAdmission,
  definition : PublicationContract,
  observation : RunEvidenceValue,
  input_artifact : RunEvidenceValue,
  program_definition_cid : String,
  program_semantics_cid : String,
  check_environment_cid : String,
  data_policy_cid : String,
) -> Result[Unit, RunEvidenceValueIssue] {
  if check_run_publication_program_binding(
      admission, definition, program_definition_cid, program_semantics_cid, check_environment_cid,
    )
    is Err(_) {
    return Err(RunEvidenceReferenceMismatch("model_attempt_evidence"))
  }
  check_source_free_model_observation_binding(
    admission.template,
    observation,
    input_artifact,
    data_policy_cid,
  )
}
