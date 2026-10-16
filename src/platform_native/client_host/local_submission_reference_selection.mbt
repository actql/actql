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
  if !submission_reference_request_id(request_id) {
    return Err(InvalidSubmission)
  }
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let current = () => {
    saved_run_selection_current(self, crypto, principal, connection, scope)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.journal.database, self.epoch.database) {
    return Err(InvalidSubmission)
  }
  // The existing Epoch Owner must advance/authenticate its durable clock before
  // verify_submission_locked; it owns any lost COMMIT response or fencing.
  match self.epoch.clock(now) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let selected = match
    self.journal.transaction(() => {
      if !current() {
        return Err(AuthorizationDenied)
      }
      match self.journal.submitted_intent_custody() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let row = match
        client_journal_read(
          self.journal.database,
          "client_submitted_intents",
          request_id,
        ) {
        Ok(Some(value)) => value
        Ok(None) => return Ok(None)
        Err(issue) => return Err(issue)
      }
      let original = match self.journal.inspect_submitted_intent_row(row) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let reference = native_submission_reference_record(original.reference)
      // Shared row validation checks key/identity/Run joins. Authentication still
      // comes from the same physical Epoch Owner and its original key/generation.
      match
        self.journal.verify_submission_locked(
          self.epoch,
          reference,
          scope,
          current(),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      Ok(Some(reference))
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  Ok(selected)
}
