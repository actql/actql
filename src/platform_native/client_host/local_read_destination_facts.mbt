///|
// The original Account/Run/Store/checked-Policy join before a destination
// acquires workspace or a file. No destination or read grant is constructed.
fn NativeLocalReadPolicyBinding::prepare_destination_facts(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
) -> Result[
  (@result_access.NativeResultReadFacts, String),
  NativeLocalReadBindingIssue,
] {
  self.result_policy_original = None
  let facts : @result_access.NativeResultReadFacts = {
    request,
    public_index_entry_cid: "",
    result_manifest_cid: "",
    result_artifact_cid: "",
    result_definition_cid: "",
    material_generation_cid: "",
    observed_at,
  }
  match
    self.require_request_selection(original, facts.request, facts.observed_at) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Join the physical Store custody and retained checked Policy before the
  // material workspace. Metadata observation is not a payload read or grant.
  let resolved = match
    store.resolve_committed_result(
      request.namespace_id,
      request.authority_scope_cid,
      request.run_definition_cid,
      request.result_name,
      65536,
      8192,
      64,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  let facts : @result_access.NativeResultReadFacts = {
    ..facts,
    public_index_entry_cid: @publication.publication_contract_identity(
      resolved.public_index_entry,
    ),
    result_manifest_cid: @publication.publication_contract_identity(
      resolved.result_manifest,
    ),
    result_artifact_cid: resolved.read.result_artifact_cid,
    result_definition_cid: resolved.read.result_definition_cid,
    material_generation_cid: resolved.read.material_generation_cid,
  }
  guard self.capture is Some(capture) else { return Err(MaterialUnavailable) }
  let policy = if self.account_purpose is InstalledOriginalResultRead(_, _) {
    // Resolve authorization, Store and Policy first. The sink constructor
    // below will retain its receiver, which delivery must check separately.
    match
      self.resolve_policy_from_snapshot(
        capture,
        original,
        store,
        facts,
        committed_result=Some(resolved),
        before_receiver=true,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    let body = match
      capture.resolve_result_policy_original_in_original_read(
        self.principal,
        self.connection,
        original,
        store,
        facts,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Adoption(issue))
    }
    match self.retain_result_policy_original(original, facts, body) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    body
  }
  match
    self.require_request_selection(original, facts.request, facts.observed_at) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok((facts, @publication.captured_effect_dependency_body_cid(policy)))
}
