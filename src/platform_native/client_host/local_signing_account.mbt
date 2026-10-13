///|
/// An adopted key configuration's current Account selection only. This is
/// not opaque private-key custody, a signing grant, Checkpoint authorization
/// or a credential claim. The same existing Host/Account Owners are used.
struct NativeLocalSigningAccountBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  file : NativeLocalSelectedFile
  selection : @credential_resource.NativeLocalSigningKeySelection
  scope : String
  account_id : String
  account_configuration_cid : String
  reviewer : NativeLocalInstalledEffectReviewer?
  kind : @checkpoint.CheckpointKind
}

///|
pub(all) enum NativeLocalSigningAccountIssue {
  SigningUnavailable
  SigningSelection(@credential_resource.NativeLocalSigningKeySelectionIssue)
}

///|
fn NativeLocalSigningAccountBinding::original_current(
  self : NativeLocalSigningAccountBinding,
) -> Bool {
  let (enabled, _, principal, connection, _, _, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    self.selection,
  )
  if !enabled ||
    !@credential_resource.native_local_signing_key_selection_allows_kind(
      self.selection,
      self.kind,
    ) ||
    !(self.host.selected_configuration(self.file.name) is Ok(bytes) &&
    bytes == self.file.body) {
    return false
  }
  if !(self.host.authority_scope_cid(principal, connection, self.crypto)
    is Ok(scope) &&
    scope == self.scope) {
    return false
  }
  self.host.configuration() is Ok(configuration) &&
  configuration.account_id() == self.account_id &&
  configuration.configuration_cid() == self.account_configuration_cid
}

///|
/// Re-evaluate the actual role-specific Account tuple. No cached Allow, Client
/// read scope, verification key or issuer decision is a signing permission.
/// This must additionally be combined with authenticated original key custody
/// and current Checkpoint/request/Run/preimage checks before a use can be claimed.
pub fn NativeLocalSigningAccountBinding::require_current_account(
  self : NativeLocalSigningAccountBinding,
) -> Result[Unit, NativeLocalSigningAccountIssue] {
  if !self.original_current() {
    return Err(SigningUnavailable)
  }
  let (_, purpose, principal, connection, resource, key_id, _, public_key_pem) = @credential_resource.native_local_signing_key_selection_projection(
    self.selection,
  )
  match purpose {
    @credential.ReviewerProof => {
      guard self.reviewer is Some(reviewer) &&
        physical_equal(reviewer.host, self.host) &&
        reviewer.reviewer.principal == principal &&
        reviewer.reviewer.connection == connection &&
        reviewer.reviewer.key_id == key_id &&
        reviewer.reviewer.public_key_pem == public_key_pem &&
        reviewer.current() else {
        return Err(SigningUnavailable)
      }
    }
    @credential.HostAttestation =>
      if self.reviewer is Some(_) ||
        !(self.host.authorize({
          principal,
          connection,
          resource,
          operation: "sign",
        })
        is Ok(@authorization.Allow(_))) {
        return Err(SigningUnavailable)
      }
  }
  // Every decision is surrounded by current physical/configuration checks.
  // A configuration replacement cannot keep this old resource selection alive.
  if !self.original_current() || self.host.check_binding() is Err(_) {
    return Err(SigningUnavailable)
  }
  Ok(())
}

///|
/// Explicit trusted installation assembly selects an already-adopted original
/// configuration. It does not inspect a private-key file, adopt a generation,
/// issue a grant or enable a signer. Default read-only Local has no selection.
/// The Reviewer registration is independent from the original Client caller.
pub fn NativeLocalHostConnection::acquire_signing_key_account(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  configuration_file : String,
  kind : @checkpoint.CheckpointKind,
  reviewer? : NativeLocalInstalledEffectReviewer? = None,
) -> Result[NativeLocalSigningAccountBinding, NativeLocalSigningAccountIssue] {
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == configuration_file)
    is Some(file) &&
    self.selected_configuration(file.name) is Ok(bytes) &&
    bytes == file.body else {
    return Err(SigningUnavailable)
  }
  let wire = @utf8.decode(file.body) catch {
    _ => return Err(SigningUnavailable)
  }
  let selection = match
    @credential_resource.admit_native_local_signing_key_selection(wire) {
    Ok(value) => value
    Err(issue) => return Err(SigningSelection(issue))
  }
  let (_, _, principal, connection, _, _, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    selection,
  )
  let (_, _, _, _, _, _, private_key_file, _) = @credential_resource.native_local_signing_key_selection_projection(
    selection,
  )
  if private_key_file == self.session.source_name ||
    self.session.settings.files.any(file => file.name == private_key_file) {
    return Err(SigningUnavailable)
  }
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(SigningUnavailable)
  }
  let configuration = match self.configuration() {
    Ok(value) => value
    Err(_) => return Err(SigningUnavailable)
  }
  let binding : NativeLocalSigningAccountBinding = {
    host: self,
    crypto,
    file,
    selection,
    scope,
    account_id: configuration.account_id(),
    account_configuration_cid: configuration.configuration_cid(),
    reviewer,
    kind,
  }
  binding.require_current_account().map(_ => binding)
}
