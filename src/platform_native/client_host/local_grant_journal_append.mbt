///|
// Storage in the same original Host/Journal Owner. The enclosing variant-specific
// opaque caller still supplies its independently current operation fence; this
// private function neither acquires issuer authority nor creates a transaction.
fn append_local_owned_grant_original_locked(
  grant_host : NativeLocalHostConnection,
  grant_crypto : @crypto.Library,
  original : NativeLocalGrantOriginal,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
  target? : NativeLocalPreparationOriginalTarget? = None,
  host_prepared? : String? = None,
  resolution_proof? : @checkpoint.PreparedResolutionProof? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if (original.grant is PreparationGrant(_)) != (target is Some(_)) {
    return Err(ChangedIntent)
  }
  let (count, revision, runs) = match
    grant_host.local_grant_custody(grant_crypto) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // A changed explicit operation cannot mint another allowance for the same
  // original preparation observation. Saved/entered/unknown use recovery
  // retains the first original grant, even if no response has been found.
  if original.grant is PreparationGrant(preparation) {
    let scope = @credential.local_preparation_credential_grant_scope(
      preparation,
    )
    let mut cursor = ""
    let mut checked = 0
    while true {
      let row = match
        grant_host.database.scan_after("client_local_grant_originals", cursor) {
        Ok(value) => value
        Err(@sqlite.NotFound) => break
        Err(issue) => return Err(Physical(issue))
      }
      checked += 1
      if checked > count {
        return Err(CustodyLost)
      }
      let prior = match read_local_grant_original(grant_crypto, row) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if prior.grant is PreparationGrant(previous) {
        let saved = @credential.local_preparation_credential_grant_scope(
          previous,
        )
        if saved.submission_scope_cid == scope.submission_scope_cid &&
          saved.operation_occurrence_cid == scope.operation_occurrence_cid &&
          saved.request_cid == scope.request_cid &&
          prior.operation_id != original.operation_id {
          return Err(Checkpoint(NeedsOriginalContinuation))
        }
      }
      cursor = row.key
    }
  }
  if original.grant is SigningGrant(_) {
    match
      grant_host.same_signing_operation_locked(original, resolution_proof~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let key = match
    local_grant_original_key(
      grant_crypto,
      original.request,
      original.operation_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reservation_scope = local_original_grant_reservation_scope(original)
  let (entries, bytes) = runs.get(reservation_scope).unwrap_or((0, 0))
  // Reserve before encoding/copying the appended grant packet. Missing
  // reservations for existing originals refuse rather than being repaired.
  match
    grant_host.database.reserve_capacity_in_transaction(
      "client_local_grant_originals",
      reservation_scope,
      65536L,
      1L,
      grant_host.journal.max_records.to_int64() * 65536L,
      grant_host.journal.max_records.to_int64(),
    ) {
    Ok(fresh) if fresh == (entries == 0) => ()
    Ok(_) => return Err(CustodyLost)
    Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
    Err(issue) => return Err(Physical(issue))
  }
  let packet = match local_grant_original_packet(original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let prepared_packet = match host_prepared {
    None => None
    Some(wire) =>
      match local_initial_host_prepared_body(grant_host, original, wire) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  // Every initial Host grant has one complete immutable preparation, even
  // before use. Other grant purposes cannot acquire a prepared-wrapper row.
  let initial_host = match original.grant {
    SigningGrant(grant) =>
      original.initial_issue is Some(_) &&
      @credential.local_signing_credential_grant_scope(grant).purpose ==
      @credential.HostAttestation
    _ => false
  }
  if initial_host != (prepared_packet is Some(_)) {
    return Err(ChangedIntent)
  }
  let target_packet = match target {
    Some(value) =>
      match local_preparation_target_record(grant_host, original, value) {
        Ok(body) => Some(body)
        Err(issue) => return Err(issue)
      }
    None => None
  }
  match grant_host.database.read("client_local_grant_originals", key) {
    Ok(row) if row.revision == 0L && row.body == packet => {
      if target_packet is Some(body) {
        match
          grant_host.database.read(
            "client_local_preparation_target_originals", key,
          ) {
          Ok(saved) if saved.revision == 0L && saved.body == body => ()
          Ok(_) => return Err(ChangedIntent)
          Err(@sqlite.NotFound) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
      }
      if prepared_packet is Some(body) {
        match local_initial_host_prepared_locked(grant_host, original) {
          Ok(saved) if saved == body => ()
          Ok(_) => return Err(ChangedIntent)
          Err(issue) => return Err(issue)
        }
      }
      return current()
    }
    Ok(_) => return Err(ChangedIntent)
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let appended_bytes = packet.length() +
    target_packet.map(body => body.length()).unwrap_or(0) +
    prepared_packet.map(body => body.length()).unwrap_or(0)
  if entries >= 64 || appended_bytes > 65536 - bytes {
    return Err(CapacityExceeded)
  }
  // Recheck actual authority and the typed original fence after finite
  // encoding and physical reads, immediately before the immutable append.
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    grant_host.database.insert("client_local_grant_originals", key, packet) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  if target_packet is Some(body) {
    match
      grant_host.database.insert(
        "client_local_preparation_target_originals", key, body,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  if prepared_packet is Some(body) {
    match
      grant_host.database.insert(
        "client_local_signing_candidate_originals",
        local_initial_host_prepared_key(original),
        body,
      ) {
      Ok(0L) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  grant_host.database
  .compare_exchange(
    "client_local_grant_custody",
    "issued",
    revision,
    @utf8.encode((count + 1).to_string()),
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}
