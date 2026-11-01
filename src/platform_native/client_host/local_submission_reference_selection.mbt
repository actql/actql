///|
// The public Native request ID is the original epoch+nonce identity emitted
// by this journal. It is a selector, never a nonce, epoch or permission.
fn submission_reference_request_id(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:]
  .iter()
  .all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
/// Resolve only an authenticated original SubmissionReference from this Host's
/// retained journal. The concrete Host's current RunRead is checked before and
/// after the existing clock and transaction. No reference is constructed from
/// the incoming ID; missing/corrupt custody cannot be repaired by this lookup.
/// This historical token is not current admission, a Run state or a read grant.
pub fn NativeLocalHostConnection::lookup_submission_reference_by_request_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request_id : String,
  now : Double,
) -> Result[NativeClientSubmissionReference?, NativeClientRunJournalIssue] {
  self.lookup_submission_reference_by_request_id_with_operations(
    crypto, principal, connection, request_id, now,
  )
}

///|
fn NativeLocalHostConnection::lookup_submission_reference_by_request_id_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request_id : String,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientSubmissionReference?, NativeClientRunJournalIssue] {
  self
  .lookup_submitted_record_by_request_id_with_operations(
    crypto,
    principal,
    connection,
    request_id,
    now,
    operations~,
    capture~,
  )
  .map(value => value.map(record => record.reference))
}

///|
// Retain the already-checked row through this one clock/current selection.
fn NativeLocalHostConnection::lookup_submitted_record_by_request_id_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request_id : String,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientSubmittedIntentRecord?, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if !submission_reference_request_id(request_id) {
    return Err(InvalidSubmission)
  }
  let scope_result = match capture {
    None => self.authority_scope_cid(principal, connection, crypto)
    Some(original) => {
      guard original.opening is JournalAcquired(host) &&
        physical_equal(host, self) else {
        return Err(AuthorizationDenied)
      }
      original.authority_scope_cid_in_original_read(principal, connection)
    }
  }
  let scope = match scope_result {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let current = () => {
    saved_run_selection_current(
      self,
      crypto,
      principal,
      connection,
      scope,
      capture~,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.journal.database, self.epoch.database) {
    return Err(InvalidSubmission)
  }
  // The existing Epoch Owner must advance/authenticate its durable clock before
  // verify_submission_locked; it owns any lost COMMIT response or fencing.
  match self.epoch.clock(now, operations~) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let selected = match
    self.journal.transaction_with_reads(
      () => {
        if !current() {
          return Err(AuthorizationDenied)
        }
        match
          client_journal_issuance_anchor(
            self.journal.database,
            "client_submitted_intent_custody",
            self.journal.max_records,
            reads~,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        let row = match
          client_journal_read(
            self.journal.database,
            "client_submitted_intents",
            request_id,
            reads~,
          ) {
          Ok(Some(value)) => value
          Ok(None) => return Ok(None)
          Err(issue) => return Err(issue)
        }
        let original = match
          self.journal.inspect_submitted_intent_row_with_record(row, reads~) {
          Ok((_, value)) => value
          Err(issue) => return Err(issue)
        }
        let reference = original.reference
        // Shared row validation checks key/identity/Run joins. Authentication still
        // comes from the same physical Epoch Owner and its original key/generation.
        match
          self.journal.verify_submission_locked(
            self.epoch,
            reference,
            scope,
            current(),
            reads~,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        if !current() {
          return Err(AuthorizationDenied)
        }
        Ok(Some(original))
      },
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  Ok(selected)
}
