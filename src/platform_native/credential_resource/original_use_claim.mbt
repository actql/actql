///|
// Existing ordinal/use custody only. Callers must first establish actual
// current purpose authority and initial eligibility through their original
// Owners. This private seam is not a permission or public signing entrypoint.
// A retained/missing/corrupt use never acquires another ordinal or gets repaired.
fn claim_original_owned_credential_use(
  database : @sqlite.Database,
  grant : NativeOwnedCredentialGrant,
  use_id : String,
  trusted_now_ms : Int64,
  revoked : Bool,
  scope : NativeOwnedCredentialScope,
  max_uses : Int,
  caller_transaction? : Bool = false,
) -> Result[NativeOwnedCredentialUse, NativeCredentialResourceIssue] {
  let grant_cid = owned_credential_grant_cid(grant)
  let claimed = if caller_transaction {
    database.claim_ordinal_action_in_transaction(
      use_scope(grant_cid),
      use_id,
      max_uses.to_int64(),
    )
  } else {
    database.claim_ordinal_action(
      use_scope(grant_cid),
      use_id,
      max_uses.to_int64(),
    )
  }
  let ordinal = match claimed {
    Ok(@sqlite.Retained(original_ordinal)) => {
      // Verify the retained original without constructing a replacement use.
      // Missing/corrupt custody is a typed refusal, never a fresh send right.
      let original_use = match
        read_owned_credential_use_record(database, grant, use_id) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !owned_credential_use_matches_ordinal(original_use, original_ordinal) {
        return Err(Journal(@sqlite.Collision))
      }
      return Err(UseAlreadyClaimed)
    }
    Ok(@sqlite.Fresh(value)) if value <= 2147483647L => value.to_int()
    Ok(_) => return Err(InvalidConfiguration)
    Err(issue) => return Err(Journal(issue))
  }
  let credential_use = match
    prepare_owned_credential_use(
      grant,
      use_id,
      trusted_now_ms,
      ordinal - 1,
      revoked,
      scope,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  let use_cid = owned_credential_use_cid(credential_use)
  let use_body = match owned_credential_use_json(credential_use) {
    Ok(value) => @utf8.encode(use_cid + "\n" + value)
    Err(issue) => return Err(Credential(issue))
  }
  match database.insert(use_scope(grant_cid), use_id, use_body) {
    Ok(_) => ()
    Err(@sqlite.Collision) => {
      let existing = match database.read(use_scope(grant_cid), use_id) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      if existing.body != use_body {
        return Err(Journal(@sqlite.Collision))
      }
      return Err(UseAlreadyClaimed)
    }
    Err(issue) => return Err(Journal(issue))
  }
  Ok(credential_use)
}
