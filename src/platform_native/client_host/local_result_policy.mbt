///|
/// Resolve the committed Artifact's Policy from the original installed Store,
/// then select its retained checked original. This grants no delivery and
/// mutates neither the Run's control revision nor its original custody.
pub fn NativeLocalHostConnection::resolve_result_policy_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  self.resolve_result_policy_original_with_operations(
    crypto, principal, connection, request, store, facts,
  )
}

///|
fn NativeLocalHostConnection::resolve_result_policy_original_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  let reads = operations.map(value => value.reads)
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadResultPolicy(facts.request.result_name),
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if facts.request.principal_id != principal ||
    facts.request.authority_scope_cid != authority.scope {
    return Err(AuthorizationDenied)
  }
  let record = match self.journal.lookup_with_reads(request, true, reads~) {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let definition_cid = @publication.publication_contract_identity(
    record.definition,
  )
  if facts.request.run_definition_cid != definition_cid {
    return Err(ForeignRun)
  }
  let (store_authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  let binding = match
    installed_publication_binding(
      facts.request.namespace_id,
      store_authority,
      device,
      inode,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if record.publication_binding != Some(binding) {
    return Err(ForeignRun)
  }
  let resolved = match
    store.resolve_committed_result(
      facts.request.namespace_id,
      authority.scope,
      definition_cid,
      facts.request.result_name,
      65536,
      8192,
      64,
    ) {
    Ok(Some(value)) => value
    Ok(None) =>
      return Err(
        PublicationObservation(@publication_store.DeliveryAttemptUnresolved),
      )
    Err(issue) => return Err(PublicationObservation(issue))
  }
  if !authority.current_for(self.journal, request) {
    return Err(AuthorizationDenied)
  }
  // Admission facts are observations, not authority. Compare all references
  // with the actual committed projection; never accept a claimed Policy CID.
  if facts.public_index_entry_cid !=
    @publication.publication_contract_identity(resolved.public_index_entry) ||
    facts.result_manifest_cid !=
    @publication.publication_contract_identity(resolved.result_manifest) ||
    facts.result_artifact_cid != resolved.read.result_artifact_cid ||
    facts.result_definition_cid != resolved.read.result_definition_cid ||
    facts.material_generation_cid != resolved.read.material_generation_cid {
    return Err(ForeignRun)
  }
  self.journal.lookup_publication_policy_original(
    request,
    resolved.read.effective_data_policy_cid,
    authority,
    reads~,
  )
}
