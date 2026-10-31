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

///|
/// Check only the exact retained receipt/Run/Manifest references selected by
/// an admitted committed index. This reads no Store, issues no receipt and
/// verifies no new execution or current authority. The trusted Store/Host
/// retains its actual original snapshot and independent read permission.
pub fn check_original_stored_run_receipt_references(
  index : PublicationContract,
  definition : PublicationContract,
  manifest : PublicationContract,
  receipt : PublicationContract,
) -> Result[Unit, DeliveryIssuanceIssue] {
  if index.name != "public_index_entry" ||
    definition.name != "run_definition" ||
    manifest.name != "result_manifest" ||
    receipt.name != "run_receipt" {
    return Err(DeliveryIssuanceWrongContract("retained_run_receipt"))
  }
  let projected = match project_public_index_read(index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (receipt_cid, _) = match public_index_run_observation_cids(index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if projected.run_definition_cid != definition.identity ||
    projected.result_manifest_cid != manifest.identity ||
    receipt_cid != receipt.identity {
    return Err(DeliveryIssuanceReferenceMismatch("retained_run_receipt.index"))
  }
  match
    check_receipt_invocation_reference(receipt.value, projected.invocation_cid) {
    Ok(_) => ()
    Err(_) =>
      return Err(
        DeliveryIssuanceReferenceMismatch("retained_run_receipt.invocation"),
      )
  }
  match check_receipt_compiled_plan_reference(receipt.value, definition) {
    Ok(_) => ()
    Err(_) =>
      return Err(
        DeliveryIssuanceReferenceMismatch("retained_run_receipt.compiled_plan"),
      )
  }
  match check_receipt_manifest_reference(receipt.value, manifest) {
    Ok(_) => Ok(())
    Err(_) =>
      Err(DeliveryIssuanceReferenceMismatch("retained_run_receipt.manifest"))
  }
}
