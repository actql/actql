///|
/// Authenticate the retained common receipt original. A terminal CID without
/// its exact body is lost custody, never permission to reconstruct success.
fn read_client_effect_receipt(
  database : @sqlite.Database,
  entry : @effect.EffectLedgerEntry,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@publication.PublicationContract, NativeClientRunJournalIssue] {
  guard entry.outcome_receipt_cid is Some(cid) else { return Err(CustodyLost) }
  let stored = match
    read_client_journal_value(database, "client_effect_row_receipt", cid, reads) {
    Ok(value) if value.revision == 0L => value
    Err(issue) if !(issue is @sqlite.NotFound) => return Err(Physical(issue))
    _ => return Err(CustodyLost)
  }
  let wire = @utf8.decode(stored.body) catch { _ => return Err(CustodyLost) }
  let limits = native_client_effect_storage_profile.receipt
  match
    @publication.admit_publication_contract(
      "effect_row_outcome_receipt",
      wire,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) if @publication.publication_contract_identity(value) == cid &&
      @publication.effect_row_outcome_receipt_terminal_state(value) ==
      Some(
        match @effect.effect_ledger_entry_state_code(entry) {
          2 => "applied"
          3 => "accepted"
          4 => "failed"
          _ => return Err(CustodyLost)
        },
      ) => Ok(value)
    _ => Err(CustodyLost)
  }
}

///|
/// Semantic Preview identity intentionally excludes the Run. Bind the actual
/// original Run and row before interpreting even an absent receipt. The common
/// single-row and dispatch Owners validate the typed item/key/request binding.
fn require_client_effect_receipt_binding(
  record : NativeClientRunRecord,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  canonical_request_cid : String,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard record.checkpoint is Some(checkpoint) &&
    @publication.effect_preview_run_identity(preview) ==
    @publication.publication_contract_identity(record.definition) &&
    @publication.effect_preview_semantic_identity(preview) ==
    checkpoint.artifact.checkpoint.required_artifact_cid &&
    @publication.effect_preview_member_kind(preview, member_index) is Some(kind) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    )
    is Some(row) else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let scope = @host.client_request_logical_scope(record.request)
  if @effect.admit_effect_single_row(
      preview, member_index, row_index, kind, scope, row, locator, key,
    )
    is Err(_) ||
    !@effect.effect_ledger_entry_admits_dispatch(
      dispatch.dispatching,
      scope,
      locator,
      key,
      canonical_request_cid,
    ) {
    return Err(Checkpoint(InvalidMaterial))
  }
  Ok(())
}

///|
/// Settle only a saved original response through the existing common row
/// receipt and Ledger Owners. No Provider, resume claim or new attempt occurs.
/// The receipt original and terminal history commit with the original Run's
/// independent witness in one transaction. Run/publication/cleanup terminality
/// is not derived from this row observation.
pub fn NativeClientRunJournal::record_effect_row_receipt(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  canonical_request_cid : String,
  outcome_wire : String,
  current : () -> Bool,
  max_response_bytes : Int,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeClientRunJournalIssue,
] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  if max_response_bytes < 1 ||
    max_response_bytes > native_client_effect_storage_profile.response_bytes {
    return Err(CapacityExceeded)
  }
  self.transaction(() => {
    let record = match self.require_effect_dispatch_locked(dispatch) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let checkpoint = record.checkpoint.unwrap()
    match
      require_client_effect_receipt_binding(
        record, dispatch, preview, member_index, row_index, locator, key, canonical_request_cid,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let dispatch_cid = @effect.effect_ledger_entry_cid(dispatch.dispatching)
    let response = match
      read_client_effect_response_record(self.database, dispatch_cid) {
      Ok(Some(value)) if value.body.length() <= max_response_bytes => value
      Ok(Some(_)) => return Err(Physical(@sqlite.BodyTooLarge))
      Ok(None) => return Err(Checkpoint(NeedsOriginalContinuation))
      Err(issue) => return Err(issue)
    }
    let bounds = native_client_effect_ledger_limits()
    let receipt = match
      @publication.issue_effect_row_outcome_receipt(
        preview,
        member_index,
        row_index,
        dispatch_cid,
        response.credential_use_cid,
        response.body,
        response.status_code,
        outcome_wire,
        max_response_bytes,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(Checkpoint(InvalidMaterial))
    }
    let history = checkpoint.effect_ledger.filter(entry => {
      @effect.effect_ledger_entry_locator_cid(entry) ==
      @effect.effect_ledger_entry_locator_cid(dispatch.dispatching)
    })
    if history.is_empty() {
      return Err(CustodyLost)
    }
    let head = history[history.length() - 1]
    let terminal = match
      @effect.issue_effect_row_receipt_terminal_entry(
        preview,
        member_index,
        row_index,
        @host.client_request_logical_scope(record.request),
        locator,
        key,
        canonical_request_cid,
        head,
        history,
        dispatch_cid,
        response.credential_use_cid,
        response.body,
        response.status_code,
        @publication.publication_contract_json(receipt),
        max_response_bytes,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(Checkpoint(InvalidMaterial))
    }
    // Authority may change during caller observation. It confers neither
    // write permission nor authority to disclose another Run's saved bytes.
    if !current() {
      return Err(AuthorizationDenied)
    }
    if terminal.cid == head.cid {
      let saved = match read_client_effect_receipt(self.database, terminal) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @publication.publication_contract_json(saved) !=
        @publication.publication_contract_json(receipt) {
        return Err(CustodyLost)
      }
      return Ok((saved, terminal))
    }
    if checkpoint.effect_ledger.length() >= 128 {
      return Err(CapacityExceeded)
    }
    let receipt_cid = @publication.publication_contract_identity(receipt)
    let bytes = @utf8.encode(@publication.publication_contract_json(receipt))
    match self.database.read("client_effect_row_receipt", receipt_cid) {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      // No unattached original is adopted into a new terminal transition.
      Ok(_) => return Err(CustodyLost)
    }
    let entries = checkpoint.effect_ledger.copy()
    entries.push(terminal)
    let next = {
      ..record,
      checkpoint: Some({ ..checkpoint, effect_ledger: entries, }),
    }
    let witness = match
      self.database.read(
        "client_effect_custody",
        @host.client_request_scope_cid(record.request),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    match
      self.database.insert("client_effect_row_receipt", receipt_cid, bytes) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    let (body, _) = match
      effect_ledger_custody_with_responses(self.database, next) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      self.database.compare_exchange(
        "client_effect_custody",
        @host.client_request_scope_cid(record.request),
        witness.revision,
        body,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    match self.save(next) {
      Ok(_) => Ok((receipt, terminal))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Re-admit an existing original terminal receipt under current evidence
/// authority. Missing evidence is never regenerated. This read cannot mutate
/// the Run, project another outcome, renew approval or invoke a Provider.
pub fn NativeClientRunJournal::effect_row_receipt(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  canonical_request_cid : String,
  current : () -> Bool,
  max_response_bytes : Int,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry)?,
  NativeClientRunJournalIssue,
] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  if max_response_bytes < 1 ||
    max_response_bytes > native_client_effect_storage_profile.response_bytes {
    return Err(CapacityExceeded)
  }
  self.transaction(() => {
    let record = match self.require_effect_dispatch_locked(dispatch) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let checkpoint = record.checkpoint.unwrap()
    match
      require_client_effect_receipt_binding(
        record, dispatch, preview, member_index, row_index, locator, key, canonical_request_cid,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let history = checkpoint.effect_ledger.filter(entry => {
      entry.logical_item_locator_cid ==
      dispatch.dispatching.logical_item_locator_cid
    })
    if history.is_empty() {
      return Err(CustodyLost)
    }
    let head = history[history.length() - 1]
    let state = @effect.effect_ledger_entry_state_code(head)
    if state == 1 || state == 5 {
      if !current() {
        return Err(AuthorizationDenied)
      }
      return Ok(None)
    }
    let receipt = match read_client_effect_receipt(self.database, head) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let response = match
      read_client_effect_response_record(
        self.database,
        dispatch.dispatching.cid,
      ) {
      Ok(Some(value)) if value.body.length() <= max_response_bytes => value
      Ok(Some(_)) => return Err(Physical(@sqlite.BodyTooLarge))
      Err(issue) => return Err(issue)
      _ => return Err(CustodyLost)
    }
    let bounds = native_client_effect_ledger_limits()
    match
      @effect.issue_effect_row_receipt_terminal_entry(
        preview,
        member_index,
        row_index,
        @host.client_request_logical_scope(record.request),
        locator,
        key,
        canonical_request_cid,
        head,
        history,
        dispatch.dispatching.cid,
        response.credential_use_cid,
        response.body,
        response.status_code,
        @publication.publication_contract_json(receipt),
        max_response_bytes,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) if value.cid == head.cid => ()
      _ => return Err(Checkpoint(InvalidMaterial))
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(Some((receipt, head)))
  })
}
