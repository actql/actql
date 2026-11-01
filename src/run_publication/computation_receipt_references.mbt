///|
// The same immutable root-reference laws are consumed by fresh commit
// validation and retained receipt projection. They grant no publication,
// current authority, physical observation or execution evidence.
fn check_receipt_invocation_reference(
  receipt : @json.CanonicalValue,
  invocation_cid : String,
) -> Result[Unit, RunEvidenceChainIssue] {
  if evidence_string(receipt, "invocation_cid") != Some(invocation_cid) {
    Err(EvidenceReferenceMismatch("invocation_cid"))
  } else {
    Ok(())
  }
}

///|
fn check_receipt_compiled_plan_reference(
  receipt : @json.CanonicalValue,
  definition : PublicationContract,
) -> Result[Unit, RunEvidenceChainIssue] {
  if evidence_string(receipt, "compiled_plan_cid") !=
    contract_string(definition, "compiled_plan_cid") {
    Err(EvidenceReferenceMismatch("compiled_plan_cid"))
  } else {
    Ok(())
  }
}

///|
fn check_receipt_manifest_reference(
  receipt : @json.CanonicalValue,
  manifest : PublicationContract,
) -> Result[Unit, RunEvidenceChainIssue] {
  if evidence_string(receipt, "result_manifest_cid") != Some(manifest.identity) {
    Err(EvidenceReferenceMismatch("result_manifest_cid"))
  } else {
    Ok(())
  }
}
