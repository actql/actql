///|
/// Check the same already-claimed signing use at an actual operational use or
/// signature-return boundary. This is not a history query or a reusable Allow.
/// The trusted Host supplies its current clock observation after its callbacks
/// and separately checks actual subject, key and current purpose authority.
///
/// No claim, ordinal, grant, expiry, signature or transport is issued. Only the
/// existing trusted-clock lower bound may advance, in the caller's active TX;
/// Err must roll back that same transaction. Original first-issue metadata is
/// never resampled or changed. Metadata-only history readers remain read-only.
fn check_local_original_signing_use_for_purpose(
  purpose : @credential.LocalSigningPurpose,
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[Unit, NativeCredentialResourceIssue] {
  match database.transaction_state() {
    Ok(@sqlite.ActiveSqliteTransaction) if !database.transaction_fenced() => ()
    Ok(_) =>
      return Err(
        Journal(
          @sqlite.Physical(
            "signing current check requires an active unfenced caller transaction",
          ),
        ),
      )
    Err(issue) => return Err(Journal(issue))
  }
  if scope.purpose != purpose ||
    @credential.local_signing_credential_grant_scope(grant) != scope {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  // Missing/corrupt/orphan history is observed before any clock write. Equal
  // public metadata cannot create its missing durable original or a new use.
  let history = match
    local_original_signing_history_for_purpose(purpose, database, grant) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if @credential.local_signing_credential_use_cid(history.original_use) !=
    @credential.local_signing_credential_use_cid(original_use) ||
    @credential.local_signing_credential_use_json(history.original_use) !=
    @credential.local_signing_credential_use_json(original_use) {
    return Err(Journal(@sqlite.Collision))
  }
  let now = match observe_credential_journal_clock(database, observed_now_ms) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // This actual journal read follows every Host/clock callback. A terminal
  // Succeeded tag and a retained signature never bypass later revocation.
  let revoked = match
    read_credential_grant_revocation(
      database,
      @credential.local_signing_credential_grant_cid(grant),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    @credential.validate_local_signing_credential_use_binding(
      history.original_use,
      now,
      revoked,
      scope,
    ) {
    Err(issue) => return Err(Credential(issue))
    Ok(_) => ()
  }
  match database.transaction_state() {
    Ok(@sqlite.ActiveSqliteTransaction) if !database.transaction_fenced() =>
      Ok(())
    Ok(_) =>
      Err(
        Journal(
          @sqlite.Physical(
            "signing current check lost its original caller transaction",
          ),
        ),
      )
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Original Reviewer-only entry; Host purpose remains unavailable here.
pub fn check_native_local_original_signing_use_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[Unit, NativeCredentialResourceIssue] {
  check_local_original_signing_use_for_purpose(
    @credential.ReviewerProof,
    database,
    grant,
    original_use,
    scope,
    observed_now_ms,
  )
}

///|
/// Explicit initial Host entry. The actual Host must authenticate its staged full wrapper, current Sign account, original key and paired subject before/after this storage phase.
pub fn check_native_local_initial_host_signing_use_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[Unit, NativeCredentialResourceIssue] {
  check_local_original_signing_use_for_purpose(
    @credential.HostAttestation,
    database,
    grant,
    original_use,
    scope,
    observed_now_ms,
  )
}
