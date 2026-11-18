///|
/// A bounded read of an already admitted immutable invocation. This contains
/// only reported availability, never a send or disclosure capability.
pub(all) struct ModelCaptureUsage {
  origin : ModelCaptureObservationOrigin
  input_tokens : Int64?
  output_tokens : Int64?
  raw_response_artifact_cid : String?
}

///|
/// Read selected fields without parsing a bundle, copying response content or
/// reconstructing an observation from Host metadata. The execution owner must
/// supply its actual adopted invocation; Store and disclosure checks are separate.
pub fn model_invocation_evidence_usage(
  value : RunEvidenceValue,
) -> Result[ModelCaptureUsage, RunEvidenceValueIssue] {
  let origin = match model_invocation_evidence_version(value) {
    Some("actql-model-invocation-evidence/0.1") => HistoricalAdmitted
    Some("actql-model-invocation-evidence/0.2") => Reported
    _ => return Err(RunEvidenceInvalidShape)
  }
  let input_tokens = match
    model_capture_optional_tokens(value.value, "input_tokens") {
    Ok(tokens) => tokens
    Err(issue) => return Err(issue)
  }
  let output_tokens = match
    model_capture_optional_tokens(value.value, "output_tokens") {
    Ok(tokens) => tokens
    Err(issue) => return Err(issue)
  }
  Ok({
    origin,
    input_tokens,
    output_tokens,
    raw_response_artifact_cid: optional_string(
      @json.object_field(value.value, "raw_response_artifact_cid"),
    ),
  })
}
