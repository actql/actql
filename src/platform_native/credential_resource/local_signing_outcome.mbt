///|
/// Record only the terminal metadata of this exact already-claimed Local
/// Reviewer signing use. The Host owns the actual retained physical attempt,
/// current subject/key/authority, signature custody and return gate. A stored
/// Succeeded tag is neither signature bytes nor permission to resolve/resume.
///
/// This joins the caller's existing active, unfenced journal transaction; it
/// never begins/commits one, samples a clock, claims another ordinal, signs or
/// repairs an absent/corrupt use. The same transaction must also retain the
/// Host's authenticated signature original before success can be returned.
fn record_local_original_signing_outcome_for_purpose(
  purpose : @credential.LocalSigningPurpose,
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  outcome : NativeLocalSigningHistoryOutcome,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  match database.transaction_state() {
    Ok(@sqlite.ActiveSqliteTransaction) if !database.transaction_fenced() => ()
    Ok(_) =>
      return Err(
        Journal(
          @sqlite.Physical(
            "signing outcome requires an active unfenced caller transaction",
          ),
        ),
      )
    Err(issue) => return Err(Journal(issue))
  }
  let text = match outcome {
    Succeeded => "succeeded\n"
    Failed => "failed\n"
    Unknown => "unknown\n"
    Claimed => return Err(InvalidConfiguration)
  }
  let candidate = match
    local_original_signing_history_for_purpose(purpose, database, grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // A copied canonical use is not its durable original. Admission above reads
  // the actual ordinal/use/whole finite history; compare complete use identity
  // and body too, rather than accepting grant/attempt/ordinal equality alone.
  if @credential.local_signing_credential_use_cid(candidate.original_use) !=
    @credential.local_signing_credential_use_cid(original_use) ||
    @credential.local_signing_credential_use_json(candidate.original_use) !=
    @credential.local_signing_credential_use_json(original_use) {
    return Err(Journal(@sqlite.Collision))
  }
  match candidate.observed_outcome {
    Claimed => {
      let (cid, use_id, _) = @credential.local_signing_credential_use_projection(
        original_use,
      )
      match database.insert(outcome_scope(cid), use_id, @utf8.encode(text)) {
        Ok(revision) if revision == 0L => ()
        Ok(_) => return Err(Journal(@sqlite.Collision))
        Err(issue) => return Err(Journal(issue))
      }
    }
    observed if observed == outcome => ()
    _ => return Err(Journal(@sqlite.Collision))
  }
  // Same exact readmission after the write. Unknown/Failed cannot be changed
  // to Succeeded by another call, and an existing outcome is never overwritten.
  let retained = match
    local_original_signing_history_for_purpose(purpose, database, grant) {
    Ok(value) if value.observed_outcome == outcome => value
    Ok(_) => return Err(Journal(@sqlite.Collision))
    Err(issue) => return Err(issue)
  }
  match database.transaction_state() {
    Ok(@sqlite.ActiveSqliteTransaction) if !database.transaction_fenced() =>
      Ok(retained)
    Ok(_) =>
      Err(
        Journal(
          @sqlite.Physical(
            "signing outcome lost its original caller transaction",
          ),
        ),
      )
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Original Reviewer-only entry; Host purpose remains unavailable here.
pub fn record_native_local_original_signing_outcome_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  outcome : NativeLocalSigningHistoryOutcome,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  record_local_original_signing_outcome_for_purpose(
    @credential.ReviewerProof,
    database,
    grant,
    original_use,
    outcome,
  )
}

///|
/// Explicit initial Host entry. The actual Host must authenticate its staged full wrapper, current Sign account, original key and paired subject before/after this storage phase.
pub fn record_native_local_initial_host_signing_outcome_in_transaction(
  database : @sqlite.Database,
  grant : @credential.LocalSigningCredentialGrant,
  original_use : @credential.LocalSigningCredentialUse,
  outcome : NativeLocalSigningHistoryOutcome,
) -> Result[NativeLocalSigningHistoryCandidate, NativeCredentialResourceIssue] {
  record_local_original_signing_outcome_for_purpose(
    @credential.HostAttestation,
    database,
    grant,
    original_use,
    outcome,
  )
}
