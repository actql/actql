///|
/// Observe only the original Run's committed Result names. The opaque ID
/// selection supplies identity, never permission. The existing journal joins
/// its authenticated Submission and Run before this actual Store is inspected.
/// No payload, grant, new attempt, execution or saved state is issued here.
pub fn NativeLocalHostConnection::lookup_original_result_names_json(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[String?, NativeClientRunJournalIssue] {
  self.lookup_original_result_names_json_with_operations(
    crypto, principal, connection, original, store, namespace_id,
  )
}

///|
fn NativeLocalHostConnection::lookup_original_result_names_json_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[String?, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      original.request,
      ReadRunMaterials,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let definition_cid = @publication.publication_contract_identity(
    original.definition,
  )
  if namespace_id.is_empty() || original.scope != authority.scope {
    return Err(ForeignRun)
  }
  // Return only the small binding. Retire the decoded Submission/Run and
  // validation scratch before reading the index and manifest below.
  let original_binding = match
    self.journal.transaction_with_reads(
      () => {
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        let (_, run) = match
          self.journal.saved_run_state_locked(
            original.reference,
            original.request,
            reads~,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if @publication.publication_contract_identity(run.definition) !=
          definition_cid {
          return Err(ForeignRun)
        }
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        Ok(run.publication_binding)
      },
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (store_authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  let binding = match
    installed_publication_binding(namespace_id, store_authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if original_binding != Some(binding) {
    return Err(ForeignRun)
  }
  let names = match
    store.inspect_committed_publication(
      namespace_id,
      authority.scope,
      definition_cid,
      65536,
      8192,
      64,
    ) {
    Ok(None) => None
    Err(issue) => return Err(PublicationObservation(issue))
    Ok(Some(index)) => {
      let projected = match @publication.project_public_index_read(index) {
        Ok(value) => value
        Err(issue) =>
          return Err(PublicationObservation(DeliveryIssuance(issue)))
      }
      let manifest = match
        store.read_publication_contract(
          "result_manifest",
          projected.result_manifest_cid,
        ) {
        Ok(value) => value
        Err(issue) => return Err(PublicationObservation(issue))
      }
      match
        @publication.public_index_manifest_result_names_json(
          index, manifest, 65536, 8192, 64,
        ) {
        Ok(value) => Some(value)
        Err(issue) =>
          return Err(PublicationObservation(DeliveryIssuance(issue)))
      }
    }
  }
  if !authority.current_for(self.journal, original.request) {
    return Err(AuthorizationDenied)
  }
  Ok(names)
}
