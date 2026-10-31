///|
/// Observed original credential-journal state, not a signature or permission.
/// Succeeded describes the stored outcome tag only; returning exact signature
/// bytes requires their separate authenticated original and current return gate.
pub(all) enum NativeLocalSigningHistoryOutcome {
  Claimed
  Succeeded
  Failed
  Unknown
} derive(Eq)

///|
/// Bounded storage candidate for the trusted Local Host. It carries no key,
/// HTTP client, issuer, clock, ordinal allocator or authorization callback.
/// The Host must authenticate operation/request/Run/key/issuer originals and
/// recheck actual Client RunRead plus Reviewer resolve/key custody before and
/// after this preparation. Candidate metadata cannot admit a Resolution or use
/// an expired grant; those independent operational gates are unchanged.
struct NativeLocalSigningHistoryCandidate {
  original_grant : @credential.LocalSigningCredentialGrant
  original_use : @credential.LocalSigningCredentialUse
  observed_outcome : NativeLocalSigningHistoryOutcome
}

///|
/// Read within the caller's original journal transaction. This never begins or
/// commits one, advances UTC, reserves capacity, claims an ordinal, repairs a
/// missing use/outcome, signs, renews or emits an authorization result.
/// Absence remains unavailable even if copied use metadata looks canonical.
pub fn prepare_native_local_signing_history_candidate(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  use_id : String,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  if use_id.is_empty() || use_id.length() > 256 {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let grant_cid = @credential.local_signing_credential_grant_cid(grant)
  let ordinal = match
    database.lookup_claim_ordinal(use_scope(grant_cid), use_id) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Journal(@sqlite.NotFound))
    Err(issue) => return Err(Journal(issue))
  }
  let (max_uses, _) = @credential.local_signing_credential_grant_limits(grant)
  if ordinal > max_uses.to_int64() {
    return Err(Journal(@sqlite.Collision))
  }
  let row = match database.read(use_scope(grant_cid), use_id) {
    Ok(value) if value.revision == 0L => value
    Ok(_) => return Err(Journal(@sqlite.Collision))
    Err(issue) => return Err(Journal(issue))
  }
  let original = match
    admit_owned_credential_use_record(SigningGrant(grant), use_id, row) {
    Ok(SigningUse(value)) if owned_credential_use_matches_ordinal(
        SigningUse(value),
        ordinal,
      ) => value
    Ok(_) => return Err(Journal(@sqlite.Collision))
    Err(issue) => return Err(issue)
  }
  // Signing has no HTTP status. Do not reuse a permissive status parser or
  // manufacture status 200; only these existing exact terminal bytes apply.
  let observed = match database.read(outcome_scope(grant_cid), use_id) {
    Err(@sqlite.NotFound) => Claimed
    Err(issue) => return Err(Journal(issue))
    Ok(value) if value.revision == 0L =>
      if value.body == b"succeeded\n" {
        Succeeded
      } else if value.body == b"failed\n" {
        Failed
      } else if value.body == b"unknown\n" {
        Unknown
      } else {
        return Err(Journal(@sqlite.Collision))
      }
    Ok(_) => return Err(Journal(@sqlite.Collision))
  }
  Ok({
    original_grant: grant,
    original_use: original,
    observed_outcome: observed,
  })
}

///|
/// History of the one-original-signature Local operation. Its retained grant
/// selects the exact use; no caller ID, new ordinal or live use authorization
/// is accepted. The generic multi-use history reader remains unchanged.
fn local_original_signing_history_for_purpose(
  purpose : @credential.LocalSigningPurpose,
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if scope.purpose != purpose {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let candidate = match
    prepare_native_local_signing_history_candidate(
      database,
      grant,
      scope.attempt_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (cid, use_id, ordinal) = @credential.local_signing_credential_use_projection(
    candidate.original_use,
  )
  if cid != @credential.local_signing_credential_grant_cid(grant) ||
    use_id != scope.attempt_id ||
    ordinal != 1 {
    return Err(Journal(@sqlite.Collision))
  }
  // At most two rows per existing bucket distinguish the exact original from
  // a legacy/foreign use or orphan outcome. Never enumerate an unbounded stream
  // or repair a missing expected use from the other row.
  for bucket in [use_scope(cid), outcome_scope(cid)] {
    let first = match database.scan_after(bucket, "") {
      Ok(row) if row.key == scope.attempt_id => row
      Ok(_) => return Err(Journal(@sqlite.Collision))
      Err(@sqlite.NotFound) => continue
      Err(issue) => return Err(Journal(issue))
    }
    match database.scan_after(bucket, first.key) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(Journal(@sqlite.Collision))
      Err(issue) => return Err(Journal(issue))
    }
  }
  Ok(candidate)
}

///|
/// Original identity metadata only. This getter issues no read or use permit.
pub fn NativeLocalSigningHistoryCandidate::original_use(
  self : NativeLocalSigningHistoryCandidate,
) -> @credential.LocalSigningCredentialUse {
  self.original_use
}

///|
pub fn NativeLocalSigningHistoryCandidate::grant_cid(
  self : NativeLocalSigningHistoryCandidate,
) -> String {
  @credential.local_signing_credential_grant_cid(self.original_grant)
}

///|
/// A persisted outcome observation, never proof that exact signature custody
/// exists or that this metadata may be disclosed to an unauthenticated caller.
pub fn NativeLocalSigningHistoryCandidate::observed_outcome(
  self : NativeLocalSigningHistoryCandidate,
) -> NativeLocalSigningHistoryOutcome {
  self.observed_outcome
}

///|
/// Original Reviewer-only entry; Host purpose remains unavailable here.
pub fn prepare_native_local_original_signing_history_candidate(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  local_original_signing_history_for_purpose(
    @credential.ReviewerProof,
    database,
    grant,
  )
}

///|
/// Explicit initial Host entry. The actual Host must authenticate its staged full wrapper, current Sign account, original key and paired subject before/after this storage phase.
pub fn prepare_native_local_initial_host_signing_history_candidate(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  local_original_signing_history_for_purpose(
    @credential.HostAttestation,
    database,
    grant,
  )
}
