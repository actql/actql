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
/// Join an original Run reference to its retained Checkpoint through the
/// current scoped definition index and exact original Submission/Checkpoint.
pub fn NativeLocalJournalCapture::lookup_effect_checkpoint_for_run_in_original_read(
  self : Self,
  principal : String,
  connection : String,
  scope : String,
  definition_cid : String,
  now : Double,
) -> Result[NativeLocalCheckpointSelection, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    let current = () => {
      saved_run_selection_current(
        host,
        self.crypto,
        principal,
        connection,
        scope,
        capture=Some(self),
      )
    }
    if !current() {
      return Err(Journal(AuthorizationDenied))
    }
    let reads = Some(operations.reads)
    let (request, checkpoint_id, checkpoint_cid) = match
      host.journal.transaction_with_reads(
        () => {
          if !current() {
            return Err(AuthorizationDenied)
          }
          let key = match
            client_journal_run_definition_key(
              host.database,
              definition_cid,
              reads,
            ) {
            Ok(Some(value)) => value
            Ok(None) => return Err(CustodyLost)
            Err(issue) => return Err(Physical(issue))
          }
          let row = match
            read_client_journal_value(host.database, "client_runs", key, reads) {
            Ok(value) => value
            Err(issue) => return Err(Physical(issue))
          }
          let original = match
            host.journal.admit_retained_record(key, row, reads~) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          guard @host.client_request_scope_cid(original.request) == key &&
            @host.client_request_authority_scope_cid(original.request) == scope &&
            @publication.publication_contract_identity(original.definition) ==
            definition_cid &&
            original.checkpoint is Some(checkpoint) &&
            checkpoint.artifact.checkpoint.kind == @checkpoint.EffectSet &&
            checkpoint.state.status == @publication.Resuming &&
            current() else {
            return Err(ForeignRun)
          }
          Ok(
            (
              original.request,
              checkpoint.artifact.checkpoint.checkpoint_id,
              checkpoint.artifact.checkpoint_cid,
            ),
          )
        },
        reads~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    match
      host.lookup_original_checkpoint_by_id_with_operations(
        self.crypto,
        principal,
        connection,
        checkpoint_id,
        now,
        operations=Some(operations),
        capture=Some(self),
      ) {
      Ok(Some(selected)) if selected.checkpoint_cid == checkpoint_cid &&
        @host.client_request_identity_relation(selected.request, request) ==
        @host.SameRequest &&
        current() => Ok(selected)
      Ok(_) => Err(Journal(CustodyLost))
      Err(issue) => Err(Journal(issue))
    }
  })
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
  self.lookup_original_checkpoint_by_id_with_operations(
    crypto, principal, connection, id, now,
  )
}

///|
fn NativeLocalHostConnection::lookup_original_checkpoint_by_id_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  id : String,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeLocalCheckpointSelection?, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if id.is_empty() || id.length() > 65536 {
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
  let request = match
    self.journal.transaction_with_reads(
      () => {
        if !current() {
          return Err(AuthorizationDenied)
        }
        let selected = self.journal.checkpoint_request_by_id_locked(
          scope,
          id,
          reads~,
        )
        if !current() {
          return Err(AuthorizationDenied)
        }
        selected
      },
      reads~,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let reference = match
    self.lookup_submission_reference_by_request_id_with_operations(
      crypto,
      principal,
      connection,
      @host.client_request_caller_id(request),
      now,
      operations~,
      capture~,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let original = match
    self.lookup_submitted_checkpoint_metadata_with_operations(
      crypto,
      principal,
      connection,
      reference,
      request,
      now,
      operations~,
      capture~,
    ) {
    Ok(Some(value)) => value
    Err(Journal(issue)) => return Err(issue)
    _ => return Err(CustodyLost)
  }
  // Recheck the same selected CID after the existing clock/current callbacks.
  // No callback may exchange the original checkpoint between selection/reply.
  let selected = match
    self.journal.transaction_with_reads(
      () => {
        if !current() {
          return Err(AuthorizationDenied)
        }
        let actual = match
          self.journal.checkpoint_request_by_id_locked(scope, id, reads~) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        if @host.client_request_identity_relation(actual, request) !=
          @host.SameRequest {
          return Err(ForeignRun)
        }
        let record = match self.journal.retained(actual, reads~) {
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
      },
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(Some(selected))
}
