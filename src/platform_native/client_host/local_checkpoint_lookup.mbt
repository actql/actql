///|
/// Original metadata from this Host's authenticated journal. This is neither
/// a review/Preview disclosure nor a resolution, resume claim or send permit.
struct NativeClientOriginalCheckpointMetadata {
  checkpoint_cid : String
  run_definition_cid : String
  revision : Int64
  cancellation_requested : Bool
  state : @checkpoint.RunStateView
}

///|
pub fn native_client_original_checkpoint_cid(
  original : NativeClientOriginalCheckpointMetadata,
) -> String {
  original.checkpoint_cid
}

///|
pub fn native_client_original_checkpoint_run_cid(
  original : NativeClientOriginalCheckpointMetadata,
) -> String {
  original.run_definition_cid
}

///|
pub fn native_client_original_checkpoint_revision(
  original : NativeClientOriginalCheckpointMetadata,
) -> Int64 {
  original.revision
}

///|
pub fn native_client_original_checkpoint_state(
  original : NativeClientOriginalCheckpointMetadata,
) -> @checkpoint.RunStateView {
  original.state
}

///|
/// The original Run's accepted cancellation request, not physical stop,
/// cancellation settlement or resource cleanup completion.
pub fn native_client_original_checkpoint_cancellation_requested(
  original : NativeClientOriginalCheckpointMetadata,
) -> Bool {
  original.cancellation_requested
}

///|
pub(all) enum NativeClientOriginalCheckpointLookupIssue {
  UnresolvedHistory
  MissingRunAdmission
  Journal(NativeClientRunJournalIssue)
}

///|
/// Read the accepted original Submission and its original Run's Checkpoint.
/// The real adopted Host supplies current Run read authority. A missing Run
/// or unresolved Submission is not an empty Checkpoint page or retry permit.
/// No current compilation, live Work, Store open or credential is consulted.
pub fn NativeLocalHostConnection::lookup_submitted_checkpoint_metadata(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[
  NativeClientOriginalCheckpointMetadata?,
  NativeClientOriginalCheckpointLookupIssue,
] {
  self.lookup_submitted_checkpoint_metadata_with_operations(
    crypto, principal, connection, reference, request, now,
  )
}

///|
fn NativeLocalHostConnection::lookup_submitted_checkpoint_metadata_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[
  NativeClientOriginalCheckpointMetadata?,
  NativeClientOriginalCheckpointLookupIssue,
] {
  let reads = operations.map(value => value.reads)
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let original = match
    self.journal.lookup_submitted_intent_with_operations(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
      operations~,
    ) {
    Ok(Submitted(value)) => value
    Ok(UnresolvedSubmissionHistory) => return Err(UnresolvedHistory)
    Err(issue) => return Err(Journal(issue))
  }
  guard original.run_admission is Some(admission) else {
    return Err(MissingRunAdmission)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(Journal(ChangedIntent))
  }
  self.journal
  .transaction_with_reads(
    () => {
      if !authority.current_for(self.journal, request) {
        return Err(AuthorizationDenied)
      }
      let read = fn() -> Result[
        NativeClientOriginalCheckpointMetadata?,
        NativeClientRunJournalIssue,
      ] {
        let record = match self.journal.retained(request, reads~) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        let run_definition_cid = @publication.publication_contract_identity(
          record.definition,
        )
        if run_definition_cid != admission.run_definition_cid {
          return Err(ForeignRun)
        }
        match record.checkpoint {
          None => Ok(None)
          Some(checkpoint) =>
            Ok(
              Some({
                checkpoint_cid: checkpoint.artifact.checkpoint_cid,
                run_definition_cid,
                revision: record.revision,
                cancellation_requested: record.cancellation_requested,
                state: checkpoint.state,
              }),
            )
        }
      }
      let result = read()
      // Current authorization also precedes disclosure of a custody refusal or
      // an authenticated empty result. No journal revision is changed by lookup.
      if !authority.current_for(self.journal, request) {
        return Err(AuthorizationDenied)
      }
      result
    },
    reads~,
  )
  .map_err(issue => Journal(issue))
}

///|
priv enum NativeLocalOwnedEffectCheckpoint {
  DispatchCheckpoint(NativeClientEffectDispatchClaim)
  PublicationCheckpoint(NativeLocalPublisherBinding)
}

///|
// Only a retained dispatch or original publisher can join this same Journal's
// transaction. Ordinary lookup/reentry stays refused. Account, epoch, original
// Submission/Run and current Checkpoint remain actual, never supplied as DATA.
fn NativeLocalHostConnection::lookup_effect_checkpoint_metadata_in_owned_transaction(
  self : Self,
  original : NativeLocalOwnedEffectCheckpoint,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  operations : NativeClientJournalOperationAccess,
  capture : NativeLocalJournalCapture,
) -> Result[
  NativeClientOriginalCheckpointMetadata?,
  NativeClientOriginalCheckpointLookupIssue,
] {
  let journal = self.journal
  let publication = match original {
    DispatchCheckpoint(dispatch) => {
      if !physical_equal(journal, dispatch.journal) ||
        dispatch.request != request ||
        journal.publication_read_locked {
        return Err(Journal(Checkpoint(InvalidMaterial)))
      }
      None
    }
    PublicationCheckpoint(publisher) => {
      if publisher.request != request ||
        !publisher.matches_owned_journal(
          journal,
          @host.client_request_authority_scope_cid(request),
        ) {
        return Err(Journal(Checkpoint(InvalidMaterial)))
      }
      Some(publisher)
    }
  }
  if !journal.transaction_active ||
    journal.fenced ||
    !physical_equal(journal.database, self.epoch.database) ||
    !physical_equal(journal.database, self.database) {
    return Err(Journal(Checkpoint(InvalidMaterial)))
  }
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
      capture=Some(capture),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let allowed = authority.current_for(journal, request)
  match
    self.epoch.verify_epoch_in_journal_transaction(
      journal,
      reference.epoch,
      authority.scope,
      allowed,
      now,
      Some(operations),
      publication~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(Epoch(issue)))
  }
  let submitted = match
    journal.retained_submission(reference, reads=Some(operations.reads)) {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnresolvedHistory)
    Err(issue) => return Err(Journal(issue))
  }
  guard submitted.run_admission is Some(admission) else {
    return Err(MissingRunAdmission)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(Journal(ChangedIntent))
  }
  let retained = fn() -> Result[
    NativeClientRunRecord,
    NativeClientRunJournalIssue,
  ] {
    match original {
      DispatchCheckpoint(dispatch) =>
        journal.require_effect_dispatch_locked(dispatch)
      PublicationCheckpoint(publisher) => {
        let record = match
          journal.retained(request, reads=Some(operations.reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        if !journal.transaction_active ||
          !publisher.matches_owned_journal(journal, authority.scope) ||
          record.publication_binding != Some(publisher.store_binding) ||
          @publication.publication_contract_identity(record.definition) !=
          @publication.publication_contract_identity(publisher.definition) {
          return Err(CustodyLost)
        }
        Ok(record)
      }
    }
  }
  let record = match retained() {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let definition = @publication.publication_contract_identity(record.definition)
  if definition != admission.run_definition_cid {
    return Err(Journal(ForeignRun))
  }
  if !authority.current_for(journal, request) ||
    !journal.transaction_active ||
    (journal.publication_read_locked && publication is None) ||
    journal.fenced {
    return Err(Journal(AuthorizationDenied))
  }
  // The Account callback cannot retire this same dispatch or replace its row.
  let current = match retained() {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard current.checkpoint is Some(checkpoint) &&
    current.revision == record.revision &&
    @publication.publication_contract_identity(current.definition) == definition else {
    return Err(Journal(CustodyLost))
  }
  Ok(
    Some({
      checkpoint_cid: checkpoint.artifact.checkpoint_cid,
      run_definition_cid: definition,
      revision: current.revision,
      cancellation_requested: current.cancellation_requested,
      state: checkpoint.state,
    }),
  )
}
