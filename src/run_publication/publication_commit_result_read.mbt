///|
/// Original stored-chain materials for the existing Result read/delivery
/// Owners. This projection is not current read authority, a grant, a delivery
/// attempt, physical availability or a Store acknowledgement.
pub(all) struct ObservedResultReadMaterials {
  index : PublicationContract
  manifest : PublicationContract
  definition : PublicationContract
  artifact : PublicationContract
  retention : PublicationContract
  read : CommittedResultRead
}

///|
pub(all) enum ObservedResultReadIssue {
  Commit(PublicationCommitIssue)
  Projection(DeliveryIssuanceIssue)
}

///|
fn observed_result_read_original(
  originals : Array[PublicationContract],
  cid : String,
) -> PublicationContract? {
  for original in originals {
    if original.identity == cid {
      return Some(original)
    }
  }
  None
}

///|
/// Select through the complete actual stored index, never the candidate index.
/// Bound every original inventory before the existing delivery selector scans
/// it. The Host must separately hold the original view/loans and current
/// File/Store, Account, publisher, retention and delivery-usage observations.
pub fn PublicationCommitPreparation::observed_result_read_materials(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  result_name : String,
  max_results : Int,
) -> Result[ObservedResultReadMaterials, ObservedResultReadIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(Commit(issue))
  }
  let index = match preparation.finish_observed_commit(view) {
    Ok(index) => index
    Err(issue) => return Err(Commit(issue))
  }
  let chain = inputs.computation
  if max_results <= 0 ||
    inputs.bindings.length() > max_results ||
    inputs.retentions.length() > max_results ||
    chain.definitions.length() > max_results ||
    chain.artifacts.length() > max_results {
    return Err(Projection(DeliveryIssuanceInvalidLimit))
  }
  let read = match
    project_committed_result_read(
      index,
      chain.manifest,
      result_name,
      inputs.bindings,
    ) {
    Ok(read) => read
    Err(issue) => return Err(Projection(issue))
  }
  // Multiple named Results may share the same original retention body. The
  // full-chain validator already binds each Result to it; do not invent a
  // uniqueness condition for that shared Policy or copy its inventory.
  guard observed_result_read_original(
      chain.definitions,
      read.result_definition_cid,
    )
    is Some(definition) &&
    observed_result_read_original(chain.artifacts, read.result_artifact_cid)
    is Some(artifact) &&
    observed_result_read_original(
      inputs.retentions,
      read.effective_retention_policy_cid,
    )
    is Some(retention) else {
    return Err(
      Projection(DeliveryIssuanceReferenceMismatch("result.originals")),
    )
  }
  Ok({ index, manifest: chain.manifest, definition, artifact, retention, read, })
}
