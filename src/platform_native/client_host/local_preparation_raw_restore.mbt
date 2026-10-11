///|
pub(all) enum NativeLocalPreparationRawReadIssue {
  UnavailableOriginalGrant
  UnavailableOriginalTarget
  Preparation(NativeLocalSalesforcePreparationIssue)
  Journal(NativeClientRunJournalIssue)
  Resource(@credential_resource.NativeCredentialResourceIssue)
}

///|
// A borrowed authorization/custody connection, not a new recovery Owner.
// No live Work, grant issuer, HTTP client or secret installation is retained.
priv struct NativeLocalPreparationRawReadBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  principal : String
  connection : String
  reference : NativeLocalPreparationGrantReference
  target : NativeLocalPreparationOriginalTarget
  store : @publication_store.Store
  namespace_id : String
  store_binding : String
}

///|
struct NativeLocalPreparationRawReader {
  binding : NativeLocalPreparationRawReadBinding
  lookup : @credential_resource.NativeLocalPreparationRawLookup
}

///|
// Caller holds the existing original journal transaction. Current Account
// authorization is separate from the saved grant's identity or issue rights.
fn NativeLocalHostConnection::original_preparation_raw_target_locked(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeLocalPreparationGrantReference,
) -> Result[
  NativeLocalPreparationOriginalTarget,
  NativeLocalPreparationRawReadIssue,
] {
  match
    self.preparation_grant_lookup_current(
      crypto, principal, connection, reference,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Preparation(issue))
  }
  match self.lookup_local_grant_original_locked(crypto, reference.original) {
    Ok(Some(_)) => ()
    Ok(None) => return Err(UnavailableOriginalGrant)
    Err(issue) => return Err(Journal(issue))
  }
  let target = match
    self.lookup_preparation_target_original_locked(crypto, reference.original) {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnavailableOriginalTarget)
    Err(issue) => return Err(Journal(issue))
  }
  if !(self.authorize({
      principal,
      connection,
      resource: target.resource,
      operation: "read",
    })
    is Ok(@authorization.Allow(_))) {
    return Err(Preparation(AuthorizationDenied))
  }
  // Authorization can observe changing policy. Recheck original Host/config
  // custody and the original Run read after that independent observation.
  self
  .preparation_grant_lookup_current(crypto, principal, connection, reference)
  .map(_ => target)
  .map_err(issue => Preparation(issue))
}

///|
fn NativeLocalPreparationRawReadBinding::require_current_locked(
  self : NativeLocalPreparationRawReadBinding,
) -> Result[Unit, NativeLocalPreparationRawReadIssue] {
  let target = match
    self.host.original_preparation_raw_target_locked(
      self.crypto,
      self.principal,
      self.connection,
      self.reference,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if target.resource != self.target.resource ||
    target.provider_file_name != self.target.provider_file_name ||
    target.provider_selection_cid != self.target.provider_selection_cid {
    return Err(Journal(ChangedIntent))
  }
  let record = match
    self.host.journal.retained(self.reference.original.request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnavailableOriginalGrant)
    Err(issue) => return Err(Journal(issue))
  }
  let (authority, device, inode) = match self.store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  let binding = match
    installed_publication_binding(self.namespace_id, authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if binding != self.store_binding ||
    record.publication_binding != Some(binding) {
    return Err(Journal(ForeignRun))
  }
  self.host
  .preparation_grant_lookup_current(
    self.crypto,
    self.principal,
    self.connection,
    self.reference,
  )
  .map_err(issue => Preparation(issue))
}

///|
fn[T] NativeLocalHostConnection::preparation_raw_read_transaction(
  self : NativeLocalHostConnection,
  action : () -> Result[T, NativeLocalPreparationRawReadIssue],
) -> Result[T, NativeLocalPreparationRawReadIssue] {
  let mut read_issue : NativeLocalPreparationRawReadIssue? = None
  let result = self.journal.transaction(() => {
    match action() {
      Ok(value) => Ok(value)
      Err(issue) => {
        read_issue = Some(issue)
        Err(AuthorizationDenied)
      }
    }
  })
  // A lost transaction ACK dominates a callback refusal, not the reverse.
  match result {
    Ok(value) => Ok(value)
    Err(TransactionUnknown) => Err(Journal(TransactionUnknown))
    Err(issue) => Err(read_issue.unwrap_or(Journal(issue)))
  }
}

///|
fn NativeLocalPreparationRawReadBinding::require_current(
  self : NativeLocalPreparationRawReadBinding,
) -> Result[Unit, NativeLocalPreparationRawReadIssue] {
  self.host.preparation_raw_read_transaction(() => self.require_current_locked())
}

///|
// The typed credential callback verifies the original request facts only after
// the current original Run/target/Store checks. It grants no issue/send rights.
fn NativeLocalPreparationRawReadBinding::authorize(
  self : NativeLocalPreparationRawReadBinding,
  facts : @credential_resource.NativeLocalPreparationCredentialAuthorization,
) -> Bool {
  guard self.reference.original.grant is PreparationGrant(grant) else {
    return false
  }
  self.require_current() is Ok(_) &&
  local_preparation_raw_request_matches(grant, facts) &&
  self.require_current() is Ok(_)
}

///|
/// Reconnect original raw observations after Work/process closure using the
/// existing credential read-only seam. Missing target is unavailable; this
/// does not install a transport, acquire a secret, issue a grant or open a send.
pub fn NativeLocalHostConnection::restore_preparation_raw_reader(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeLocalPreparationGrantReference,
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[NativeLocalPreparationRawReader, NativeLocalPreparationRawReadIssue] {
  let admitted = self.preparation_raw_read_transaction(() => {
    let target = match
      self.original_preparation_raw_target_locked(
        crypto, principal, connection, reference,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (authority, device, inode) = match store.custody_location() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    let binding = match
      installed_publication_binding(namespace_id, authority, device, inode) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    let context : NativeLocalPreparationRawReadBinding = {
      host: self,
      crypto,
      principal,
      connection,
      reference,
      target,
      store,
      namespace_id,
      store_binding: binding,
    }
    match context.require_current_locked() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let key = match
      local_preparation_raw_key_preimage(self.adoption_cid, binding) {
      Ok(value) => value
      Err(_) => return Err(Journal(Encoding))
    }
    let (epoch_key, _, _) = match read_epoch_custody(self.database) {
      Ok(value) => value
      Err(issue) => return Err(Journal(Epoch(issue)))
    }
    self.epoch.crypto
    .hmac_sha256(epoch_key, key)
    .map(key => (context, key))
    .map_err(issue => Journal(Epoch(Crypto(issue))))
  })
  let (binding, key) = match admitted {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard reference.original.grant is PreparationGrant(grant) else {
    return Err(Journal(ForeignRun))
  }
  let raw = match
    @credential_resource.bind_native_local_preparation_raw_store(
      store, crypto, key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let lookup = match
    @credential_resource.bind_native_local_preparation_raw_lookup(
      self.database,
      raw,
      grant,
      @credential.local_preparation_credential_grant_scope(grant),
      facts => binding.authorize(facts),
      () => binding.require_current() is Ok(_),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  binding.require_current().map(_ => { binding, lookup, })
}

///|
/// Repeated lookup consumes no grant use or Provider call and does not convert
/// a claimed/unknown use into success. The original credential/Store Owner
/// verifies use, outcome, raw descriptor/body, revocation and retention.
pub fn NativeLocalPreparationRawReader::lookup(
  self : NativeLocalPreparationRawReader,
  use_id : String,
) -> Result[
  @credential_resource.NativeLocalPreparationRawRecovery,
  NativeLocalPreparationRawReadIssue,
] {
  match self.binding.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = match self.lookup.lookup(use_id) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  self.binding.require_current().map(_ => result)
}
