///|
/// An explicit current Account selection for the original initialized Host
/// key. This view owns no key, grant or permission. Its resource is selected
/// by trusted installation assembly, never inferred from Client Read or Resolve.
struct NativeLocalInitialHostSigningAccount {
  original : NativeLocalInitialHostSigningOriginal
  installed : NativeLocalInstalledEffectReviewer
  principal : String
  connection : String
  resource : String
  authority_scope_cid : String
}

///|
pub fn NativeLocalHostConnection::acquire_initial_host_signing_account(
  self : NativeLocalHostConnection,
  original : NativeLocalInitialHostSigningOriginal,
  installed : NativeLocalInstalledEffectReviewer,
  principal : String,
  connection : String,
  resource : String,
) -> Result[
  NativeLocalInitialHostSigningAccount,
  NativeLocalSigningAccountIssue,
] {
  if principal.is_empty() ||
    principal.length() > 256 ||
    principal.contains("\u{0}") ||
    connection.is_empty() ||
    connection.length() > 256 ||
    connection.contains("\u{0}") ||
    resource.is_empty() ||
    resource.length() > 256 ||
    resource.contains("\u{0}") ||
    !physical_equal(self, original.reviewer.host) ||
    !physical_equal(self, installed.host) {
    return Err(SigningUnavailable)
  }
  if original.signing_subject is Some(subject) &&
    subject != (principal, connection, resource) {
    return Err(SigningUnavailable)
  }
  let authority_scope_cid = match
    original.reviewer.authority_scope_cid(principal, connection) {
    Ok(value) => value
    Err(_) => return Err(SigningUnavailable)
  }
  let account : NativeLocalInitialHostSigningAccount = {
    original,
    installed,
    principal,
    connection,
    resource,
    authority_scope_cid,
  }
  account.require_current_account().map(_ => account)
}

///|
/// Role-specific actual Sign authorization, surrounded by the same physical
/// original/configuration checks. Read and Resolve do not substitute for it.
pub fn NativeLocalInitialHostSigningAccount::require_current_account(
  self : NativeLocalInitialHostSigningAccount,
) -> Result[Unit, NativeLocalSigningAccountIssue] {
  guard self.installed.initial_original is Some(reviewer) &&
    reviewer.control_body == self.original.reviewer.control_body &&
    reviewer.exported == self.original.reviewer.exported &&
    self.installed.current() &&
    self.original.require_current() is Ok(_) &&
    self.original.reviewer.authority_scope_cid(self.principal, self.connection)
    is Ok(scope) &&
    scope == self.authority_scope_cid else {
    return Err(SigningUnavailable)
  }
  if !(self.original.reviewer.authorize({
      principal: self.principal,
      connection: self.connection,
      resource: self.resource,
      operation: "sign",
    })
    is Ok(@authorization.Allow(_))) {
    return Err(SigningUnavailable)
  }
  guard self.installed.current() &&
    self.original.require_current() is Ok(_) &&
    self.original.reviewer.authority_scope_cid(self.principal, self.connection)
    is Ok(scope) &&
    scope == self.authority_scope_cid else {
    return Err(SigningUnavailable)
  }
  Ok(())
}

///|
fn NativeLocalInitialHostSigningAccount::require_signing_scope(
  self : NativeLocalInitialHostSigningAccount,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeClientRunJournalIssue] {
  match self.require_current_account() {
    Err(_) => return Err(AuthorizationDenied)
    Ok(_) => ()
  }
  self.require_signing_scope_after_current(scope)
}

///|
// Private continuation of this SAME account observation. The caller may share
// it only across noncallback subject/field comparisons, never a TX or IO cut.
fn NativeLocalInitialHostSigningAccount::require_signing_scope_after_current(
  self : NativeLocalInitialHostSigningAccount,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let host = self.original.reviewer.host
  guard scope.purpose == @credential.HostAttestation &&
    scope.checkpoint_kind == @checkpoint.EffectSet &&
    scope.principal == self.principal &&
    scope.authority_scope_cid == self.authority_scope_cid &&
    scope.account_id == host.session.configuration.account_id() &&
    scope.account_configuration_cid ==
    host.session.configuration.configuration_cid() &&
    scope.host_adoption_cid == host.adoption_cid &&
    local_adoption_digest(
      host.epoch.crypto,
      self.original.reviewer.control_body,
    )
    is Ok(configuration) &&
    scope.key_configuration_cid == configuration &&
    local_adoption_digest(host.epoch.crypto, self.original.exported)
    is Ok(generation) &&
    scope.key_generation_cid == generation &&
    scope.key_id == self.original.public_key.cid() &&
    scope.key_public_key_cid == self.original.public_key.cid() else {
    return Err(ChangedIntent)
  }
  Ok(())
}

///|
// Private issue arithmetic/authenticated DATA only. Actual paired/current
// fences, full preparation append and its confirmed TX precede any use claim.
fn local_initial_host_signing_grant_original_locked(
  account : NativeLocalInitialHostSigningAccount,
  request : @host.ClientRequestIdentity,
  scope : @credential.LocalSigningCredentialScope,
  operation_id : String,
  sampled_at : Int64,
  earlier_valid_until : Int64?,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  match account.require_signing_scope(scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let key = account.original
  let host = key.reviewer.host
  let issue = match
    key.reviewer.policy.prepare_first_issue(sampled_at, earlier_valid_until) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let grant = match
    @credential.prepare_local_signing_credential_grant(
      key.reviewer.issuer,
      scope,
      issue.expires_at(),
      key.reviewer.policy.max_uses(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let original = match
    local_owned_grant_original(
      host.epoch.crypto,
      operation_id,
      request,
      scope.key_configuration_cid,
      SigningGrant(grant),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let configuration = match
    local_adoption_digest(host.epoch.crypto, account.installed.original_bytes) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let payload = match
    local_initial_signing_issue_payload(
      original,
      host.session.intent_cid,
      key.reviewer.policy.cid(),
      {
        sampled_at,
        earlier_valid_until,
        host_configuration_file: account.installed.file,
        host_configuration_cid: configuration,
        connection: account.connection,
        signing_resource: Some(account.resource),
      },
    ) {
    Ok(value) if value.length() <= 2048 => value
    Ok(_) => return Err(CapacityExceeded)
    Err(issue) => return Err(issue)
  }
  let packet = match
    local_installation_packet_in_transaction(
      host.database,
      host.epoch.crypto,
      payload,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let retained = { ..original, initial_issue: Some(packet), }
  host
  .check_initial_host_attestation_grant_original_locked(
    retained,
    scope.run_definition_cid,
    capture=key.reviewer.original_read.map(value => value.0),
  )
  .map(_ => retained)
}

///|
/// Restore only the actor tuple authenticated by this same original initial
/// installation. Missing legacy metadata never discovers or installs a role.
/// The existing Account Sign and physical/key/current checks still decide use.
pub fn NativeLocalHostConnection::restore_initial_host_signing_account(
  self : NativeLocalHostConnection,
  installed : NativeLocalInstalledEffectReviewer,
) -> Result[
  NativeLocalInitialHostSigningAccount,
  NativeLocalSigningAccountIssue,
] {
  let reviewer_original = match installed.initial_original {
    Some(original) =>
      if original.original_read is Some(_) {
        Some(original)
      } else {
        None
      }
    None => None
  }
  let original = match
    self.restore_initial_host_signing_original(reviewer_original~) {
    Ok(value) => value
    Err(_) => return Err(SigningUnavailable)
  }
  guard original.signing_subject is Some((principal, connection, resource)) else {
    return Err(SigningUnavailable)
  }
  self.acquire_initial_host_signing_account(
    original, installed, principal, connection, resource,
  )
}
