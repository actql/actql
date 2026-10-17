///|
/// Exact Receipt and Captured Run references, in that order, from an admitted
/// index. A Store may retrieve these original bodies before the existing full
/// commit validator runs. This projection neither validates that chain nor
/// observes physical completion, current authority or Result availability.
pub fn public_index_run_observation_cids(
  index : PublicationContract,
) -> Result[(String, String), DeliveryIssuanceIssue] {
  if index.name != "public_index_entry" {
    return Err(DeliveryIssuanceWrongContract("public_index_entry"))
  }
  guard contract_string(index, "run_receipt_cid") is Some(receipt) &&
    contract_string(index, "captured_run_cid") is Some(captured) else {
    return Err(DeliveryIssuanceReferenceMismatch("public_index.observation"))
  }
  Ok((receipt, captured))
}

///|
// Borrow the original admitted array. Do not copy its contents into a second
// dependency inventory or interpret provenance as permission/completion.
fn result_artifact_provenance(
  artifact : PublicationContract,
) -> Result[@json.FrozenArray[@json.CanonicalValue], DeliveryIssuanceIssue] {
  if artifact.name != "result_artifact" {
    return Err(DeliveryIssuanceWrongContract("result_artifact"))
  }
  guard @json.object_field(artifact.value, "provenance_evidence_cids")
    is Some(@json.Array(provenance)) else {
    return Err(DeliveryIssuanceReferenceMismatch("result_artifact.provenance"))
  }
  Ok(provenance)
}

///|
/// Size of the original provenance list, including a valid empty list. Codec
/// bounds are not physical funding; the caller retains its actual input loan.
pub fn result_artifact_provenance_count(
  artifact : PublicationContract,
) -> Result[Int, DeliveryIssuanceIssue] {
  result_artifact_provenance(artifact).map(value => @json.array_count(value))
}

///|
/// Select one original provenance CID without constructing another array.
/// Original order is retained. Missing/negative/out-of-range is refusal, never
/// a substituted body, empty dependency, or completion/authorization result.
pub fn result_artifact_provenance_at(
  artifact : PublicationContract,
  ordinal : Int,
) -> Result[String, DeliveryIssuanceIssue] {
  let provenance = match result_artifact_provenance(artifact) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if ordinal < 0 || ordinal >= @json.array_count(provenance) {
    return Err(
      DeliveryIssuanceReferenceMismatch("result_artifact.provenance_index"),
    )
  }
  guard @json.array_at(provenance, ordinal) is Some(@json.String(cid)) else {
    return Err(DeliveryIssuanceReferenceMismatch("result_artifact.provenance"))
  }
  Ok(cid)
}
