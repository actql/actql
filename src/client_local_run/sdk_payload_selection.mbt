///|
/// Read-only routing coordinates of the original selected Result and binding.
/// These coordinates grant no byte access or physical Store acknowledgement.
pub(all) enum LocalSDKPayloadSelectionIssue {
  Stored(@publication.ObservedResultReadIssue)
  InvalidLimit
  ChangedOriginal
  MissingOriginal
}

///|
/// Select through the existing actual stored-chain Owner, bounded by the
/// selected profile. Python must still bind its exact Sealed record and current
/// physical generation before opening a descriptor; an ordinal is not a permit.
pub fn LocalSDKPayloadEncoding::original_payload_ordinals(
  self : LocalSDKPayloadEncoding,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  originals : Array[LocalResultPublication],
  result_name : String,
  max_results : Int,
) -> Result[(Int, Int), LocalSDKPayloadSelectionIssue] {
  if max_results <= 0 || originals.length() > max_results {
    return Err(InvalidLimit)
  }
  let selected = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(selected) => selected
    Err(issue) => return Err(Stored(issue))
  }
  if @publication.publication_contract_identity(selected.index) !=
    @publication.publication_contract_identity(self.materials.index) ||
    selected.read.durable_result_binding_cid !=
    self.materials.read.durable_result_binding_cid ||
    selected.read.result_artifact_cid != self.materials.read.result_artifact_cid {
    return Err(ChangedOriginal)
  }
  let mut result = None
  for i = 0; i < originals.length(); i = i + 1 {
    let artifact = originals[i].artifact
    if @publication.publication_contract_identity(artifact) ==
      selected.read.result_artifact_cid &&
      @publication.publication_contract_json(artifact) ==
      @publication.publication_contract_json(selected.artifact) {
      // Equal references may alias the same original artifact. This chooses
      // routing only; binding the exact record performs the final Owner check.
      if result is None {
        result = Some(i)
      }
    }
  }
  let mut binding = None
  for i = 0; i < max_results; i = i + 1 {
    match owner.view_binding(view, i) {
      Err(_) => break
      Ok(original) =>
        if @publication.publication_contract_identity(original) ==
          selected.read.durable_result_binding_cid {
          binding = Some(i)
          break
        }
    }
  }
  match (result, binding) {
    (Some(result), Some(binding)) => Ok((result, binding))
    _ => Err(MissingOriginal)
  }
}
