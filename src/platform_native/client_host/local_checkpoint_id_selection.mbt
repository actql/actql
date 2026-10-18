///|
/// Original selected identity, not a disclosure of Preview, approval, a signing
/// use, a grant or a continuation. Only the same adopted Host constructs it.
struct NativeLocalCheckpointSelection {
  reference : NativeClientSubmissionReference
  request : @host.ClientRequestIdentity
  checkpoint_id : String
  checkpoint_cid : String
}

///|
pub fn NativeLocalCheckpointSelection::reference(
  self : NativeLocalCheckpointSelection,
) -> NativeClientSubmissionReference {
  self.reference
}

///|
pub fn NativeLocalCheckpointSelection::request(
  self : NativeLocalCheckpointSelection,
) -> @host.ClientRequestIdentity {
  self.request
}

///|
pub fn NativeLocalCheckpointSelection::checkpoint_id(
  self : NativeLocalCheckpointSelection,
) -> String {
  self.checkpoint_id
}

///|
pub fn NativeLocalCheckpointSelection::checkpoint_cid(
  self : NativeLocalCheckpointSelection,
) -> String {
  self.checkpoint_cid
}

///|
/// Exact ID is a selector only. The locator is rejoined to the authenticated
/// original Submission, Run and Checkpoint under current RunRead. A missing
/// legacy locator stays unavailable; this never scans, backfills or prepares.
pub fn NativeLocalHostConnection::lookup_original_checkpoint_by_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  id : String,
  now : Double,
) -> Result[NativeLocalCheckpointSelection?, NativeClientRunJournalIssue] {
  if id.is_empty() || id.length() > 65536 {
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
  let request = match
    self.journal.transaction(() => {
      if !current() {
        return Err(AuthorizationDenied)
      }
      let selected = self.journal.checkpoint_request_by_id_locked(scope, id)
      if !current() {
        return Err(AuthorizationDenied)
      }
      selected
    }) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let reference = match
    self.lookup_submission_reference_by_request_id(
      crypto,
      principal,
      connection,
      @host.client_request_caller_id(request),
      now,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let original = match
    self.lookup_submitted_checkpoint_metadata(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(Some(value)) => value
    _ => return Err(CustodyLost)
  }
  // Recheck the same selected CID after the existing clock/current callbacks.
  // No callback may exchange the original checkpoint between selection/reply.
  let selected = match
    self.journal.transaction(() => {
      if !current() {
        return Err(AuthorizationDenied)
      }
      let actual = match
        self.journal.checkpoint_request_by_id_locked(scope, id) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if @host.client_request_identity_relation(actual, request) !=
        @host.SameRequest {
        return Err(ForeignRun)
      }
      let record = match self.journal.retained(actual) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      guard record.checkpoint is Some(checkpoint) &&
        checkpoint.artifact.checkpoint_cid == original.checkpoint_cid else {
        return Err(CustodyLost)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      Ok({
        reference,
        request,
        checkpoint_id: id,
        checkpoint_cid: original.checkpoint_cid,
      })
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(Some(selected))
}
