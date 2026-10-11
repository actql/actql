///|
/// Replay checks freshly reconstructed request, key and response/output facts,
/// then retains the admitted original observation. It does not upgrade an old
/// record or confer profile, dispatch, custody or publication authority.
pub fn check_model_replayed_observation(
  original : RunEvidenceValue,
  reconstructed : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  if original.name != "model_invocation_evidence" ||
    reconstructed.name != "model_invocation_evidence" {
    return Err(UnknownRunEvidence)
  }
  if contract_string_from_value(reconstructed.value, "version") !=
    Some("actql-model-invocation-evidence/0.1") {
    return Err(RunEvidenceInvalidShape)
  }
  match contract_string_from_value(original.value, "version") {
    Some("actql-model-invocation-evidence/0.1") => {
      // Preserve the old reader's full exact-body comparison.
      if original.identity != reconstructed.identity {
        return Err(RunEvidenceIdentityMismatch)
      }
      return Ok(())
    }
    Some("actql-model-invocation-evidence/0.2") => ()
    _ => return Err(RunEvidenceInvalidShape)
  }
  for
    name in [
      "model_task_contract_cid", "semantic_request_cid", "model_call_slot_cid", "input_result_artifact_cid",
      "input_row_identity_cid", "authored_model_selector", "provider_reported_model_id",
      "provider_request_id", "structured_response_artifact_cid", "validated_structured_output_cid",
      "observed_at",
    ] {
    guard contract_string_from_value(original.value, name) is Some(actual) &&
      contract_string_from_value(reconstructed.value, name) == Some(actual) else {
      return Err(RunEvidenceReferenceMismatch(name))
    }
  }
  // The current synchronous response carrier cannot represent absent usage.
  // Do not substitute zero; nullable async observations need their own carrier.
  for name in ["attempt", "input_tokens", "output_tokens"] {
    guard @json.object_field(original.value, name) is Some(@json.Number(actual)) &&
      @json.object_field(reconstructed.value, name)
      is Some(@json.Number(expected)) &&
      actual == expected else {
      return Err(RunEvidenceReferenceMismatch(name))
    }
  }
  guard @json.object_field(original.value, "input_row_identity") is Some(actual) &&
    @json.object_field(reconstructed.value, "input_row_identity")
    is Some(expected) else {
    return Err(RunEvidenceReferenceMismatch("input_row_identity"))
  }
  if !model_replay_key_equal(actual, expected) {
    return Err(RunEvidenceReferenceMismatch("input_row_identity"))
  }
  // The exact new record is already admitted. Its profile, raw response and
  // opaque metadata remain original observations, not reconstructed defaults.
  // In particular the old writer's fixed stop is not a reported finish reason.
  Ok(())
}

///|
/// Admitted keys are scalars or a flat scalar tuple, not arbitrary JSON trees.
/// Compare borrowed original components without two extra wire/writer copies.
fn model_replay_key_equal(
  actual : @json.CanonicalValue,
  expected : @json.CanonicalValue,
) -> Bool {
  match (actual, expected) {
    (@json.Array(left), @json.Array(right)) => {
      let count = @json.array_count(left)
      if count != @json.array_count(right) || count > 1024 {
        return false
      }
      for index in 0..<count {
        guard @json.array_at(left, index) is Some(left) &&
          @json.array_at(right, index) is Some(right) &&
          model_replay_key_scalar_equal(left, right) else {
          return false
        }
      }
      true
    }
    _ => model_replay_key_scalar_equal(actual, expected)
  }
}

///|
fn model_replay_key_scalar_equal(
  actual : @json.CanonicalValue,
  expected : @json.CanonicalValue,
) -> Bool {
  match (actual, expected) {
    (@json.String(left), @json.String(right)) => left == right
    (@json.Number(left), @json.Number(right)) => left == right
    (@json.Bool(left), @json.Bool(right)) => left == right
    _ => false
  }
}

///|
/// Exact observation discriminator for the existing bounded capture writer.
/// This grants no permission to reinterpret an unknown record version.
pub fn model_invocation_evidence_version(value : RunEvidenceValue) -> String? {
  if value.name != "model_invocation_evidence" {
    None
  } else {
    contract_string_from_value(value.value, "version")
  }
}
