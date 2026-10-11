///|
// Prepared material for one explicit issuance/adoption intent. Construction
// authorizes no issuance and writes no journal row. Initial adoption is never
// edited to include these later grant bytes or their identity.
struct NativeLocalPreparationGrantOperation {
  provider : NativeLocalSalesforcePreparationBinding
  target : NativeClientLocalPreparationTarget
  issuer_file : NativeLocalSelectedFile
  original : NativeLocalGrantOriginal
}

///|
// Issued only after the original immutable journal transaction and a final
// current check. It is not a physical-use receipt, response or write approval.
struct NativeLocalPreparationGrantAcknowledgement {
  operation : NativeLocalPreparationGrantOperation
  issuer : NativeLocalCredentialIssuerBinding
}

///|
fn NativeLocalPreparationGrantOperation::require_current(
  self : NativeLocalPreparationGrantOperation,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.provider.require_target(self.target) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let selected = match
    self.provider.host.selected_configuration(self.issuer_file.name) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if selected != self.issuer_file.body ||
    self.original.issuer_selection_cid != self.issuer_file.content_cid {
    return Err(ForeignInstallation)
  }
  guard self.original.grant is PreparationGrant(grant) else {
    return Err(ForeignInstallation)
  }
  let expected_scope = match
    self.target.credential_scope(
      @credential.local_preparation_credential_grant_scope(grant).attempt_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Target(issue))
  }
  if expected_scope !=
    @credential.local_preparation_credential_grant_scope(grant) ||
    !(@host.client_request_identity_relation(
      self.original.request,
      self.target.fence.work.request,
    )
    is @host.SameRequest) {
    return Err(ForeignInstallation)
  }
  self.provider.require_target(self.target)
}

///|
/// Prepare exact bounded material from the live original target and explicitly
/// selected issuer original. This does not issue or adopt a grant. The caller
/// must invoke the distinct authorized adoption operation explicitly.
pub fn NativeLocalSalesforcePreparationBinding::prepare_grant_operation(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
  issuer_file_name : String,
  operation_id : String,
  attempt_id : String,
) -> Result[
  NativeLocalPreparationGrantOperation,
  NativeLocalSalesforcePreparationIssue,
] {
  match self.require_target(target) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.host.session.settings.files
    .iter()
    .find_first(file => file.name == issuer_file_name)
    is Some(issuer_file) else {
    return Err(ForeignInstallation)
  }
  let wire = @utf8.decode(issuer_file.body) catch {
    _ => return Err(InvalidSelection)
  }
  let selection = match admit_native_local_credential_issuer_selection(wire) {
    Ok(value) => value
    Err(issue) => return Err(Issuer(issue))
  }
  if selection.principal != self.principal ||
    selection.connection != self.connection {
    return Err(ForeignInstallation)
  }
  if !selection.enabled {
    return Err(Issuer(Disabled))
  }
  let scope = match target.credential_scope(attempt_id) {
    Ok(value) => value
    Err(issue) => return Err(Target(issue))
  }
  let grant = match
    @credential.prepare_local_preparation_credential_grant(
      selection.issuer_authority,
      scope,
      @values.timestamp_epoch_milliseconds(selection.expires_at).unwrap(),
      selection.max_uses,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  let original = match
    local_preparation_grant_original(
      self.crypto,
      operation_id,
      target.fence.work.request,
      issuer_file.content_cid,
      grant,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let operation : NativeLocalPreparationGrantOperation = {
    provider: self,
    target,
    issuer_file,
    original,
  }
  operation.require_current().map(_ => operation)
}

///|
/// Stable original operation identity for response-loss lookup. Reading it
/// does not acquire authority, append a grant, claim a use or recreate Work.
pub fn NativeLocalPreparationGrantOperation::operation_cid(
  self : NativeLocalPreparationGrantOperation,
) -> String {
  self.original.operation_cid
}

///|
// Current read/installation checks inside the existing journal lock use its
// established read projection, never a nested write or a second transaction.
fn NativeLocalPreparationGrantOperation::require_current_locked(
  self : NativeLocalPreparationGrantOperation,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let journal = self.provider.host.journal
  let before = journal.publication_read_locked
  journal.publication_read_locked = true
  let outcome = self.require_current()
  journal.publication_read_locked = before
  outcome.map_err(_ => AuthorizationDenied)
}

///|
/// Explicit authorized Host adoption after successful original preparation.
/// Reuse the selected issuer's independent Account decision, exact grant bytes
/// and same immutable append/capacity transaction. No submit/approve/resume
/// entrypoint calls this implicitly, and an unknown commit issues no ACK.
pub fn NativeLocalSalesforcePreparationBinding::adopt_grant_operation(
  self : NativeLocalSalesforcePreparationBinding,
  operation : NativeLocalPreparationGrantOperation,
) -> Result[
  NativeLocalPreparationGrantAcknowledgement,
  NativeLocalSalesforcePreparationIssue,
] {
  if !physical_equal(self, operation.provider) {
    return Err(ForeignInstallation)
  }
  match operation.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let issuer = match
    self.host.acquire_credential_issuer(
      self.crypto,
      operation.issuer_file.name,
      self.principal,
      self.connection,
      operation.original.operation_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Issuer(issue))
  }
  match operation.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match issuer.retain_preparation_grant_original(operation) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let acknowledgement : NativeLocalPreparationGrantAcknowledgement = {
    operation,
    issuer,
  }
  acknowledgement.require_current().map(_ => acknowledgement)
}

///|
fn NativeLocalPreparationGrantAcknowledgement::require_current(
  self : NativeLocalPreparationGrantAcknowledgement,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.operation.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    self.issuer.require_current(
      self.operation.provider.host,
      self.operation.original.operation_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Issuer(issue))
  }
  // Confirm exact committed custody and reservation before returning any grant
  // material. Missing/unknown originals remain refusal, never reissuance.
  match self.issuer.lookup_grant_original(self.operation.original) {
    Ok(Some(original)) if original.intent == self.operation.original.intent &&
      original.operation_cid == self.operation.original.operation_cid => ()
    Ok(_) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  match
    self.operation.provider.host.journal.transaction(() => {
      self.operation.require_original_target_locked()
    }) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  self.operation.require_current()
}

///|
/// Read an acknowledged original grant for trusted transport assembly. Its
/// Work, read, issuer, custody and installation are still independently current;
/// Provider entry must additionally check its original use and secret binding.
pub fn NativeLocalPreparationGrantAcknowledgement::grant(
  self : NativeLocalPreparationGrantAcknowledgement,
) -> Result[
  @credential.LocalPreparationCredentialGrant,
  NativeLocalSalesforcePreparationIssue,
] {
  self
  .require_current()
  .map(_ => {
    match self.operation.original.grant {
      PreparationGrant(value) => value
      _ => abort("checked Preparation acknowledgement required")
    }
  })
}
