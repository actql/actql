///|
/// Private admission metadata for the selected SDK sink. Persisting these
/// originals, current Host/Account checks, grant issuance and usage are distinct
/// gates. A copied wire body cannot acquire the original read handle's custody.
struct LocalSDKReadOriginals {
  request : @host.ClientRequestIdentity
  materials : @publication.ObservedResultReadMaterials
  authorization : (String, String)
  ceiling : (String, String)
  egress : (String, String)
}

///|
pub(all) enum LocalSDKReadOriginalsIssue {
  Preflight(LocalPublicationIntentIssue)
  StoredChain(@publication.ObservedResultReadIssue)
  Projection(@publication.DeliveryIssuanceIssue)
  Codec(@host.ClientLocalReadPreimageIssue)
  InvalidOriginal
  InvalidSelection
  PolicyUnavailable
  Expired
}

///|
fn sdk_read_preimage(
  fields : Array[(String, @host.ClientLocalReadEvidenceValue)],
) -> Result[(String, String), LocalSDKReadOriginalsIssue] {
  @host.encode_client_local_read_preimage(fields)
  .map(wire => (wire, "sha256:" + @sha.hex(@utf8.encode(wire))))
  .map_err(issue => Codec(issue))
}

///|
/// The same original current/selection/Run/adoption binding checks for both
/// read preparation and metadata lookup. Availability is a separate byte gate.
fn validate_sdk_read_original_binding(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  original : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  result_name : String,
  format : String,
  attempt_id : String,
) -> Result[(String, String, String), LocalSDKReadOriginalsIssue] {
  let resource = match source.validate_current(account, result_name) {
    Ok(resource) => resource
    Err(issue) => return Err(issue)
  }
  let (principal, connection, _, _, selected_format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  if !@publication.local_sdk_result_read_selection_accepts_name(
      selection, result_name,
    ) ||
    source.installed_original_result !=
    @publication.local_sdk_result_read_selection_uses_installed_result_authority(
      selection,
    ) ||
    format != selected_format ||
    attempt_id.is_empty() ||
    source.principal_connection().0 != principal ||
    source.principal_connection().1 != connection {
    return Err(InvalidSelection)
  }
  match source.validate_finite_original(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (adoption, read_cid) = match
    @host.client_local_run_policy_original_run_dependencies(
      original,
      source.request(),
      source.definition(),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if adoption != host_adoption_cid ||
    read_cid != @publication.local_sdk_result_read_selection_cid(selection) {
    return Err(InvalidOriginal)
  }
  Ok((adoption, read_cid, resource))
}

///|
/// Select original read evidence through the existing current Account,
/// checked source, saved finite packet and complete stored-chain Owners.
/// No grant, attempt, write, renewal or authority registry is created here.
/// The physical caller still fences actual original custody/current before
/// and after this operation and before adopting/persisting its output.
pub fn prepare_local_sdk_read_originals_for_source(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  original : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
) -> Result[LocalSDKReadOriginals, LocalSDKReadOriginalsIssue] {
  let (adoption, read_cid, resource) = match
    validate_sdk_read_original_binding(
      source, account, original, selection, host_adoption_cid, result_name, format,
      attempt_id,
    ) {
    Err(issue) => return Err(issue)
    Ok(pair) => pair
  }
  let (principal, connection, purpose, _, _, max_bytes, max_uses) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  match source.validate_view(owner, view) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(issue))
  }
  let index = match @publication.project_public_index_read(materials.index) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  // A Saved source in accepted-Run mode already restored the exact admitted
  // policy closure. The finite envelope bounds custody and time; the actual
  // Result policy is selected by that original closure and committed view.
  let accepted_retention = match source.origin {
    Saved(saved) => saved.accepted_retention
    Live(_) => None
  }
  let retention_matches = match accepted_retention {
    Some(retention) =>
      @publication.result_retention_bounds_equal(materials.retention, retention)
    None =>
      @publication.publication_contract_identity(materials.retention) ==
      @publication.publication_contract_identity(
        @host.client_local_run_policy_original_retention(original),
      )
  }
  if index.run_definition_cid !=
    @publication.publication_contract_identity(source.definition()) ||
    index.authority_scope_cid !=
    @host.client_request_authority_scope_cid(source.request()) ||
    index.publication_request_cid != source.publication_request_cid() ||
    !retention_matches {
    return Err(InvalidOriginal)
  }
  guard source.source_policy() is Some(policy) &&
    @publication.captured_effect_dependency_body_cid(policy) ==
    materials.read.effective_data_policy_cid &&
    (if accepted_retention is Some(_) {
      @publication.local_sdk_result_read_selection_uses_accepted_run_policy(
        selection,
      )
    } else {
      @publication.local_sdk_result_read_selection_data_policy_cid(selection) ==
      materials.read.effective_data_policy_cid
    }) else {
    return Err(PolicyUnavailable)
  }
  match
    @publication.result_read_availability(
      materials.manifest,
      result_name,
      materials.retention,
      observed_at,
    ) {
    Err(issue) => return Err(Projection(issue))
    Ok("available") => ()
    Ok(_) => return Err(Expired)
  }
  let expires_at = @host.client_local_run_policy_original_read_expires_at(
    original,
  )
  // Retention availability includes its endpoint; the selected read/grant
  // endpoint is exclusive, as in the original Native read binding. Both
  // timestamps are canonical UTC values validated by the existing Owners.
  if observed_at >= expires_at {
    return Err(Expired)
  }
  let authorization = match
    sdk_read_preimage([
      ("account_configuration_cid", Text(account.configuration_cid())),
      ("adoption_cid", Text(adoption)),
      ("attempt_id", Text(attempt_id)),
      ("authority_scope_cid", Text(index.authority_scope_cid)),
      ("connection", Text(connection)),
      ("decisions", AllowedReadResource(resource)),
      ("domain", Text("python_local_read.authorization_context")),
      ("format", Text(format)),
      (
        "original_request_scope_cid",
        Text(@host.client_request_scope_cid(source.request())),
      ),
      ("principal_id", Text(principal)),
      ("purpose", Text(purpose)),
      ("read_original_cid", Text(read_cid)),
      ("result_name", Text(result_name)),
      ("run_definition_cid", Text(index.run_definition_cid)),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let ceiling = match
    sdk_read_preimage([
      ("data_policy_cids", Texts([materials.read.effective_data_policy_cid])),
      ("domain", Text("python_local_read.data_ceiling")),
      ("expires_at", Text(expires_at)),
      ("max_bytes", Quantity(max_bytes)),
      ("max_uses", Quantity(max_uses)),
      ("read_original_cid", Text(read_cid)),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let egress = match
    sdk_read_preimage([
      ("attempt_id", Text(attempt_id)),
      ("authority_scope_cid", Text(index.authority_scope_cid)),
      ("authorization_context_cid", Text(authorization.1)),
      ("data_ceiling_cid", Text(ceiling.1)),
      ("domain", Text("python_local_read.egress_admission")),
      (
        "effective_data_policy_cid",
        Text(materials.read.effective_data_policy_cid),
      ),
      ("expires_at", Text(expires_at)),
      ("format", Text(format)),
      ("material_generation_cid", Text(materials.read.material_generation_cid)),
      ("max_bytes", Quantity(max_bytes)),
      ("max_uses", Quantity(max_uses)),
      ("principal_id", Text(principal)),
      (
        "public_index_entry_cid",
        Text(@publication.publication_contract_identity(materials.index)),
      ),
      ("purpose", Text(purpose)),
      ("read_original_cid", Text(read_cid)),
      ("result_artifact_cid", Text(materials.read.result_artifact_cid)),
      ("result_definition_cid", Text(materials.read.result_definition_cid)),
      (
        "result_manifest_cid",
        Text(@publication.publication_contract_identity(materials.manifest)),
      ),
      ("result_name", Text(result_name)),
      ("run_definition_cid", Text(index.run_definition_cid)),
      ("sink", Text("sdk-rows")),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Recheck the independent current decisions after all fallible projection.
  match source.validate_current(account, result_name) {
    Err(issue) => Err(issue)
    Ok(current_resource) if current_resource == resource =>
      Ok({
        request: source.request(),
        materials,
        authorization,
        ceiling,
        egress,
      })
    Ok(_) => Err(InvalidSelection)
  }
}

///|
/// One immutable original body/CID pair. This read-only transport projection
/// does not confirm that a Store persisted it or grant permission to disclose.
pub fn local_sdk_read_original(
  original : LocalSDKReadOriginals,
  ordinal : Int,
) -> Result[(String, String), LocalSDKReadOriginalsIssue] {
  match ordinal {
    0 => Ok(original.authorization)
    1 => Ok(original.ceiling)
    2 => Ok(original.egress)
    _ => Err(InvalidOriginal)
  }
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn prepare_local_sdk_read_originals(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  original : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
) -> Result[LocalSDKReadOriginals, LocalSDKReadOriginalsIssue] {
  prepare_local_sdk_read_originals_for_source(
    live_sdk_read_source(preflight, selection~),
    account,
    original,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
  )
}
