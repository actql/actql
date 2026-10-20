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

///|
/// Routing within the original stored inventory. These are actual view
/// coordinates, not an invented live Result/plan or permission to open bytes.
pub fn LocalSDKPayloadEncoding::stored_payload_ordinals(
  self : LocalSDKPayloadEncoding,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  max_results : Int,
  max_contracts : Int,
) -> Result[(Int, Int), LocalSDKPayloadSelectionIssue] {
  if max_results <= 0 || max_contracts <= 0 || max_contracts > 256 {
    return Err(InvalidLimit)
  }
  let selected = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(issue) => return Err(Stored(issue))
  }
  if @publication.publication_contract_identity(selected.index) !=
    @publication.publication_contract_identity(self.materials.index) ||
    selected.read.durable_result_binding_cid !=
    self.materials.read.durable_result_binding_cid ||
    selected.read.result_artifact_cid != self.materials.read.result_artifact_cid {
    return Err(ChangedOriginal)
  }
  stored_sdk_payload_coordinates(
    owner, view, result_name, max_results, max_contracts,
  )
}

///|
/// Result occurrence order comes from the original admitted manifest, not the
/// global contract inventory ordinal. Both coordinates retain their distinct
/// bounded domains and convey no payload access or physical acknowledgement.
fn stored_sdk_payload_coordinates(
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  max_results : Int,
  max_contracts : Int,
) -> Result[(Int, Int), LocalSDKPayloadSelectionIssue] {
  if max_results < 1 ||
    max_results > 16 ||
    max_contracts < 1 ||
    max_contracts > 256 {
    return Err(InvalidLimit)
  }
  match owner.view_count(view) {
    Ok(count) if count <= max_contracts => ()
    _ => return Err(InvalidLimit)
  }
  let selected = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(issue) => return Err(Stored(issue))
  }
  let manifest = match owner.view_contract(view, 2) {
    Ok(value) => value
    Err(_) => return Err(MissingOriginal)
  }
  let names = match @publication.manifest_result_names(manifest) {
    Ok(names) if names.length() <= max_results => names
    _ => return Err(InvalidLimit)
  }
  let mut result = None
  for i = 0; i < names.length(); i = i + 1 {
    if names[i] == result_name {
      result = Some(i)
      break
    }
  }
  for i = 0; i < max_results; i = i + 1 {
    match owner.view_binding(view, i) {
      Ok(binding) if @publication.publication_contract_identity(binding) ==
        selected.read.durable_result_binding_cid => {
        guard result is Some(ordinal) else { return Err(MissingOriginal) }
        return Ok((ordinal, i))
      }
      Ok(_) => ()
      Err(_) => break
    }
  }
  Err(MissingOriginal)
}

///|
/// Pure routing under this same nominal saved source and current read checks.
/// The physical Reader and later original attempt/grant checks remain required.
pub fn local_sdk_saved_result_coordinates(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
) -> Result[(Int, Int), LocalSDKReadOriginalsIssue] {
  guard source.origin is Saved(_) else { return Err(InvalidOriginal) }
  match source.validate_view(owner, view) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match source.validate_current(account, result_name) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  stored_sdk_payload_coordinates(owner, view, result_name, 8, 256).map_err(_ => {
    InvalidOriginal
  })
}
