///|
/// A checked source observation to accompany model slots. This binds evidence;
/// it neither grants source access nor permits model dispatch or replay.
pub struct ModelSourceObservation {
  source : RunEvidenceValue
  input : RunEvidenceValue
  started_at : String
  completed_at : String
}

///|
pub fn admit_model_source_observation(
  source : RunEvidenceValue,
  input : RunEvidenceValue,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  started_at : String,
  completed_at : String,
) -> Result[ModelSourceObservation, RunEvidenceValueIssue] {
  if !valid_timestamp(started_at) ||
    !valid_timestamp(completed_at) ||
    started_at > completed_at {
    return Err(RunEvidenceReferenceMismatch("source.capture_interval"))
  }
  if admit_completed_source_observation_binding(
      source, input, source_ref, source_contract_cid, authority_scope_cid, data_policy_cid,
      100000, 10000, 100,
    )
    is Err(_) {
    return Err(RunEvidenceReferenceMismatch("source_evidence"))
  }
  Ok({ source, input, started_at, completed_at, })
}

///|
pub fn model_source_observation_fields(
  value : ModelSourceObservation,
) -> (String, String, String) {
  (value.source.identity, value.started_at, value.completed_at)
}

///|
pub fn model_source_observation_matches_input(
  value : ModelSourceObservation,
  input : RunEvidenceValue,
) -> Bool {
  input.name == "source_input_logical" && value.input.identity == input.identity
}

///|
/// Restore the original observation against a newly checked input. Fresh
/// acquisition times are not replay identity; source, input and policy are.
pub fn restore_model_source_observation(
  current : ModelSourceObservation,
  source : RunEvidenceValue,
  observation : RunEvidenceValue,
) -> Result[ModelSourceObservation, RunEvidenceValueIssue] {
  guard source.name == "source_evidence" &&
    observation.name == "observation_set" &&
    contract_string_from_value(observation.value, "consistency") ==
    Some("independent_snapshots") &&
    @json.object_field(observation.value, "source_evidence_cids")
    is Some(@json.Array(sources)) &&
    @json.array_count(sources) == 1 &&
    optional_string(@json.array_at(sources, 0)) == Some(source.identity) else {
    return Err(RunEvidenceReferenceMismatch("observation.source_evidence_cids"))
  }
  guard contract_string_from_value(observation.value, "capture_started_at")
    is Some(started_at) &&
    contract_string_from_value(observation.value, "capture_completed_at")
    is Some(completed_at) &&
    contract_string_from_value(current.source.value, "source_ref")
    is Some(source_ref) &&
    contract_string_from_value(current.source.value, "source_contract_cid")
    is Some(source_contract) &&
    contract_string_from_value(current.source.value, "authority_scope_cid")
    is Some(authority) &&
    contract_string_from_value(
      current.source.value,
      "effective_data_policy_cid",
    )
    is Some(policy) else {
    return Err(RunEvidenceReferenceMismatch("source_evidence"))
  }
  admit_model_source_observation(
    source,
    current.input,
    source_ref,
    source_contract,
    authority,
    policy,
    started_at,
    completed_at,
  )
}
