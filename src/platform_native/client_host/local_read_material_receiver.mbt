///|
/// Admit the actual same-Store material workspace after current independent
/// Account and selected Material policy checks. The resulting opaque receiver
/// still cannot open a payload without the ordinary read admission/session.
pub fn NativeLocalReadPolicyBinding::prepare_material_receiver(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  request : @result_access.NativeResultAccessRequest,
  receiver_cid : String,
  observed_at : String,
  max_rows : Int,
  max_row_bytes : Int,
  max_fields : Int,
  chunk_bytes : Int,
) -> Result[
  @result_access.NativeResultMaterialReceiver,
  NativeLocalReadBindingIssue,
] {
  if self.selection.sink != Material ||
    self.selection.purpose != "cli-table" ||
    self.material_receiver is Some(_) ||
    self.material_original is Some(_) ||
    self.selection.max_uses != 1 {
    return Err(MaterialUnavailable)
  }
  let facts : @result_access.NativeResultReadFacts = {
    request,
    public_index_entry_cid: "",
    result_manifest_cid: "",
    result_artifact_cid: "",
    result_definition_cid: "",
    material_generation_cid: "",
    observed_at,
  }
  match self.require_request_selection(original, facts) {
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
  let policy = match
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
  if !self.selection.data_policy_cids.contains(
      @publication.captured_effect_dependency_body_cid(policy),
    ) {
    return Err(PolicyNotSelected)
  }
  match self.require_request_selection(original, facts) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let receiver = match
    @result_access.prepare_native_result_material_receiver(
      store,
      request,
      receiver_cid,
      self.selection.max_bytes,
      max_rows,
      max_row_bytes,
      max_fields,
      chunk_bytes,
      8192,
      64,
      self.selection.data_policy_cids,
    ) {
    Ok(value) => value
    Err(_) => return Err(MaterialUnavailable)
  }
  // Retain before the final fallible current check. No replacement workspace
  // or read attempt is constructed by a failed return or cleanup retry.
  self.material_receiver = Some(receiver)
  let identity = receiver.identity()
  self.material_original = Some({
    receiver_cid: identity.receiver_cid,
    result_schema_cid: identity.result_schema_cid,
    ordering_evidence_cid: identity.ordering_evidence_cid,
  })
  self.require_request(original, facts).map(_ => receiver)
}
