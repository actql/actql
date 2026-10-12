///|
pub(all) enum NativeLocalPreparationTransportIssue {
  Preparation(NativeLocalSalesforcePreparationIssue)
  Resource(@credential_resource.NativeCredentialResourceIssue)
}

///|
// Assembly of borrowed existing Owners, not a new send/response state machine.
// The acknowledgement is live Work material; an identity-only reference cannot
// construct this connection. It does not represent post-closure recovery.
struct NativeLocalPreparationTransport {
  acknowledgement : NativeLocalPreparationGrantAcknowledgement
  service : @credential_resource.NativeCredentialResourceService
  store : @publication_store.Store
  namespace_id : String
  store_binding : String
}

///|
fn NativeLocalPreparationGrantOperation::original_raw_store_binding(
  self : NativeLocalPreparationGrantOperation,
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[String, NativeLocalSalesforcePreparationIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let record = match
    self.provider.host.journal.lookup(self.original.request, true) {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
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
  if record.publication_binding != Some(binding) {
    return Err(Journal(ForeignRun))
  }
  self.require_current().map(_ => binding)
}

///|
// A private crypto derivation, not a public grant or identity domain. Use the
// already authenticated epoch key and original adoption/Store binding. Missing
// custody never creates a replacement key. The AES key is never disclosed.
fn local_preparation_raw_key_preimage(
  adoption_cid : String,
  store_binding : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_adoption_record([
    ("adoption_cid", adoption_cid),
    ("domain", "actql-native-local-preparation-raw-key/0.1"),
    ("store_binding", store_binding),
  ])
}

///|
fn NativeLocalPreparationGrantOperation::original_raw_store_key(
  self : NativeLocalPreparationGrantOperation,
  binding : String,
) -> Result[Bytes, NativeLocalSalesforcePreparationIssue] {
  let preimage = match
    local_preparation_raw_key_preimage(self.provider.host.adoption_cid, binding) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  let key = self.provider.host.journal.transaction(() => {
    match self.require_current_locked() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let (epoch_key, _, _) = match
      read_epoch_custody(self.provider.host.database) {
      Ok(value) => value
      Err(issue) => return Err(Epoch(issue))
    }
    self.provider.crypto
    .hmac_sha256(epoch_key, preimage)
    .map_err(issue => Epoch(Crypto(issue)))
  })
  match key {
    Err(issue) => Err(Journal(issue))
    Ok(value) => self.require_current().map(_ => value)
  }
}

///|
fn NativeLocalPreparationTransport::require_store(
  self : NativeLocalPreparationTransport,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match
    self.acknowledgement.operation.original_raw_store_binding(
      self.store,
      self.namespace_id,
    ) {
    Ok(value) if value == self.store_binding => Ok(())
    Ok(_) => Err(Journal(CustodyLost))
    Err(issue) => Err(issue)
  }
}

///|
fn NativeLocalPreparationTransport::require_send(
  self : NativeLocalPreparationTransport,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.acknowledgement.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.require_store() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.acknowledgement.require_current()
}

///|
fn NativeLocalPreparationTransport::require_read(
  self : NativeLocalPreparationTransport,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.acknowledgement.operation.require_raw_read() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.require_store() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.acknowledgement.operation.require_raw_read()
}

///|
/// Connect an explicitly acknowledged original to the existing credential-use
/// journal and the Run's original installed Store. Restore only authenticated
/// installation material. This neither issues a grant, adopts a new file/Store,
/// claims a use, reserves response capacity nor enters the Provider.
pub fn NativeLocalPreparationGrantAcknowledgement::open_preparation_transport(
  self : NativeLocalPreparationGrantAcknowledgement,
  client : @http.Client,
  store : @publication_store.Store,
  namespace_id : String,
  installation_setting : String,
) -> Result[
  NativeLocalPreparationTransport,
  NativeLocalPreparationTransportIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Preparation(issue))
  }
  let operation = self.operation
  let installation = match
    operation.provider.restore_credential_installation(
      operation.target,
      installation_setting,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let binding = match
    operation.original_raw_store_binding(store, namespace_id) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let key = match operation.original_raw_store_key(binding) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let raw = match
    @credential_resource.bind_native_local_preparation_raw_store(
      store,
      operation.provider.crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let authorize = (
    facts : @credential_resource.NativeLocalPreparationCredentialAuthorization,
  ) => {
    let permitted = match facts.stage {
      "claim" | "send" => self.authorize_credential_request(facts)
      _ => operation.authorize_raw_read(facts)
    }
    if permitted is Err(_) {
      return false
    }
    // Recheck the original Store after authorization callbacks. This cannot
    // silently rebind a changed Store to the same original grant/use.
    operation.original_raw_store_binding(store, namespace_id) is Ok(current) &&
    current == binding
  }
  let service = match
    @credential_resource.install_native_local_preparation_credential_resource_service(
      operation.provider.host.database,
      client,
      [installation],
      authorize,
      raw_store=Some(raw),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let transport : NativeLocalPreparationTransport = {
    acknowledgement: self,
    service,
    store,
    namespace_id,
    store_binding: binding,
  }
  transport
  .require_send()
  .map(_ => transport)
  .map_err(issue => Preparation(issue))
}

///|
/// Explicit original use only. The existing credential Owner persists claim,
/// prefunds descriptor/raw bytes, fences physical entry and retains the response
/// before terminal ACK. Repetition refuses a retained claim; it never resends.
pub fn NativeLocalPreparationTransport::observe(
  self : NativeLocalPreparationTransport,
  use_id : String,
) -> Result[
  @credential_resource.NativeCredentialResponse,
  NativeLocalPreparationTransportIssue,
] {
  match self.require_send() {
    Ok(_) => ()
    Err(issue) => return Err(Preparation(issue))
  }
  guard self.acknowledgement.operation.original.grant is PreparationGrant(grant) else {
    return Err(Preparation(ForeignInstallation))
  }
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  @credential_resource.call_native_local_preparation_credential_resource_guarded_request_at_path(
    self.service,
    grant,
    use_id,
    scope,
    scope.request_path,
    () => self.require_send() is Ok(_),
  ).map_err(issue => Resource(issue))
}

///|
/// Read the same original use/response under current read authority. No issuer
/// issue permission is borrowed for disclosure, and no absent or unknown record
/// is repaired by another use, GET, grant or terminal outcome.
pub fn NativeLocalPreparationTransport::lookup_raw_observation(
  self : NativeLocalPreparationTransport,
  use_id : String,
) -> Result[
  @credential_resource.NativeLocalPreparationRawRecovery,
  NativeLocalPreparationTransportIssue,
] {
  match self.require_read() {
    Ok(_) => ()
    Err(issue) => return Err(Preparation(issue))
  }
  guard self.acknowledgement.operation.original.grant is PreparationGrant(grant) else {
    return Err(Preparation(ForeignInstallation))
  }
  @credential_resource.query_native_local_preparation_raw_observation(
    self.service,
    grant,
    use_id,
    @credential.local_preparation_credential_grant_scope(grant),
    () => self.require_read() is Ok(_),
  ).map_err(issue => Resource(issue))
}
