///|
fn native_client_effect_ledger_limits() -> @checkpoint.WireLimits {
  native_client_effect_storage_profile.ledger
}

///|
fn effect_ledger_head(
  entries : Array[@effect.EffectLedgerEntry],
  locator_cid : String,
) -> @effect.EffectLedgerEntry? {
  let mut head = None
  for entry in entries {
    if @effect.effect_ledger_entry_locator_cid(entry) == locator_cid {
      head = Some(entry)
    }
  }
  head
}

///|
/// Bounded independent physical custody, not another Ledger state machine.
/// Only formal identity strings are framed; authored values are never altered.
fn effect_ledger_custody_body(record : NativeClientRunRecord) -> Bytes? {
  guard record.checkpoint is Some(checkpoint) &&
    checkpoint.effect_ledger.length() <= 128 else {
    return None
  }
  let body = checkpoint.artifact.checkpoint_cid +
    "\n" +
    @publication.publication_contract_identity(record.definition) +
    "\n" +
    @host.client_request_scope_cid(record.request) +
    "\n" +
    checkpoint.effect_ledger
    .map(entry => @effect.effect_ledger_entry_cid(entry))
    .join("\n")
  Some(@utf8.encode(body))
}

///|
fn confirm_effect_ledger_custody(
  database : @sqlite.Database,
  record : NativeClientRunRecord,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let stored = read_client_journal_value(
    database,
    "client_effect_custody",
    @host.client_request_scope_cid(record.request),
    reads,
  )
  if record.checkpoint is None {
    return match stored {
      Err(@sqlite.NotFound) => Ok(())
      Err(issue) => Err(Physical(issue))
      Ok(_) => Err(CustodyLost)
    }
  }
  let (body, responses) = match
    effect_ledger_custody_with_responses(database, record, reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match stored {
    Ok(saved) if saved.body == body &&
      record.checkpoint.unwrap().effect_ledger
      .filter(entry => @effect.effect_ledger_entry_state_code(entry) != 0)
      .length()
      .to_int64() +
      responses.to_int64() ==
      saved.revision => Ok(())
    Err(@sqlite.NotFound) => Err(CustodyLost)
    Err(issue) => Err(Physical(issue))
    _ => Err(CustodyLost)
  }
}

///|
fn NativeClientRunJournal::save_effect_ledger(
  self : NativeClientRunJournal,
  original : NativeClientRunRecord,
  entries : Array[@effect.EffectLedgerEntry],
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  match confirm_effect_ledger_custody(self.database, original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard original.checkpoint is Some(checkpoint) else { return Err(CustodyLost) }
  let next = {
    ..original,
    checkpoint: Some({ ..checkpoint, effect_ledger: entries, }),
  }
  let (body, _) = match
    effect_ledger_custody_with_responses(self.database, next) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = @host.client_request_scope_cid(original.request)
  let witness = match self.database.read("client_effect_custody", key) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  self.invalidate_operation_record()
  match
    self.database.compare_exchange(
      "client_effect_custody",
      key,
      witness.revision,
      body,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  self.save(next)
}

///|
/// Original dispatch custody, not Provider authorization. The checked Native
/// write owner must independently validate the actual request, Preview,
/// current target/credential authority and cancellation immediately before
/// physical sending. This handle may retain a sent row's unknown observation
/// after cancellation or lease expiry; it cannot issue another dispatch.
struct NativeClientEffectDispatchClaim {
  journal : NativeClientRunJournal
  request : @host.ClientRequestIdentity
  checkpoint_cid : String
  resolution_cid : String
  dispatching : @effect.EffectLedgerEntry
}

///|
pub enum NativeClientEffectRowDispatchAction {
  DispatchRecorded(NativeClientEffectDispatchClaim)
  OriginalRowRetained(@effect.EffectLedgerEntry)
  NoSend
}

///|
/// The existing common Ledger decides whether this original row is unsent.
/// Its exact prepared/dispatching chain is committed with the original Run
/// revision under the current resume fence. Commit uncertainty returns no
/// dispatch handle. No outcome, terminality or cleanup is inferred here.
pub fn NativeClientRunJournal::record_effect_row_dispatch(
  self : NativeClientRunJournal,
  claim : NativeClientEffectResumeClaim,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  basis : @effect.EffectLedgerBasis,
  current : () -> Bool,
  clock : () -> Int64,
) -> Result[NativeClientEffectRowDispatchAction, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  let at = clock()
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    match self.effect_resume_fence_locked(claim, at) {
      Ok(Current) => ()
      Ok(SettlementOnly) => return Ok(NoSend)
      Ok(Stale) => return Err(Checkpoint(StaleRevision))
      Err(issue) => return Err(issue)
    }
    let record = match self.retained(claim.request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.checkpoint is Some(checkpoint) else { return Err(CustodyLost) }
    let scope = @host.client_request_logical_scope(claim.request)
    let limits = native_client_effect_ledger_limits()
    let prepared = match
      @effect.issue_prepared_effect_ledger_entry(
        basis,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Checkpoint(Ledger(issue)))
    }
    let dispatching = match
      @effect.issue_next_effect_ledger_entry(
        prepared,
        "dispatching",
        None,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Checkpoint(Ledger(issue)))
    }
    if basis.effect_preview_cid !=
      checkpoint.artifact.checkpoint.required_artifact_cid ||
      !@effect.effect_ledger_entry_admits_dispatch(
        dispatching,
        scope,
        locator,
        key,
        basis.canonical_request_cid,
      ) {
      return Err(Checkpoint(InvalidMaterial))
    }
    let prior = effect_ledger_head(
      checkpoint.effect_ledger,
      @effect.logical_item_locator_cid(locator),
    )
    if prior is Some(entry) &&
      !@effect.effect_ledger_entry_matches_basis(entry, basis) {
      return Err(Checkpoint(InvalidMaterial))
    }
    let action = @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      prior,
      false,
    )
    if action >= 3 && action <= 7 {
      return Ok(OriginalRowRetained(prior.unwrap()))
    }
    if action != 0 && action != 1 {
      return Err(Checkpoint(InvalidMaterial))
    }
    let prior = prior.unwrap_or(prepared)
    let dispatching = match
      @effect.issue_next_effect_ledger_entry(
        prior,
        "dispatching",
        None,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Checkpoint(Ledger(issue)))
    }
    if !@effect.effect_ledger_entry_follows(Some(prior), dispatching) {
      return Err(Checkpoint(InvalidMaterial))
    }
    let entries = checkpoint.effect_ledger.copy()
    if action == 0 {
      entries.push(prior)
    }
    entries.push(dispatching)
    if entries.length() > 128 {
      return Err(CapacityExceeded)
    }
    match self.save_effect_ledger(record, entries) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    Ok(
      DispatchRecorded({
        journal: self,
        request: claim.request,
        checkpoint_cid: claim.checkpoint_cid,
        resolution_cid: claim.resolution_cid,
        dispatching,
      }),
    )
  })
}

///|
/// Preserve the original possibly-sent row's observation after authorization,
/// cancellation or lease changes. Only an opaque original dispatch handle can
/// do this. It cannot inspect another row, mark success or send/retry a call.
pub fn NativeClientRunJournal::record_effect_row_unknown(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
) -> Result[@effect.EffectLedgerEntry, NativeClientRunJournalIssue] {
  if !physical_equal(self, dispatch.journal) {
    return Err(Checkpoint(InvalidMaterial))
  }
  self.transaction(() => {
    let record = match self.retained(dispatch.request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.checkpoint is Some(checkpoint) &&
      checkpoint.artifact.checkpoint_cid == dispatch.checkpoint_cid &&
      checkpoint.resolution_cid == Some(dispatch.resolution_cid) else {
      return Err(Checkpoint(InvalidMaterial))
    }
    let entries = checkpoint.effect_ledger
    if !entries.any(entry => {
        @effect.effect_ledger_entry_cid(entry) ==
        @effect.effect_ledger_entry_cid(dispatch.dispatching) &&
        @effect.effect_ledger_entry_wire(entry) ==
        @effect.effect_ledger_entry_wire(dispatch.dispatching)
      }) {
      return Err(CustodyLost)
    }
    let head = effect_ledger_head(
      entries,
      @effect.effect_ledger_entry_locator_cid(dispatch.dispatching),
    ).unwrap()
    // An identical observation is idempotent. Terminal receipt application
    // belongs to the common outcome Owner and cannot be overwritten here.
    if @effect.effect_ledger_entry_state_code(head) == 5 {
      return Ok(head)
    }
    let limits = native_client_effect_ledger_limits()
    let unknown = match
      @effect.issue_next_effect_ledger_entry(
        head,
        "unknown",
        None,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Checkpoint(Ledger(issue)))
    }
    if entries.length() >= 128 {
      return Err(CapacityExceeded)
    }
    let next = entries.copy()
    next.push(unknown)
    match self.save_effect_ledger(record, next) {
      Ok(_) => Ok(unknown)
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Lookup never opens a Provider or emits a replacement dispatch. The caller
/// supplies current Run disclosure authority, not a saved cursor/claim grant.
pub fn NativeClientRunJournal::lookup_effect_row(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  locator : @effect.LogicalItemLocator,
  current : () -> Bool,
) -> Result[@effect.EffectLedgerEntry?, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let record = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if locator.logical_request_scope_cid !=
      @host.client_request_scope_cid(request) {
      return Err(Checkpoint(InvalidMaterial))
    }
    guard record.checkpoint is Some(checkpoint) else { return Err(CustodyLost) }
    Ok(
      effect_ledger_head(
        checkpoint.effect_ledger,
        @effect.logical_item_locator_cid(locator),
      ),
    )
  })
}

///|
/// Restore observation custody for the exact original possibly-sent attempt.
/// A retained row is not a fresh dispatch claim. Current Run disclosure is
/// required; current write approval and lease ownership confer no additional
/// rights here. The restored handle can retain unknown observations, not send.
pub fn NativeClientRunJournal::restore_effect_row_observation(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  locator : @effect.LogicalItemLocator,
  current : () -> Bool,
) -> Result[NativeClientEffectDispatchClaim?, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let record = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if locator.logical_request_scope_cid !=
      @host.client_request_scope_cid(request) {
      return Err(Checkpoint(InvalidMaterial))
    }
    guard record.checkpoint is Some(checkpoint) &&
      checkpoint.resolution_cid is Some(resolution_cid) else {
      return Err(CustodyLost)
    }
    let locator_cid = @effect.logical_item_locator_cid(locator)
    guard effect_ledger_head(checkpoint.effect_ledger, locator_cid)
      is Some(head) else {
      // Missing head grants neither sending nor evidence of non-execution.
      return Ok(None)
    }
    let state = @effect.effect_ledger_entry_state_code(head)
    if state < 1 || state > 5 {
      return Err(Checkpoint(InvalidMaterial))
    }
    let original = checkpoint.effect_ledger.filter(entry => {
      @effect.effect_ledger_entry_locator_cid(entry) == locator_cid &&
      entry.attempt_sequence == head.attempt_sequence &&
      @effect.effect_ledger_entry_state_code(entry) == 1
    })
    if original.length() != 1 {
      return Err(CustodyLost)
    }
    Ok(
      Some({
        journal: self,
        request,
        checkpoint_cid: checkpoint.artifact.checkpoint_cid,
        resolution_cid,
        dispatching: original[0],
      }),
    )
  })
}
