///|
/// Storage phase of the one-original-signature Local adapter. The trusted Host
/// must authenticate its saved grant/operation and original subject, current
/// RunRead/Reviewer/key, cancellation, reservation and entered original journal
/// TX before calling. It must roll back on Err and confirm the same TX before
/// using a returned record. Public metadata or a copied grant is no permission.
///
/// The exact original attempt selects this adapter's use ID; callers cannot
/// choose another ID after a missing/lost response. Generic grant/use APIs,
/// max_uses and previously saved HTTP/Signing records remain unchanged.
/// No key, signature, issuer, authorization Bool or HTTP client is involved.
fn claim_local_original_signing_use_for_purpose(
  purpose : @credential.LocalSigningPurpose,
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[
  @credential.LocalSigningCredentialUse,
  NativeCredentialResourceIssue,
] {
  if scope.purpose != purpose ||
    owned_grant_matches_scope(SigningGrant(grant), SigningScope(scope)) is None {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let cid = @credential.local_signing_credential_grant_cid(grant)
  let use_id = scope.attempt_id
  match database.lookup_claim_ordinal(use_scope(cid), use_id) {
    Ok(Some(_)) =>
      // Authenticate all retained original claim/use/outcome metadata; neither
      // a succeeded tag nor missing signature bytes permits another signature.
      match
        prepare_native_local_signing_history_candidate(database, grant, use_id) {
        Ok(_) => return Err(UseAlreadyClaimed)
        Err(issue) => return Err(issue)
      }
    Ok(None) => ()
    Err(issue) => return Err(Journal(issue))
  }
  // A legacy use, missing claim, or orphan outcome is not initial eligibility.
  // There is no repair, adoption of another ID, or cleanup of that old row.
  for bucket in [use_scope(cid), outcome_scope(cid)] {
    match database.scan_after(bucket, "") {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(Journal(@sqlite.Collision))
      Err(issue) => return Err(Journal(issue))
    }
  }
  let now = observed_now_ms
  let revoked = match read_credential_grant_revocation(database, cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (max_uses, _) = @credential.local_signing_credential_grant_limits(grant)
  // Pure eligibility precedes ordinal allocation. It grants no current purpose
  // permission; that remains the typed original Host's independent boundary.
  match
    @credential.prepare_local_signing_credential_use(
      grant, use_id, now, 0, revoked, scope,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Credential(issue))
  }
  let original = match
    claim_original_owned_credential_use(
      database,
      SigningGrant(grant),
      use_id,
      now,
      revoked,
      SigningScope(scope),
      max_uses,
      caller_transaction=true,
    ) {
    Ok(SigningUse(value)) => value
    Ok(_) => return Err(Journal(@sqlite.Collision))
    Err(issue) => return Err(issue)
  }
  // Another legacy ordinal without its use row also refuses. This is a
  // tentative caller-TX write; Err must roll back it, never leave a new ordinal.
  let (_, _, ordinal) = @credential.local_signing_credential_use_projection(
    original,
  )
  if ordinal != 1 {
    return Err(Journal(@sqlite.Collision))
  }
  // Caller-mode ordinal allocation proved an active, unfenced TX before
  // any clock write. Rollback/current denial must roll back this same CAS too.
  match observe_credential_journal_clock(database, now) {
    Ok(_) => Ok(original)
    Err(issue) => Err(issue)
  }
}

///|
/// Original Reviewer-only entry; Host purpose remains unavailable here.
pub fn claim_native_local_original_signing_use_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[
  @credential.LocalSigningCredentialUse,
  NativeCredentialResourceIssue,
] {
  claim_local_original_signing_use_for_purpose(
    @credential.ReviewerProof,
    database,
    grant,
    scope,
    observed_now_ms,
  )
}

///|
/// Explicit initial Host entry. The actual Host must authenticate its staged full wrapper, current Sign account, original key and paired subject before/after this storage phase.
pub fn claim_native_local_initial_host_signing_use_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  scope : @credential.LocalSigningCredentialScope,
  observed_now_ms : Int64,
) -> Result[
  @credential.LocalSigningCredentialUse,
  NativeCredentialResourceIssue,
] {
  claim_local_original_signing_use_for_purpose(
    @credential.HostAttestation,
    database,
    grant,
    scope,
    observed_now_ms,
  )
}
