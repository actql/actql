///|
// Read-only original metadata and its existing concrete current/read subjects.
// This is not a publisher, receipt issuer, resource Owner or reusable Allow.
struct NativeLocalRetainedRunReceipt {
  host : NativeLocalHostConnection
  capture : NativeLocalJournalCapture
  authority : NativeLocalPolicyAuthority
  request : @host.ClientRequestIdentity
  store : @publication_store.Store
  namespace_id : String
  store_binding : String
  receipt : @publication.PublicationContract
  path : String
  parent : String
  name : String
}

///|
/// Exact already-admitted immutable DATA from this observation. Current export
/// was checked by its constructor; a later external write requires the same
/// observation's final current check. This getter grants no new permission.
pub fn NativeLocalRetainedRunReceipt::original_receipt(
  self : NativeLocalRetainedRunReceipt,
) -> @publication.PublicationContract {
  self.receipt
}

///|
// Keep path meanings with the same receipt-export Owner for fresh and retained
// observations. This pure check supplies no current decision or filesystem ACK.
fn native_local_receipt_export_path(
  state_path : String,
  path : String,
  parent : String,
  name : String,
) -> Bool {
  local_read_file_location(path, parent, name) &&
  !local_read_file_inside(path, state_path)
}

///|
fn native_local_receipt_export_managed_path(
  capture : NativeLocalJournalCapture,
  path : String,
) -> Result[Unit, NativeLocalObservedRunStateIssue] {
  match capture.managed_root_path_in_original_read() {
    Ok(Some(directory)) if local_read_file_inside(path, directory) =>
      Err(ForeignOriginal)
    Ok(_) => Ok(())
    Err(_) => Err(OriginalUnavailable)
  }
}

///|
/// Check the same retained path, actual original Store and independent current
/// RunRead after external export. It neither reissues nor rereads the receipt,
/// retries a Writer, reopens a Store or acknowledges physical release.
pub fn NativeLocalRetainedRunReceipt::check_current_export(
  self : NativeLocalRetainedRunReceipt,
) -> Result[Unit, NativeLocalObservedRunStateIssue] {
  if !native_local_receipt_export_path(
      self.host.session.state_path,
      self.path,
      self.parent,
      self.name,
    ) {
    return Err(ForeignOriginal)
  }
  if !self.authority.current_for(self.host.journal, self.request) {
    return Err(AuthorizationDenied)
  }
  match native_local_receipt_export_managed_path(self.capture, self.path) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (store_authority, device, inode) = match self.store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  match
    installed_publication_binding(
      self.namespace_id,
      store_authority,
      device,
      inode,
    ) {
    Ok(binding) if binding == self.store_binding => ()
    _ => return Err(ForeignOriginal)
  }
  if !self.authority.current_for(self.host.journal, self.request) {
    return Err(AuthorizationDenied)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::observe_retained_run_receipt_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  path : String,
  parent : String,
  name : String,
  operations : NativeClientJournalOperationAccess,
  capture : NativeLocalJournalCapture,
) -> Result[NativeLocalRetainedRunReceipt, NativeLocalObservedRunStateIssue] {
  if !native_local_receipt_export_path(
      self.session.state_path,
      path,
      parent,
      name,
    ) {
    return Err(ForeignOriginal)
  }
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      original.request,
      ReadRunMaterials,
      capture=Some(capture),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if namespace_id.is_empty() || original.scope != authority.scope {
    return Err(ForeignOriginal)
  }
  let definition = original.definition
  // The Journal restores the same authenticated Submission, Run and immutable
  // Manifest. No current Program, new compilation or Publisher is constructed.
  let (binding, manifest) = match
    self.journal.transaction_with_reads(
      () => {
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        let (record, run) = match
          self.journal.saved_run_state_locked(
            original.reference,
            original.request,
            reads=Some(operations.reads),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if @publication.publication_contract_identity(run.definition) !=
          @publication.publication_contract_identity(definition) {
          return Err(ForeignRun)
        }
        guard run.publication_binding is Some(binding) &&
          record.restored_state_original is Some((_, state)) else {
          return Err(CustodyLost)
        }
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        Ok((binding, state.original_manifest()))
      },
      reads=Some(operations.reads),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let (store_authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  match
    installed_publication_binding(namespace_id, store_authority, device, inode) {
    Ok(actual) if actual == binding => ()
    _ => return Err(ForeignOriginal)
  }
  let index = match
    store.inspect_committed_publication(
      namespace_id,
      authority.scope,
      @publication.publication_contract_identity(definition),
      65536,
      8192,
      64,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(OriginalUnavailable)
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  let (receipt_cid, _) = match
    @publication.public_index_run_observation_cids(index) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  let receipt = match
    store.read_publication_contract("run_receipt", receipt_cid) {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  if @publication.check_original_stored_run_receipt_references(
      index, definition, manifest, receipt,
    )
    is Err(_) {
    return Err(Journal(CustodyLost))
  }
  let observed : NativeLocalRetainedRunReceipt = {
    host: self,
    capture,
    authority,
    request: original.request,
    store,
    namespace_id,
    store_binding: binding,
    receipt,
    path,
    parent,
    name,
  }
  match observed.check_current_export() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(observed)
}

///|
/// Observe an existing original receipt through this SAME Read/Journal/Store.
/// The nested Result preserves the observation Owner's typed refusal; neither
/// result is a new publication, read grant or cleanup acknowledgement.
pub fn NativeLocalJournalCapture::observe_retained_run_receipt_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  path : String,
  parent : String,
  name : String,
) -> Result[
  Result[NativeLocalRetainedRunReceipt, NativeLocalObservedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    Ok(
      host.observe_retained_run_receipt_with_operations(
        self.crypto,
        principal,
        connection,
        original,
        store,
        namespace_id,
        path,
        parent,
        name,
        operations,
        self,
      ),
    )
  })
}
