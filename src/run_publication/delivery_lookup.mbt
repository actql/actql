///|
/// The existing public delivery lookup scope. Format and current payload
/// availability are not part of this historical metadata operation.
pub(all) struct DeliveryAttemptLookupScope {
  namespace_id : String
  authority_scope_cid : String
  run_definition_cid : String
  principal_id : String
  purpose : String
  result_name : String
  attempt_id : String
} derive(Eq, Debug)

///|
pub fn delivery_attempt_read_grant_cid(
  attempt : PublicationContract,
) -> Result[String, DeliveryIssuanceIssue] {
  if attempt.name != "delivery_attempt" {
    return Err(DeliveryIssuanceWrongContract("delivery_attempt"))
  }
  match contract_string(attempt, "result_read_grant_cid") {
    Some(value) => Ok(value)
    None => Err(DeliveryIssuanceReferenceMismatch("result_read_grant_cid"))
  }
}

///|
/// Validate retained originals before matching a caller's authorized scope.
/// The original grant binds identity; its expiry is not a current lookup
/// permission. This never issues/consumes a grant or opens Result material.
pub fn delivery_attempt_lookup_matches_scope(
  attempt : PublicationContract,
  grant : PublicationContract,
  scope : DeliveryAttemptLookupScope,
) -> Result[Bool, DeliveryIssuanceIssue] {
  let grant_cid = match delivery_attempt_read_grant_cid(attempt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if grant.name != "result_read_grant" {
    return Err(DeliveryIssuanceWrongContract("result_read_grant"))
  }
  if grant.identity != grant_cid ||
    contract_string(grant, "run_definition_cid") !=
    contract_string(attempt, "run_definition_cid") ||
    contract_string(grant, "result_manifest_cid") !=
    contract_string(attempt, "result_manifest_cid") {
    return Err(DeliveryIssuanceReferenceMismatch("delivery_attempt_grant"))
  }
  guard contract_string(attempt, "result_name") is Some(result_name) &&
    contract_string(attempt, "result_artifact_cid") is Some(artifact) &&
    grant_has_result(grant, result_name, artifact) else {
    return Err(DeliveryIssuanceReferenceMismatch("grant.results"))
  }
  let serialization = contract_string(attempt, "serialization_contract_cid")
  let mut permitted_format = false
  for format in ["json", "jsonl", "csv"] {
    let cid = match result_serialization_contract_cid(format, 4096, 128, 8) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if serialization == Some(cid) && grant_has_format(grant, format) {
      permitted_format = true
    }
  }
  if !permitted_format {
    return Err(DeliveryIssuanceReferenceMismatch("grant.formats"))
  }
  Ok(
    contract_string(attempt, "attempt_id") == Some(scope.attempt_id) &&
    contract_string(attempt, "run_definition_cid") ==
    Some(scope.run_definition_cid) &&
    contract_string(attempt, "result_name") == Some(scope.result_name) &&
    contract_string(grant, "namespace_id") == Some(scope.namespace_id) &&
    contract_string(grant, "authority_scope_cid") ==
    Some(scope.authority_scope_cid) &&
    contract_string(grant, "principal_id") == Some(scope.principal_id) &&
    contract_string(grant, "purpose") == Some(scope.purpose),
  )
}
