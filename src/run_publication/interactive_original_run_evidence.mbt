///|
/// Validate immutable original evidence for the same Run Definition. This pure
/// metadata check does not grant current RunRead, execution or control authority.
/// Durable callers must authenticate the original journal row separately.
pub fn validate_original_interactive_run_evidence(
  run : PublicationContract,
  prepared : RunEvidenceValue,
  authorization : RunEvidenceValue,
) -> Result[Unit, RunControlReadIssue] {
  if run.name != "run_definition" ||
    prepared.name != "prepared_invocation" ||
    authorization.name != "run_authorization" {
    return Err(LegacyProjectionMismatch("original_evidence"))
  }
  for field in ["compiled_plan_cid", "invocation_template_cid"] {
    if contract_string_from_value(prepared.value, field) !=
      contract_string(run, field) {
      return Err(LegacyProjectionMismatch(field))
    }
  }
  if contract_string_from_value(authorization.value, "prepared_invocation_cid") !=
    Some(prepared.identity) ||
    contract_string_from_value(prepared.value, "policy_decision") !=
    Some("allow") ||
    contract_string_from_value(authorization.value, "decision") !=
    Some("allowed") {
    return Err(LegacyProjectionMismatch("authorization"))
  }
  let context = contract_string(run, "authorization_context_cid")
  if context !=
    contract_string_from_value(prepared.value, "execution_context_cid") ||
    context !=
    contract_string_from_value(authorization.value, "execution_context_cid") {
    return Err(LegacyProjectionMismatch("execution_context_cid"))
  }
  let policy = contract_string_from_value(
    authorization.value,
    "host_policy_cid",
  )
  if policy != contract_string_from_value(prepared.value, "host_policy_cid") {
    return Err(LegacyProjectionMismatch("host_policy_cid"))
  }
  Ok(())
}
