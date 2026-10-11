///|
// A borrowed read view of the original credential journal and private Store.
// It has no HTTP client, secret installation, grant issuer or claim operation.
// The trusted Host supplies separate current lookup/disclosure authorization;
// neither the admitted grant nor this view creates that authority.
struct NativeLocalPreparationRawLookup {
  database : @sqlite.Database
  raw : NativeLocalPreparationRawStore
  grant : @credential.LocalPreparationCredentialGrant
  scope : @credential.LocalPreparationCredentialScope
  authorize : (NativeLocalPreparationCredentialAuthorization) -> Bool
  current : () -> Bool
  clock : () -> Int64
}

///|
fn local_preparation_raw_lookup_scope_matches(
  grant : @credential.LocalPreparationCredentialGrant,
  scope : @credential.LocalPreparationCredentialScope,
) -> Bool {
  @credential.local_preparation_credential_grant_scope(grant) == scope &&
  scope.operation == "salesforce:record:observe" &&
  owned_request_matches_scope(
    PreparationScope(scope),
    @http.Get,
    scope.request_path,
    b"",
  )
}

///|
/// Connect the same already-open credential journal and retained raw Store
/// without installing a transport. The Host must bind this read-only view to
/// authenticated original grant/Run/Store custody and current target read.
/// This does not bootstrap a database, recover an unsent permission, repair
/// missing records, issue another grant or acknowledge a semantic outcome.
pub fn bind_native_local_preparation_raw_lookup(
  database : @sqlite.Database,
  raw : NativeLocalPreparationRawStore,
  grant : @credential.LocalPreparationCredentialGrant,
  scope : @credential.LocalPreparationCredentialScope,
  authorize : (NativeLocalPreparationCredentialAuthorization) -> Bool,
  current : () -> Bool,
) -> Result[NativeLocalPreparationRawLookup, NativeCredentialResourceIssue] {
  bind_native_local_preparation_raw_lookup_with_clock(
    database,
    raw,
    grant,
    scope,
    authorize,
    current,
    () => @env.now().reinterpret_as_int64(),
  )
}

///|
fn bind_native_local_preparation_raw_lookup_with_clock(
  database : @sqlite.Database,
  raw : NativeLocalPreparationRawStore,
  grant : @credential.LocalPreparationCredentialGrant,
  scope : @credential.LocalPreparationCredentialScope,
  authorize : (NativeLocalPreparationCredentialAuthorization) -> Bool,
  current : () -> Bool,
  clock : () -> Int64,
) -> Result[NativeLocalPreparationRawLookup, NativeCredentialResourceIssue] {
  if !local_preparation_raw_lookup_scope_matches(grant, scope) {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  Ok({ database, raw, grant, scope, authorize, current, clock, })
}

///|
fn NativeLocalPreparationRawLookup::require_current_read(
  self : NativeLocalPreparationRawLookup,
  stage : String,
  original_use : @credential.LocalPreparationCredentialUse?,
) -> Result[Unit, NativeCredentialResourceIssue] {
  if !local_preparation_raw_lookup_scope_matches(self.grant, self.scope) {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let grant_cid = @credential.local_preparation_credential_grant_cid(self.grant)
  let use_cid = original_use.map(value => {
    @credential.local_preparation_credential_use_cid(value)
  })
  let request : NativeCredentialRequest? = match stage {
    "query" if use_cid is None => None
    "raw-query" | "raw-return" if use_cid is Some(_) =>
      Some({ verb: @http.Get, path: self.scope.request_path, body: b"", })
    _ => return Err(AccessDenied)
  }
  let allowed = (self.authorize)({
    stage,
    grant_cid,
    use_cid,
    scope: self.scope,
    request,
  })
  let now = match
    observe_credential_journal_clock(self.database, (self.clock)()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let current = (self.current)()
  // Read durable revocation last, after every authorization/clock/Host callback.
  // Failure leaves the original response and cleanup responsibility intact.
  let revoked = match
    read_credential_grant_revocation(self.database, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !allowed || !current {
    return Err(AccessDenied)
  }
  match original_use {
    Some(value) =>
      @credential.authorize_local_preparation_credential_use(
        value,
        now,
        revoked,
        self.scope,
      ).map_err(issue => Credential(issue))
    None => {
      guard owned_grant_matches_scope(
          PreparationGrant(self.grant),
          PreparationScope(self.scope),
        )
        is Some((_, expires_at)) &&
        !revoked &&
        now >= 0L &&
        now < expires_at else {
        return Err(Credential(@credential.CredentialGrantInactive))
      }
      Ok(())
    }
  }
}

///|
/// Read the exact persisted use and raw response after process restart. This
/// cannot call a Provider: all original journal/Store readers are shared with
/// the existing credential Owner and this view carries no transport capability.
/// Claimed/unknown stays distinct from succeeded even when raw bytes exist.
pub fn NativeLocalPreparationRawLookup::lookup(
  self : NativeLocalPreparationRawLookup,
  use_id : String,
) -> Result[NativeLocalPreparationRawRecovery, NativeCredentialResourceIssue] {
  if use_id.is_empty() || use_id.length() > 256 {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  match self.require_current_read("query", None) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let original = match
    read_owned_credential_use_record(
      self.database,
      PreparationGrant(self.grant),
      use_id,
    ) {
    Ok(PreparationUse(value)) => value
    Ok(_) => return Err(Credential(@credential.CredentialUseCollision))
    Err(issue) => return Err(issue)
  }
  match self.require_current_read("raw-query", Some(original)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let status = match
    read_credential_use_outcome(
      self.database,
      @credential.local_preparation_credential_grant_cid(self.grant),
      use_id,
      @credential.local_preparation_credential_use_cid(original),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observation = match
    read_retained_preparation_raw_observation(
      self.raw,
      self.grant,
      original,
      status,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self
  .require_current_read("raw-return", Some(original))
  .map(_ => { original_use: status, observation, })
}
