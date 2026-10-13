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
/// Select original read evidence through the existing current Account,
/// checked preflight, saved finite packet and complete stored-chain Owners.
/// No grant, attempt, write, renewal or authority registry is created here.
/// The physical caller still fences actual original custody/current before
/// and after this operation and before adopting/persisting its output.
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
  match
    validate_local_preflight_result_read_current(
      preflight, account, result_name,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Preflight(issue))
  }
  let (
    principal,
    connection,
    purpose,
    name,
    selected_format,
    max_bytes,
    max_uses,
  ) = @publication.local_sdk_result_read_selection_parameters(selection)
  let plan = preflight.intent.plan
  if result_name != name ||
    format != selected_format ||
    attempt_id.is_empty() ||
    plan.tuple.principal != principal ||
    plan.tuple.connection != connection {
    return Err(InvalidSelection)
  }
  if @host.validate_client_local_run_policy_original_run(
      @host.client_local_run_policy_original_body(original),
      plan.request,
      plan.definition,
    )
    is Err(_) {
    return Err(InvalidOriginal)
  }
  let (adoption, read_cid) = match
    @host.client_local_run_policy_original_read_dependencies(original) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if adoption != host_adoption_cid ||
    read_cid != @publication.local_sdk_result_read_selection_cid(selection) {
    return Err(InvalidOriginal)
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
  if index.run_definition_cid !=
    @publication.publication_contract_identity(plan.definition) ||
    index.authority_scope_cid !=
    @host.client_request_authority_scope_cid(plan.request) ||
    index.publication_request_cid !=
    @publication.publication_contract_identity(preflight.intent.request) ||
    @publication.publication_contract_identity(materials.retention) !=
    @publication.publication_contract_identity(
      @host.client_local_run_policy_original_retention(original),
    ) {
    return Err(InvalidOriginal)
  }
  guard @host.client_compiled_run_source_free_result_policy_body(plan.compiled)
    is Some(policy) &&
    @publication.captured_effect_dependency_body_cid(policy) ==
    materials.read.effective_data_policy_cid &&
    @publication.local_sdk_result_read_selection_data_policy_cid(selection) ==
    materials.read.effective_data_policy_cid else {
    // The initial supplier is explicitly Source-free. Other profiles must
    // resolve their real retained Policy bodies through their existing Owners.
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
      ("decisions", AllowedReads(result_name)),
      ("domain", Text("python_local_read.authorization_context")),
      ("format", Text(format)),
      (
        "original_request_scope_cid",
        Text(@host.client_request_scope_cid(plan.request)),
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
  match
    validate_local_preflight_result_read_current(
      preflight, account, result_name,
    ) {
    Err(issue) => Err(Preflight(issue))
    Ok(_) =>
      Ok({ request: plan.request, materials, authorization, ceiling, egress, })
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
