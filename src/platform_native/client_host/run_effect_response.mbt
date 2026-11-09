///|
priv struct NativeClientEffectResponseRecord {
  metadata : Bytes
  body : Bytes
  credential_use_cid : String
  status_code : Int
}

///|
/// Read a paired physical response; absence is not evidence of non-execution.
/// The independent original Run witness detects loss of a previously saved
/// pair. This helper neither copies payload nor grants disclosure authority.
fn read_client_effect_response_record(
  database : @sqlite.Database,
  dispatch_cid : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientEffectResponseRecord?, NativeClientRunJournalIssue] {
  match
    (
      read_client_journal_value(
        database, "client_effect_response_meta", dispatch_cid, reads,
      ),
      read_client_journal_value(
        database, "client_effect_response_bytes", dispatch_cid, reads,
      ),
    ) {
    (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => Ok(None)
    (Ok(meta), Ok(body)) if meta.revision == 0L && body.revision == 0L => {
      guard @journal.effect_response_record_fields(
          meta.body,
          body.body,
          native_client_effect_storage_profile.response_bytes.to_int64(),
        )
        is Some((credential_use_cid, status_code)) else {
        return Err(CustodyLost)
      }
      Ok(
        Some({
          metadata: meta.body,
          body: body.body,
          credential_use_cid,
          status_code,
        }),
      )
    }
    (Err(issue), _) | (_, Err(issue)) if !(issue is @sqlite.NotFound) =>
      Err(Physical(issue))
    _ => Err(CustodyLost)
  }
}

///|
/// Extend the existing witness with original saved-response identities. An
/// unsaved original keeps its exact previous witness bytes. Losing even both
/// response rows cannot turn saved history into an unsent or empty response.
fn effect_ledger_custody_with_responses(
  database : @sqlite.Database,
  record : NativeClientRunRecord,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Bytes, Int), NativeClientRunJournalIssue] {
  guard effect_ledger_custody_body(record) is Some(base) &&
    record.checkpoint is Some(checkpoint) else {
    return Err(CustodyLost)
  }
  let mut body = @utf8.decode(base) catch { _ => return Err(CustodyLost) }
  let mut count = 0
  for entry in checkpoint.effect_ledger {
    let state = @effect.effect_ledger_entry_state_code(entry)
    if state >= 2 && state <= 4 {
      let receipt = match read_client_effect_receipt(database, entry, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard @publication.effect_row_outcome_receipt_dispatch_identity(receipt)
        is Some(dispatch_cid) &&
        checkpoint.effect_ledger.any(original => {
          original.cid == dispatch_cid &&
          @effect.effect_ledger_entry_state_code(original) == 1 &&
          original.logical_item_locator_cid == entry.logical_item_locator_cid &&
          original.attempt_sequence == entry.attempt_sequence
        }) else {
        return Err(CustodyLost)
      }
      match read_client_effect_response_record(database, dispatch_cid, reads~) {
        Ok(Some(_)) => ()
        Err(issue) => return Err(issue)
        _ => return Err(CustodyLost)
      }
      body += "\nreceipt\n" +
        entry.cid +
        "\n" +
        @publication.publication_contract_identity(receipt)
    }
    if @effect.effect_ledger_entry_state_code(entry) != 1 {
      continue
    }
    let cid = @effect.effect_ledger_entry_cid(entry)
    match read_client_effect_response_record(database, cid, reads~) {
      Ok(Some(response)) => {
        body += "\nresponse\n" +
          cid +
          "\n" +
          @journal.effect_response_body_digest(response.metadata)
        count += 1
      }
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok((@utf8.encode(body), count))
}

///|
/// Validate an opaque original dispatch handle while the existing journal
/// transaction is held. This is observation custody, never a new send permit.
fn NativeClientRunJournal::require_effect_dispatch_locked(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if !physical_equal(self, dispatch.journal) ||
    @effect.effect_ledger_entry_state_code(dispatch.dispatching) != 1 {
    return Err(Checkpoint(InvalidMaterial))
  }
  let record = match self.retained(dispatch.request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard record.checkpoint is Some(checkpoint) &&
    checkpoint.artifact.checkpoint_cid == dispatch.checkpoint_cid &&
    checkpoint.resolution_cid == Some(dispatch.resolution_cid) &&
    checkpoint.effect_ledger.any(entry => {
      @effect.effect_ledger_entry_cid(entry) ==
      @effect.effect_ledger_entry_cid(dispatch.dispatching) &&
      @effect.effect_ledger_entry_wire(entry) ==
      @effect.effect_ledger_entry_wire(dispatch.dispatching)
    }) else {
    return Err(CustodyLost)
  }
  Ok(record)
}

///|
/// Preserve an observed original response even after cancellation, authority
/// loss or lease expiry. The exact response pair and original Run witness commit
/// in the same durable transaction. A lost commit reply returns no success;
/// retry retains these bytes and cannot dispatch or classify an Effect.
pub fn NativeClientRunJournal::record_effect_row_response(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  response : @journal.NativeEffectSavedResponse,
  max_response_bytes : Int,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !physical_equal(self, dispatch.journal) {
    return Err(Checkpoint(InvalidMaterial))
  }
  if max_response_bytes < 1 ||
    max_response_bytes > native_client_effect_storage_profile.response_bytes {
    return Err(CapacityExceeded)
  }
  if response.body.length() > max_response_bytes {
    return Err(Physical(@sqlite.BodyTooLarge))
  }
  let metadata = match
    @journal.effect_response_record_metadata(
      response,
      max_response_bytes.to_int64(),
    ) {
    Some(value) => value
    None => return Err(Checkpoint(InvalidMaterial))
  }
  self.transaction(() => {
    let record = match self.require_effect_dispatch_locked(dispatch) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = @effect.effect_ledger_entry_cid(dispatch.dispatching)
    match read_client_effect_response_record(self.database, cid) {
      Ok(Some(saved)) if saved.metadata == metadata &&
        saved.body == response.body => return Ok(())
      Ok(Some(_)) => return Err(Checkpoint(InvalidMaterial))
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
    let key = @host.client_request_scope_cid(record.request)
    let prior = match self.database.read("client_effect_custody", key) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    for
      (table, body) in [
        ("client_effect_response_meta", metadata),
        ("client_effect_response_bytes", response.body),
      ] {
      match self.database.insert(table, cid, body) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    let (witness, _) = match
      effect_ledger_custody_with_responses(self.database, record) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      self.database.compare_exchange(
        "client_effect_custody",
        key,
        prior.revision,
        witness,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    self.save(record).map(_ => ())
  })
}

///|
/// Read the original saved response under current evidence authority, including
/// after a lease expires. The original dispatch handle and independent witness
/// must still match. Reading never renews approval, sends or changes Run state.
pub fn NativeClientRunJournal::effect_row_response(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  current : () -> Bool,
  max_response_bytes : Int,
) -> Result[@journal.NativeEffectSavedResponse?, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self, dispatch.journal) {
    return Err(Checkpoint(InvalidMaterial))
  }
  if max_response_bytes < 1 ||
    max_response_bytes > native_client_effect_storage_profile.response_bytes {
    return Err(CapacityExceeded)
  }
  self.transaction(() => {
    match self.require_effect_dispatch_locked(dispatch) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let saved = match
      read_client_effect_response_record(
        self.database,
        @effect.effect_ledger_entry_cid(dispatch.dispatching),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if saved is Some(response) && response.body.length() > max_response_bytes {
      return Err(Physical(@sqlite.BodyTooLarge))
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(
      saved.map(response => {
        credential_use_cid: response.credential_use_cid,
        status_code: response.status_code,
        body: Bytes::from_array(response.body.to_array()),
      }),
    )
  })
}
