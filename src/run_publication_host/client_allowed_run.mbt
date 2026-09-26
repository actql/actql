///|
pub(all) enum ClientAllowedRunEvidenceIssue {
  Prepared(@publication.RunEvidenceValueIssue)
  Authorization(@publication.RunEvidenceValueIssue)
}

///|
/// The installing Host must authorize the caller before invoking this issuer.
/// These linked policy records never grant an Effect apply permit.
pub fn issue_client_allowed_run_evidence(
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[
  (@publication.RunEvidenceValue, @publication.RunEvidenceValue),
  ClientAllowedRunEvidenceIssue,
] {
  let prepared_value = match
    @publication.seal_run_evidence_value(
      "prepared_invocation",
      "{\"version\":\"actql-prepared-invocation/0.1\"," +
      "\"invocation_template_cid\":\"" +
      @publication.run_evidence_value_identity(template) +
      "\",\"compiled_plan_cid\":\"" +
      @publication.publication_contract_identity(plan) +
      "\",\"execution_context_cid\":\"" +
      execution_context_cid +
      "\",\"host_policy_cid\":\"" +
      host_policy_cid +
      "\",\"policy_decision\":\"allow\",\"expires_at\":\"" +
      expires_at +
      "\"}",
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepared(issue))
  }
  let authorization = match
    @publication.seal_run_evidence_value(
      "run_authorization",
      "{\"version\":\"actql-run-authorization/0.1\"," +
      "\"prepared_invocation_cid\":\"" +
      @publication.run_evidence_value_identity(prepared_value) +
      "\",\"execution_context_cid\":\"" +
      execution_context_cid +
      "\",\"host_policy_cid\":\"" +
      host_policy_cid +
      "\",\"decision\":\"allowed\"}",
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  Ok((prepared_value, authorization))
}
